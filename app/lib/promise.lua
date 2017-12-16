local fiber = require 'fiber'
local log   = require 'log'

local M = {}

M.lastid = 0
M.MAX_RETRY = 3

local function new (async_func)
	local id = M.lastid + 1
	local self = setmetatable({}, {
		__index = M,
		__tostring = function (wself)
			return "Promise#" .. wself.id or '<unknown>'
		end
	})

	self.attempt = 0

	self.async = function ()
		self.attempt = self.attempt + 1
		repeat
			self.__retry = 0

			local ret = { pcall(async_func, self) }
			local ok = table.remove(ret, 1)
			if not ok then
				log.error("PROMISE: %s.", ret[1])
			else
				return ret[1]
			end

		until self.__retry == 0
	end

	self.__retry = 1

	self.id = id
	M.lastid = self.id

	return self
end

-- setters
function M:callback(callback)
	self.__callback = function (...)
		local ret = { pcall(callback, ...) }
		local ok = table.remove(ret, 1)
		if not ok then
			log.info('PROMISE: error in callback %s', ret[1])
			return nil
		end
		return ret[1]
	end

	self.fiber = fiber.create(
		function()
			fiber.self().name('promise #' .. self.id)

			self.rv = self.async()
			self.__status = 'done'

			self.rv = self.__callback(self.rv)
			self.fiber = nil
		end
	)
	return self
end

function M:retry()
	if self.attempt < self.MAX_RETRY then
		self.__retry = 1
	end
end

function M:direct()

	if self.fiber then
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
