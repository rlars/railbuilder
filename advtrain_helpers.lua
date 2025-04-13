math_helpers = dofile(railbuilder_path.."/math_helpers.lua");

local known_track_styles = {{ ui_name="AdvTrains", node_prefix="advtrains:dtrack"}, { ui_name="Tieless", node_prefix="advtrains:dtrack_tieless"}, }

local advtrains_track_flat_suffix = advtrains.ap.t_30deg_flat.rotation
local advtrains_track_slope_straight2_suffix = advtrains.ap.t_30deg_slope.slopeplacer[2]
local advtrains_track_slope_straight3_suffix = advtrains.ap.t_30deg_slope.slopeplacer[3]
local advtrains_track_slope_diagonal_suffix = advtrains.ap.t_30deg_slope.slopeplacer_45[2]

local function node_is_advtrains_rail(node)
	if advtrains.is_track then
		return advtrains.is_track(node.name)
	else -- advtrains < 2.5.0
		return advtrains.is_track_and_drives_on(node.name)
	end
end

local function is_advtrains_rail_at_pos_or_below(pos)
	return node_is_advtrains_rail(minetest.get_node(pos)) or node_is_advtrains_rail(minetest.get_node(vector.subtract(pos, vector.new(0, 1, 0))))
end

-- returns advtrains connection index (a value from 0 to 15)
local function direction_delta_to_advtrains_conn(direction_delta)
	return (math.floor(math.atan2(direction_delta.x,direction_delta.z) / math.pi * 8 + 0.5)) % 16
end

-- create a list of steps that can be added when showing possible end points
-- calculate the direction depending on current player position
local function get_closest_directions(player, rail_start_pos)
	local delta_pos = vector.subtract(player:get_pos(), rail_start_pos)
	local rotation_index = direction_delta_to_advtrains_conn(delta_pos)
	local out_directions = {}
	for i=-1,1 do
		table.insert(out_directions, (rotation_index + i) % 16)
	end
	return out_directions
end

-- generate a vector in the plain
-- rotation_index values 0 to 15
local function rotation_index_to_advtrains_dir(rotation_index)
	return advtrains.dir_to_vector(rotation_index)
end

-- generate a vector in 3D
-- rotation_index values -7 to 8
-- vertical_direction values in {- 1/2, -1/3, 0, 1/3, 1/2}
local function rotation_index_and_vertical_direction_to_advtrains_dir(rotation_index, vertical_direction)
	local plain_dir = rotation_index_to_advtrains_dir(rotation_index)
	if vertical_direction == 0 then
		return plain_dir
	elseif rotation_index % 4 == 0 then
		-- straights have two possible inclinations
		local multiplier = 1/math.abs(vertical_direction)
		return vector.multiply( vector.add(plain_dir, vector.new(0, vertical_direction, 0)), multiplier)
	elseif rotation_index % 4 == 2 then
		return vector.multiply( vector.add(plain_dir, vector.new(0, math.sign(vertical_direction)*1/2, 0)), 2)
	else
		return nil
	end
end

-- returns possible directions starting from a given track at pos
local function get_advtrains_dirs(original_pos, last_horizontal_direction, last_vertical_direction)
	local p_rails={}
	local p_railpos={}
	local node = minetest.get_node(original_pos)
	if last_vertical_direction and last_vertical_direction ~= 0 then
		table.insert(p_rails, last_horizontal_direction)
		return p_rails
	end
	
	if not node or not node_is_advtrains_rail(node) then return nil end
	
	local cconns=advtrains.get_track_connections(node.name, node.param2)
	for _, conn in ipairs(cconns) do
		table.insert(p_rails, conn.c)
	end

	if #p_rails == 2 then
		local a = p_rails[1]
		local b = p_rails[2]
		local diff = (a-b)%8
		local more_conns = nil
		if diff == 0 then
			more_conns = {(a-1) % 16, (a+1) % 16, (b-1) % 16, (b+1) % 16}
		end
		if diff == 7 then
			more_conns = {(a+1) % 16, (a+2) % 16, (b-2) % 16, (b-1) % 16}
		end
		if diff == 1 then
			more_conns = {(a-2) % 16, (a-1) % 16, (b+1) % 16, (b+2) % 16}
		end
		table.insert_all(p_rails, more_conns)
	end


	return p_rails
end

local function make_slope_node_names(name_prefix, suffix_list)
	local names = {}
	for _, suffix in ipairs(suffix_list) do
		table.insert(names, name_prefix .. "_" .. suffix)
	end

	return names
end

