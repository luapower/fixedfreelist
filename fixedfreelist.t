
--Fixed-size freelist for Terra.
--Written by Cosmin Apreutesei. Public Domain.

local freelist_type = function(T, size_t, C)

	setfenv(1, C)

	local items_arr = arr {T=T, size_t = size_t, C = C}

	local struct freelist {
		items: items_arr;      --{item1, ...}
		freelist: arr(size_t); --{free_item_index1, ...}
	}

	--storage

	terra freelist:init()
		self.items:init()
		self.freelist:init()
	end

	terra freelist:free()
		self.items:free()
		self.freelist:free()
	end

	terra freelist:preallocate(size: size_t)
		return self.items:preallocate(size)
			and self.freelist:preallocate(size)
	end

	function freelist.metamethods.__cast(from, to, exp)
		if from == niltype or from:isunit() then
			return `freelist {items=nil, freelist=nil}
		else
			error'invalid cast'
		end
	end

	--alloc/release

	terra freelist:alloc()
		if self.freelist.len > 0 then
			return self.items:at(self.freelist:pop())
		elseif self.items.len < self.items.size then --prevent realloc!
			return self.items:push_junk()
		end
		return nil
	end
	terra freelist:new()
		var p = self:alloc()
		return iif(p ~= nil, fill(p), nil)
	end

	terra freelist:release(pv: &T)
		var i: size_t = pv - self.items.elements
		assert(i >= 0 and i < self.items.len)
		if self.freelist.len > 0 then --poorman's double-release protection.
			if self.freelist(self.freelist.len-1) == i then
				return
			end
		end
		assert(self.freelist:push(i) ~= -1)
	end

	return freelist
end
freelist_type = terralib.memoize(freelist_type)

local freelist_type = function(T, size_t, C)
	if terralib.type(T) == 'table' then
		T, size_t, C = T.T, T.size_t, T.C
	end
	size_t = size_t or int
	C = C or require'low'
	return freelist_type(T, size_t, C)
end

local freelist = macro(
	--calling it from Terra returns a new freelist.
	function(T,size_t)
		T = T and T:astype()
		size_t = size_t and size_t:astype()
		local freelist = freelist_type(T, size_t)
		return `freelist(nil)
	end,
	--calling it from Lua or from an escape or in a type declaration returns
	--just the type, and you can also pass a custom C namespace.
	freelist_type
)

if not ... then --self-test
	setfenv(1, require'low')
	local struct S { x: int; y: int; }
	local terra test()
		var fl = freelist(S)
		fl:preallocate(2)
		var p1 = fl:alloc(); assert(p1 ~= nil)
		var p2 = fl:alloc(); assert(p2 ~= nil)
		var p3 = fl:alloc(); assert(p3 == nil)
		fl:release(p2)
		fl:release(p2) --prevented, but that's the only case covered
		fl:release(p1)
		assert(fl.freelist.len == 2)
	end
	test()
end

return freelist
