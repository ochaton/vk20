local log = require 'log'

queue = require 'queue'
require 'scheme'

local M = {}

M.__tokens = require 'tokens'

M.tokens = {}
setmetatable(M.tokens, {
	__index = function (t, method)

		return function (...)
			if type(M.__tokens[method]) ~= 'function' then
				log.error('Trying to call method %s which not exists', method)
				return nil
			end

			local func = M.__tokens[method]
			local resp = { pcall(func, ...) }

			local ok = table.remove(resp, 1)
			if not ok then
				local error = table.remove(resp, 1)
				log.error('Processing [%s] failed with: %s', method, error)
				return box.tuple.new{ nil }
			else
				log.info('Processing [%s] successfull %s', method)
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
end

function M.destroy()
	log.info('Unloading vk')
end

return M
