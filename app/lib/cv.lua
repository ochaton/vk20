local fiber = require 'fiber'

local M = {}
M._NAME = ...

function M:begin()
	self.__counter = self.__counter + 1
end

function M:fin()
	self.__counter = self.__counter - 1
	if self.__counter == 0 then

		if self.__channel:has_readers() then
			self.__channel:put(true)
		else
			self.__channel:close()
		end

		if self.__callback then
			self.__callback()
		end
	end
end

function M:recv()
	local data = self.__channel:get()
	self.__channel:close()
	return data
end

function M:send( ... )
	self.__counter = 0
	self.__channel:put(...)
end

function M:callback(callback)
	if callback then
		assert(type(callback) == 'function', 'Callback must be a function')
	end
	self.__callback = callback
end

local function new (callback)
	local self = setmetatable({}, {
		__index = M
	})

	if type(callback) == 'function' then
		self.__callback = callback
	end

	self.__channel = fiber.channel()
	self.__counter = 0

	return self
end

return setmetatable(M, {
	__call = new
})
