box = {
	listen = os.getenv("LISTEN_URI") or "127.0.0.1:3301",
	memtx_memory = 1.5 * 2^30,
	background = not tonumber(os.getenv("DEV")) == 1,
	vinyl_cache = 134217728,
	-- snapshot_period = 3600,
	-- snapshot_count  = 2,
	pid_file = "tarantool.pid",
	-- log = 'file:tarantool.log',
	-- replication_source = { }
}

-- console = {
--     listen = '127.0.0.1:3302'
-- }

app = {

	expires = {
		user_friends = 3600 * 24 * 7,
		user         = 3600 * 24 * 7
	},

	oauth = {
		authorize_uri = 'https://oauth.vk.com/authorize';
		client_id     = 6013906;
		redirect_uri  = 'http://88.99.82.227/vkauth/';
		scope         = 'wall,friends';
	}

}
