

local function is_number_close_to(a, b, absolute_tolerance)
	if not absolute_tolerance then absolute_tolerance = 1e-7 end
	return math.abs(a - b) < absolute_tolerance
end

local function table_contains_number(t, compared_value, absolute_tolerance)
	return table.foreachi(t, function(_, table_value)
		if is_number_close_to(table_value, compared_value) then return true end
	end)
end

-- calculate the slope of a given vector
local function calc_slope(delta_pos)
	if delta_pos.x == 0 then return delta_pos.y / math.abs(delta_pos.z) end
	if delta_pos.z == 0 then return delta_pos.y / math.abs(delta_pos.x) end
	return delta_pos.y / math.abs(math.sqrt(1/2 * (delta_pos.x * delta_pos.x + delta_pos.z * delta_pos.z)))
end

-- return a vector with the step width of 1 or 2 in x and z dimension and a fractional y dimension
local function delta_to_dir(delta_pos)
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

return {
	calc_slope = calc_slope,
	delta_to_dir = delta_to_dir,
	is_number_close_to = is_number_close_to,
	table_contains_number = table_contains_number,
}