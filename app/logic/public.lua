local log  = require 'log'
local uuid = require 'uuid'
local cv   = require 'lib.cv'


local M = {}

function M.info(gid)
	local gid = assert(tonumber(gid), 'Gid must be a number')
	local reply = vk.api.groups.getById({ token = vk.internal.get_token(), gid = gid,
		fields = 'counters,members_count,can_see_all_posts,verified' }):direct()

	assert(type(reply) == 'table' and reply[1], 'Reply is Null')

	local public = table.remove(reply, 1)
	local posts

	reply = vk.api.wall.get({ token = vk.internal.get_token(), owner_id = -gid, count = 1 }):direct()
	if (type(reply) == 'table' and reply[1]) then
		posts = table.remove(reply, 1)
	else
		box.log.error('Reply wall for %s failed', -gid)
	end

	return T.publics.hash(box.space.publics:insert(T.publics.tuple {
		gid     = gid;
		members = public.members_count;
		posts   = posts;
		videos  = public.counters.videos or 0;
	}))
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

		vk.api.wall.get({ token = vk.internal.get_token(); owner_id = -gid, count = 100, offset = offset }):callback(
		function(prom, reply)

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
			token      = vk.internal.get_token();
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

return M