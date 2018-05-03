local M = {}
function table.merge(h1,h2,dep)
	dep = dep or 1
	if type(h1) ~= 'table' then
		if h1 == nil then
			h1 = {}
		else
			error('h1 '..h1..' type '..type(h1)..' incorrect for merge',dep+1)
		end
	end
	if type(h2) ~= 'table' then
		if h2 == nil then
			h2 = {}
		else
			error('h2 '..h2..' type '..type(h2)..' incorrect for merge',dep+1)
		end
	end
	for k,v in pairs( h2 ) do
		if not h1[k] or type(h1[k]) ~= 'table' or type(h2[k]) ~= 'table' then
			if h2[k] == require'msgpack'.NULL then
				h1[k] = nil
			else
				h1[k] = h2[k]
			end
		else
			h1[k] = table.merge(h1[k],h2[k],dep+1)
		end
	end
	return h1
end

function list2hash(...)
	local hash = {}
	local list
	if select("#", ...) == 0 then
		return {}
	end
	if select("#", ...) == 1 then
		if type(...) == 'table' then
			list = ...
		else
			list = {...}
		end
	else
		list = {...}
	end
	for _, val in ipairs(list) do
		hash[val] = true
	end
	return hash
end

function keys(hash)
	local keys = {}
	for key, val in pairs(hash) do
		table.insert(keys, key)
	end
	return keys
end

function values(hash)
	local values = {}
	for key, val in pairs(hash) do
		table.insert(values, val)
	end
	return values
end

function union(list1, list2)
	local list = {}
	for _, tbl in ipairs{ list1, list2 } do
		for _, id in ipairs(tbl) do
			table.insert(list, id)
		end
	end
	return keys(list2hash(list))
end

function intersection(list1, list2)
	local hash1 = list2hash(list1)
	local hash2 = list2hash(list2)

	local inter = {}
	for k,_ in pairs(hash1) do
		if hash2[k] then
			inter[k] = true
		end
	end
	return keys(inter)
end

function expand(vec, how_much)
	local len = #vec
	for i = len, len + how_much do
		vec[i] = 0
	end
end

function concat(vec1, vec2)
	local len = #vec1
	for i = 1, #vec2 do
		vec1[len + i] = vec2[i]
	end
end

