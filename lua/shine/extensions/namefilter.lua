--[[
	Provides a way to filter out player names.
]]

local Shine = Shine

local Clamp = math.Clamp
local Floor = math.floor
local GetOwner = Server.GetOwner
local Max = math.max
local pcall = pcall
local Random = math.random
local StringChar = string.char
local StringFind = string.find
local StringGSub = string.gsub
local StringLower = string.lower
local TableConcat = table.concat
local tostring = tostring

local Plugin = {}

Plugin.PrintName = "Name Filter"

Plugin.ConfigName = "NameFilter.json"
Plugin.HasConfig = true

Plugin.RENAME = 1
Plugin.KICK = 2
Plugin.BAN = 3

Plugin.DefaultConfig = {
	Filters = {},
	FilterAction = Plugin.RENAME,
	BanLength = 1440
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Config.BanLength = Max( 0, self.Config.BanLength )
	self.Config.FilterAction = Clamp( Floor( self.Config.FilterAction ), 1, 3 )

	self:CreateCommands()
	self.InvalidFilters = {}

	self.Enabled = true

	return true
end

function Plugin:CreateCommands()
	local RenameCommand = self:BindCommand( "sh_rename", "rename",
	function( Client, Target, NewName )
		local TargetPlayer = Target:GetControllingPlayer()

		if not TargetPlayer then return end

		local CallingInfo = Shine.GetClientInfo( Client )
		local TargetInfo = Shine.GetClientInfo( Target )

		TargetPlayer:SetName( NewName )

		self:Print( "%s was renamed to '%s' by %s.", true, TargetInfo, NewName, CallingInfo )
	end )
	RenameCommand:AddParam{ Type = "client" }
	RenameCommand:AddParam{ Type = "string", TakeRestOfLine = true, Help = "new name" }
	RenameCommand:Help( "Renames the given player." )
end

Plugin.FilterActions = {
	function( self, Player, OldName ) -- Rename them to NSPlayer<RandomLargeNumber>
		local UserName = "NSPlayer"..Random( 1e3, 1e5 )
		Player:SetName( UserName )

		local Client = GetOwner( Player )
		if not Client then return end

		self:Print( "Client %s[%s] was renamed from filtered name: %s", true,
			UserName, Client:GetUserId(), OldName )
	end,

	function( self, Player, OldName ) --Kick them out.
		local Client = GetOwner( Player )

		if not Client then return end

		self:Print( "Client %s[%s] was kicked for filtered name.", true,
			OldName, Client:GetUserId() )

		Server.DisconnectClient( Client )
	end,

	function( self, Player, OldName ) --Ban them.
		local Client = GetOwner( Player )
		if not Client then return end

		local ID = Client:GetUserId()
		local Enabled, BanPlugin = Shine:IsExtensionEnabled( "ban" )

		if Enabled then
			self:Print( "Client %s[%s] was banned for filtered name.", true,
				OldName, ID )

			BanPlugin:AddBan( ID, OldName, self.Config.BanLength * 60, "NameFilter", 0,
				"Player used filtered name." )
		else
			self:Print( "Client %s[%s] was kicked for filtered name (unable to ban, ban plugin not loaded).",
				true, OldName, ID )
		end

		Server.DisconnectClient( Client )
	end
}

--[[
	Checks a player's name for a match with the given pattern.

	Excluded should be an NS2ID which identifies the player who owns this name pattern.
]]
function Plugin:ProcessFilter( Player, Name, Filter )
	if not Filter.Pattern then return end

	local Client = GetOwner( Player )
	if Client and tostring( Client:GetUserId() ) == tostring( Filter.Excluded ) then return end

	local LoweredName = StringLower( Name )
	local Pattern = StringLower( Filter.Pattern )

	local Start
	if Filter.PlainText then
		Start = StringFind( LoweredName, Pattern, 1, true )
	else
		local Success
		Success, Start = pcall( StringFind, LoweredName, Pattern )

		if not Success then
			self.InvalidFilters[ Filter ] = true
			self:Print( "Pattern '%s' is invalid: %s. Set \"PlainText\": true if you do not want to use a Lua pattern match.",
				true, Pattern, StringGSub( Start, "^.+:%d+:(.+)$", "%1" ) )
			return
		end
	end

	if Start then
		self.FilterActions[ self.Config.FilterAction ]( self, Player, Name )

		return true
	end
end

--[[
	When a player's name changes, we check all set filters on their new name.
]]
function Plugin:PlayerNameChange( Player, Name, OldName )
	local Filters = self.Config.Filters

	for i = 1, #Filters do
		if not self.InvalidFilters[ Filters[ i ] ]
		and self:ProcessFilter( Player, Name, Filters[ i ] ) then
			break
		end
	end
end

Shine:RegisterExtension( "namefilter", Plugin )
