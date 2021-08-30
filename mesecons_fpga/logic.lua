
local lg = {}

local operations = 
{
	-- table index: Index in the formspec dropdown
	-- gate:    Internal name
	-- short:   Serialized form, single character
	-- fs_name: Display name, padded to 4 characters
	-- func:    Function that applies the operation
	-- unary:   Whether this gate only has one input
	{ gate = "and",  short = "&", fs_name = " AND", func = function(a, b) return a and b end },
	{ gate = "or",   short = "|", fs_name = "  OR", func = function(a, b) return a or b end },
	{ gate = "not",  short = "~", fs_name = " NOT", func = function(a, b) return not b end, unary = true },
	{ gate = "xor",  short = "^", fs_name = " XOR", func = function(a, b) return a ~= b end },
	{ gate = "nand", short = "?", fs_name = "NAND", func = function(a, b) return not (a and b) end },
	{ gate = "buf",  short = "_", fs_name = "   =", func = function(a, b) return b end, unary = true },
	{ gate = "xnor", short = "=", fs_name = "XNOR", func = function(a, b) return a == b end },
	{ gate = "nor",  short = "!", fs_name = " NOR", func = function(a, b) return not (a or b) end },
}

-- <PK>
local m_gates_op = { ["and"]=1, ["or"]=2, ["not"]=3, ["xor"]=4, ["nand"]=5, ["buf"]=6, ["xnor"]=7, ["nor"]=8 }
local m_fs_names_op = { [" AND"]=1, ["  OR"]=2, [" NOT"]=3, [" XOR"]=4, ["NAND"]=5, ["   ="]=6, ["XNOR"]=7, [" NOR"]=8 }
local m_shorts_op = { ["&"]=1, ["|"]=2, ["~"]=3, ["^"]=4, ["?"]=5, ["_"]=6, ["="]=7, ["!"]=8 }

lg.find_gate = function(gate)
	local i = m_gates_op[gate] 
	return i or 0
end

lg.find_fs_name = function(fs_name)
	local i = m_fs_names_op[gate] 
	return i or 0
end

lg.find_short = function(short)
	local i = m_shorts_op[short] 
	return i or 0
end
-- </PK>

lg.get_operations = function()
	return operations
end

-- (de)serialize
lg.serialize = function(t) -- t is the array of fpga-entries.
	local function _op(t) -- t is one element of that array.
		if t == nil then
			return " "
		elseif t.type == "io" then
			return t.port
		else -- t.type == "reg"
			if t.n == 10 then
				return "L"
			else
				return tostring(t.n)
			end
		end
	end
	-- Serialize actions (gates) from eg. "and" to "&"
	local function _action(action)
		-- <PK>
		local i = lg.find_gate(action)
		return i>0 and operations[i].short or " "
		-- </PK>
		-- <prev>
		--for i, data in ipairs(operations) do
		--	if data.gate == action then
		--		return data.short
		--	end
		--end
		--return " "
	end

	local s = ""
	for i = 1, 14 do
		local cur = t[i]
		if next(cur) ~= nil then
			s = s .. _op(cur.op1) .. _action(cur.action) .. _op(cur.op2) .. _op(cur.dst)
		end
		s = s .. "/"
	end
	return s
end

