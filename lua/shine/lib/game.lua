--[[
	Gamemode stuff.
]]

local Gamemode

--[[
	Gets the name of the currently running gamemode.
]]
function Shine.GetGamemode()
	if Gamemode then return Gamemode end

	local GameSetup = io.open( "game_setup.xml", "r" )

	if not GameSetup then
		Gamemode = "combat"

		return "combat"
	end

	local Data = GameSetup:read( "*all" )

	GameSetup:close()

	local Match = Data:match( "<name>(.+)</name>" )

	Gamemode = Match or "combat"

	return Gamemode
end
