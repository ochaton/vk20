local M = {}

function M.extend_users(count, start)
	start = start or 0

	local limit = 0
	local toupdate = {}
	for _, user in box.space.users.index.primary:pairs(start, { iterator = "GE" }) do
		limit = limit + 1
		if limit > count then break end

		if box.space.users_extended:get{ user[ F.users.id ] } then
		else
			table.insert(toupdate, user[ F.users.id ])
		end
	end

	print(#toupdate)

	return vk.logic.user.download(toupdate, 'photo_id,verified,sex,bdate,city,country,home_town,has_photo,photo_50,photo_100,photo_200_orig,photo_200, photo_400_orig,photo_max,photo_max_orig,online,domain,has_mobile,contacts,site,education,universities, schools,status,last_seen,followers_count,occupation,nickname,relatives,relation,personal,connections,exports,wall_comments,activities,interests,music,movies,tv,books,games,about,quotes,can_post,can_see_all_posts,is_favorite,timezone,screen_name,maiden_name,crop_photo,career,military,counters,first_name_nom,last_name_nom')
end


return M
