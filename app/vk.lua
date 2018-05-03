local log = require 'log'
local fiber = require 'fiber'
local json = require 'json'

local ctx_t = require 'ctx.log'

queue = require 'queue'
require 'scheme'

local M = {}

M.internal = require 'internal'

M.api   = require 'api'
M.logic = require 'logic'
M.feed  = require 'logic.feed'

M.auth = require 'auth.oauth'
M.scripts = require 'scripts.extend_users'
M.vectorize = require 'scripts.vectorize'

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

function M.feed_actualize()
	local users = {}
	local to_actualize = {}

	local cv = require'lib.cv'()

	for _, tup in box.space.feed.index.user:pairs({}, { iterator = box.index.ALL }) do
		if not (users[ tup[F.feed.user] ] and box.space.users:get{ tup[F.feed.user] }) then
			table.insert(to_actualize, tup[ F.feed.user ])
			users[ tup[F.feed.user] ] = true

			if #to_actualize > 10000 then
				cv:begin()
				vk.logic.user.download(to_actualize):callback(function ()
					cv:fin()
				end)
				to_actualize = {}
			end
		end
	end

	if #to_actualize > 0 then
		vk.logic.user.download(to_actualize):direct()
	end

	cv:recv()

	print("DONE")
end

M.__gc = {
	collect   = collectgarbage;
	requests  = 0;
	threshold = 1;
	sleep     = 10;
}

function collectgarbage (...)
	local args = { ... }
	if args[1] and args[1] ~= 'collect' then
		return M.__gc.collect(...)
	end

	M.__gc.requests = M.__gc.requests + 1
	if M.__gc.chan then
		if M.__gc.requests > M.__gc.threshold then
			M.__gc.chan:put(1)
		end
		return "ok"
	end

	M.__gc.chan = fiber.channel()
	M.__gc.fiber = fiber.create(function ()
		while M.__gc.chan do
			local res = M.__gc.chan:get(tonumber(M.__gc.sleep) or 2)
			M.__gc.reason = res and 'requests' or 'timeout'
			M.__gc.collect('collect')
			M.__gc.requests = 0
			M.__gc.free = M.__gc.collect('count')
		end
	end)
	return "ok"
end

local url_sanitize = require 'tools'.url_sanitize

function http_api(req)
	log.info(json.encode(req))

	req.log = ctx_t().log
	req.log.store = nil -- print all log-messages

	req.uri:gsub('^/', '/')
	req.uri = url_sanitize(req.uri)

	req.guard = box.tuple.new{}
	debug.setmetatable(req.guard, {
		__gc = function (...)
			if req.status == 200 then
				req.log:info("[END=%s] on %s", req.status or '000', req.uri)
			else
				req.log:info("[END=%s] on %s reason: %s", req.status or '000', req.uri, req.reason)
			end
		end
	})

	req.log:info("[START] %s %s with args '%s'",
		req.method,
		req.uri,
		json.encode(req.args)
	)

	local method
	if req.uri == '/vk/auth' then
		method = M.auth.get_code
	elseif req.uri == '/vk/code' then
		method = M.auth.user
	end

	if not method then
		req.log.error("Method for '%s' not found", req.uri)
		req.status = 404
		return 404, {}
	end

	local ret = { pcall(method, req) }
	local ok  = table.remove(ret, 1)

	if not ok then
		req.log.error('Error happened on method: %s', ret[1])
		req.status = 500
		req.reason = string.format('Internal error: %s', ret[1])
		return 500, {}
	end

	req.status = ret[1]
	return unpack(ret)
end

require 'strict'.on()

return M
