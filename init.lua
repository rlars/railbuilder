
railbuilder = {}
railbuilder_path = minetest.get_modpath("railbuilder")

advtrain_helpers = dofile(railbuilder_path.."/advtrain_helpers.lua");
tunnelmaker_helpers = dofile(railbuilder_path.."/tunnelmaker_helpers.lua");
math_helpers = dofile(railbuilder_path.."/math_helpers.lua");

dofile(railbuilder_path.."/railbuilder_datastore.lua");
dofile(railbuilder_path.."/railbuilder_ui.lua");

local S = minetest.get_translator "railbuilder"
local function quote_string(s)
	return string.format("%q", s)
end

-- tries to find values for last_direction from the underlying node
local function try_initialize_last_direction(player, pos)
	local player_data = railbuilder.datastore.get_data(player)
	local node = minetest.get_node(pos)
	player_data.railbuilder_last_direction, player_data.railbuilder_last_vertical_direction = advtrain_helpers.node_params_to_directions(node)
end

local function use_railbuilder_marker_tool(_, user, pointed_thing)
	local player_data = railbuilder.datastore.get_data(user)
	local target_pos = nil

	if get_selected_position(user) then
		target_pos = get_selected_position(user)
	elseif false and pointed_thing.type == "nothing" then
		local player_pos = vector.add(user:get_pos(),user:get_eye_offset())
		local destination = vector.add(player_pos, vector.multiply(user:get_look_dir(), 50))
		local hits = Raycast(player_pos, destination)
		local thing = hits:next()
		local hit = nil
		while thing do
			if thing.type == "node" then
				hit = thing
				break
			end
			thing = hits:next()
		end
		if hit == nil then
			return
		end
		target_pos = hit.above
	elseif pointed_thing.type == "node" then
		local node = minetest.get_node(pointed_thing.under)
		if advtrain_helpers.node_is_advtrains_rail(node) then
			target_pos = pointed_thing.under
		else
			target_pos = pointed_thing.above
		end
	else
		return
	end
	
	local did_try_build = false
	local did_build = false
	local direction_delta = nil
	
	if is_start_marker_valid(user) then
		did_try_build = true
		remove_start_marker(user)
		
		local railbuilder_start_pos = player_data.railbuilder_start_pos		
		local delta_pos = vector.subtract(target_pos, railbuilder_start_pos)
		direction_delta = delta_to_dir(delta_pos)
		local can_build = can_build_rail(railbuilder_start_pos, target_pos)

		if not tunnelmaker_helpers.is_supported_tunnelmaker_version() then
			minetest.chat_send_player(user:get_player_name(), "This version of tunnelmaker is not supported! Please update tunnelmaker.
			build_rail(user, railbuilder_start_pos, target_pos, true or delta_pos.y <= 0)
			did_build = true
			if delta_pos.y > 0 then
				-- set end pos to previous position
			end
			player_data.railbuilder_last_direction = advtrain_helpers.direction_delta_to_advtrains_conn(vector.subtract(target_pos, railbuilder_start_pos))
			player_data.railbuilder_last_vertical_direction = direction_delta.y
		else
			-- place a single rail if there is none already
			if vector.equals(railbuilder_start_pos, target_pos) and player_data.railbuilder_last_direction ~= nil then
				-- check target_pos and the one below if there is a rail
				if not advtrain_helpers.is_advtrains_rail_at_pos_or_below(target_pos) then
					minetest.set_node(target_pos, advtrain_helpers.direction_step_to_rail_params_sequence(advtrain_helpers.rotation_index_to_advtrains_dir(player_data.railbuilder_last_direction))())
				end
			end
			player_data.railbuilder_last_direction = nil
		end
	end
	
	-- eventually continue with showing marker for next track
	if not did_try_build or did_build then
		if not did_try_build then
			try_initialize_last_direction(user, target_pos)
			if advtrain_helpers.node_is_end_of_upper_slope(minetest.get_node(target_pos)) then
				target_pos.y = target_pos.y + 1
			end
		end
		player_data.railbuilder_start_pos = target_pos
		set_start_marker(user, target_pos, direction_delta)
	end
	
	update_hud(user, true)
end

function update_railbuilder_callback(dtime)

	for _, player in pairs(railbuilder.datastore.get_players()) do
		if is_start_marker_lost(player) then
			-- abort if start_pos was unloaded
			remove_start_marker(player)
			minetest.chat_send_player(player:get_player_name(), "Railbuilder: Start point is too far away, cancelling!")
			update_hud(player, true)
		else
			update_hud(player, false)
		end
	end
end

function can_build_rail(start_pos, end_pos)
	local valid_xz_ratios = { -2, -1, -0.5, 0.5, 1, 2 }
	local valid_dy_ratios = { -0.5, -1/3, 0, 1/3, 0.5 }
	local valid_xzy_ratios = { -0.5/math.sqrt(2), 0, 0.5/math.sqrt(2) }
	
	local delta_pos = vector.subtract(end_pos, start_pos)
	
	if delta_pos.x ~= 0 and delta_pos.z ~= 0 and math_helpers.table_contains_number(valid_xz_ratios, delta_pos.x / delta_pos.z) then
		if math.abs(delta_pos.x) == math.abs(delta_pos.z) then
			local xz = math.sqrt(delta_pos.x * delta_pos.x + delta_pos.z * delta_pos.z)
			return math_helpers.table_contains_number(valid_xzy_ratios, delta_pos.y/xz)
		end
		-- diagonal with 30 or 60 degrees must have 0 slope
		return delta_pos.y == 0
	end
	if delta_pos.x ~= 0 and delta_pos.z == 0 and math_helpers.table_contains_number(valid_dy_ratios, delta_pos.y / delta_pos.x) then
		return true
	end
	if delta_pos.x == 0 and delta_pos.z ~= 0 and math_helpers.table_contains_number(valid_dy_ratios, delta_pos.y / delta_pos.z) then
		return true
	end
	return false
end

--[[
Checks if it is "appropriate" to change the node at <pos> to <newnode>
Returns: new node (may be adjusted for e.g. turnouts or crossings), error message for the player
--]]
local function can_overwrite_track_at(pos, newnode)
	local oldnode = advtrains.ndb.get_node(pos)
	local oldname, oldparam2, newname, newparam2 = oldnode.name, oldnode.param2, newnode.name, newnode.param2
	local can_dig, errmsg = advtrains.can_dig_or_modify_track(pos)
	if not can_dig then
		return false, S("Cannot modify @1: @2", minetest.pos_to_string(pos), errmsg)
	end
	if oldname == newname and oldparam2 == newparam2 then
		return false
	end
	if not advtrains.is_track_and_drives_on(oldname) then
		return newnode
	end
	if not advtrains.is_track_and_drives_on(newname) then
		return false, S("@1 is not a track", quote_string(newname))
	end
	local oldconns, _, oldtype = advtrains.get_track_connections(oldname, oldparam2)
	local newconns, _, newtype = advtrains.get_track_connections(newname, newparam2)
	if oldtype ~= newtype then
		return false, S("The track at @1 is of a different type than @2", minetest.pos_to_string(pos), quote_string(newname))
	elseif #oldconns > #newconns then
		return false, S("@1 would not fit the track at @2", quote_string(newname), minetest.pos_to_string(pos))
	end
	if oldconns[3] and newconns[3] and type(oldconns[5]) ~= type(newconns[5]) then
		return false, S("@1 would not fit the track at @2", quote_string(newname), minetest.pos_to_string(pos))
	end
	return newnode
end

-- build a rail with a fixed direction
function build_rail(player, start_pos, end_pos, build_last_node)
	local delta_pos = vector.subtract(end_pos, start_pos)
	local rail_node_params_seq = advtrain_helpers.direction_step_to_rail_params_sequence(delta_pos)
	local direction_delta = delta_to_dir(delta_pos)
	local current_pos = table.copy(start_pos)
	current_pos.y = current_pos.y - 0.2 -- decrement a little bit, because y values will be rounded for slope placement
	local tunnelmaker_horizontal_direction = advtrain_helpers.direction_delta_to_advtrains_conn(direction_delta)
	
	-- skip first pos if there is already a rail
	local start_on_rail = advtrain_helpers.is_advtrains_rail_at_pos_or_below(start_pos)
	if direction_delta.y > 0 then
		-- dont build last node if building up and we start with a slope
		build_last_node = false
	elseif direction_delta.y < 0 then
		-- dont build first node if building down and we start with a slope
		current_pos = vector.add(current_pos, direction_delta)
	end
	
	local is_first = true

	while math.abs(current_pos.x - end_pos.x) > 1/2 or math.abs(current_pos.z - end_pos.z) > 1/2 do
		local tunnelmaker_vertical_direction = 0
		if math.floor(current_pos.y) ~= math.floor(current_pos.y - direction_delta.y) then
			tunnelmaker_vertical_direction = math.sign(direction_delta.y)
		end
		tunnelmaker_helpers.dig_tunnel(player, current_pos, tunnelmaker_horizontal_direction, tunnelmaker_vertical_direction)
		local place_current, errmsg = can_overwrite_track_at(current_pos, rail_node_params_seq())
		if place_current then
			advtrains.ndb.swap_node(current_pos, place_current)
			if is_first then
				advtrain_helpers.try_bend_rail_start(start_pos, direction_delta)
			end
		end
		if errmsg then
			minetest.chat_send_player(player:get_player_name(), errmsg)
		end
		is_first = false
		current_pos = vector.add(current_pos, direction_delta)
	end
	
	-- place last node only if building on same level or down, as the end point is the start of a ramp
	if build_last_node then
		tunnelmaker_helpers.dig_tunnel(player, current_pos, tunnelmaker_horizontal_direction, 0)
		advtrains.ndb.swap_node(current_pos, rail_node_params_seq())
	
		-- if only one rail is placed, then this was not called yet
		if is_first then
			-- bend start rail (if any)
			advtrain_helpers.try_bend_rail_start(start_pos, direction_delta)
		end
	end
end

function on_use_callback(_, user, pointed_thing)
	show_slope_selection_ui(user)
end


minetest.register_craftitem("railbuilder:trackmarker", {
	description = "Move",
	inventory_image = "railbuilder_trackmarker.png",
	on_use = on_use_callback,
	on_secondary_use = use_railbuilder_marker_tool,
	on_place = use_railbuilder_marker_tool

})

minetest.register_globalstep(update_railbuilder_callback)
