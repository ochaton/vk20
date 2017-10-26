local M = {}

function M.intersection(uid1, uid2)
	local uid1 = assert(tonumber(uid1), 'uid1 must be a number')
	local uid2 = assert(tonumber(uid2), 'uid2 must be a number')

	local friends1 = vk.api.friends.get{ token = vk.intapi.get_token(); user_id = uid1 }
	local friends2 = vk.api.friends.get{ token = vk.intapi.get_token(); user_id = uid2 }

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

return M