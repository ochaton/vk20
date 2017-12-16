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

spacer.create_space('publics', {
	{ name = 'gid',      type = 'number' },
	{ name = 'members',  type = 'number' },
	{ name = 'active',   type = 'number' },
	{ name = 'videos',   type = 'number' },
	{ name = 'comments', type = 'number' },
	{ name = 'posts',    type = 'number' },
}, {
	{ name = 'primary', type = 'tree', parts = { 'gid' } },
	{ name = 'members', type = 'tree', unique = false, parts = { 'members' } },
})

spacer.create_space('comments', {
	{ name = 'uuid',   type = 'string' },
	{ name = 'author', type = 'number' }, -- userId
	{ name = 'wall',   type = 'number' }, -- wallId (public or user)
	{ name = 'length', type = 'number' },
	{ name = 'text',   type = 'string' },
	{ name = 'vk_id',  type = 'string' },
	{ name = 'timestamp', type = 'number' },
}, {
	{ name = 'primary', type = 'tree', parts = { 'uuid' } },
	{ name = 'vk_id', type = 'tree', parts = { 'vk_id' } },
	{ name = 'time',    type = 'tree', unique = false, parts = { 'timestamp' } },
	{ name = 'author',  type = 'tree', unique = false, parts = { 'author', 'timestamp' } },
	{ name = 'wall',    type = 'tree', unique = false, parts = { 'wall', 'timestamp' } },
}, {
	engine = 'vinyl',
})

spacer.create_space('feed', {
	{ name = 'uuid',   type = 'string' },
	{ name = 'user',   type = 'number' },
	{ name = 'action', type = 'string' },
	{ name = 'wall',   type = 'number' },
	{ name = 'post',   type = 'number' },
	{ name = 'timestamp', type = 'number' },
	{ name = 'text',   type = 'string' },
	{ name = 'extra',  type = '*' },
}, {
	{ name = 'primary',     type = 'tree', parts = { 'uuid' } },
	{ name = 'user',        type = 'tree', unique = false, parts = { 'user', 'timestamp' } },
	{ name = 'user_action', type = 'tree', parts = { 'user', 'action', 'timestamp' } },
	{ name = 'user_wall',   type = 'tree', parts = { 'user', 'wall', 'timestamp' } },
}, {
	engine = 'vinyl',
})

spacer.create_space('users', {
	{ name = 'id',      type = 'number' },
	{ name = 'friends', type = 'number' },
	{ name = 'blocked', type = 'string' },
	{ name = 'mtime',   type = 'number' },
	{ name = 'ctime',   type = 'number' },
	{ name = 'count',   type = 'number' },
	{ name = 'isbot',   type = 'number' },
	{ name = 'extra',   type = '*'      },
}, {
	{ name = 'primary',  type = 'tree', parts = { 'id' } },
	{ name = 'time',     type = 'tree', unique = false, parts = { 'mtime' } },
	-- { name = 'bot',      type = 'tree', unique = false, parts = { 'isbot' } },
})

spacer.create_space('posts', {
	{ name = 'owner_id', type = 'number' },
	{ name = 'post_id',  type = 'number' },
	{ name = 'type',     type = 'string' },
	{ name = 'text',     type = 'string' },
	{ name = 'mtime',    type = 'number' },
	{ name = 'ctime',    type = 'number' },
	{ name = 'likes',    type = '*'      },
	{ name = 'comments', type = '*'      },
	{ name = 'reposts',  type = '*'      },
	{ name = 'extra',    type = '*'      },
}, {
	{ name = 'vk_id',  type = 'tree', parts = { 'owner_id', 'post_id' } },
	{ name = 'time',   type = 'tree', unique = false, parts = { 'mtime' } },
}, {
	engine = 'vinyl',
})
