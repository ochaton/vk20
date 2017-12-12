local fiber = require 'fiber'
local log   = require 'log'

local M = {}

M.lastid = 0
M.MAX_RETRY = 3

local function new (async_func)
	local id = M.lastid + 1
	local self = setmetatable({}, { __index = M })

	self.attempt = 0

	self.async = function ()
		self.attempt = self.attempt + 1
		repeat
			self.__retry = 0

			local ret = { pcall(async_func, self) }
			local ok = table.remove(ret, 1)
			if not ok then
				log.error("PROMISE: %s", ret[1])
			else
				return ret[1]
			end

		until self.__retry == 0
	end

	self.chan  = fiber.channel()
	self.__retry = 1

	self.fiber = fiber.create(function ()
		fiber.self().name('promise #' .. id)

		while true do

			local mustbreak
			if self.chan then
				mustbreak = self.chan:get(1)
			end

			if mustbreak == nil then
				-- That means that promise was destroyed
				log.info("Promise destroyed")
				if self.chan then
					self.chan:close()
					self.chan = nil
				end
				return
			elseif mustbreak then
				break
			end
		end

		if self.chan then
			self.chan:close()
			self.chan = nil
		end

		self.rv = self.async()
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
	self.__callback = function (...)
		local ret = { pcall(callback, ...) }
		local ok = table.remove(ret, 1)
		if not ok then
			log.info('PROMISE: error in callback %s', ret[1])
			return nil
		end
		return ret[1]
	end
	self.chan:put(true)
	return self
end

function M:retry()
	if self.attempt < self.MAX_RETRY then
		self.__retry = 1
	end
end

function M:direct()

	if self.chan then
		self.fiber:cancel()
		self.chan:close()
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
