-- HUD stuff and marker entities

math_helpers = dofile(railbuilder_path.."/math_helpers.lua");

-- first_person_offset from API is 0...
local FIRST_PERSON_EYE_OFFSET = vector.new(0, 1.5, 0)

local SelectionEntity = {
	conquer = true,
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = false,
		collisionbox = {-0.5, 0.05, -0.5, 0.5, 0.1, 0.5},
		visual_size = {x = 8, y = 2 },
		mesh = "conquer_selection_disc.obj",
		textures = { "conquer_selection_disc.png" },
		visual = "mesh",
		static_save = false,
		use_texture_alpha = true,
	},
}

function SelectionEntity:set_color(color, ratio)
	self.object:set_properties({
		textures = {
			("conquer_selection_disc.png^[colorize:%s:%d"):format(color, ratio or 200),
		},
	})
end

function SelectionEntity:on_activate()
	self.object:set_armor_groups({ immortal = 1 })
end

function SelectionEntity:on_detach()
	self.object:remove()
end


local function show_possible_endpoints(player, pos, color)
	return player:hud_add {
		hud_elem_type = "image_waypoint",
		scale={x=4,y=4},
		text = ("conquer_selection_disc.png^[colorize:%s:%d"):format(color, 200),
		world_pos = pos,
		z_index = -300,
	}
end


local function draw_debug_point(player, pos, color)
	return player:hud_add {
		hud_elem_type = "image_waypoint",
		scale={x=0.5,y=0.5},
		text = ("conquer_selection_disc.png^[colorize:%s:%d"):format(color, 200),
		world_pos = pos,
		z_index = -300,
	}
end

-- for vectors p, q, v, w find scalars r, s so that p + r*v - (q + s*w) takes the smallest value possible
local function min_distance_lines(p, v, q, w)
	local a = vector.dot(v, v)
	local b = vector.dot(v, w)
	local c = vector.dot(v, vector.subtract(q, p))
	local d = vector.dot(v, w)
	local e = vector.dot(w, w)
	local f = vector.dot(w, vector.subtract(q, p))
	return (b*f-c*e)/(b*d-a*e),(a*f-c*d)/(b*d-a*e)
end

-- for vectors p, q, v, w find scalars r, s so that p + r*v - (q + s*w) takes the smallest value possible
-- return p + r*v, q + s*w
local function closest_points_on_lines(p, v, q, w)
	local r, s = min_distance_lines(p, v, q, w)
	return vector.add( p, vector.multiply(v, r) ), vector.add( q, vector.multiply(w, s) )
end

local function trace_player_view(player, directions)
	local player_data = railbuilder.datastore.get_data(player)
	local start_pos = player_data.railbuilder_start_pos
	if start_pos and directions then
		local min_dist_found = 1E99
		local min_dist_point = vector.new(0, 0, 0)
		local first_person_eye_offset, third_person_offset = player:get_eye_offset()
		first_person_eye_offset = FIRST_PERSON_EYE_OFFSET
		local eye_pos = vector.add(player:get_pos(), first_person_eye_offset)
		local look_dir = player:get_look_dir()
		for _, direction in ipairs(directions) do
			local dir_vector = advtrain_helpers.rotation_index_and_vertical_direction_to_advtrains_dir(direction, player_data.railbuilder_desired_vertical_direction or 0)
			if dir_vector then
				-- hud marker is at the center of the node
				local p, q = closest_points_on_lines(start_pos, dir_vector, eye_pos, look_dir)
				local r, s = min_distance_lines(start_pos, dir_vector, eye_pos, look_dir)
				
				local dist = vector.length( vector.subtract(q, p) )
				if r > 0 and s > 0 and dist < min_dist_found then
					min_dist_found = dist
					min_dist_point = p
				end
			end
		end
		if player_data.ui.hud_track_preview_points.selected ~= nil then
			player:hud_change(player_data.ui.hud_track_preview_points.selected.id, "text", ("conquer_selection_disc.png^[colorize:%s:%d"):format("#44FF44", 200))
			player_data.ui.hud_track_preview_points.selected = nil
		end
		for _, point in ipairs(player_data.ui.hud_track_preview_points) do
			if vector.distance(point.pos, min_dist_point) < 0.5 then
				player:hud_change(point.id, "text", ("conquer_selection_disc.png^[colorize:%s:%d"):format("#FF0000", 200))
				player_data.ui.hud_track_preview_points.selected = point
			end
		end
	end
end

local function length_2d(v)
	return math.sqrt(v.x * v.x + v.z * v.z)
