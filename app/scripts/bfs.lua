local promise = require 'lib.promise'
local cv      = require 'lib.cv'
local log     = require 'log'
local json    = require 'json'

local spacer = require 'spacer'
spacer.create_space('temporary', {
	{ name = 'uid', type = 'number' },
},{
	{ name = 'primary', type = 'tree', parts = { 'uid' } },
})

return function (uid, max_depth)
	assert(tonumber(uid) > 0, "Uid required and must be > 0")
	max_depth = tonumber(max_depth) or 2
	log.info("Depth = %s", max_depth)

	local to_download = {{ uid = uid, depth = 0 }}
	local downloaded = {}

	local function get_friends(uid)
		local friends = vk.api.friends.get{ user_id = uid, fields = 'name,blocked', count = 5000, order = 'random' }:direct()
		if type(friends) ~= 'table' or not next(friends) then
			log.error("Friends not found")
			return {}
		end
		return friends
	end

	local cv = cv()

	local file = require 'io'.open(string.format('%s_%s.csv', uid, max_depth), "w+")

	local function again()
		while next(to_download) do
			local user
			repeat
				user = table.remove(to_download, 1)
				if not user then return end

			until user.depth <= max_depth

			cv:begin()
			vk.api.friends.get{ user_id = user.uid, fields = 'name,blocked', count = 5000, order = 'random' }:callback(function(friends)
				assert(type(friends) == 'table', "Must be table. Got = " .. type(friends))
				log.info("New %s", #friends)

				for _, friend in pairs(friends) do
					friend.uid = tonumber(friend.uid)
					if type(friend) == 'table' and friend.uid and not box.space.temporary:get{friend.uid} then
						friend.depth = user.depth + 1
						box.space.temporary:insert(T.temporary.tuple {
							uid   = friend.uid,
						})

						file:write(string.format("%s\t%s\t%s\t%s\n", friend.uid, friend.first_name, friend.last_name, friend.depth))
						file:flush()

						table.insert(to_download, {
							uid   = friend.uid,
							depth = friend.depth,
						})
					end
				end

				log.info("Downloaded: %s", box.space.temporary:len())
				log.info("To Download: %s", #to_download)

				again()
				cv:fin()
			end):on_fail(function ( ... )
				cv:fin()
				log.error("On_fail called for %s", uid)
				log.error("Err = %s", json.encode({...}))
			end)
		end
	end

	again()

	cv:recv()
	file:write("uid\tfirst_name\tlast_name\tdepth\n")
	for k, user in pairs(downloaded) do
	end
	file:close()
	return "ok"
end

