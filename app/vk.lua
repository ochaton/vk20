local log = require 'log'
local fiber = require 'fiber'
local json = require 'json'

queue = require 'queue'
require 'scheme'

local M = {}

M.internal = require 'internal'

M.api   = require 'api'
M.logic = require 'logic'
M.feed  = require 'logic.feed'

M.auth = require 'auth.oauth'

local tokens = require 'tokens'
M.tokens = {}
setmetatable(M.tokens, {
	__index = function (t, method)
		return function (...)
			local func = tokens[method]
			if type(func) ~= 'function' then
				log.error('Trying to call method %s which not exists', method)
				return nil
			end

			local resp = { pcall(func, ...) }

			local ok = table.remove(resp, 1)
			if not ok then
				local error = table.remove(resp, 1)
				log.error('Processing [%s] failed with: %s', method, error)
				return box.tuple.new{ nil }
			else
				log.info('Processing [%s] successfull', method)
				print(resp[1])
				return resp[1]
			end
		end
	end
})

function M.start(config)
	log.info('Staring vk')
	queue.create_tube('refresh_token', 'fifo',
		{
			temporary = false,
			if_not_exists = true,
			on_task_change = function (...) end,
		}
	)
	queue.create_tube('token_queue', 'fifottl',
		{
			temporary = true,
			if_not_exists = true,
			on_task_change = function ( ... ) end,
		}
	)
	M.put_tokens()
end

function M.put_tokens()
	for _,tok in box.space.tokens:pairs() do
		local t = T.tokens.hash(tok)
		queue.tube.token_queue:put({ token = t.token, ctime = fiber.time(), try = 0 })
	end
end

function M.destroy()
	log.info('Unloading vk')
end

local url_sanitize = require 'tools'.url_sanitize

function http_api(req)
	log.info(json.encode(req))

	req.uri:gsub('^/', '/')
	req.uri = url_sanitize(req.uri)

	local method
	if req.uri == '/auth' then
		method = M.auth.get_code
	end

	if not method then
		log.error("Method for '%s' not found", req.uri)
		return 404, {}
	end

	local ret = { pcall(method, req) }
	local ok  = table.remove(ret, 1)

	if not ok then
		log.error('Error happened on method %s: %s', req.uri, ret[1])
		return 500, {}
	end

	return unpack(ret)
end

return M
