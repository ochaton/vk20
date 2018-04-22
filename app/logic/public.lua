local log  = require 'log'
local uuid = require 'uuid'
local cv   = require 'lib.cv'
local promise = require 'lib.promise'
local json = require 'json'


local M = {}

function M.info(gid)
	local gid = assert(tonumber(gid), 'Gid must be a number')
	local reply = vk.api.groups.getById({ gid = gid,
		fields = 'counters,members_count,can_see_all_posts,verified' }):direct()

	assert(type(reply) == 'table' and reply[1], 'Reply is Null')

	local public = table.remove(reply, 1)
	local posts

	reply = vk.api.wall.get({ owner_id = -gid, count = 1 }):direct()
	if (type(reply) == 'table' and reply[1]) then
		posts = table.remove(reply, 1)
	else
		box.log.error('Reply wall for %s failed', -gid)
	end

	local tup

	local found = box.space.publics:get{ gid }
	if found then
		tup = box.space.publics:update({ gid }, {
			{ '=', F.publics.members, public.members_count };
			{ '=', F.publics.posts, posts };
			{ '=', F.publics.videos, public.counters.videos or 0  }
		})
	else
		tup = box.space.publics:insert(T.publics.tuple {
			gid     = gid;
			members = public.members_count;
			posts   = posts;
			videos  = public.counters.videos or 0;
		})
	end

	return T.publics.hash(tup)
end

function M.async_info(gid)
	local gid = assert(tonumber(gid), 'Gid must be a number')
	return promise(
	function()
		vk.api.groups.getById({ gid = gid, fields = 'counters,members_count,can_see_all_posts,verified' }):callback(
		function (reply)
			assert(type(reply) == 'table' and reply[1], 'Reply is Null')
			local public = table.remove(reply, 1)

			vk.api.wall.get({ owner_id = -gid, count = 1 }):callback(
			function(resp)
				local posts
				if (type(resp) == 'table' and resp[1]) then
					posts = resp[1]
				else
					log.error('Reply wall for %s failed. got %s', -gid, json.encode(resp))
					return
				end
				local found = box.space.publics:get{ gid }
				if found then
					box.space.publics:update({ gid }, {
						{ '=', F.publics.members, public.members_count };
						{ '=', F.publics.posts, posts };
						{ '=', F.publics.videos, public.counters.videos or 0  }
					})
				else
					box.space.publics:insert(T.publics.tuple {
						gid     = gid;
						members = public.members_count;
						posts   = posts;
						videos  = public.counters.videos or 0;
					})
				end
			end)
		end)
	end)
end

function M.find_active(gid, maximum)
	local gid = assert(tonumber(gid), 'Gid must be a number')
	local public
	if not box.space.publics:get{gid} then
		public = M.info(gid)
	else
		public = T.publics.hash(box.space.publics:get{ gid })
	end

	local comments_count = 0
	local active_count = 0

	local start_from
	local till
	local offset = 0
	maximum = maximum or 100

	local cv = cv() cv:begin()

	while offset < maximum do
		cv:begin()

		offset = offset + 100

		vk.api.wall.get({ owner_id = -gid, count = 100, offset = offset }):callback(
		function(reply)

			if not (type(reply) == 'table' and reply[1]) then
				log.warn("EMPTY REPLY")
				cv:fin()
				return
			end

			local posts = table.remove(reply, 1)
			if posts < maximum then maximum = posts end

			local wall = reply
			local check_comments = {}

			for _, post in ipairs(wall) do
				if not start_from then
					start_from = post.date
					till = start_from - 24 * 3600 * 180
				end
				if post.date < till then break end

				if post.from_id > 0 then
					vk.feed.post({
						user      = post.from_id;
						timestamp = post.date;
						wall      = post.to_id;
						post      = post.id;
						text      = post.text;
					})
				end

				log.info('Searching for comments for %s_%s', post.to_id, post.id)
				local users = M.commentators({
					wall  = post.to_id;
					post  = post.id;
					count = post.comments.count;
				})

				comments_count = comments_count + post.comments.count

				local active = {}

				for user, _ in pairs(users) do
					if not active[user] then
						active[user] = true
						active_count = active_count + 1
					end
				end
			end

			cv:fin()

		end)
	end

	cv:fin() cv:recv()


	return box.space.publics:update({ public.gid }, {
		{ '=', F.publics.active, active_count },
		{ '=', F.publics.comments, comments_count },
	})
end

function M.commentators(post)

	local commentators = {}
	local offset = 0

	while offset < post.count do
		local reply = vk.api.wall.getComments({
			owner_id   = post.wall,
			post_id    = post.post,
			count      = 100,
			offset     = offset,
			sort       = 'desc',
		}):direct()

		if not (type(reply) == 'table' and reply) then
			log.error('Reply for comments is null')
			goto again
		end

		local count = table.remove(reply, 1)

		local comments = reply

		for _, comment in ipairs(comments) do
			if comment.from_id > 0 then
				if comment.reply_to_cid then
					vk.feed.reply {
						user = comment.from_id;
						wall = post.wall;
						post = post.post;
						timestamp = comment.date;
						text = comment.text;
						reply = {
							cid = comment.reply_to_cid;
							uid = comment.reply_to_uid;
						}
					}
				else
					vk.feed.comment {
						user = comment.from_id;
						wall = post.wall;
						post = post.post;
						timestamp = comment.date;
						text = comment.text;
					}
				end
				commentators[comment.from_id] = (commentators[comment.from_id] or 0) + 1
			end

			local vk_id = string.format("%s_%s", post.wall, comment.cid)

			if not box.space.comments.index.vk_id:get{vk_id} then
				box.space.comments:insert(T.comments.tuple {
					uuid   = uuid.str();
					author = comment.from_id;
					wall   = post.wall;
					length = #comment.text;
					vk_id  = vk_id;
					text   = comment.text;
					timestamp = comment.date;
				})
			end
		end
		offset = offset + 100
		::again::
	end

	return commentators
end

function M.get_members(gid)
	local public = vk.logic.public.info(gid)

	return promise(
	function (promise)

		local members = {}

		local offset = 0
		while offset < public.members do
			local reply = vk.api.groups.getMembers{ group_id = gid, count = 1000, offset = offset }:direct()
			if type(reply) == 'table' and type(reply.users) then
				for _, uid in ipairs(reply.users) do
					table.insert(members, uid)
				end
			end
			offset = offset + 1000
		end

		return members
	end)
end

function M.next_public(gid)
	local members = vk.logic.public.get_members(gid):direct()

	local cv = cv() cv:begin()

	for _, uid in ipairs(members) do
		-- local user = box.space.users:get{ uid }
		-- while offset < user.counters do
		-- 	cv:begin()
		-- 	vk.api.groups.get{ uid = uid }:callback(function (res)

		-- 	end)
		-- end
	end

	cv:fin() cv:recv()
end

return M