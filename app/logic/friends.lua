local config = require 'config'
local log = require 'log'

local promise = require 'lib.promise'
local cv  = require 'lib.cv'

local M = {}

function M.intersection_async(uid1, uid2, friends1, friends2)
	local uid1 = assert(tonumber(uid1), 'uid1 must be a number')
	local uid2 = assert(tonumber(uid2), 'uid2 must be a number')

	return promise(
	function ()
		if not friends1 then
			friends1 = vk.api.friends.get({ user_id = uid1 }):direct() or {}
		end
		if not friends2 then
			local retry = 3
			repeat
				friends2 = vk.api.friends.get({ user_id = uid2 }):direct()
				retry = retry - 1
			until (not friends2[1] or retry < 0)
			friends2 = friends2 or {}
		end

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
	end)
end

function M.intersection(uid1, uid2, friends1, friends2)
	local uid1 = assert(tonumber(uid1), 'uid1 must be a number')
	local uid2 = assert(tonumber(uid2), 'uid2 must be a number')

	local cv = cv() cv:begin()

	if not friends1 then
		cv:begin()
		vk.api.friends.get({ user_id = uid1 }):callback(
		function (reply)
			friends1 = reply or {}
			cv:fin()
		end)
	end

	if not friends2 then
		cv:begin()
		vk.api.friends.get({ user_id = uid2 }):callback(
		function (reply)
			friends2 = reply or {}
			cv:fin()
		end)
	end

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
	local user = vk.logic.user.actualize(uid):direct()

	log.info('Start processing %s', user.id)

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

function M.clusters(uid)
	-- 1. Get friends
	local friends = vk.api.friends.get({ user_id = uid }):direct()
	local clusters = {}

	local fid2cluster = {}

	local cv = cv()

	for _, fid in ipairs(friends) do
		clusters[fid] = {}
		cv:begin()
		vk.logic.friends.intersection_async(uid, fid, friends):callback(function (common)
			-- common is subset of friends
			for _, uid in ipairs(common) do
				table.insert(clusters[fid], uid)
				fid2cluster[uid] = fid2cluster[uid] or {}
				table.insert(fid2cluster[uid], fid)
			end
			cv:fin()
		end)
	end

	cv:recv()

	return clusters, vk.logic.friends.cluster_simmilarity(clusters, vk.logic.friends.friends2vspace(friends), #friends)
end

function M.friends2vspace(args)
	local friends
	if type(args) == 'table' then
		friends = args
	else
		friends = vk.api.friends.get({ user_id = args }):direct()
	end

	local vspace = {}
	for _, fid in ipairs(friends) do
		vspace[fid] = _
	end

	return vspace
end

function M.cluster_vectors(clusters, vspace, vsize)
	jit.opt.start(3)

	local vectors = {}
	for name, cluster in pairs(clusters) do
		local vector = {} for i = 1, vsize do vector[i] = 0 end

		for _, item in ipairs(cluster) do
			vector[vspace[item]] = 1
		end

		vectors[name] = vector
	end

	jit.opt.start(1)

	return vectors
end

function M.cluster_simmilarity(clusters, vspace, vsize)

	local vclusters = {}
	jit.opt.start(3)

	for name, cluster in pairs(clusters) do
		local vector = {} for i = 1, vsize do vector[i] = 0 end

		for _, item in ipairs(cluster) do
			vector[vspace[item]] = 1
		end

		vclusters[name] = vector
	end

	local result = {}

	for name1, vcluster1 in pairs(vclusters) do
		for name2, vcluster2 in pairs(vclusters) do
			if name2 <= name1 then
				goto continue
			end

			local simm = 0.0
			for i = 1, vsize do
				simm = simm + vcluster1[i] * vcluster2[i]
			end

			-- drop 0
			if simm ~= 0 then
				result[name1] = result[name1] or {}
				result[name1][name2] = simm / vsize
			end

			::continue::
		end
	end

	jit.opt.start(1)
	return result
end

return M