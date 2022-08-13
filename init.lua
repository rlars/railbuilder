
railbuilder = {}
railbuilder_path = minetest.get_modpath("railbuilder")

advtrain_helpers = dofile(railbuilder_path.."/advtrain_helpers.lua");
tunnelmaker_helpers = dofile(railbuilder_path.."/tunnelmaker_helpers.lua");

dofile(railbuilder_path.."/railbuilder_datastore.lua");
dofile(railbuilder_path.."/railbuilder_ui.lua");


-- tries to find values for last_direction from the underlying node
local function try_initialize_last_direction(player, pos)
	player_data = railbuilder.datastore.get_data(player)
	node = minetest.get_node(pos)
	player_data.railbuilder_last_direction, player_data.railbuilder_last_vertical_direction = advtrain_helpers.node_params_to_directions(node)
end

local function use_railbuilder_marker_tool(_, user, pointed_thing)
	player_data = railbuilder.datastore.get_data(user)
	
	if get_selected_position(user) then
		target_pos = get_selected_position(user)
	elseif false and pointed_thing.type == "nothing" then
		player_pos = vector.add(user:get_pos(),user:get_eye_offset())
		destination = vector.add(player_pos, vector.multiply(user:get_look_dir(), 50))
		hits = Raycast(player_pos, destination)
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
	
	did_try_build = false
	did_build = false
	
	if player_data.railbuilder_start_marker then
		did_try_build = true
		remove_railbuilder_start_marker(user)
		
		railbuilder_start_pos = player_data.railbuilder_start_pos		
		delta_pos = vector.subtract(target_pos, railbuilder_start_pos)
		direction_delta = delta_to_dir(delta_pos)
		can_build = can_build_rail(railbuilder_start_pos, target_pos)
		if can_build then
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
		-- assert player_data.railbuilder_start_marker == nil
		-- check if there is already a track
		-- TODO: get direction from node on first use
		-- adj1, adj2 = advtrain_helpers.find_already_connected(target_pos, player_data.railbuilder_last_direction)
		railbuilder_start_marker_pos = vector.new(target_pos.x, target_pos.y, target_pos.z) --table.copy(target_pos)
		-- for positive slope, move the start marker a little bit down
		if direction_delta and direction_delta.y > 0 then railbuilder_start_marker_pos.y = railbuilder_start_marker_pos.y - direction_delta.y end
		railbuilder_start_marker = minetest.add_entity(railbuilder_start_marker_pos, "railbuilder:selection")
		player_data.railbuilder_start_pos = target_pos
		player_data.railbuilder_start_marker = railbuilder_start_marker
	end
	
	update_hud(user, true)
end

function update_railbuilder_callback(dtime)

	for _, player in pairs(railbuilder.datastore.get_players()) do
	
		player_data = railbuilder.datastore.get_data(player)
		
		if player_data.railbuilder_start_marker and not player_data.railbuilder_start_marker:get_luaentity() then
			-- abort if start_pos was unloaded
			remove_railbuilder_start_marker(user)
			minetest.chat_send_player(player:get_player_name(), "Railbuilder: Start point is too far away, cancelling!")
			update_hud(player, force)
			return
		end
		
		
		force_by_slope_selection_ui = false
		-- slope ui
		if player:get_player_control().dig then
			force_by_slope_selection_ui = update_slope_selection_ui(player)
		else
			hide_slope_selection_ui(player)
		end
		
		update_hud(player, force_by_slope_selection_ui)
	end
end

function can_build_rail(start_pos, end_pos)
	valid_xz_ratios = { -2, -1, -0.5, 0.5, 1, 2 }
	valid_dy_ratios = { -0.5, -1/3, 0, 1/3, 0.5 }
	valid_xzy_ratios = { -0.5/math.sqrt(2), 0, 0.5/math.sqrt(2) }
	
	delta_pos = vector.subtract(end_pos, start_pos)
	
	if delta_pos.x ~= 0 and delta_pos.z ~= 0 and table.indexof(valid_xz_ratios, delta_pos.x / delta_pos.z) ~= -1 then
		if math.abs(delta_pos.x) == math.abs(delta_pos.z) then
			xz = math.sqrt(delta_pos.x * delta_pos.x + delta_pos.z * delta_pos.z)
			return table.indexof(valid_xzy_ratios, delta_pos.y/xz) ~= -1
		end
		-- diagonal with 30 or 60 degrees must have 0 slope
		return delta_pos.y == 0
	end
	if delta_pos.x ~= 0 and delta_pos.z == 0 and table.indexof(valid_dy_ratios, delta_pos.y / delta_pos.x) ~= -1 then
		return true
	end
	if delta_pos.x == 0 and delta_pos.z ~= 0 and table.indexof(valid_dy_ratios, delta_pos.y / delta_pos.z) ~= -1 then
		return true
	end
	return false
end

-- build a rail with a fixed direction
function build_rail(player, start_pos, end_pos, build_last_node)
	delta_pos = vector.subtract(end_pos, start_pos)
	rail_node_params_seq = advtrain_helpers.direction_step_to_rail_params_sequence(delta_pos)
	direction_delta = delta_to_dir(delta_pos)
	current_pos = table.copy(start_pos)
	current_pos.y = current_pos.y - 0.2 -- decrement a little bit, because y values will be rounded for slope placement
	tunnelmaker_horizontal_direction = advtrain_helpers.direction_delta_to_advtrains_conn(direction_delta)
	
	-- skip first pos if there is already a rail
	start_on_rail = advtrain_helpers.is_advtrains_rail_at_pos_or_below(start_pos)
	if advtrain_helpers.is_advtrains_rail_at_pos_or_below(start_pos) then
		current_pos = vector.add(current_pos, direction_delta)
		if direction_delta.y > 0 then
			current_pos.y = current_pos.y - direction_delta.y
		end
	elseif direction_delta.y > 0 then
		-- dont build last node if building up and we start with a slope
		build_last_node = false
	elseif direction_delta.y < 0 then
		-- dont build first node if building down and we start with a slope
		current_pos = vector.add(current_pos, direction_delta)
	end
	
	is_first = true
	
	while math.abs(current_pos.x - end_pos.x) > 1/2 or math.abs(current_pos.z - end_pos.z) > 1/2 do
		tunnelmaker_vertical_direction = 0
		if math.floor(current_pos.y) ~= math.floor(current_pos.y - direction_delta.y) then
			tunnelmaker_vertical_direction = signum(direction_delta.y)
		end
		tunnelmaker_helpers.dig_tunnel(player, current_pos, tunnelmaker_horizontal_direction, tunnelmaker_vertical_direction)
		minetest.set_node(current_pos, rail_node_params_seq())
		if is_first then
			advtrain_helpers.try_bend_rail_start(start_pos, direction_delta)
			is_first = false
		end
		current_pos = vector.add(current_pos, direction_delta)
	end
	
	-- place last node only if building on same level or down, as the end point is the start of a ramp
	if build_last_node then
		tunnelmaker_helpers.dig_tunnel(player, current_pos, tunnelmaker_horizontal_direction, 0)
		minetest.set_node(current_pos, rail_node_params_seq())
	
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
