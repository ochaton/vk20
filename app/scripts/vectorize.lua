local M = {}

function list2hash(...)
	local hash = {}
	local list
	if select("#", ...) == 0 then
		return {}
	end
	if select("#", ...) == 1 then
		if type(...) == 'table' then
			list = ...
		else
			list = {...}
		end
	else
		list = {...}
	end
	for _, val in ipairs(list) do
		hash[val] = true
	end
	return hash
end

function keys(hash)
	local keys = {}
	for key, val in pairs(hash) do
		table.insert(keys, key)
	end
	return keys
end

function values(hash)
	local values = {}
	for key, val in pairs(hash) do
		table.insert(values, val)
	end
	return values
end

function union(list1, list2)
	local list = {}
	for _, tbl in ipairs{ list1, list2 } do
		for _, id in ipairs(tbl) do
			table.insert(list, id)
		end
	end
	return keys(list2hash(list))
end

function intersection(list1, list2)
	local hash1 = list2hash(list1)
	local hash2 = list2hash(list2)

	local inter = {}
	for k,_ in pairs(hash1) do
		if hash2[k] then
			inter[k] = true
		end
	end
	return keys(inter)
end

function M.user_similiarity(uid1, uid2)
	local user1 = vk.logic.user.actualize(uid1)
	local user2 = vk.logic.user.actualize(uid2)

	local vector = {}
	local aliases = {
		isFriend    = 1,
		comComments = 2,
		comLikes    = 3,
		commFriends = 4,
		commPublics = 5,
		commReposts = 6,
		avgPostsCount = 7,
	}

	-- 1. Friends ?
	do
		local friends = list2hash(vk.logic.friends.get_friends(uid1))
		vector[aliases.isFriend] = friends[uid2] and 1 or 0
	end

	-- 2+3. Comments and likes to each other
	do
		local function common_likes_and_comms (uid1, uid2)
			local comms = 0
			local likes = 0
			for _, t in box.space.feed.index.user_wall:pairs({uid1, uid2}, { iterator="EQ" }) do
				if t[F.feed.action] == 'comment' or t[F.feed.action] == 'reply' then
					comms = comms + 1
				elseif t[F.feed.action] == 'like' then
					likes = likes + 1
				end
			end
			-- Theese lines should be cached
			local total_comms = box.space.feed.index.user_action:count({uid1, "comment"})
								+ box.space.feed.index.user_action:count({uid1, "reply"})
			local total_likes = box.space.feed.index.user_action:count({uid1, "likes"})

			return {
				comms = comms,
				likes = likes,
				total_likes = total_likes,
				total_comms = total_comms,

				com_prcnt = total_comms == 0 and 0 or comms / total_comms,
				like_prcnt = total_likes == 0 and 0 or likes / total_likes,
			}
		end

		local comm1 = common_likes_and_comms(uid1, uid2)
		local comm2 = common_likes_and_comms(uid2, uid1)

		vector[aliases.comComments] = (comm1.com_prcnt + comm2.com_prcnt) / 2
		vector[aliases.comLikes] = (comm1.like_prcnt + comm2.like_prcnt) / 2
	end

	-- 4. Common friends
	do
		local friends1 = vk.logic.friends.get_friends(uid1)
		local friends2 = vk.logic.friends.get_friends(uid2)
		local commonFriends = vk.logic.friends.intersection(uid1, uid2, friends1, friends2)

		local union = union(friends1, friends2)
		vector[aliases.commFriends] = #commonFriends / #union
	end

	-- 5. Common publics
	do
		local publics = {{}, {}}
		for idx, uid in ipairs{uid1, uid2} do
			local subscriptions = vk.api.users.getSubscriptions{ uid = uid }:direct()
			local groups = vk.api.groups.get{ uid = uid }:direct()

			for _,tbl in ipairs{subscriptions, groups} do
				for _, id in ipairs(tbl) do
					table.insert(publics[idx], id)
				end
			end
		end

		local union = union(publics[1], publics[2])
		local inter = intersection(publics[1], publics[2])

		vector[aliases.commPublics] = #inter / #union
	end

	-- 6. Common reposts
	do
		local replies = {}
		for _, uid in ipairs{uid1, uid2} do
			replies[_] = box.space.feed.index.user_action
				:pairs({uid, "post"},{iterator="EQ"})
				:map(T.feed.hash)
				:map(function (t) return T.posts.hash(box.space.posts:get{t.wall, t.post}) end)
				:grep(function(post) return post.type == "copy" end)
				:map(function (post) return post.extra.copy_owner_id .. "+" .. post.extra.copy_post_id end)
				:take_n(50):totable()
		end

		local union = union(replies[1], replies[2])
		local inter = intersection(replies[1], replies[2])

		vector[aliases.commReposts] = #inter / #union
	end

	-- 7. Avg posts
	do
		local postsCount = {}
		for _, uid in ipairs{uid1, uid2} do
			postsCount[_] = box.space.feed.index.user_action:count({uid, "post"})
		end

		vector[aliases.avgPostsCount] = (postsCount[1] + postsCount[2]) / 2
	end

	return vector
end

return M