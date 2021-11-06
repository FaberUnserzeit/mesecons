return function(plg, lcore)


minetest.register_tool("mesecons_fpga:programmer", {
	description = "FPGA Programmer",
	inventory_image = "jeija_fpga_programmer.png",
	stack_max = 1,
	on_place = function(itemstack, placer, pointed_thing)
		if pointed_thing.type ~= "node" then
			return itemstack
		end

		local pos = pointed_thing.under
		if minetest.get_node(pos).name:find("mesecons_fpga:fpga") ~= 1 then
			return itemstack
		end

		local meta = minetest.get_meta(pos)
		local instr = meta:get_string("instr") or ""
		if instr == "//////////////" or instr == "" then
			minetest.chat_send_player(placer:get_player_name(), "This FPGA is unprogrammed.")
			minetest.sound_play("mesecons_fpga_fail", { pos = placer:get_pos(), gain = 0.1, max_hear_distance = 4 }, true)
			return itemstack
		end
		local name_s = meta:get_string("name_s") or ""
		local desc_s = meta:get_string("desc_s") or ""
		minetest.debug("Read name_s via meta:get_string():" .. name_s)
		minetest.debug("Read desc_s via meta:get_string():" .. desc_s)

		local imeta = itemstack:get_meta()
		imeta:set_string("instr", instr)
		minetest.debug("Called imeta:set_string('instr', '" .. instr .. "')")
		imeta:set_string("infotext", "FPGA-Programmer " .. name_s)
		imeta:set_string("description", "FPGA-Programmer " .. name_s)
		imeta:set_string("name_s", name_s)
		imeta:set_string("desc_s", desc_s)

		minetest.chat_send_player(placer:get_player_name(), "FPGA gate configuration was successfully copied!")
		minetest.sound_play("mesecons_fpga_copy", { pos = placer:get_pos(), gain = 0.1, max_hear_distance = 4 }, true)
		return itemstack
	end,
	on_use = function(itemstack, user, pointed_thing)
		if pointed_thing.type ~= "node" then
			return itemstack
		end

		local pos = pointed_thing.under
		if minetest.get_node(pos).name:find("mesecons_fpga:fpga") ~= 1 then
			return itemstack
		end
		local player_name = user:get_player_name()
		if minetest.is_protected(pos, player_name) then
			minetest.record_protection_violation(pos, player_name)
			return itemstack
		end

		local imeta = itemstack:get_meta()
		local instr = imeta:get_string("instr") or ""
		if instr == "" then
			minetest.chat_send_player(player_name, "Use shift+right-click to copy a gate configuration first.")
			minetest.sound_play("mesecons_fpga_fail", { pos = user:get_pos(), gain = 0.1, max_hear_distance = 4 }, true)
			return itemstack
		end
		minetest.debug("tool.lua:60: " .. instr)
		local is = lcore.deserialize(instr)
		local name_s = imeta:get_string("name_s") or ""
		local desc_s = imeta:get_string("desc_s") or ""

		local meta = minetest.get_meta(pos)
		meta:set_string("instr", instr)
		meta:set_string("name_s", name_s)
		meta:set_string("desc_s", desc_s)

		plg.update_meta(pos, is, name_s, desc_s)
		minetest.chat_send_player(player_name, "Gate configuration was successfully written to FPGA!")
		minetest.sound_play("mesecons_fpga_write", { pos = user:get_pos(), gain = 0.1, max_hear_distance = 4 }, true)

		return itemstack
	end
})

minetest.register_craft({
	output = "mesecons_fpga:programmer",
	recipe = {
		{'group:mesecon_conductor_craftable'},
		{'mesecons_materials:silicon'},
	}
})


end
