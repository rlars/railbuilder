
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
			minetest.chat_send_player(user:get_player_name(), "This version of tunnelmaker is not supported! Please update tunnelmaker.")
		elseif can_build then
			build_rail(user, railbuilder_start_pos, target_pos)
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

local function can_dig(pos, player)
	return (minetest.registered_nodes[advtrains.ndb.get_node(pos).name].can_dig or function() return true end)(pos, player)
end

--[[
Checks if it is "appropriate" to change the node at <pos> to <newnode>
Returns: new node (may be adjusted for e.g. turnouts or crossings), error message for the player
--]]
local function can_overwrite_track_at(player, pos, newnode, no_overwrite)
	local oldnode = advtrains.ndb.get_node(pos)
	local oldname, oldparam2, newname, newparam2 = oldnode.name, oldnode.param2, newnode.name, newnode.param2
	local oldndef = minetest.registered_nodes[oldname]
	if not can_dig(pos, player) then
		return false, S("Cannot modify the node at @1", minetest.pos_to_string(pos))
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
	if next(oldndef.advtrains or {}) ~= nil then
		return false, S("the track at @1 is a feature track", minetest.pos_to_string(pos))
	end
	local oldconns, _, oldtype = advtrains.get_track_connections(oldname, oldparam2)
	local newconns, _, newtype = advtrains.get_track_connections(newname, newparam2)
	if oldtype and no_overwrite then
		return false
	end
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

local function try_build(player, pos, newnode, no_overwrite)
	local place_current, errmsg = can_overwrite_track_at(player, pos, newnode, no_overwrite)
	if place_current then
		advtrains.ndb.swap_node(pos, place_current)
	end
	if errmsg then
		if not place_current then
			errmsg = S("Not modifying @1: @2", minetest.pos_to_string(pos), errmsg)
		end
		minetest.chat_send_player(player:get_player_name(), errmsg)
	end
	return place_current
end

-- build a rail with a fixed direction
function build_rail(player, start_pos, end_pos)
	local delta_pos = vector.subtract(end_pos, start_pos)
	local rail_node_params_seq, slope_length = advtrain_helpers.direction_step_to_rail_params_sequence(delta_pos)
	local direction_delta = delta_to_dir(delta_pos)
	local current_pos = table.copy(start_pos)
	local tunnelmaker_horizontal_direction = advtrain_helpers.direction_delta_to_advtrains_conn(direction_delta)
	
	local step_delta = vector.new(direction_delta.x, 0, direction_delta.z)

	local total_step_count = 0

	if direction_delta.x ~= 0 then
		total_step_count = math.floor(delta_pos.x / direction_delta.x)
	else
		total_step_count = math.floor(delta_pos.z / direction_delta.z)
	end

	local build_count, build_successful_count = 0, 0

	if advtrain_helpers.is_advtrains_rail_at_pos_or_below(start_pos) then
		current_pos = vector.add(current_pos, step_delta)
	elseif direction_delta.y == 0 then
		total_step_count = total_step_count + 1
	end

	local y_shift_at = (direction_delta.y < 0 and 0) or 1

	while build_count < total_step_count do
		local node, dy = rail_node_params_seq()
		dy = dy or 0
		local ry = math.floor(dy)
		local rounded_pos = vector.add(current_pos, vector.new(0, ry, 0))
		local tunnelmaker_vertical_direction = 0
		if slope_length and build_count%slope_length == y_shift_at then
			tunnelmaker_vertical_direction = math.sign(direction_delta.y)
		end
		tunnelmaker_helpers.dig_tunnel(player, rounded_pos, tunnelmaker_horizontal_direction, tunnelmaker_vertical_direction)
		local built = try_build(player, rounded_pos, node, build_count == 0)
		build_count = build_count + 1
		if built then
			build_successful_count = build_successful_count + 1
		end
		current_pos = vector.add(current_pos, step_delta)
	end
	if build_count > 0 then
		advtrain_helpers.try_bend_rail_start(start_pos, direction_delta)
	end
	minetest.chat_send_player(player:get_player_name(), S("Successfully built @1 piece(s) of tracks (expected @2 total)", build_successful_count, build_count))
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
