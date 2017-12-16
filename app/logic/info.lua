local M = {}

local cv = require 'lib.cv'

function M.user(uid, days)
	local user = vk.logic.user.actualize(uid, true):direct()
	local wall = vk.logic.wall.posts(uid, 10):direct()

	local subscriptions = vk.api.users.getSubscriptions{ uid = uid }:direct()
	local followers = vk.api.users.getFollowers{ uid = uid }:direct()

	local groups = vk.api.groups.get{ uid = uid }:direct()

	local cv = cv() cv:begin()
	if type(subscriptions) == 'table' and subscriptions.count and type(subscriptions.groups.items) == 'table' then
		for _, group in ipairs(subscriptions.groups.items) do
			cv:begin()
			vk.logic.wall.posts(group, 10):callback(function () cv:fin() end).MAX_RETRY = 1
		end
	end

	if type(followers) == 'table' and followers.count and type(followers.items) == 'table' then
		cv:begin()
		vk.logic.user.download(followers.items):callback(function () cv:fin() end)

		for _, user in ipairs(followers.items) do
			cv:begin()
			vk.logic.wall.posts(user, 10):callback(function() cv:fin() end).MAX_RETRY = 1
		end
	end

	if type(groups) == 'table' then
		for _, group in ipairs(groups) do
			cv:begin()
			vk.logic.wall.posts(group, 10):callback(function() cv:fin() end).MAX_RETRY = 1
		end
	end

	cv:fin() cv:recv()

	local feed = {}

	for _, tup in box.space.feed.index.user:pairs({ uid }, { iterator = box.index.EQ }) do
		local tup = T.feed.hash(tup)
		if tup.timestamp < os.time() - days * 86400 then
			break
		end
		table.insert(feed, tup)
	end

	return {
		info = user,
		wall = wall,

		feed = feed,

		subscriptions = subscriptions,
		followers = followers
	}
end


return M