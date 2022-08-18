math_helpers = dofile(railbuilder_path.."/math_helpers.lua");

ADVTRAINS_RAILS_STRAIGHT2 = { "advtrains:dtrack_vst1", "advtrains:dtrack_vst2" }
ADVTRAINS_RAILS_STRAIGHT3 = { "advtrains:dtrack_vst31", "advtrains:dtrack_vst32", "advtrains:dtrack_vst33" }
ADVTRAINS_RAILS_DIAGONAL = { "advtrains:dtrack_vst1_45", "advtrains:dtrack_vst2_45" }

-- calculate the slope of a given vector
function calc_slope(delta_pos)
	if delta_pos.x == 0 then return delta_pos.y / math.abs(delta_pos.z) end
	if delta_pos.z == 0 then return delta_pos.y / math.abs(delta_pos.x) end
	return delta_pos.y / math.abs(math.sqrt(1/2 * (delta_pos.x * delta_pos.x + delta_pos.z * delta_pos.z)))
end

-- return a vector with the step width of 1 or 2 in x and z dimension and a fractional y dimension
function delta_to_dir(delta_pos)
	local slope = calc_slope(delta_pos)
	if delta_pos.x == 0 then return vector.new(0, slope, math.sign(delta_pos.z)) end
	if delta_pos.z == 0 then return vector.new(math.sign(delta_pos.x), slope, 0) end
	if math.abs(delta_pos.x) == 2 * math.abs(delta_pos.z) then
		return vector.new(2 * math.sign(delta_pos.x), slope, math.sign(delta_pos.z))
	end	
	if 2 * math.abs(delta_pos.x) == math.abs(delta_pos.z) then
		return vector.new(math.sign(delta_pos.x), slope, 2 * math.sign(delta_pos.z))
	end
	return vector.new(math.sign(delta_pos.x), slope, math.sign(delta_pos.z))
end

local function node_is_advtrains_rail(node)
	return advtrains.is_track_and_drives_on(node.name)
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
-- rotation_index values -7 to 8
local function rotation_index_to_advtrains_dir(rotation_index)
	local rotation_index_mod = rotation_index % 4
	local rotation_index_whole = math.floor(rotation_index / 4)
	
	local v = nil
	if rotation_index_mod == 0 then
		v = vector.new(0, 0, 1)
	elseif rotation_index_mod == 1 then
		v = vector.new(1, 0, 2)
	elseif rotation_index_mod == 2 then
		v = vector.new(1, 0, 1)
	elseif rotation_index_mod == 3 then
		v = vector.new(2, 0, 1)
	end
	local rot_v = vector.rotate(v, { x = 0, y = rotation_index_whole * math.pi / 2, z = 0 })
	if rotation_index_whole == 1 or rotation_index_whole == 3 then
		-- some bug in Minetest version 5.4 ...
		return vector.subtract(vector.new(), rot_v)
	end
	return rot_v
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

-- TODO: tried with rail_and_can_be_bent from advtrains/trackplacer.lua first, but this did not work - can we improve this?
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
	
	--if false then return p_rails end
	--p_rails = {}
	--tp = advtrains.trackplacer
	--for i = 0, 15 do
	--	pos = vector.add(original_pos, rotation_index_to_advtrains_dir(i))
	--	if tp.rail_and_can_be_bent(pos, (i+8)%16) then
	--		table.insert(p_rails, i)
	--	end
	--end
	return p_rails
end

