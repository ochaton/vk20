local M = {}

local log   = require 'log'
local json  = require 'json'
local http  = require 'http.client'
local tools = require 'api.tools'

-- https://api.vk.com/method/METHOD_NAME?PARAMETERS&access_token=ACCESS_TOKEN&v=vk

local function request (method, args)
	assert(args.token, 'token is required')

	args.access_token = args.token
	args.token = nil

	local url = string.format('https://api.vk.com/method/%s?', method)
	local req = tools.url_query(args)

	local response = http.request('POST', url, req)
	if response.status ~= 200 then
		log.error('Request to %s failed with %s %s', self.authorize_url, response.status, response.reason)
		return nil
	end

	do
		local ret = { pcall(json.decode, response.body) }
		local ok = table.remove(ret, 1)
		if not ok then
			log.error('JSON-decode failed: %s (%s)', body, response.body or '')
			return nil
		end

		local body = table.remove(ret, 1)
		return body.response
	end

	return body
end

return request
