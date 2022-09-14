

local function is_number_close_to(a, b, absolute_tolerance)
	if not absolute_tolerance then absolute_tolerance = 1e-7 end
	return math.abs(a - b) < absolute_tolerance
end

local function table_contains_number(t, compared_value, absolute_tolerance)
	return table.foreachi(t, function(_, table_value)
		if is_number_close_to(table_value, compared_value) then return true end
	end)
end

return {
	is_number_close_to = is_number_close_to,
	table_contains_number = table_contains_number,
}