function M.user_similiarity(uid1, uid2)
	local user1 = vk.logic.user.actualize(uid1)
	local user2 = vk.logic.user.actualize(uid2)

	local vector = {}
	local aliases = {
		isFriend    = 1,
		comComments = 2,
		comLikes    = 3,
		commFriends = 4,
		commPublics = 5,
		commReposts = 6,
		avgPostsCount = 7,
	}

	-- 1. Friends ?
	do
		local friends = list2hash(vk.logic.friends.get_friends(uid1))
		vector[aliases.isFriend] = friends[uid2] and 1 or 0
	end

	-- 2+3. Comments and likes to each other
	do
		local function common_likes_and_comms (uid1, uid2)
			local comms = 0
			local likes = 0
			for _, t in box.space.feed.index.user_wall:pairs({uid1, uid2}, { iterator="EQ" }) do
				if t[F.feed.action] == 'comment' or t[F.feed.action] == 'reply' then
					comms = comms + 1
				elseif t[F.feed.action] == 'like' then
					likes = likes + 1
				end
			end
			-- Theese lines should be cached
			local total_comms = box.space.feed.index.user_action:count({uid1, "comment"})
								+ box.space.feed.index.user_action:count({uid1, "reply"})
			local total_likes = box.space.feed.index.user_action:count({uid1, "likes"})

			return {
				comms = comms,
				likes = likes,
				total_likes = total_likes,
				total_comms = total_comms,

				com_prcnt = total_comms == 0 and 0 or comms / total_comms,
				like_prcnt = total_likes == 0 and 0 or likes / total_likes,
			}
		end

		local comm1 = common_likes_and_comms(uid1, uid2)
		local comm2 = common_likes_and_comms(uid2, uid1)

		vector[aliases.comComments] = (comm1.com_prcnt + comm2.com_prcnt) / 2
		vector[aliases.comLikes] = (comm1.like_prcnt + comm2.like_prcnt) / 2
	end

	-- 4. Common friends
	do
		local friends1 = vk.logic.friends.get_friends(uid1)
		local friends2 = vk.logic.friends.get_friends(uid2)
		local commonFriends = vk.logic.friends.intersection(uid1, uid2, friends1, friends2)

		local union = union(friends1, friends2)
		vector[aliases.commFriends] = #commonFriends / #union
	end

	-- 5. Common publics
	do
		local publics = {{}, {}}
		for idx, uid in ipairs{uid1, uid2} do
			local subscriptions = vk.api.users.getSubscriptions{ uid = uid }:direct()
			local groups = vk.api.groups.get{ uid = uid }:direct()

			for _,tbl in ipairs{subscriptions, groups} do
				for _, id in ipairs(tbl) do
					table.insert(publics[idx], id)
				end
			end
		end

		local union = union(publics[1], publics[2])
		local inter = intersection(publics[1], publics[2])

		vector[aliases.commPublics] = #inter / #union
	end

	-- 6. Common reposts
	do
		local replies = {}
		for _, uid in ipairs{uid1, uid2} do
			replies[_] = box.space.feed.index.user_action
				:pairs({uid, "post"},{iterator="EQ"})
				:map(T.feed.hash)
				:map(function (t) return T.posts.hash(box.space.posts:get{t.wall, t.post}) end)
				:grep(function(post) return post.type == "copy" end)
				:map(function (post) return post.extra.copy_owner_id .. "+" .. post.extra.copy_post_id end)
				:take_n(50):totable()
		end

		local union = union(replies[1], replies[2])
		local inter = intersection(replies[1], replies[2])

		vector[aliases.commReposts] = #inter / #union
	end

	-- 7. Avg posts
	do
		local postsCount = {}
		for _, uid in ipairs{uid1, uid2} do
			postsCount[_] = box.space.feed.index.user_action:count({uid, "post"})
		end

		vector[aliases.avgPostsCount] = (postsCount[1] + postsCount[2]) / 2
	end

	return vector
end

local function words_split(texts)
	local words = {}
	for i = 1, #texts do
		local text = texts[i]

		for word in text:gmatch("[абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ]+") do
			table.insert(words, word)
		end
	end
	return words
end

