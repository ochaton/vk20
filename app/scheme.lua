local spacer = require 'spacer'

spacer.create_space('tokens', {
	{ name = 'uuid', type = 'str' },
	{ name = 'token', type = 'str' },
	{ name = 'ctime', type = 'number' },
	{ name = 'atime', type = 'number' },
	{ name = 'expires', type = 'number' },
	{ name = 'user_id', type = 'str' },
},{
	{ name = 'primary', type = 'tree', parts = { 'uuid' } },
	{ name = 'atime',   type = 'tree', unique = false, parts = { 'atime' } },
	{ name = 'expires', type = 'tree', unique = false, parts = { 'expires' } },
})
