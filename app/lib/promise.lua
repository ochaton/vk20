local fiber = require 'fiber'
local log   = require 'log'

local M = {}

M.lastid = 0
M.MAX_RETRY = 3

local function new (async_func)
	local id = M.lastid + 1
	local self = setmetatable({}, { __index = M })

	self.async = async_func
	self.chan  = fiber.channel()
	self.__retry = 1

	-- local wself = setmetatable({
	-- 	obj = self,
	-- }, setmetatable({ __mode = 'v', __index = self, __newindex = self }, { __mode = 'v' }))

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

		self.attempt = 0

		repeat
			self.attempt = self.attempt + 1
			self.__retry = 0

			local ret = { pcall(function () self.rv = self.async(self) end) }
			do
				local ok = table.remove(ret, 1)
				if not ok then
					log.error("PROMISE: %s", ret[1])
				end
			end
		until self.__retry == 0

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

function M:retry()
	if self.attempt < self.MAX_RETRY then
		self.__retry = 1
	end
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
