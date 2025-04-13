
local datastore = {
	_data = {}
}

function datastore.get_players()
	local players = {}
	for player, _ in pairs(datastore._data) do
		table.insert(players, player)
	end
	return players
end

-- returns write-accessible data for specified player
-- if there is none, it will be created
function datastore.get_data(player)
	if not datastore._data[player] then
		datastore._data[player] =
		{
			railbuilder_start_pos = vector.new(0, 0, 0),
			railbuilder_built_last_node = false, -- UNUSED; if last node of previous track was built
			railbuilder_last_direction = nil, -- direction of previous track
			railbuilder_last_vertical_direction = nil, -- 1 = built up, 0 = straight, -1 = down
			railbuilder_desired_vertical_direction = nil, -- 1/2, 1/3, 0, -1/3, -1/2
			ui = {
				hud_slope_selection_points = {},
				hud_track_preview_points = {},
				hud_update_last_player_pos = vector.new(0, 0, 0),
				railbuilder_start_marker = nil,
			},
			use_tunnelmaker = true,
			track_style = nil,
		}
	end
	return datastore._data[player]
end

railbuilder.datastore = datastore