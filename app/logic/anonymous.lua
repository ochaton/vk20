local cv   = require 'lib.cv'
local log  = require 'log'
local uuid = require 'uuid'

local M = {}

-- Steps:
-- 1. Download all walls
-- 2. Grep only anonymous posts
-- 3. Get comments into feed

local owner_id = 454810986

function M.download(limit, from_id)

	local post_id = 1
	local posts = {}

	local seen = {}
	local last_post_id = from_id or 1

	while last_post_id < limit do

		local posts = {}
		do
			local i = last_post_id
			while #posts < 100 do
				if not seen[i] then
					table.insert(posts, i)
				end
				i = i + 1
			end
			log.info('Try to get %s', table.concat(posts, "_"))
		end

		::retry::

		local reply = vk.api.wall.getById{ posts = '454810986_' .. table.concat(posts, ",454810986_") }:direct()
		if not reply then
			goto retry
		end

		if not next(reply) then
			last_post_id = posts[#posts] + 1
			goto continue
		end

		last_post_id = math.max(reply[#reply].id, posts[#posts] + 1)
		log.info('Downloaded posts %s-%s -> %s-%s: %s', posts[1], posts[#posts], reply[1].id, reply[#reply].id, #reply)

		local cv = cv() cv:begin()

		for _,post in ipairs(reply) do
			if post.from_id > 0 then
				vk.feed.post({
					user      = post.from_id;
					timestamp = post.date;
					wall      = post.to_id;
					post      = post.id;
					text      = post.text;
				})
			end

			cv:begin()

			vk.api.wall.getComments{ owner_id = owner_id, post_id = post.id }:callback(
			function(reply)
				if not reply then
					cv:fin()
					return
				end

				local comments_count = table.remove(reply, 1)
				local comments = reply

				log.info('Got %s commments in %s', comments_count, post.id)

				for _, comment in ipairs(comments) do
					seen[comment.cid] = true
					if comment.reply_to_cid then
						vk.feed.reply {
							user = comment.from_id;
							wall = owner_id;
							post = post_id;
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
							wall = owner_id;
							post = post_id;
							timestamp = comment.date;
							text = comment.text;
						}
					end

					local vk_id = string.format("%s_%s", post.wall, comment.cid)

					if not box.space.comments.index.vk_id:get{vk_id} then
						box.space.comments:insert(T.comments.tuple {
							uuid   = uuid.str();
							author = comment.from_id;
							wall   = owner_id;
							length = #comment.text;
							vk_id  = vk_id;
							text   = comment.text;
							timestamp = comment.date;
						})
					end
				end

				cv:fin()
			end)
		end

		cv:callback(function (...)
			log.info('Downloading comments for %s-%s finished', posts[1], posts[#posts])
		end)

		cv:fin()
		cv:recv()

		::continue::
	end

end


return M