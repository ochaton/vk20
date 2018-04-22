return function (index, itype, key)
	local f, ctx, state = index:pairs(key, { iterator = itype })
	local tuple
	return function ()
		state, tuple = f(ctx,state)
		if not state then return nil end
		return tuple
	end
end
