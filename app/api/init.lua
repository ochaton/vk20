-- This is API-file
local M = {}


-- function M.request (...)
-- 	print(...)
-- end
M.request = require 'api.request'

-- vk.api.users.get
-- vk.api.friends.get
-- vk.api.wall.get
-- vk.api.likes.getList

M.__prefix = ''
local mt = {}

function mt.__index(self, key)
	self[key] = {
		__prefix = self.__prefix .. key .. '.'
	}
	return setmetatable(self[key], mt)
end

function mt.__call(self, ...)
	local method = self.__prefix:sub(0, -2)
	return M.request(method, ...)
end

return setmetatable(M, mt)

--[[
Usage:
	vk.api.users.get(...)
	vk.api.request(...)
]]