end

local function update_hud_track_preview_points(player, rail_start_pos, directions)

	local player_data = railbuilder.datastore.get_data(player)
	
	player_data.ui.hud_update_last_player_pos = player:get_pos()
	
	if #directions == 0 then return end
	
	local delta_pos = vector.subtract(player:get_pos(), rail_start_pos)
	local distance_to_start_pos_2d = length_2d(delta_pos)
	local normalized_delta_2d = vector.normalize(vector.new(delta_pos.x, 0, delta_pos.z))
	
	for _, direction in ipairs(directions) do
		local dir_step = advtrain_helpers.rotation_index_and_vertical_direction_to_advtrains_dir(direction, player_data.railbuilder_desired_vertical_direction or 0)
		if dir_step then
			if distance_to_start_pos_2d < 5 or vector.dot(normalized_delta_2d, dir_step) > 0 then
				local step_size = vector.length(dir_step)
				local end_i = 9 / step_size
				local step_multiplier = math.max(math.floor(distance_to_start_pos_2d / step_size - 1/2*end_i), 1)
				for i=0,end_i do
					local point_pos = vector.add(rail_start_pos, vector.multiply(dir_step, step_multiplier + i))
					table.insert(player_data.ui.hud_track_preview_points,
						{
							id = show_possible_endpoints(player, point_pos, "#44FF44"),
							pos = point_pos
						})
				end
			end
		end
	end
end

function update_hud(player, force)
	local player_data = railbuilder.datastore.get_data(player)
	local start_pos = player_data.railbuilder_start_pos

	if player:get_player_control().dig then
		force = update_slope_selection_ui(player) or force
	else
		hide_slope_selection_ui(player)
	end

	-- nothing to update if player did not move
	if force or vector.distance(player_data.ui.hud_update_last_player_pos, player:get_pos()) > 1 then
		remove_hud_track_preview_points(player)
		
		if is_start_marker_valid(player) then
			local directions = advtrain_helpers.get_advtrains_dirs(start_pos, player_data.railbuilder_last_direction, player_data.railbuilder_last_vertical_direction) or
					advtrain_helpers.get_closest_directions(player, start_pos)
			update_hud_track_preview_points(player, start_pos, directions)
			player_data.ui.hud_track_preview_directions = directions
		end
	end
	if is_start_marker_valid(player) then
		trace_player_view(player, player_data.ui.hud_track_preview_directions)
	end
end

local function remove_hud_points(player, hud_points)
	for _, hud_point in ipairs(hud_points) do
		player:hud_remove(hud_point.id)
	end
end

function remove_hud_track_preview_points(player)
	local player_data = railbuilder.datastore.get_data(player)
	if #player_data.ui.hud_track_preview_points > 0 then
		remove_hud_points(player, player_data.ui.hud_track_preview_points)
		player_data.ui.hud_track_preview_points = {}
	end
end

function highlight_point(player, directions)
	-- deselect last marked
	if last_marked_node then
	end
end

function get_selected_position(player)
	local player_data = railbuilder.datastore.get_data(player)
	if player_data.ui.hud_track_preview_points.selected then
		return player_data.ui.hud_track_preview_points.selected.pos
	end
	return nil
end


local function draw_slope_selection_point(player, pos, color)
	return player:hud_add {
		hud_elem_type = "image_waypoint",
		scale={x=2,y=2},
		text = ("conquer_selection_disc.png^[colorize:%s:%d"):format(color, 200),
		world_pos = pos,
		z_index = -300,
	}
end

local function init_slope_selection_ui(player)
	local player_data = railbuilder.datastore.get_data(player)
	-- store initial look_dir
	player_data.ui.slope_selection_initial_look_yaw = player:get_look_horizontal()
	player_data.ui.slope_selection_initial_look_pitch = player:get_look_vertical()
	player_data.ui.slope_selection_is_showing = true
end


local function slope_to_enum(slope)
	if math_helpers.is_number_close_to(slope, -1/2) then return 1
	elseif math_helpers.is_number_close_to(slope, -1/3) then return 2
	elseif math_helpers.is_number_close_to(slope, 1/3) then return 3
	elseif math_helpers.is_number_close_to(slope, 1/2) then return 4
	end
	return 0
end

