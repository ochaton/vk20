local M = {}

local log = require 'log'
local json = require 'json'
local spacer = require 'spacer'

spacer.create_space('last_visit', {
	{ name = 'key', type = 'string' },
	{ name = 'meta', type = '*' },
},{
	{ name = 'primary', type = 'tree', parts = { 'key' } },
})

local re = require 're'
local utf8 = require 'lua-utf8'

do
	local s = ""
	debug.setmetatable(s, { __index = utf8 })
end

function M.words(text)
	local words = {}

	for word in text:gmatch("[абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ]+") do
		table.insert(words, word:lower())
	end
	return words
end

function M.words_hash(text)
	local words = {}

	for word in text:gmatch("[абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ]+") do
		words[ word:lower() ] = true
	end
	return words
end

function M.df(limit)
	local limit = limit or 10
	local offset = 0

	local tup = T.last_visit.hash(box.space.last_visit:get{'tdf'})
	if tup then
		offset = tup.meta.offset
	end

	local cnt = 0
	local last = 0
	for _,tup in box.space.posts.index.vk_id:pairs(offset, { iterator = box.index.GE }) do
		local tup = T.posts.hash(tup)
		last = { tup.owner_id, tup.post_id }

		cnt = cnt + 1

		local words = M.words_hash(tup.text)
		box.begin()
			for word,_ in pairs(words) do
				local found = box.space.words:get{word}
				if found then
					if found[ F.words.tdf ] then
						box.space.words:update(word, {
							{ '+', F.words.tdf, 1 }
						})
					else
						box.space.words:update(word, {
							{ '=', F.words.tdf, 1 }
						})
					end
				else
					box.space.words:insert(box.tuple.new{ word, 1, 1 })
				end
			end
		box.commit()

		if cnt >= limit then break end
	end

	if not box.space.last_visit:get{'tdf'} then
		box.space.last_visit:insert(box.tuple.new{ 'tdf', { offset = last } })
	else
		box.space.last_visit:update({'tdf'},{ { '=', F.last_visit.meta, { offset = last } } })
	end
end

function M.tf(limit)
	local limit = limit or 10
	local offset = 0

	local tup = T.last_visit.hash(box.space.last_visit:get{'idf'})
	if tup then
		offset = tup.meta.offset
	end

	local cnt = 0
	local last = 0
	for _,tup in box.space.posts.index.vk_id:pairs(offset, { iterator = box.index.GE }) do
		local tup = T.posts.hash(tup)
		last = { tup.owner_id, tup.post_id }

		cnt = cnt + 1

		local words = M.words(tup.text)
		box.begin()
			for _,word in ipairs(words) do
				if box.space.words:get{word} then
					box.space.words:update(word, {
						{ '+', F.words.count, 1 }
					})
				else
					box.space.words:insert(box.tuple.new{ word, 1 })
				end
			end
		box.commit()

		if cnt >= limit then break end
	end

	if not box.space.last_visit:get{'idf'} then
		box.space.last_visit:insert(box.tuple.new{ 'idf', { offset = last } })
	else
		box.space.last_visit:update({'idf'},{ { '=', F.last_visit.meta, { offset = last } } })
	end
end


return M
