local M = {}

local cv = require 'lib.cv'
local json = require 'json'
local promise = require 'lib.promise'

function M.user_info(uid, days, wall_depth)
	wall_depth = wall_depth or 1
	days = days or 0

	return promise(
	function ()
		local user, wall, friends, subscriptions, followers, groups

		local cv = cv() cv:begin()

		cv:begin() vk.logic.user.actualize(uid, true):callback(function (reply) user = reply cv:fin() end)
		cv:begin() vk.logic.wall.posts(uid, 100):callback(function (reply) wall = reply cv:fin() end)
		cv:begin() vk.logic.user.get_friends(uid):callback(function (reply) friends = reply cv:fin() end)

		cv:begin() vk.api.users.getSubscriptions({ uid = uid }):callback(function(reply)
			subscriptions = reply
			subscriptions = subscriptions or {}
			subscriptions.groups = subscriptions.groups or {}
			subscriptions.groups.items = subscriptions.groups.items or {}
			cv:fin()
		end):callback(function ()
			for _, group in ipairs(subscriptions.groups.items) do
				cv:begin() vk.logic.wall.posts(group, wall_depth):callback(function () cv:fin() end)
			end
		end)

		cv:begin() vk.api.users.getFollowers({ uid = uid }):callback(function(reply)
			followers = reply
			followers = followers or {}
			followers.items = followers.items or {}
			cv:fin()
		end):callback(function ()
			cv:begin() vk.logic.user.download(followers.items):callback(function () cv:fin() end)

			for _, user in ipairs(followers.items) do
				cv:begin() vk.logic.wall.posts(user, wall_depth):callback(function() cv:fin() end)
			end
		end)

		cv:begin() vk.api.groups.get({ uid = uid }):callback(function(reply)
			groups = reply
			cv:fin()
		end):callback(function ()
			for _, group in ipairs(groups) do
				cv:begin() vk.logic.wall.posts(group, wall_depth):callback(function() cv:fin() end)
			end
		end)

		cv:fin() cv:recv()

		return {
			info = user,
			wall = wall,

			subscriptions = subscriptions,
			followers = followers
		}
	end)
end

function M.user(uid, days, wall_depth)
	wall_depth = wall_depth or 1
	days = days or 0
	local user = vk.logic.user.actualize(uid, true):direct()
	local wall = vk.logic.wall.posts(uid, 100):direct()

	local friends = vk.logic.user.get_friends(uid):direct()

	local subscriptions = vk.api.users.getSubscriptions{ uid = uid }:direct()
	local followers = vk.api.users.getFollowers{ uid = uid }:direct()

	local groups = vk.api.groups.get{ uid = uid }:direct()

	local cv = cv() cv:begin()
	if type(subscriptions) == 'table' and subscriptions.count and type(subscriptions.groups.items) == 'table' then
		for _, group in ipairs(subscriptions.groups.items) do
			cv:begin()
			vk.logic.wall.posts(group, wall_depth):callback(function () cv:fin() end)
		end
	end

	if type(followers) == 'table' and followers.count and type(followers.items) == 'table' then
		cv:begin()
		vk.logic.user.download(followers.items):callback(function () cv:fin() end)

		for _, user in ipairs(followers.items) do
			cv:begin()
			vk.logic.wall.posts(user, wall_depth):callback(function() cv:fin() end)
		end
	end

	for _, friend in ipairs(friends) do
		cv:begin()
		vk.logic.wall.posts(friend, wall_depth):callback(function() cv:fin() end)
	end

	if type(groups) == 'table' then
		for _, group in ipairs(groups) do
			cv:begin()
			vk.logic.wall.posts(group, wall_depth):callback(function() cv:fin() end)
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

