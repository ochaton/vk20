local fiber = require 'fiber'
local log   = require 'log'

local M = {}

M.lastid = 0

local function new (async_func)
	local self = setmetatable({}, {
		__index = M,
		__gc    = function (self, ... )
			log.info("Promise #%s destroyed", self.id)
			local ok, err = pcall(function()
				self.chan:close()
				self.fiber:cancel()
			end)
			if not ok then
				log.error("Error on promise destruction %s", err)
			end
		end,
	})

	self.async = async_func
	self.chan  = fiber.channel()

	self.fiber = fiber.create(function ()
		self.chan:get()
		self.chan:close()
		self.__callback(self.async())
	end)

	self.id = M.lastid + 1
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
	self.fiber:cancel()
	self.chan:close()

	return self.async()
end

return setmetatable(M, {
	__call = function (pkg, ...)
		return new(...)
	end
})
