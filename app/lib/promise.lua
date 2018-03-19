local fiber = require 'fiber'
local log   = require 'log'

local guard = require 'lib.guard'

local M = {}

M.lastid = 0
M.destroyed = 0
M.MAX_RETRY = 3
M.promises = {}

local function new (async_func)
	local id = M.lastid + 1
	local self = setmetatable({
		MAX_RETRY = M.MAX_RETRY,
	}, {
		__index = M,
		__tostring = function (wself)
			return "Promise#" .. wself.id or '<unknown>'
		end
	})

	self.attempt = 0

	self.async = function ()
		M.promises[ self.id ] = true
		local guard = guard(function ()
			-- Destroy phase:
			log.info("Finishing %s", self.id)
			M.promises[ self.id ] = nil
			M.destroyed = M.destroyed + 1
		end)

		repeat
			self.attempt = self.attempt + 1
			self.__retry = 0

			local ret = { pcall(async_func, self) }
			local ok = table.remove(ret, 1)
			if not ok then
				log.error("PROMISE: %s.", ret[1])
				self.__fail_callback(ret)
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

			collectgarbage()

			self.rv = self.__callback(self.rv)
			self.fiber = nil
		end
	)
	return self
end

function M:retry(set_retry)
	if set_retry then
		self.MAX_RETRY = set_retry
	else
		if self.attempt < self.MAX_RETRY then
			self.__retry = 1
		end
	end
end

function M:on_fail(on_fail_cb)
	self.__fail_callback = function ( ... )
		local ret = { pcall(on_fail_cb, ...) }
		local ok = table.remove(ret, 1)
		if not ok then
			log.info('PROMISE: error in fail_callback %s', ret[1])
			return nil
		end
		return ret[1]
	end
	return self
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
	end,
	__index = {
		stat = function ()
			local active = 0
			for promise in pairs(M.promises) do
				active = active + 1
			end
			return {
				created   = M.lastid,
				destroyed = M.destroyed,
				active    = active
			}
		end
	}
})
