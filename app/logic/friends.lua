local config = require 'config'
local log = require 'log'

local cv  = require 'lib.cv'

local M = {}

function M.intersection(uid1, uid2)
	local uid1 = assert(tonumber(uid1), 'uid1 must be a number')
	local uid2 = assert(tonumber(uid2), 'uid2 must be a number')

	local friends1, friends2

	local cv = cv() cv:begin()

	cv:begin()
	vk.api.friends.get({ token = vk.internal.get_token(); user_id = uid1 }):callback(
	function (reply)
		friends1 = reply or {}
		cv:fin()
	end)

	cv:begin()

	vk.api.friends.get({ token = vk.internal.get_token(); user_id = uid2 }):callback(
	function (reply)
		friends2 = reply or {}
		cv:fin()
	end)

	cv:fin()

	cv:recv() -- block here

	local hash = {}
	local common = {}

	for _, uid in ipairs(friends1) do
		hash[uid] = true
	end

	for _, uid in ipairs(friends2) do
		if hash[uid] then
			table.insert(common, uid)
		end
	end

	return common
end

local function list2hash(...)
	local hash = {}
	for _, val in ipairs({...}) do
		hash[val] = true
	end
	return hash
end

function M.bot_coff(uid)
	local user = vk.logic.user.actualize(uid)

	log.info('Start processing %s', uid)

	if user.blocked ~= 'false' then return user.blocked end

	local friends_ids = vk.logic.user.get_friends(user.id):direct()

	local friendship = list2hash(unpack(friends_ids), uid)

	vk.logic.user.download(friends_ids):direct()

	local cv = cv() cv:begin()

	local total_increment = 0
	for _, fid in ipairs(friends_ids) do

		log.info('Get Friends for %s', fid)

		cv:begin()
		vk.logic.user.get_friends(fid):callback(
		function (strangers)
			log.info('Get Friends for %s OK', fid)

			local increment = 0
			-- Count difference Friendship \ Strangers
			for _, sid in ipairs(strangers) do
				if not friendship[sid] then
					increment = increment + 1
				end
			end

			if #strangers > 0 then
				-- log.info('Incremented %s', increment / #strangers)
				total_increment = total_increment + increment / #strangers
			end

			cv:fin()
		end)
	end

	cv:fin() cv:recv()

	local updated = box.space.users:update({ user.id }, {
		{ '=', F.users.isbot, 1.0 - (total_increment / #friends_ids) }
	})

	return updated[ F.users.isbot ]
end

return M