function M.textual(vector, uid)
	local posts = box.space.feed.index.user
		:pairs(uid, {iterator="EQ"})
		:map(T.feed.hash)
		:grep(function(f) local allow = {post=1, comment=1} return allow[f.action] end)
		:map(function(t)
			if t.action == 'comment' then
				return T.comments.hash(box.space.comments:get{t.wall .. t.post}) or t
			elseif t.action == 'post' then
				local post = T.posts.hash(box.space.posts:get{t.wall, t.post})
				if post and post.type == 'post' then
					return post
				else
					return t
				end
			end
		end)
		:map(function(t) return t.text end)
	:totable()

	local words = words_split(posts)
	if #words == 0 then
		words = {""} -- list with 1st empty string
	end
	do
		-- Avg symbols in word
		local total = 0
		for _, word in ipairs(words) do
			total = total + #word
		end
		table.insert(vector, total / #words)
	end

	do
		-- More than 7
		local count = 0
		for _, word in ipairs(words) do
			if #word > 7 then
				count = count + 1
			end
		end
		table.insert(vector, count / #words)
	end

	do
		-- Parts of word
		local parts = {
			[0] = 0,
		}
		for _, word in ipairs(words) do
			local vowels = 0
			for _,_ in word:gmatch("([аАоОуУыЫэЭяЯёЁюЮиИеЕ])") do
				vowels = vowels + 1
			end

			parts[vowels] = (parts[vowels] or 0) + 1
		end

		table.insert(vector, parts[0])
		table.insert(vector, parts[1])
		table.insert(vector, parts[2])
		table.insert(vector, parts[3])

		local more_than_3 = 0
		for i, count in pairs(parts) do
			if i > 3 then
				more_than_3 = more_than_3 + 1
			end
		end

		table.insert(vector, more_than_3)
	end

	do
		local count_bi = 0
		local count_else = 0
		for _, word in ipairs(words) do
			local lower = word:lower()
			if lower == 'бы' then
				count_bi = count_bi + 1
			elseif lower == 'ну' or lower == 'вот' or lower == 'ведь' then
				count_else = count_else + 1
			end
		end
		table.insert(vector, count_bi)
		table.insert(vector, count_else)
	end

	do
		local symbols = 0
		local others = 0
		for _, text in ipairs(posts) do
			local id = 0
			while id < #text do
				local _, till = text:find("(%!|%?)", id)
				if till then
					id = till + 1
					symbols = symbols + 1
				else
					local from, till = text:find("(%.+)", id)
					if not till then break end

					if from < till then
						others = others + 1
					else
						symbols = symbols + 1
					end

					id = till + 1
				end
			end
		end
		table.insert(vector, symbols / (symbols + others))
	end

	do
		-- Caps words
		local total = 0
		local caps = 0
		for _, word in ipairs(words) do
			total = total + 1
			if word == word:upper() then
				caps = caps + 1
			end
		end
		table.insert(vector, caps / total)
	end

	return words
end

function M.user_vector(uid)
	local user = table.merge(
		T.users_extended.hash(box.space.users_extended:get{uid}),
		T.users.hash(box.space.users:get{uid})
	)

	local vector = {}
	-- Counters:
	table.insert(vector, user.uid)
	table.insert(vector, user.friends)
	table.insert(vector, user.posts)
	table.insert(vector, user.groups)
	table.insert(vector, user.subscriptions)
	table.insert(vector, user.subscribers)
	table.insert(vector, user.albums)
	table.insert(vector, user.audios)
	table.insert(vector, user.likes)
	table.insert(vector, user.photos)
	table.insert(vector, user.videos)
	table.insert(vector, user.reposts)
	table.insert(vector, user.comments)

	-- Static
	if user.raw then
		user.raw = require'json'.decode(user.raw)
		table.insert(vector, user.raw.has_photo)
		table.insert(vector, user.raw.domain:match("^id%d+") and 0 or 1)
		table.insert(vector, user.raw.has_mobile)
		table.insert(vector, user.raw.verified)
		table.insert(vector, user.raw.city == 0 and 0 or 1)
		table.insert(vector, user.raw.country == 0 and 0 or 1)
		table.insert(vector, user.raw.university == 0 and 0 or 1)
		table.insert(vector, user.raw.wall_comments)
		table.insert(vector, user.raw.followers_count)
		table.insert(vector, user.raw.posts)
		table.insert(vector, user.raw.site == '' and 0 or 1)
		table.insert(vector, user.raw.graduation == 0 and 0 or 1)
		table.insert(vector, user.raw.notes)
		table.insert(vector, user.raw.counters.friends)
		table.insert(vector, user.raw.counters.gifts)
		table.insert(vector, user.raw.counters.groups)
		table.insert(vector, user.raw.counters.audios)
		table.insert(vector, user.raw.counters.user_photos)
		table.insert(vector, user.raw.counters.photos)
		table.insert(vector, user.raw.counters.videos)
		table.insert(vector, user.raw.counters.pages)
		table.insert(vector, user.raw.counters.albums)
		table.insert(vector, user.raw.counters.subscriptions)
		table.insert(vector, user.raw.career and #user.raw.career == 0 and 0 or 1)
		table.insert(vector, user.raw.books and #user.raw.books or 0)
		table.insert(vector, user.raw.quotes and #user.raw.quotes or 0)
		table.insert(vector, user.raw.reposts)
		table.insert(vector, user.raw.activities and #user.raw.activities or 0)
		table.insert(vector, user.raw.last_seen and user.raw.last_seen.time and (os.time() - user.raw.last_seen.time) or 0)
	else
		expand(vector, 29)
	end

	-- Dynamic:
	M.textual(vector, uid)

	return vector
end

return M