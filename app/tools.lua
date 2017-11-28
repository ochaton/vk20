local M = {}

local json = require 'json'

function M.url_escape(str)
	if type(str) == 'string' then
		local s = str:gsub("[^%a%d-~._]",function(c)return'%'..c:hex()end)
		return s
	elseif tonumber(str) then
		return tonumber(str)
	elseif type(str) == 'table' then
		return table.concat(str, ',')
	end

	error('Unescapable type ' .. type(str) .. ' transmitted')
end

local url_escape = M.url_escape

function M.url_unescape(str)
	return str:gsub('%%(%x+)', function (c) return string.char(tonumber(c, 16)) end)
end

function M.url_query(tbl)
	local rv = {}
	for k,v in pairs(tbl) do
		table.insert(rv, url_escape(k)..'='..url_escape(v))
	end
	return table.concat(rv, '&')
end

function M.url_sanitize(url)
	local ret = url:gsub('/+', '/')
	return ret:gsub('/$', '')
end

return M