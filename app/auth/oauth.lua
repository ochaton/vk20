local M = {}

local config = require 'config'
local url_escape   = require'tools'.url_escape
local url_unescape = require'tools'.url_unescape
local url_query    = require'tools'.url_query

function M.get_code(args)
	local url =
	string.format(
		"%s?%s", config.get('app.oauth.authorize_uri'),
		url_query {
			client_id     = config.get('app.oauth.client_id');
			redirect_uri  = config.get('app.oauth.redirect_uri');
			scope         = config.get('app.oauth.scope', 'wall,friends');
			response_type = 'code';
		}
	)

	return 302, {
		location = url
	}
end

-- function M.get_access_token(args)
-- end

return M