-- returns closure that generates item name and params to place a rail in the given direction
local function direction_step_to_rail_params_sequence(dir_step)
	local rotation_index = direction_delta_to_advtrains_conn(dir_step) -- maps to values from [0 to 15]
	local rotation_index_mod = rotation_index % 4
	local rotation_index_whole = math.floor(rotation_index / 4)
	if dir_step.y == 0 then
		local rail_name = nil
		if rotation_index_mod == 0 then
			rail_name = "advtrains:dtrack_st"
		end
		if rotation_index_mod == 1 then
			rail_name = "advtrains:dtrack_st_30"
		end
		if rotation_index_mod == 2 then
			rail_name = "advtrains:dtrack_st_45"
		end
		if rotation_index_mod == 3 then
			rail_name = "advtrains:dtrack_st_60"
		end
		return function()
			return { name=rail_name, param1=14, param2=rotation_index_whole }
		end
	else
		local slope = calc_slope(dir_step)
		if dir_step.y < 0 then
			rotation_index_whole = (rotation_index_whole + 2) % 4
		end
		local rail_node_names = nil
		if rotation_index_mod == 0 and math_helpers.is_number_close_to(math.abs(slope), 0.5) then
			rail_node_names = ADVTRAINS_RAILS_STRAIGHT2
		elseif rotation_index_mod == 0 and math_helpers.is_number_close_to(math.abs(slope), 1/3) then
			rail_node_names = ADVTRAINS_RAILS_STRAIGHT3
		elseif rotation_index_mod == 2 then
			rail_node_names = ADVTRAINS_RAILS_DIAGONAL
		end
		local increment = math.sign(dir_step.y)
		local rail_name_table_length = #rail_node_names
		local i = (increment == -1 and rail_name_table_length - 1) or 0
		return function()
			local rail_name = rail_node_names[i + 1]
			i = (i + increment) % rail_name_table_length
			return { name=rail_name, param1=14, param2=rotation_index_whole }
		end
	end
end

local function try_bend_rail_start(start_pos, direction_delta)
	if advtrains.trackplacer then
		advtrains.trackplacer.bend_rail(vector.add(start_pos, direction_delta), (8 + advtrain_helpers.direction_delta_to_advtrains_conn(direction_delta)) % 16)
	end
end

-- rturns a pair of booleans indicating if the rails in the direction or its opposite are connected
local function find_already_connected(pos)
	if advtrains.trackplacer then
		return advtrains.trackplacer.find_already_connected(pos, direction)
	end
	return false, false
end

local function node_is_end_of_upper_slope(node)
	return table.indexof(ADVTRAINS_RAILS_STRAIGHT2, node.name) == 2 or
			table.indexof(ADVTRAINS_RAILS_STRAIGHT3, node.name) == 3 or
			table.indexof(ADVTRAINS_RAILS_DIAGONAL, node.name) == 2
end

-- return horizontal direction in [0, 15] and vertical direction in {-1/2,-1/3,0,1/3,1/2}
local function node_params_to_directions(node)
	local mod4offset = 0
	local vertical_direction = 0
	if node.name == "advtrains:dtrack_st_30" then mod4offset = 1
	elseif node.name == "advtrains:dtrack_st_45" then mod4offset = 2
	elseif node.name == "advtrains:dtrack_st_60" then mod4offset = 3
	elseif table.indexof(ADVTRAINS_RAILS_STRAIGHT2, node.name) == 1 then vertical_direction = -1/2
	elseif table.indexof(ADVTRAINS_RAILS_STRAIGHT2, node.name) == 2 then vertical_direction = 1/2
	elseif table.indexof(ADVTRAINS_RAILS_STRAIGHT3, node.name) == 1 then vertical_direction = -1/3
	elseif table.indexof(ADVTRAINS_RAILS_STRAIGHT3, node.name) == 3 then vertical_direction = 1/3
	elseif table.indexof(ADVTRAINS_RAILS_DIAGONAL, node.name) > 0 then
		mod4offset = 2
		if table.indexof(ADVTRAINS_RAILS_DIAGONAL, node.name) == 1 then vertical_direction = -1/2
		else vertical_direction = 1/2
		end
	end
	-- invert direction if lower end of ramp
	if vertical_direction < 0 then mod4offset = mod4offset + 8 end
	return (node.param2 * 4 + mod4offset) % 16, vertical_direction
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
	node_params_to_directions = node_params_to_directions,
}
