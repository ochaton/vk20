local log  = require 'log'
local uuid = require 'uuid'

local M = {}

function M.like(args)
	args.user = tonumber(args.user)
	args.wall = tonumber(args.wall)
	args.timestamp = tonumber(args.timestamp) or os.time()
	args.post = tonumber(args.post)

	if not args.user then
		log.error('user must be a number')
		return
	end
	if not args.wall then
		log.error('wall must be a number')
		return
	end
	if not args.post then
		log.error('post must be a number')
		return
	end
	if not args.timestamp then
		log.error('timestamp must be a number')
		return
	end

	local tup = T.feed.tuple {
		uuid = uuid.str();
		user = args.user;
		action = 'like';
		wall = args.wall;
		post = args.post;
		timestamp = args.timestamp;
	}

	local ok, err = pcall(function ()
		box.space.feed:insert(tup)
	end)

	if not ok then
		-- log.error('Error on insert like-event %s: %s', tup, err)
	end
end


function M.post(args)
	args.user = tonumber(args.user)
	args.wall = tonumber(args.wall)
	args.timestamp = tonumber(args.timestamp) or os.time()
	args.post = tonumber(args.post)

	if not args.user then
		log.error('user must be a number')
		return
	end
	if not args.wall then
		log.error('wall must be a number')
		return
	end
	if not args.post then
		log.error('post must be a number')
		return
	end
	if not args.timestamp then
		log.error('timestamp must be a number')
		return
	end
	if not args.text then
		log.error('text must be a string')
		return
	end

	local tup = T.feed.tuple {
		uuid = uuid.str();
		user = args.user;
		action = 'post';
		wall = args.wall;
		post = args.post;
		timestamp = args.timestamp;
		text = args.text;
	}

	local ok, err = pcall(function ()
		box.space.feed:insert(tup)
	end)

	if not ok then
		-- log.error('Error on insert post-event %s: %s', tup, err)
	end
end

function M.comment(args)
	args.user = tonumber(args.user)
	args.wall = tonumber(args.wall)
	args.timestamp = tonumber(args.timestamp) or os.time()
	args.post = tonumber(args.post)

	if not args.user then
		log.error('user must be a number')
		return
	end
	if not args.wall then
		log.error('wall must be a number')
		return
	end
	if not args.post then
		log.error('post must be a number')
		return
	end
	if not args.timestamp then
		log.error('timestamp must be a number')
		return
	end
	if not args.text then
		log.error('text must be a string')
		return
	end

	args.text = args.text:sub(0, 1024)

	local tup = T.feed.tuple {
		uuid = uuid.str();
		user = args.user;
		action = 'comment';
		wall = args.wall;
		post = args.post;
		timestamp = args.timestamp;
		text = args.text;
	}

	local ok, err = pcall(function ()
		box.space.feed:insert(tup)
	end)

	if not ok then
		-- log.error('Error on insert comment-event %s: %s', tup, err)
	end
end

function M.reply(args)
	args.user = tonumber(args.user)
	args.wall = tonumber(args.wall)
	args.timestamp = tonumber(args.timestamp) or os.time()
	args.post = tonumber(args.post)

	if not args.user then
		log.error('user must be a number')
		return
	end
	if not args.wall then
		log.error('wall must be a number')
		return
	end
	if not args.post then
		log.error('post must be a number')
		return
	end
	if not args.timestamp then
		log.error('timestamp must be a number')
		return
	end
	if not args.text then
		log.error('text must be a string')
		return
	end
	if type(args.reply) ~= type({}) then
		log.error('reply must be a table')
		return
	end
	if not (args.reply.cid and args.reply.uid) then
		log.error('reply.cid reply.uid required')
		return
	end

	args.text = args.text:sub(0, 1024)

	local tup = T.feed.tuple {
		uuid = uuid.str();
		user = args.user;
		action = 'reply';
		wall = args.wall;
		post = args.post;
		timestamp = args.timestamp;
		text = args.text;
		extra = args.reply;
	}

	local ok, err = pcall(function ()
		box.space.feed:insert(tup)
	end)

	if not ok then
		-- log.error('Error on insert reply-event %s: %s', tup, err)
	end
end

return M