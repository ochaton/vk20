local M = {}

local promise = require 'lib.promise'
local cv      = require 'lib.cv'
local log     = require 'log'
local json    = require 'json'
local uuid    = require 'uuid'

M.DEFAULT_COUNT = 100

function M.posts(wall_id, count, offset, opts)
	count = count or M.DEFAULT_COUNT
	local start_from = offset or 0

	if wall_id < 0 then
		vk.logic.public.info(-wall_id)
	end

	opts = opts or {}

	if opts.only_wall then
		opts.comments = false
		opts.likes = false
	else
		if opts.likes == nil then
			opts.likes = true
		end
		if opts.comments == nil then
			opts.comments = true
		end
	end

	return promise(
		function (promise)
			local cv = cv() cv:begin()

			local rv = {}
			rv.posts = {}
			rv.comments = {}
			rv.likes = {}

			local offset = start_from
			while offset < count do

				cv:begin()
				vk.api.wall.get{ owner_id = wall_id, count = 100, offset = offset, extended = 1 }:callback(
				function(res)
					if not (type(res) == 'table' and res.wall) then
						cv:fin()
						return {}
					end

					local post_count = table.remove(res.wall, 1)

					for _, post in ipairs(res.wall) do
						rv.posts[post.id] = {
							owner_id = tonumber(wall_id);
							post_id  = tonumber(post.id);
							type     = post.post_type;
							text     = post.text or '';
							mtime    = os.time();
							ctime    = tonumber(post.date);

							likes    = type(post.likes) == 'table' and post.likes.count;
							comments = type(post.comments) == 'table' and post.comments.count;
							reposts = type(post.reposts) == 'table' and post.reposts.count;

							extra   = {
								copy_owner_id = post.copy_owner_id;
								copy_post_id  = post.copy_post_id;
							}
						}

						if not box.space.posts.index.vk_id:get{ wall_id, tonumber(post.id) } then
							box.space.posts:insert(T.posts.tuple(rv.posts[post.id]))
						end

						if post.from_id > 0 then
							vk.feed.post({
								user      = post.from_id;
								timestamp = post.date;
								wall      = post.to_id;
								post      = post.id;
								text      = post.text;
							})
						end

						if opts.comments and post.comments.count > 0 then
							rv.comments[ post.id ] =  vk.logic.wall.comments(post):direct()
						end

						if opts.likes and post.likes.count > 0 then
							rv.likes[ post.id ] = vk.logic.wall.likes(post):direct()
						end
					end

					cv:fin()
				end)

				offset = offset + 100
			end

			cv:fin() cv:recv()

			return rv
		end
	)
end

function M.likes(post, noreturn)
	return promise(
	function ( ... )

		local offset = 0

		if box.space.likes.index.vk_id:get{ post.to_id, post.id } then
			return {}
		end

		if not (type(post.likes) == 'table' and post.likes.count) then
			post.likes = post.likes or {}
			local likes = vk.api.likes.getList{ owner_id = post.to_id, item_id = post.id, type = 'post' }:direct()
			if type(likes) == 'table' and type(likes.users) == 'table' then
				for _, uid in ipairs(likes.users) do
					vk.feed.like {
						user      = uid;
						wall      = post.to_id;
						post      = post.id;
						timestamp = post.date;
					}
				end
				post.likes.count = likes.count

				offset = 100
			else
				return {}
			end
		end

		local cv = cv() cv:begin()
		while offset < post.likes.count do

			cv:begin()

			vk.api.likes.getList{
				owner_id = post.to_id,
				item_id = post.id,
				type = 'post',
				offset = offset
			}:callback(function (likes)
				if type(likes) == 'table' and type(likes.users) == 'table' then
					for _, uid in ipairs(likes.users) do
						vk.feed.like {
							user      = uid;
							wall      = post.to_id;
							post      = post.id;
							timestamp = post.date;
						}
					end
				end
				cv:fin()
			end)

			offset = offset + 100
		end

		cv:fin() cv:recv()

		local ok, err = pcall(function()
			box.space.likes:insert(T.likes.tuple {
				owner_id = post.to_id;
				item_id  = post.id;
				count    = post.likes.count;
				mtime    = os.time();
			})
		end)
		if not ok then print(err) end

		return {}
	end)
end

function M.comments(post)

	return promise(
	function (...)

		local cv = cv() cv:begin()

		local rv = {}
		local offset = 0
		while offset < post.comments.count do
			cv:begin()
			local promise = vk.api.wall.getComments({
				owner_id   = post.to_id,
				post_id    = post.id,
				count      = math.min(100, post.comments.count),
				offset     = offset,
				sort       = 'desc',
				preview_length = 1024,
			}):callback(
			function (reply)
				if not type(reply) == 'table' then
					log.error('Reply for comments is null')
					cv:fin()
					return {}
				end

				local count = table.remove(reply, 1)
				local comments = reply

				for _, comment in ipairs(comments) do
					if comment.from_id > 0 then
						if comment.reply_to_cid then
							vk.feed.reply {
								user = comment.from_id;
								wall = post.to_id;
								post = post.id;
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
								wall = post.to_id;
								post = post.id;
								timestamp = comment.date;
								text = comment.text;
							}
						end
					end

					local vk_id = string.format("%s_%s", post.to_id, comment.cid)

					if not box.space.comments.index.vk_id:get{vk_id} then
						box.space.comments:insert(T.comments.tuple {
							uuid   = uuid.str();
							author = comment.from_id;
							wall   = post.to_id;
							length = #comment.text;
							vk_id  = vk_id;
							text   = comment.text;
							timestamp = comment.date;
						})
					end
				end

				table.insert(rv, comments)
				cv:fin()

				return comments
			end)

			promise.MAX_RETRY = 1
			offset = offset + 100
		end

		cv:fin() cv:recv()

		return rv
	end)
end

return M