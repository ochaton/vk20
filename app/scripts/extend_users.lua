local M = {}

local json = require'json'

function M.extend_users(count, start)
	start = start or 0

	local limit = 0
	local toupdate = {}
	for _, user in box.space.users.index.primary:pairs(start, { iterator = "GE" }) do
		if limit >= count then break end

		if box.space.users_extended:get{ user[ F.users.id ] } then
			local count = 0
			for p in box.space.feed.index.user:pairs(user[ F.users.id ], { iterator = "EQ" }) do
				count = count + 1
				if count >= 100 then break end
			end

			if count < 100 then
			else
				limit = limit + 1
				table.insert(toupdate, user[ F.users.id ])
			end
		end
	end

	print(json.encode(toupdate))

	return vk.logic.user.download(toupdate, 'force', 'photo_id,verified,sex,bdate,city,country,home_town,has_photo,domain,has_mobile,contacts,site,education,universities, schools,status,last_seen,followers_count,occupation,nickname,relatives,relation,personal,connections,exports,wall_comments,activities,interests,music,movies,tv,books,games,about,quotes,is_favorite,timezone,screen_name,maiden_name,career,military,counters')
end


return M
