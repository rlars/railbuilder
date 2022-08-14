
local function directions_to_tunnelmaker_index(horizontal_direction, vertical_direction)
	if vertical_direction == 1 then
		return (-horizontal_direction / 2) % 8 + 16
	elseif vertical_direction == -1 then
		return (-horizontal_direction / 2) % 8 + 24
	end
	return (-horizontal_direction) % 16
end

-- horizontal_direction is advtrains_direction
-- 
local function dig_tunnel(player, start_pos, horizontal_direction, vertical_direction)
	tunnelmaker.dig_tunnel(directions_to_tunnelmaker_index(horizontal_direction % 16, vertical_direction), player, { above = start_pos, under = vector.subtract(start_pos, vector.new(0, 1, 0)) })
end

local function is_supported_tunnelmaker_version()
	return tunnelmaker.dig_tunnel ~= nil
end

return {
	dig_tunnel = dig_tunnel,
	is_supported_tunnelmaker_version = is_supported_tunnelmaker_version,
}