-- local log = require 'log'

local M = {}
local Methods = {}

function Methods:push (callback)
	table.insert(self.cbs, callback)
end

-- Default behavior: count = 1
function Methods:pop(count)
	local rv = {}

	if count == 0 then
		for _, cb in ipairs(self.cbs) do
			table.insert(rv, cb)
		end
		self.cbs = {}
		return unpack(rv)
	end

	count = count or 1

	while count > 0 do
		count = count - 1
		table.insert(rv, table.remove(self.cbs))
	end
	return unpack(rv)
end

function Methods:cancel()
	return self:pop(0)
end

local function destroy (self)
	for _, method in ipairs(self.cbs) do
		local ok, err = pcall(method)
		if not ok then
			print(string.format("Error in callback while destruction: %s", err))
		end
	end
end

local new

if _VERSION:match("5.1") and jit then
	local ffi = require 'ffi'
	new = function (callback)
		local self = setmetatable({}, { __index = Methods })
		self.cbs = { callback }

		return setmetatable({
			["\x00"] = ffi.gc(ffi.new('char[1]'), function () destroy(self) end)
		}, {
			__index = self,
			__newindex = self
		})
	end
elseif tonumber(_VERSION:sub(-3)) > 5.1 then
	new = function (callback)
		return setmetatable({
			cbs = { callback }
		}, {
			__index = Methods,
			__mode  = 'k',
			__gc = function (self)
				destroy(self)
			end
		})
	end
else
	error("Not implemented for " .. _VERSION)
end

return setmetatable(M, {
	__call = function (pkg, ...)
		return new(...)
	end
})
