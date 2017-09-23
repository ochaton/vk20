local M = {}

local http = require 'http.client'

local function url_escape(str)
	return str:gsub("[^%a%d-~._]",function(c)return'%'..c:hex()end)
end

local function url_unescape(str)
	return str:gsub('%%(%x+)', function (c) return string.char(tonumber(c, 16)) end)
end

local function url_query(tbl)
	local rv = {}
	for k,v in pairs(tbl) do
		table.insert(rv, url_escape(k))
		table.insert(rv, url_escape(v))
	end
	return table.concat(rv, '&')
end

--[[
	authorize_url = 'https://oauth.vk.com/authorize'
	redirect_uri  = ''
	scope = ''
	access_token_url = 'https://oauth.vk.com/access_token'
]]--

-- Step 1. Get code
function M.authorize(args)
	local url = string.format('%s?%s', self.authorize_url, url_query {
		client_id     = args.client_id;
		redirect_uri  = self.redirect_uri;
		display       = 'mobile';
		scope         = args.scope;
		response_type = 'code';
	})

	local response = http.request('GET', self.authorize_url)
	if response.status ~= 200 then
		log.error('Request to %s failed with %s %s', self.authorize_url, response.status, response.reason)
		return
	end

end

return M