-- update the nth point
local function update_slope_selection_nth_point(player, n)
	local player_data = railbuilder.datastore.get_data(player)
	for i, point in ipairs(player_data.ui.hud_slope_selection_points) do
		if i == n then
			player:hud_change(point.id, "text", ("conquer_selection_disc.png^[colorize:%s:%d"):format("#FF0000", 200))
		else
			player:hud_change(point.id, "text", ("conquer_selection_disc.png^[colorize:%s:%d"):format("#FFFFFF", 200))
		end
	end
end

function show_slope_selection_ui(player)
	init_slope_selection_ui(player)
	local player_data = railbuilder.datastore.get_data(player)
	local start_pos = player_data.railbuilder_start_pos
	if start_pos then
		table.insert(player_data.ui.hud_slope_selection_points,
		{
			id = draw_slope_selection_point(player, vector.add(start_pos, vector.new(0, -0.5, 0)), "#FFFFFF")
		})
		table.insert(player_data.ui.hud_slope_selection_points,
		{
			id = draw_slope_selection_point(player, vector.add(start_pos, vector.new(0, -1/3, 0)), "#FFFFFF")
		})
		table.insert(player_data.ui.hud_slope_selection_points,
		{
			id = draw_slope_selection_point(player, vector.add(start_pos, vector.new(0, 1/3, 0)), "#FFFFFF")
		})
		table.insert(player_data.ui.hud_slope_selection_points,
		{
			id = draw_slope_selection_point(player, vector.add(start_pos, vector.new(0, 0.5, 0)), "#FFFFFF")
		})
	end
end


-- update the hud points for slope selection
-- return true if selected slope changed
function update_slope_selection_ui(player)
	local player_data = railbuilder.datastore.get_data(player)
	if not player_data.ui.slope_selection_is_showing then
		return
	end
	local current_yaw = player:get_look_horizontal()
	local current_pitch = player:get_look_vertical()
	
	local desired_vertical_direction = player_data.railbuilder_desired_vertical_direction
	
	-- abort if too much to the side
	local yaw_diff_abs = math.abs(player_data.ui.slope_selection_initial_look_yaw - current_yaw)
	if yaw_diff_abs < 0.3 or yaw_diff_abs > 2 * math.pi - 0.3 then
		local pitch_diff = player_data.ui.slope_selection_initial_look_pitch - current_pitch
		if pitch_diff < -0.15 then
			desired_vertical_direction = -1/2
		elseif pitch_diff < -0.07 then
			desired_vertical_direction = -1/3
		elseif pitch_diff < 0.07 then
			desired_vertical_direction = 0
		elseif pitch_diff < 0.15 then
			desired_vertical_direction = 1/3
		else
			desired_vertical_direction = 1/2
		end
	end
	
	if player_data.railbuilder_desired_vertical_direction ~= desired_vertical_direction then
		player_data.railbuilder_desired_vertical_direction = desired_vertical_direction
		update_slope_selection_nth_point(player, slope_to_enum(desired_vertical_direction))
		return true
	end
	return false
end


function hide_slope_selection_ui(player)
	local player_data = railbuilder.datastore.get_data(player)
	if #player_data.ui.hud_slope_selection_points > 0 then
		remove_hud_points(player, player_data.ui.hud_slope_selection_points)
		player_data.ui.hud_slope_selection_points = {}
	end
	player_data.ui.slope_selection_is_showing = false
end

function set_start_marker(player, position, direction_delta)
	local player_data = railbuilder.datastore.get_data(player)
	local railbuilder_start_marker_pos = vector.new(position.x, position.y, position.z)
	-- for positive slope, move the start marker a little bit down
	if direction_delta and direction_delta.y > 0 then railbuilder_start_marker_pos.y = railbuilder_start_marker_pos.y - direction_delta.y end
	player_data.ui.railbuilder_start_marker = minetest.add_entity(railbuilder_start_marker_pos, "railbuilder:selection")
end

function remove_start_marker(player)
	local player_data = railbuilder.datastore.get_data(player)
	
	local old_start_marker = player_data.ui.railbuilder_start_marker
	
	player_data.ui.railbuilder_start_marker = nil
	old_start_marker:remove()
end

function is_start_marker_valid(player)
	local player_data = railbuilder.datastore.get_data(player)
	return player_data.ui.railbuilder_start_marker and player_data.ui.railbuilder_start_marker:get_luaentity() ~= nil
end

-- returns true if the start marker exists but is unloaded because it is too far away
function is_start_marker_lost(player)
	local player_data = railbuilder.datastore.get_data(player)
	return player_data.ui.railbuilder_start_marker and not player_data.ui.railbuilder_start_marker:get_luaentity()
end

minetest.register_entity("railbuilder:selection", SelectionEntity)

