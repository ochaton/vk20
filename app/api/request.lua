local M = {}

local log   = require 'log'
local json  = require 'json'
local http  = require 'http.client'
local tools = require 'api.tools'

-- https://api.vk.com/method/METHOD_NAME?PARAMETERS&access_token=ACCESS_TOKEN&v=V 

local function request (method, args)
	assert(args.token, 'token is required')
	assert(args.method, 'method is required')

	args.access_token = args.token
	args.token = nil

	local method = args.method

	local url = string.format('https://api.vk.com/method/%s?', args.method, tools.url_query(args))

	local response = http.request('POST', url)
	if response.status ~= 200 then
		log.error('Request to %s failed with %s %s', self.authorize_url, response.status, response.reason)
		return nil
	end

	local ok, body = pcall(json.decode, response.body)
	if not ok then
		log.error('JSON-decode failed: %s (%s)', body, response.body or '')
		return nil
	end

	return body
end

return request
