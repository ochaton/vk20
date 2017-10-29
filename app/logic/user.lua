local log = require 'log'
local cv  = require 'lib.cv'
local promise = require 'lib.promise'

local M = {}

function M.actualize(uid, force)
	local uid = assert(tonumber(uid), 'Uid must be number')
	local user = T.users.hash(box.space.users:get{ uid })

	if user and ((os.time() - user.ctime) < config.get('app.expires.user', 3600)) and not force then
		return user
	end

	local users = vk.api.users.get({ token = vk.internal.get_token(); user_id = uid, fields = 'counters' }):direct()
	local new = users[1]

	new.counters = new.counters or {}

	if user then
		user = box.space.users:update({ uid }, {
			{ '=', F.users.friends, new.counters.friends or 0 },
			{ '=', F.users.ctime, os.time() },
			{ '=', F.users.blocked, new.deactivated or 'false' },
		})
	else
		user = box.space.users:insert(T.users.tuple {
			id      = tonumber(new.uid);
			friends = new.counters.friends or 0;
			blocked = new.deactivated or 'false';
			mtime   = 0;
			ctime   = os.time();
			extra   = {};
		})
		log.info('Inserted %s', user)
	end

	return T.users.hash(user)
end

function M.download(uids)

	-- preparation
	local quids = {}
	local uhash = {}
	for _, uid in ipairs(uids) do
		local uid_str = tostring(uid)
		if not uhash[uid_str] then
			uhash[uid_str] = true
			if not box.space.users:get{ uid } then
				table.insert(quids, uid_str)
			end
		end
	end

	return promise(function (...)
		local cv = cv() cv:begin()

		local i = 1
		while i < #quids do

			local q = {}
			local j = 1
			while j < 1000 and i < #quids do
				q[#q + 1] = quids[i]
				i = i + 1
				j = j + 1
			end

			cv:begin()

			vk.api.users.get({ token = vk.internal.get_token(); uids = q; fields = 'counters' }):callback(function (users)
				for _, user in ipairs(users) do
					local found = box.space.users:get{ user.uid }
					if found then
						box.space.users:update({ user.uid }, {
							{ '=', F.users.friends, (user.counters and user.counters.friends) or 0 };
							{ '=', F.users.blocked, user.deactivated or 'false' };
							{ '=', F.users.ctime, os.time() };
						})
					else
						box.space.users:insert(T.users.tuple {
							id      = tonumber(user.uid);
							friends = (user.counters and user.counters.friends) or 0;
							blocked = user.deactivated or 'false';
							ctime   = os.time();
							mtime   = 0;
							extra   = {};
						})
						-- log.info('Inserted %s', user)
					end
				end

				cv:fin()
			end)
		end

		cv:fin()
		cv:recv()

		return true
	end)
end

function M.get_friends(uid)
	local uid  = assert(tonumber(uid), 'Uid must be number')
	local user = vk.logic.user.actualize(uid)

	if user.blocked ~= 'false' then
		return promise(function (...) return {} end)
	end

	if os.time() - user.mtime > config.get('app.expires.user_friends', 3600) then
		return promise(function (...)
			local friends = vk.api.friends.get({ token = vk.internal.get_token(); user_id = uid }):direct()
			user.extra = user.extra or {}
			user.extra.friends = friends

			box.space.users:update({ user.id }, {
				{ '=', F.users.mtime, os.time() },
				{ '=', F.users.extra, user.extra },
			})

			return user.extra.friends
		end)
	end

	return promise(function (...) return user.extra.friends end)
end

return M