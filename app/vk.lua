local log = require 'log'
local fiber = require 'fiber'

queue = require 'queue'
require 'scheme'

local M = {}

M.internal = require 'internal'

M.api   = require 'api'
M.logic = require 'logic'
M.feed  = require 'logic.feed'

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

return M