-- returns closure that generates item name and params to place a rail in the given direction
local function direction_step_to_rail_params_sequence(dir_step, name_prefix)
	local rotation_index = direction_delta_to_advtrains_conn(dir_step) -- maps to values from [0 to 15]
	local rotation_index_mod = rotation_index % 4
	local rotation_index_whole = math.floor(rotation_index / 4)
	if dir_step.y == 0 then
		local rail_name = name_prefix .. "_st" .. advtrains_track_flat_suffix[rotation_index_mod + 1]
		return function()
			return { name=rail_name, param1=14, param2=rotation_index_whole }
		end
	else
		local slope = math_helpers.calc_slope(dir_step)
		if dir_step.y < 0 then
			rotation_index_whole = (rotation_index_whole + 2) % 4
		end
		local rail_node_names = nil
		if rotation_index_mod == 0 and math_helpers.is_number_close_to(math.abs(slope), 0.5) then
			rail_node_names = make_slope_node_names(name_prefix, advtrains_track_slope_straight2_suffix)
		elseif rotation_index_mod == 0 and math_helpers.is_number_close_to(math.abs(slope), 1/3) then
			rail_node_names = make_slope_node_names(name_prefix, advtrains_track_slope_straight3_suffix)
		elseif rotation_index_mod == 2 then
			rail_node_names = make_slope_node_names(name_prefix, advtrains_track_slope_diagonal_suffix)
		end
		local increment = math.sign(dir_step.y)
		local rail_name_table_length = #rail_node_names
		local i = (increment == -1 and -1) or 0
		return function()
			local rail_name = rail_node_names[i%rail_name_table_length + 1]
			local dy = i
			i = i + increment
			return { name=rail_name, param1=14, param2=rotation_index_whole }, dy/rail_name_table_length
		end, rail_name_table_length
	end
end

local function try_bend_rail_start(start_pos, player, track_node_prefix)
	if advtrains.trackplacer then
		if advtrains.trackplacer.place_track then
			advtrains.trackplacer.place_track(start_pos, track_node_prefix, player:get_player_name(), player:get_look_horizontal())
		else
			minetest.log("warning", "Cannot bend start rail, please upgrade advtrains!")
		end
	end
end

-- returns a pair of booleans indicating if the rails in the direction or its opposite are connected
local function find_already_connected(pos)
	if advtrains.trackplacer then
		return advtrains.trackplacer.find_already_connected(pos, direction)
	end
	return false, false
end

-- return horizontal direction in [0, 15] and vertical direction in {-1/2,-1/3,0,1/3,1/2}
local function node_params_to_directions(node, get_opposite)
	if not node_is_advtrains_rail(node) then return nil, nil end
	local conns, _ = advtrains.get_track_connections(node.name, node.param2)
	local adv_hor = get_opposite and conns[2].c or conns[1].c
	local adv_vert = conns[1].y and (conns[1].y - conns[2].y) or 0
	if adv_vert >= -0.34 and adv_vert <= -0.33 then adv_vert = -1/3 end
	if adv_vert >= 0.33 and adv_vert <= 0.34 then adv_vert = 1/3 end
	return adv_hor, adv_vert
end

local function node_is_end_of_upper_slope(node)
	if not node_is_advtrains_rail(node) then return nil end
	local conns, _ = advtrains.get_track_connections(node.name, node.param2)
	return #conns >= 2 and (conns[1].y == 1 or conns[2].y == 1)
end

local function node_is_slope(node)
	if not node_is_advtrains_rail(node) then return nil end
	local conns, _ = advtrains.get_track_connections(node.name, node.param2)
	return #conns >= 2 and (conns[1].y ~= conns[2].y)
end

local function get_track_prefix(player_data)
	return player_data.track_style or known_track_styles[1].node_prefix
end

return {
	node_is_advtrains_rail = node_is_advtrains_rail,
	is_advtrains_rail_at_pos_or_below = is_advtrains_rail_at_pos_or_below,
	direction_delta_to_advtrains_conn = direction_delta_to_advtrains_conn,
	get_closest_directions = get_closest_directions,
	rotation_index_to_advtrains_dir = rotation_index_to_advtrains_dir,
	rotation_index_and_vertical_direction_to_advtrains_dir = rotation_index_and_vertical_direction_to_advtrains_dir,
	get_advtrains_dirs = get_advtrains_dirs,
	direction_step_to_rail_params_sequence = direction_step_to_rail_params_sequence,
	try_bend_rail_start = try_bend_rail_start,
	find_already_connected = find_already_connected,
	node_is_end_of_upper_slope = node_is_end_of_upper_slope,
	node_is_slope = node_is_slope,
	node_params_to_directions = node_params_to_directions,
	known_track_styles = known_track_styles,
	get_track_prefix = get_track_prefix,
}
