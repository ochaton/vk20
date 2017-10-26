local log  = require 'log'
local uuid = require 'uuid'

local M = {}

function M.info(gid)
	local gid = assert(tonumber(gid), 'Gid must be a number')
	local reply = vk.api.groups.getById{ token = vk.internal.get_token(), gid = gid,
		fields = 'counters,members_count,can_see_all_posts,verified' }

	assert(type(reply) == 'table' and reply[1], 'Reply is Null')

	local public = table.remove(reply, 1)
	local posts

	reply = vk.api.wall.get{ token = vk.internal.get_token(), owner_id = -gid, count = 1 }
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

function M.find_active(gid)
	local gid = assert(tonumber(gid), 'Gid must be a number')
	local public
	if not box.space.publics:get{gid} then
		public = M.info(gid)
	else
		public = T.publics.hash(box.space.publics:get{ gid })
	end

	local till = os.time() - 24 * 3600 * 60

	local reply = vk.api.wall.get{ token = vk.internal.get_token(); owner_id = -gid, count = 100 }
	assert(type(reply) == 'table' and reply[1], 'Reply for wall failed')

	local posts = table.remove(reply, 1)
	local wall = reply

	local check_comments = {}

	for _, post in ipairs(wall) do
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

		table.insert(check_comments, {
			wall  = post.to_id;
			post  = post.id;
			count = post.comments.count;
		})
	end

	local active = {}

	for _, comment in ipairs(check_comments) do
		log.info('Searching for comments for %s_%s', comment.wall, comment.post)
		local users = M.commentators(comment)

		for user, _ in pairs(users) do
			active[user] = true
		end
	end
	log.info('Comments proccesed')

	local active_count = 0
	for _, _ in pairs(active) do
		active_count = active_count + 1
	end

	local comments_count = 0
	for _, post in pairs(check_comments) do
		comments_count = comments_count + post.count
	end

	return box.space.publics:update({ public.gid }, {
		{ '=', F.publics.active, active_count },
		{ '=', F.publics.comments, comments_count },
	})
end


function M.commentators(post)

	local commentators = {}
	local offset = 0

	while offset < post.count do
		local reply = vk.api.wall.getComments{
			token      = vk.internal.get_token();
			owner_id   = post.wall,
			post_id    = post.post,
			count      = 100,
			offset     = offset,
			sort       = 'desc',
		}

		assert(type(reply) == 'table' and reply, 'Reply for comments is null')
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

			box.space.comments:insert(T.comments.tuple {
				uuid   = uuid.str();
				author = comment.from_id;
				wall   = post.wall;
				length = #comment.text;
				vk_id  = string.format("%s_%s", post.wall, comment.cid);
				timestamp = comment.date;
			})
		end
		offset = offset + 100
	end

	return commentators
end

return M