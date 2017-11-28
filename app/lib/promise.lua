local fiber = require 'fiber'
local log   = require 'log'

local M = {}

M.lastid = 0

local function new (async_func)
	local id = M.lastid + 1
	local self = setmetatable({}, {
		__index = M,
		__gc    = function ( ... )
			log.info("Promise #%s destroyed", id)
		end,
	})

	self.async = async_func
	self.chan  = fiber.channel()

	self.fiber = fiber.create(function ()
		self.chan:get()
		self.chan:close()
		self.chan = nil
		local ret = { pcall(function ()
			self.rv = self.async(self)
		end) }
		do
			local ok = table.remove(ret, 1)
			if not ok then
				log.error("PROMISE: %s", ret[1])
			end
		end
		self.__status = 'done'

		if self.__callback then
			self.rv = self.__callback(self.rv)
		end
		self.fiber = nil
	end)

	self.id = id
	M.lastid = self.id

	return self
end

-- setters
function M:callback(callback)
	self.__callback = callback
	self.chan:put(true)
	return self
end

function M:direct()

	if self.chan then
		self.chan:close()
		self.fiber:cancel()
	end

	if self.__callback then
		while self.__status ~= 'done' do
			fiber.sleep(0)
		end
		return self.rv
	end

	return self.async()
end

return setmetatable(M, {
	__call = function (pkg, ...)
		return new(...)
	end
})