lg.deserialize = function(s)
	local function _op(c)
		if c == "A" or c == "B" or c == "C" or c == "D" then
			return {type = "io", port = c}
		elseif c == " " then
			return nil
		else
			if c == "L" then
				return {type = "reg", n = 10}
			else
				return {type = "reg", n = tonumber(c)}
			end
		end
	end
	-- Deserialize actions (gates) from eg. "&" to "and"
	local function _action(action)
		-- <PK>
		local i = lg.find_short(action)
		if (i > 0) then return operations[i].gate end
		-- </PK>
		-- <prev>
		--for i, data in ipairs(operations) do
		--	if data.short == action then
		--		return data.gate
		--	end
		--end
		-- nil
		-- </prev>
	end

	local ret = {}
	for part in s:gmatch("(.-)/") do
		local parsed
		if part == "" then
			parsed = {}
		else
			parsed = {
				action = _action( part:sub(2,2) ),
				op1 = _op( part:sub(1,1) ),
				op2 = _op( part:sub(3,3) ),
				dst = _op( part:sub(4,4) ),
			}
		end
		ret[#ret + 1] = parsed
	end
	-- More than 14 instructions (write to all 10 regs + 4 outputs)
	-- will not pass the write-once requirement of the validator
	assert(#ret == 14)
	return ret
end

-- validation
lg.validate_single = function(t, i)
	local function is_reg_written_to(t, n, max)
		for i = 1, max-1 do
			if next(t[i]) ~= nil
					and t[i].dst and t[i].dst.type == "reg"
					and t[i].dst.n == n then
				return true
			end
		end
		return false
	end
	local function compare_op(t1, t2, allow_same_io)
		if t1 == nil or t2 == nil then
			return false
		elseif t1.type ~= t2.type then
			return false
		end
		if t1.type == "reg" and t1.n == t2.n then
			return true
		elseif t1.type == "io" and t1.port == t2.port then
			return not allow_same_io
		end
		return false
	end
	local elem = t[i]

	local gate_data
	-- <PK>
	gate_data = operations[lg.find_gate(elem.action)]
	-- </PK>
	--<prev>
	--for j, data in ipairs(operations) do
	--	if data.gate == elem.action then
	--		gate_data = data
	--		break
	--	end
	--end
	-- </prev>
	-- check for completeness
	if not gate_data then
		return {i = i, msg = "Gate type is required"}
	elseif gate_data.unary then
		if elem.op1 ~= nil or elem.op2 == nil or elem.dst == nil then
			return {i = i, msg = "Second operand (only) and destination are required"}
		end
	else
		if elem.op1 == nil or elem.op2 == nil or elem.dst == nil then
			return {i = i, msg = "Operands and destination are required"}
		end
	end
	-- check whether operands/destination are identical
	if compare_op(elem.op1, elem.op2) then
		return {i = i, msg = "Operands cannot be identical"}
	end
	if compare_op(elem.op1, elem.dst, true) or compare_op(elem.op2, elem.dst, true) then
		return {i = i, msg = "Destination and operands must be different"}
	end
	-- check whether operands point to defined registers
	if elem.op1 ~= nil and elem.op1.type == "reg"
			-- <PK>
			and not is_reg_written_to(t, elem.op1.n, 14) then
			-- </PK>
			-- <prev>
			-- and not is_reg_written_to(t, elem.op1.n, i) then
			-- </prev>
		return {i = i, msg = "First operand is undefined register"}
	end
	if elem.op2.type == "reg" 
			-- <PK>
			and not is_reg_written_to(t, elem.op2.n, 14) then
			-- </PK>
			-- <prev>
			-- and not is_reg_written_to(t, elem.op2.n, i) then
			-- </prev>
		return {i = i, msg = "Second operand is undefined register"}
	end
	-- check whether destination points to undefined register
	if elem.dst.type == "reg" and is_reg_written_to(t, elem.dst.n, i) then
		return {i = i, msg = "Destination is already used register"}
	end

	return nil
end

lg.validate = function(t)
	for i = 1, 14 do
		if next(t[i]) ~= nil then
			local r = lg.validate_single(t, i)
			if r ~= nil then
				return r
			end
		end
	end
	return nil
end

-- interpreter
lg.interpret = function(t, a, b, c, d
-- <PK>
, regs
, pos
-- </PK>
)
	local function _action(s, v1, v2)
	-- <PK>
		local j = lg.find_gate(s)
		if j ~= nil and j > 0 then
			return operations[j].func(v1, v2)
		end
	-- </PK>
	-- <prev>
		--for i, data in ipairs(operations) do
		--	if data.gate == s then
		--		return data.func(v1, v2)
		--	end
		--end
	-- </prev>
		return false -- unknown gate
	end
	local function _op(t, regs, io_in)
		if t.type == "reg" then
			return regs[t.n]
		else -- t.type == "io"
			return io_in[t.port]
		end
	end

	local io_in = {A=a, B=b, C=c, D=d}
	-- <prev> local regs = {} </prev>
	local io_out = {}
	-- <PK>
	local reg_chg = false;
	local reg_chk_cnt = 0
	repeat
		reg_chg = false;
	-- </PK>
		for i = 1, 14 do
			local cur = t[i]
			if next(cur) ~= nil then
				local v1, v2
				if cur.op1 ~= nil then
					v1 = _op(cur.op1, regs, io_in)
				end
				v2 = _op(cur.op2, regs, io_in)

				local result = _action(cur.action, v1, v2)

				if cur.dst.type == "reg" then
					-- <PK>
				   if (regs[cur.dst.n] ~= result) then
						reg_chg = true
						regs[cur.dst.n] = result
					end
					-- </PK>
				else -- cur.dst.type == "io"
					io_out[cur.dst.port] = result
				end
			end
		end
		-- <PK>
		reg_chk_cnt = reg_chk_cnt + 1
	until( (not reg_chg) or (reg_chk_cnt > 180))
	if reg_chk_cnt > 11 then
		minetest.debug("FPGA at "..pos.x..","..pos.y..","..pos.z.." does not behave well.")
	end
	-- </PK>
	return io_out.A, io_out.B, io_out.C, io_out.D
end

return lg
