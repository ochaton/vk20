local M = {}

function M.url_escape(str)
	return str:gsub("[^%a%d-~._]",function(c)return'%'..c:hex()end)
end

function M.url_unescape(str)
	return str:gsub('%%(%x+)', function (c) return string.char(tonumber(c, 16)) end)
end

function M.url_query(tbl)
	local rv = {}
	for k,v in pairs(tbl) do
		table.insert(rv, url_escape(k))
		table.insert(rv, url_escape(v))
	end
	return table.concat(rv, '&')
end

return M