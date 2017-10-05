local spacer = require 'spacer'

spacer.create_space('tokens', {
	{ name = 'uuid', type = 'str' },
	{ name = 'token', type = 'str' },
	{ name = 'ctime', type = 'number' },
	{ name = 'atime', type = 'number' },
	{ name = 'expires', type = 'number' },
	{ name = 'user_id', type = 'number' },
	{ name = 'email', type = 'str' },
	{ name = 'app_id', type = 'number' },
},{
	{ name = 'primary', type = 'tree', parts = { 'uuid' } },
	{ name = 'atime',   type = 'tree', unique = false, parts = { 'atime' } },
	{ name = 'expires', type = 'tree', unique = false, parts = { 'expires' } },
	{ name = 'email',   type = 'tree', unique = false, parts = { 'email' } },
	{ name = 'app_id',  type = 'tree', unique = false, parts = { 'app_id' } },
})

spacer.create_space('oauth_users', {
	{ name = 'email', type = 'str' },
	{ name = 'password', type = 'str' },
}, {
	{ name = 'primary', type = 'tree', parts = { 'email' } },
})

spacer.create_space('oauth_application', {
	{ name = 'app_id', type = 'number' },
}, {
	{ name = 'primary', type = 'tree', parts = { 'app_id' } },
})
