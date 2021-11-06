
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

-- maps for quick index-reference:
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
		local i = lg.find_gate(action)
		return i>0 and operations[i].short or " "
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
		local i = lg.find_short(action)
		if (i > 0) then return operations[i].gate end
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
	minetest.debug("Anzahl " .. #ret)
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
	gate_data = operations[lg.find_gate(elem.action)]
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
			and not is_reg_written_to(t, elem.op1.n, 14) then
		return {i = i, msg = "First operand is undefined register"}
	end
	if elem.op2.type == "reg" 
			and not is_reg_written_to(t, elem.op2.n, 14) then
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
-- parameters:
-- t: the array containing the FPGA-entries
-- a,b,c,d: the io-registers
-- regs: a reference to the values of the internal registers from last call.
--       this includes an 11th register (number 10) for the LED, special name "L"
-- pos: the position, for error- and misbehaviour-reporting.
lg.interpret = function(t, a, b, c, d, regs, pos)
	local function _action(s, v1, v2)
		local j = lg.find_gate(s)
		if j ~= nil and j > 0 then
			return operations[j].func(v1, v2)
		end
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
	local io_out = {}
	local first_refs = {} 
	local back_reg_chg = false;
	local reg_chk_cnt = 0
	local startndx = 1
	local first_iteration = true
	repeat
		back_reg_chg = false;
		for i = startndx, 14 do
			local cur = t[i]
			if next(cur) ~= nil then
				local v1, v2
				if cur.op1 ~= nil then
					v1 = _op(cur.op1, regs, io_in)
					if cur.op1.type == "reg" and first_refs[cur.op1.n] == nil then
						first_refs[cur.op1.n] = i -- remember, where this register ist first used.
						-- minetest.debug("FPGA at "..pos.x..","..pos.y..","..pos.z..": first_refs["..cur.op1.n.."]="..i)
					end
				end
				v2 = _op(cur.op2, regs, io_in)
				if cur.op2.type == "reg" and first_refs[cur.op2.n] == nil then
					first_refs[cur.op2.n] = i -- remember, where this register ist first used.
				end
				local result = _action(cur.action, v1, v2)

				if cur.dst.type == "reg" then
				   if (regs[cur.dst.n] ~= result) then
						regs[cur.dst.n] = result
						if first_refs[cur.dst.n] and first_refs[cur.dst.n] <= i then
							-- a register has been set to a different value, that has been used previously: 
							--  We must recalculate in the next iteration ... 
							back_reg_chg = true
							-- ... from that point on:
							if first_iteration or startndx > first_refs[cur.dst.n] then 
								-- if we are in the first iteration or startndx has not been set 
								-- to a prior location than the first use of this destination register, 
								-- then we can safely assume, that it is sufficient, to recalculate from 
								-- there on in the next iteration.
								startndx = first_refs[cur.dst.n] -- only recalculate what may have changed
								-- uncomment the following line to inspect your FPGAs' behaviour in debug.txt. 
								-- (Dont forget to re-comment it later, for it produces a LOT of output!!)
								-- minetest.debug("FPGA at "..pos.x..","..pos.y..","..pos.z..": startndx = first_refs["..cur.dst.n.."] = "..startndx)
							end
						end
					end
				else -- cur.dst.type == "io"
					io_out[cur.dst.port] = result
				end
			end
		end
		reg_chk_cnt = reg_chk_cnt + 1
	until( (not back_reg_chg) or (reg_chk_cnt > 14)) -- Safe value - the highest that I could reach 
																	 -- by reverse-chaining register-assignments was 11.
	-- uncomment the following line to inspect your FPGAs' behaviour in debug.txt. 
	-- (Dont forget to re-comment it later, for it produces a lot of output!)
	-- minetest.debug("FPGA at "..pos.x..","..pos.y..","..pos.z.." iterated "..reg_chk_cnt.."times.")
	if reg_chk_cnt > 5 then -- a ms-jk flipflop (with two NOR rs-latches and two feedbacks) 
									-- like a counter normally performs in 2 iterations, sometimes 1, 
									-- sometimes 3. 5 Must be evil and can be reported. ;-) 
		minetest.debug("FPGA at "..pos.x..","..pos.y..","..pos.z.." does not behave well.")
	end
	return io_out.A, io_out.B, io_out.C, io_out.D
end

return lg
