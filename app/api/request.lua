local M = {}

local log   = require 'log'
local json  = require 'json'
local http  = require 'http.client'
local tools = require 'tools'
local fiber = require 'fiber'
local yaml  = require 'yaml'

local promise = require 'lib.promise'

-- https://api.vk.com/method/METHOD_NAME?PARAMETERS&access_token=ACCESS_TOKEN&v=vk

local function request (method, args)
	-- assert(args.token, 'token is required')
	args.access_token = vk.internal.get_token()

	local url = string.format('https://api.vk.com/method/%s?', method)
	local req = tools.url_query(args)

	return promise(function (promise, ... )
		log.info('Request to %s. %s try', method, promise.attempt)

		local started = fiber.time()

		local response = http.request('POST', url, req)
		log.info('Request to %s finished in %0.3f', method, fiber.time() - started)

		do
			local ret = { pcall(json.decode, response.body) }
			local ok = table.remove(ret, 1)
			if not ok then
				log.error('JSON-decode failed: %s (%s)', ret[1], response.body)
				response.body = nil
			else
				response.body = ret[1]
			end
		end

		if response.status ~= 200 or response.body == nil then
			log.error('Request to %s failed with %s %s %s', url, response.status, response.reason, yaml.encode(response.body))

			if response.body then
				if response.status == 408 then
					if response.body.response then
						return response.body.response
					elseif tonumber(response.body.error.error_code) == 6 then
						return nil
					end
				end
			end

			if response.status == 500 then
				args.access_token = vk.internal.get_token()
				req = tools.url_query(args)

				promise:retry()
			end

			return nil
		end

		return response.body.response
	end)
end

return request
