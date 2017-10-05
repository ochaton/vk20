local M ={}

local log   = require 'log'
local queue = require 'queue'
local fiber = require 'fiber'

local MAX_TOKEN_USE = 3

function M.add_user(args)
	assert(args.email, 'Email is required')
	assert(args.password, 'Password is required')

	if not box.space.oauth_users:get{ args.email } then
		box.space.oauth_users:insert(T.oauth_users.tuple {
			email    = args.email;
			password = args.password;
		})
	else
		return box.tuple.new{ 1, "FAIL" }
	end

	return box.tuple.new{ 0, "OK" }
end

function M.add_application(args)
	assert(tonumber(args.app_id), 'App_id is required and must be a number')

	if not box.space.oauth_application:get{ args.app_id } then
		box.space.oauth_application:insert(T.oauth_application.tuple{ app_id = args.app_id })
	else
		log.error('Application %s is already exists', args.app_id)
		return box.tuple.new{ 1, "FAIL" }
	end

	return box.tuple.new{ 0, "OK" }
end

function M.refresh_access_tokens(args)
	local delay = 0

	for _,u in box.space.oauth_users.index.primary:pairs() do
		for _,app in box.space.oauth_application.index.primary:pairs() do
			queue.tube.refresh_token:put({
				email    = u[ F.oauth_users.email ];
				password = u[ F.oauth_users.password ];
				app_id   = app[ F.oauth_application.app_id ];
			}, { delay = delay })
			delay = delay + 1
		end
	end

	log.info('All task puted')
end

function M.get_token()
	local task = queue.tube.token_queue:take(1)
	if not task then return M.get_token() end

	local taskid, info = task[1], task[3]

	info.try = info.try + 1
	if info.try < MAX_TOKEN_USE then

		box.begin()
			queue.tube.token_queue:release(taskid)
			box.space.token_queue:update({ taskid }, {{ '=', 8, info }})
		box.commit()
		return info.token

	elseif info.ctime + 1 > fiber.time() then

		local delay = fiber.time() - info.ctime + 1
		info = {
			ctime = info.ctime + 1;
			try   = 0;
			token = info.token;
		}
		box.begin()
			box.space.token_queue:update({ taskid }, {{ '=', 8, info }})
			queue.tube.token_queue:release(taskid, { delay = delay })
		box.commit()
		return M.get_token()

	else
		info = {
			ctime = fiber.time();
			try   = 1;
			token = info.token;
		}
		box.begin()
			box.space.token_queue:update({ taskid }, {{ '=', 8, info }})
			queue.tube.token_queue:release(taskid)
		box.commit()
		return info.token
	end
end

return setmetatable(M, {
	__index = function (self, name)
		log.error('Trying to call not implemented method %s', name)
		return function (...)
			return box.tuple.new{ 2, "FATAL" }
		end
	end
})