function M.update_extend_user(uinfo)
	local uid = uinfo.uid
	if uinfo.deactivated then return {} end

	vk.api.groups.get{ uid = uid, count = 1000 }:callback(function (groups)
		vk.logic.wall.posts(uid, 10):callback(function (ret)
			uinfo.wall_posts = 0
			uinfo.wall_likes = 0
			uinfo.wall_comments = 0

			uinfo.posts = 0
			uinfo.reposts = 0

			if not uinfo.counters then
				local ret
				while not (type(ret) == 'table' and type(ret[1]) == 'table' and type(ret[1].counters) == 'table') do
					ret = vk.api.users.get{ uid = uinfo.uid, fields = "counters" }:direct()
				end
				uinfo.counters = ret[1].counters
			end
			-- print(require'json'.encode(uinfo))

			for _, post in pairs(ret.posts) do
				uinfo.wall_posts = uinfo.wall_posts + 1
				uinfo.wall_likes = uinfo.wall_likes + post.likes
				uinfo.wall_comments = uinfo.wall_comments + post.comments

				if post.type == 'post' then
					uinfo.posts = uinfo.posts + 1
				elseif post.type == 'copy' then
					uinfo.reposts = uinfo.reposts + 1
				end
			end

			local found = box.space.users_extended:replace(T.users_extended.tuple {
				uid            = tonumber(uid);
				name           = uinfo.last_name .. " " .. uinfo.first_name;
				photos         = tonumber(uinfo.counters.photos) or 0;
				albums         = tonumber(uinfo.counters.albums) or 0;
				friends        = tonumber(uinfo.counters.friends) or 0;
				subscribers    = tonumber(uinfo.counters.followers) or 0;
				videos         = tonumber(uinfo.counters.videos) or 0;
				audios         = tonumber(uinfo.counters.audios) or 0;
				posts          = tonumber(uinfo.posts) or 0;
				reposts        = tonumber(uinfo.reposts) or 0;
				comments       = tonumber(uinfo.wall_comments) or 0;
				likes          = tonumber(uinfo.wall_likes) or 0;
				groups         = tonumber(#groups) or 0;
				subscriptions  = tonumber(uinfo.counters.subscriptions) or 0;
				raw            = json.encode(uinfo);
			})
		end)
	end)

	return true
end

function M.extend_user(uid)
	local ret = {}
	while type(ret[1]) ~= 'table' do
		ret = vk.api.users.get {user_id = uid; fields = 'photo_id,verified,sex,bdate,city,country,home_town,has_photo,photo_50,photo_100,photo_200_orig,photo_200, photo_400_orig,photo_max,photo_max_orig,online,domain,has_mobile,contacts,site,education,universities, schools,status,last_seen,followers_count,occupation,nickname,relatives,relation,personal,connections,exports,wall_comments,activities,interests,music,movies,tv,books,games,about,quotes,can_post,can_see_all_posts,is_favorite,timezone,screen_name,maiden_name,crop_photo,career,military,counters,first_name_nom,last_name_nom' }:direct()
	end

	local uinfo = table.remove(ret, 1)
	if uinfo.deactivated then return {} end

	do
		local ret = vk.logic.wall.posts(uid):direct()

		uinfo.wall_posts = 0
		uinfo.wall_likes = 0
		uinfo.wall_comments = 0

		uinfo.posts = 0
		uinfo.reposts = 0

		for _, post in pairs(ret.posts) do
			uinfo.wall_posts = uinfo.wall_posts + 1
			uinfo.wall_likes = uinfo.wall_likes + post.likes
			uinfo.wall_comments = uinfo.wall_comments + post.comments

			if post.type == 'post' then
				uinfo.posts = uinfo.posts + 1
			elseif post.type == 'copy' then
				uinfo.reposts = uinfo.reposts + 1
			end
		end
	end

	local groups = vk.api.groups.get{ uid = uid, count = 1000 }:direct()

	local found = box.space.users_extended:get({ uid })
	if found then
		box.space.users_extended:update({ uid }, {
			{ '=', F.users_extended.uid,           uid };
			{ '=', F.users_extended.name,          uinfo.last_name .. " " .. uinfo.first_name };
			{ '=', F.users_extended.photos,        uinfo.counters.photos };
			{ '=', F.users_extended.albums,        uinfo.counters.albums };
			{ '=', F.users_extended.friends,       uinfo.counters.friends };
			{ '=', F.users_extended.subscribers,   uinfo.counters.followers };
			{ '=', F.users_extended.videos,        uinfo.counters.videos };
			{ '=', F.users_extended.audios,        uinfo.counters.audios };
			{ '=', F.users_extended.posts,         uinfo.posts };
			{ '=', F.users_extended.reposts,       uinfo.reposts };
			{ '=', F.users_extended.comments,      uinfo.wall_comments };
			{ '=', F.users_extended.likes,         uinfo.wall_likes };
			{ '=', F.users_extended.groups,        #groups };
			{ '=', F.users_extended.subscriptions, uinfo.counters.subscriptions };
			{ '=', F.users_extended.raw,           json.encode(uinfo) };
		})
	else
		found = box.space.users_extended:insert(T.users_extended.tuple {
			uid            = tonumber(uid);
			name           = uinfo.last_name .. " " .. uinfo.first_name;
			photos         = tonumber(uinfo.counters.photos);
			albums         = tonumber(uinfo.counters.albums);
			friends        = tonumber(uinfo.counters.friends);
			subscribers    = tonumber(uinfo.counters.followers);
			videos         = tonumber(uinfo.counters.videos);
			audios         = tonumber(uinfo.counters.audios);
			posts          = tonumber(uinfo.posts);
			reposts        = tonumber(uinfo.reposts);
			comments       = tonumber(uinfo.wall_comments);
			likes          = tonumber(uinfo.wall_likes);
			groups         = tonumber(#groups);
			subscriptions  = tonumber(uinfo.counters.subscriptions);
			raw            = json.encode(uinfo);
		})
	end
	return T.users_extended.hash(found)
end

return M