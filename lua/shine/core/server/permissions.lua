--[[
	Shine permissions/user ranking system.
]]

local Shine = Shine

Shine.UserData = {}

local Decode = json.decode
local GetClientById = Server.GetClientById
local IsType = Shine.IsType
local next = next
local Notify = Shared.Message
local pairs = pairs
local TableEmpty = table.Empty
local tonumber = tonumber
local tostring = tostring

local UserPath = "config://shine/UserConfig.json"
local BackupPath = "config://Shine_UserConfig.json"
local DefaultUsers = "config://ServerAdmin.json"

function Shine:RequestUsers( Reload )
	local function UsersResponse( Response )
		if not Response and not Reload then
			self:LoadUsers()

			return
		end

		local UserData = Decode( Response ) or {}

		if not IsType( UserData, "table" ) or not next( UserData ) then
			if Reload then --Don't replace with a blank table if request failed when reloading.
				self:AdminPrint( nil,
					"Reloading from the web failed. User data has not been changed." )

				return
			end

			Notify( "Loading from the web failed. Using local file instead." )

			self:LoadUsers()

			return
		end

		self.UserData = UserData

		self:ConvertData( self.UserData, true )

		--Cache the current user data, so if we fail to load it on
		--a later map we still have something to load.
		self:SaveUsers( true )

		Notify( Reload and "Shine reloaded users from the web."
			or "Shine loaded users from web." )

		self.Hook.Call( "OnUserReload" )
	end

	if self.Config.GetUsersWithPOST then
		Shared.SendHTTPRequest( self.Config.UsersURL, "POST",
			self.Config.UserRetrieveArguments, UsersResponse )
	else
		Shared.SendHTTPRequest( self.Config.UsersURL, "GET", UsersResponse )
	end
end

--[[
	Loads the Shine user data either from a local JSON file or from one hosted on a webserver.
	If retrieving the web users fails, it will fall back to a local file.
	If a local file does not exist, the default is created and used.
]]
function Shine:LoadUsers( Web, Reload )
	if Web then
		if Reload then
			self:RequestUsers( true )
		else
			self.Hook.Add( "ClientConnect", "LoadUsers", function( Client )
				self:RequestUsers()
				self.Hook.Remove( "ClientConnect", "LoadUsers" )
			end, -20 )
		end

		return
	end

	--Check the default path.
	local UserFile = self.LoadJSONFile( UserPath )

	if not UserFile then
		UserFile = self.LoadJSONFile( BackupPath ) --Check the secondary path.

		if not UserFile then
			UserFile = self.LoadJSONFile( DefaultUsers ) --Check the default NS2 users file.

			if not UserFile then
				self:GenerateDefaultUsers( true )

				return
			end
		end
	end

	Notify( "Loading Shine users..." )

	self.UserData = UserFile

	if not IsType( self.UserData, "table" ) or not next( self.UserData ) then
		Notify( "The user data file is not valid JSON, unable to load user data." )

		--Dummy data to avoid errors.
		if not Reload then
			self.UserData = { Groups = {}, Users = {} }
		end

		return
	end

	self:ConvertData( self.UserData )

	if Reload then
		self.Hook.Call( "OnUserReload" )
	end
end

--[[
	Saves the Shine user data to the JSON file.
]]
function Shine:SaveUsers( Silent )
	local Success, Err = self.SaveJSONFile( self.UserData, UserPath )

	if not Success then
		self.Error = "Error writing user file: "..Err

		Notify( self.Error )

		return
	end

	if not Silent then
		Notify( "Saving Shine users..." )
	end
end

--[[
	Generates the default users and groups.
	Optionally saves the default settings to a local JSON file.
]]
function Shine:GenerateDefaultUsers( Save )
	self.UserData = {
		Groups = {
			SuperAdmin = { IsBlacklist = true, Commands = {}, Immunity = 100 },
			Admin = { IsBlacklist = false, Commands = { "sh_kick", "sh_ban" }, Immunity = 50 },
			Mod = { IsBlacklist = false, Commands = { "sh_kick" }, Immunity = 10 }
		},
		Users = {
			[ "90000000000001" ] = { Group = "Mod", Immunity = 2 }
		}
	}

	if Save then
		self:SaveUsers()
	end
end

local CommandMapping = {
	sv_hasreserve = "sh_reservedslot",
	sv_rrall = "sh_rr",
	sv_afkimmune = "sh_afk",
	sv_randomall = "sh_forcerandom",
	sv_switchteam = "sh_setteam",
	sv_maps = "sh_listmaps",
	sv_randomon = "sh_enablerandom",
	sv_cancelmapvote = "sh_veto",
	sv_nick = "sh_rename",
	sv_reloadplugins = "sh_loadplugin",
	sv_dontrandom = "sh_randomimmune"
}

local function ConvertCommands( Commands )
	local Ret = {}

	for i = 1, #Commands do
		local Command = Commands[ i ]
		local Equivalent = CommandMapping[ Command ]

		if Equivalent then
			Ret[ i ] = Equivalent
		else
			Ret[ i ] = Command:gsub( "sv", "sh" )
		end
	end

	return Ret
end

--[[
	Converts the default/DAK style user file into one compatible with Shine.
	Inputs: Userdata table, optional boolean to not save (for web loading).
]]
function Shine:ConvertData( Data, DontSave )
	local Edited

	if Data.groups then
		if not DontSave then
			Shared.Message( "Converting user groups from NS2/DAK format to Shine format..." )
		end

		Data.Groups = {}

		for Name, Vals in pairs( Data.groups ) do
			if Vals.type or Vals.commands or Vals.level then
				Data.Groups[ Name ] = {
					IsBlacklist = Vals.type == "disallowed",
					Commands = Vals.commands and ConvertCommands( Vals.commands ) or {},
					Immunity = Vals.level or 10,
					Badge = Vals.badge,
					Badges = Vals.badges
				}
			--Someone's called it "groups" without knowing it's case sensitive...
			elseif Vals.Commands and Vals.Immunity then
				Data.Groups[ Name ] = Vals
			end
		end

		Edited = true
		Data.groups = nil
	end

	if Data.users then
		if not DontSave then
			Shared.Message( "Converting users from NS2/DAK format to Shine format..." )
		end

		Data.Users = {}

		for Name, Vals in pairs( Data.users ) do
			if Vals.id then
				Data.Users[ tostring( Vals.id ) ] = {
					Group = Vals.groups and Vals.groups[ 1 ],
					Immunity = Vals.level,
					Badge = Vals.badge,
					Badges = Vals.badges
				}
			--Someone's called it "users" without knowing it's case sensitive...
			elseif Vals.Group or Vals.Immunity or Vals.Badge or Vals.Badges then
				Data.Users[ Name ] = Vals
			end
		end

		Edited = true
		Data.users = nil
	end

	if Edited and not DontSave then
		self:SaveUsers()
	end
end

--[[
	We need to load the users after loading the configuration file.
	This ensures we know whether we should be getting them from the web or not.
]]
Shine.Hook.Add( "PostloadConfig", "LoadShineUsers", function()
	local WebUsers = Shine.Config.GetUsersFromWeb
	Shine:LoadUsers( WebUsers )

	if WebUsers and Shine.Config.RefreshUsers then
		Shine.Timer.Create( "UserRefresh", Shine.Config.RefreshInterval or 60, -1, function()
			Shine:RequestUsers( true )
		end )
	end
end )

--[[
	Game IDs handling.
]]
local GameIDs = Shine.Map()

Shine.GameIDs = GameIDs

local GameID = 0

Shine.Hook.Add( "ClientConnect", "AssignGameID", function( Client )
	--I have a suspicion that this event is being called again for a client that never disconnected.
	if GameIDs:Get( Client ) then return true end

	GameID = GameID + 1
	GameIDs:Add( Client, GameID )
end, -20 )

Shine.Hook.Add( "ClientDisconnect", "AssignGameID", function( Client )
	GameIDs:Remove( Client )
end, -20 )

local function GetIDFromClient( Client )
	return IsType( Client, "number" ) and Client or ( Client.GetUserId and Client:GetUserId() )
end

--[[
	Gets the user data table for the given client/NS2ID.
	Input: Client or NS2ID.
	Output: User data table if they are registered in UserConfig.json, user ID.
]]
function Shine:GetUserData( Client )
	if not self.UserData then return nil end
	if not self.UserData.Users then return nil end

	local ID = GetIDFromClient( Client )
	if not ID then return nil end

	local User = self.UserData.Users[ tostring( ID ) ]
	if not User then
		--Try the STEAM_0:X:YYYY format
		local SteamID = self.NS2ToSteamID( ID )
		User = self.UserData.Users[ SteamID ]
		if User then
			return User, SteamID
		end

		--Try the [U:1:YYYY] format
		local Steam3ID = self.NS2ToSteam3ID( ID )
		User = self.UserData.Users[ ID ]

		if User then
			return User, Steam3ID
		end

		return nil, ID
	end

	return User, ID
end

--[[
	Gets the group data table for the given group name.
	Input: Group name.
	Output: Group data table if it exists, nil otherwise.
]]
function Shine:GetGroupData( GroupName )
	if not GroupName then return self:GetDefaultGroup() end
	if not self.UserData then return nil end
	if not self.UserData.Groups then return nil end

	return self.UserData.Groups[ GroupName ]
end

--[[
	Gets the group data table for the default group if it exists.
]]
function Shine:GetDefaultGroup()
	if not self.UserData then return nil end
	if not self.UserData.DefaultGroup then return nil end

	self.UserData.DefaultGroup.InheritsFrom = nil
	self.UserData.DefaultGroup.InheritFromDefault = nil

	return self.UserData.DefaultGroup
end

--[[
	Gets the default immunity value. Usually 0.
]]
function Shine:GetDefaultImmunity()
	local DefaultGroup = self:GetDefaultGroup()

	if DefaultGroup then
		return tonumber( DefaultGroup.Immunity ) or 0
	end

	return 0
end

--[[
	Gets a client's immunity value.
	Input: Client or NS2ID.
	Output: Immunity value, 0 if they have no group/user.
]]
function Shine:GetUserImmunity( Client )
	if not Client then return 0 end
	if not self.UserData then return 0 end
	if not self.UserData.Groups then return 0 end

	local Data = self:GetUserData( Client )

	if not Data then
		return self:GetDefaultImmunity()
	end
	if Data.Immunity then return tonumber( Data.Immunity ) or 0 end

	local Group = Data.Group
	local GroupData = self.UserData.Groups[ Group ]

	if not GroupData then
		return self:GetDefaultImmunity()
	end

	return tonumber( GroupData.Immunity ) or 0
end

local PermissionCache = {}

--[[
	Checks a command list table for the given command name,
	taking into account table entries with argument restrictions.
]]
local function CheckForCommand( GroupName, Table, Command )
	-- -1 denotes the default group, as JSON can't have a number key of -1.
	GroupName = GroupName or -1

	local Permissions = PermissionCache[ GroupName ]

	if not Permissions then
		Permissions = {}

		for i = 1, #Table do
			local Entry = Table[ i ]

			if IsType( Entry, "table" ) then
				Permissions[ Entry.Command ] = Entry
			else
				Permissions[ Entry ] = true
			end
		end

		PermissionCache[ GroupName ] = Permissions
	end

	local Entry = Permissions[ Command ]
	if not Entry then return false end

	if IsType( Entry, "table" ) then
		return true, Entry
	end

	return true
end

--[[
	Verifies the given group has a commands table.
	Inputs: Group name, group table.
	Output: True if the group has a commands table, false otherwise.
]]
function Shine:VerifyGroup( GroupName, GroupTable )
	if not IsType( GroupTable.Commands, "table" ) then
		if GroupName then
			self:Print( "Group with ID %s has a missing/incorrect \"Commands\" list! It should be a list of commands.",
				true, GroupName )
		end

		return false
	end

	return true
end

--[[
	Gets whether the given group has the given permission.
	Inputs: Group name, group table, command.
	Output: True/false permission, allowed arguments if set.
]]
function Shine:GetGroupPermission( GroupName, GroupTable, ConCommand )
	if not self:VerifyGroup( GroupName, GroupTable ) then return false end

	local Exists, AllowedArgs = CheckForCommand( GroupName, GroupTable.Commands, ConCommand )

	if GroupTable.IsBlacklist then
		--A blacklist entry with allowed arguments restricts to only those arguments.
		if AllowedArgs then
			return true, AllowedArgs
		else
			return not Exists
		end
	end

	return Exists, AllowedArgs
end

--[[
	Determines if the given client has permission to run the given command.
	Inputs: Client or Steam ID, command name (sh_*).
	Output: True if allowed.
]]
function Shine:GetPermission( Client, ConCommand )
	local Command = self.Commands[ ConCommand ]

	if not Command then return false end
	if not Client then return true end

	local User, ID = self:GetUserData( Client )

	if not User then
		if Command.NoPerm then
			return true
		end

		local DefaultGroup = self:GetDefaultGroup()

		if not DefaultGroup then
			return false
		end

		return self:GetGroupPermission( nil, DefaultGroup, ConCommand )
	end

	if Command.NoPerm then return true end

	local UserGroup = User.Group
	local GroupTable = self:GetGroupData( UserGroup )

	if not GroupTable then
		self:Print( "User with ID %s belongs to a non-existent group (%s)!",
			true, ID, UserGroup )

		return false
	end

	if GroupTable.InheritsFrom or GroupTable.InheritFromDefault then
		return self:GetPermissionInheritance( UserGroup, GroupTable, ConCommand )
	end

	return self:GetGroupPermission( UserGroup, GroupTable, ConCommand )
end

--[[
	Adds all commands in the Permissions table to the table of
	commands being built. Will add argument restrictions to the table
	if they are set, otherwise just adds the command as 'true'.

	Whitelists take the first occurrence of the command, blacklists take
	the last occurrence.
]]
local function AddPermissionsToTable( Permissions, Table, Blacklist )
	for i = 1, #Permissions do
		local Entry = Permissions[ i ]

		if IsType( Entry, "string" ) then
			if Blacklist then
				Table[ Entry ] = true
			elseif not Table[ Entry ] then
				Table[ Entry ] = true
			end
		elseif IsType( Entry, "table" ) then
			local Command = Entry.Command

			if Command then
				local Allowed = Entry.Allowed

				--Blacklists should take the lowest allowed entry,
				--whitelists should take the highest.
				if Blacklist then
					Table[ Command ] = Allowed or true
				elseif not Table[ Command ] then
					Table[ Command ] = Allowed or true
				end
			end
		end
	end
end

--[[
	Recursively builds permissions table from all inherited groups,
	and their inherited groups, and their inherited groups and...

	Inputs: Current group name, current group table, blacklist setting,
	permissions table to build.
]]
local function BuildPermissions( self, GroupName, GroupTable, Blacklist, Permissions, Processed )
	Processed = Processed or {}

	--Avoid cycles!
	if Processed[ GroupName ] then return end

	Processed[ GroupName ] = true

	local InheritGroups = GroupTable.InheritsFrom
	local InheritFromDefault = GroupTable.InheritFromDefault
	local TopLevelCommands = GroupTable.Commands

	if GroupTable.IsBlacklist == Blacklist then
		if IsType( TopLevelCommands, "table" ) then
			AddPermissionsToTable( TopLevelCommands, Permissions, Blacklist )
		else
			self:Print( "Group with ID %s has a missing/incorrect \"Commands\" list! It should be a list of commands.",
				true, GroupName )
		end
	end

	--Inherit from the default group, which cannot inherit from others.
	if InheritFromDefault then
		local DefaultGroup = self:GetDefaultGroup()
		if not DefaultGroup then
			self:Print( "Group with ID %s inherits from the default group, but no default group exists!", true, GroupName )
		else
			if not Processed[ DefaultGroup ] then
				Processed[ DefaultGroup ] = true
				if self:VerifyGroup( nil, DefaultGroup )
				and DefaultGroup.IsBlacklist == Blacklist then
					AddPermissionsToTable( DefaultGroup.Commands, Permissions, Blacklist )
				end
			end
		end
	end

	if not InheritGroups then return end

	for i = 1, #InheritGroups do
		local Name = InheritGroups[ i ]

		if Name then
			local CurGroup = self:GetGroupData( Name )

			if not CurGroup then
				self:Print( "Group with ID %s inherits from a non-existant group (%s)!",
					true, GroupName, Name )
			else
				BuildPermissions( self, Name, CurGroup, Blacklist, Permissions, Processed )
			end
		end
	end
end

Shine.Hook.Add( "OnUserReload", "FlushPermissionCache", function()
	TableEmpty( PermissionCache )
end )

--[[
	Checks all inherited groups to determine command access.
	Inputs: Group name, group table, command name.
	Output: True if allowed.
]]
function Shine:GetPermissionInheritance( GroupName, GroupTable, ConCommand )
	local InheritGroups = GroupTable.InheritsFrom
	local InheritFromDefault = GroupTable.InheritFromDefault

	if not InheritFromDefault then
		if not IsType( InheritGroups, "table" ) then
			self:Print( "Group with ID %s has a non-array entry for \"InheritsFrom\"!",
				true, GroupName )

			return false
		end

		local NumInheritGroups = #InheritGroups
		if NumInheritGroups == 0 then
			self:Print( "Group with ID %s has an empty \"InheritsFrom\" entry!",
				true, GroupName )

			return false
		end
	end

	local Blacklist = GroupTable.IsBlacklist
	local Permissions = PermissionCache[ GroupName ]

	if not Permissions then
		Permissions = {}

		BuildPermissions( self, GroupName, GroupTable, Blacklist, Permissions )

		PermissionCache[ GroupName ] = Permissions
	end

	if Blacklist then
		if not Permissions[ ConCommand ] then
			return true
		else
			if IsType( Permissions[ ConCommand ], "table" ) then
				return true, Permissions[ ConCommand ]
			else
				return false
			end
		end
	end

	--Return the allowed arguments.
	if IsType( Permissions[ ConCommand ], "table" ) then
		return true, Permissions[ ConCommand ]
	else
		return Permissions[ ConCommand ]
	end
end

--[[
	Gets whether the given group has raw acccess to the given permission.
	Inputs: Group name, group table, command.
	Output: True/false permission.
]]
function Shine:GetGroupAccess( GroupName, GroupTable, ConCommand )
	if not self:VerifyGroup( GroupName, GroupTable ) then return false end

	local Exists = CheckForCommand( GroupName, GroupTable.Commands, ConCommand )

	--Access doesn't care about allowed args, if it's present, we consider it denied.
	if GroupTable.IsBlacklist then
		return not Exists
	end

	return Exists
end

--[[
	Determines if the given client has raw access to the given command.
	Unlike get permission, this looks specifically for a user group with explicit permission.
	It also does not require the command to exist.

	Inputs: Client or Steam ID, command name (sh_*)
	Output: True if explicitly allowed.
]]
function Shine:HasAccess( Client, ConCommand )
	if not Client then return true end

	local User, ID = self:GetUserData( Client )

	if not User then
		local DefaultGroup = self:GetDefaultGroup()
		if not DefaultGroup then
			return false
		end

		return self:GetGroupAccess( nil, DefaultGroup, ConCommand )
	end

	local UserGroup = User.Group
	local GroupTable = self:GetGroupData( UserGroup )

	if not GroupTable then
		self:Print( "User with ID %s belongs to a non-existent group (%s)!",
			true, ID, UserGroup )
		return false
	end

	if GroupTable.InheritsFrom or GroupTable.InheritFromDefault then
		return self:GetPermissionInheritance( UserGroup, GroupTable, ConCommand )
	end

	return self:GetGroupAccess( UserGroup, GroupTable, ConCommand )
end

local function GetGroupAndImmunity( self, Groups, User, ID )
	if not User then
		local DefaultGroup = self:GetDefaultGroup()

		if not DefaultGroup then
			return nil
		end

		return DefaultGroup, tonumber( DefaultGroup.Immunity ) or 0
	end

	local Group = Groups[ User.Group or -1 ]

	if not Group then
		self:Print( "User with ID %s belongs to a non-existent group (%s)!",
			true, ID, tostring( User.Group ) )
		return nil
	end

	--Read from the user's immunity first, then the groups.
	local Immunity = tonumber( User.Immunity or Group.Immunity )

	if not Immunity then
		self:Print( "User with ID %s belongs to a group with an empty or incorrect immunity value! (Group: %s)",
			true, ID, tostring( User.Group ) )
		return nil
	end

	return Group, Immunity
end

--[[
	Determines if the given client can use a command on the given target client.
	Inputs: Client (or Steam ID) calling, target client (or Steam ID).
	Output: True if allowed.
]]
function Shine:CanTarget( Client, Target )
	if not Client or not Target then return true end --Console can target all.
	if Client == Target then return true end --Can always target yourself.
	if not self.UserData then return false end

	local Users = self.UserData.Users
	local Groups = self.UserData.Groups
	if not Users or not Groups then return false end

	local ID = GetIDFromClient( Client )
	local TargetID = GetIDFromClient( Target )

	if not ID then return false end
	if not TargetID then return false end
	if ID == TargetID then return true end

	local User
	local TargetUser

	User, ID = self:GetUserData( ID )
	TargetUser, TargetID = self:GetUserData( TargetID )

	local TargetGroup, TargetImmunity = GetGroupAndImmunity( self, Groups, TargetUser, TargetID )
	if not TargetGroup then
		return true
	end

	local Group, Immunity = GetGroupAndImmunity( self, Groups, User, ID )
	if not Group then
		--No user and no default group means can only target negative immunity groups.
		return TargetImmunity < 0
	end

	--Both guests in the default group.
	if Group == TargetGroup and Group == self:GetDefaultGroup() then
		return true
	end

	if self.Config.EqualsCanTarget then
		return Immunity >= TargetImmunity
	end

	return Immunity > TargetImmunity
end

--[[
	Determines if the given client is in the given user group.
	Inputs: Client (or Steam ID), group name.
	Output: Boolean result.
]]
function Shine:IsInGroup( Client, Group )
	if not Client then return false end

	if Client.GetIsVirtual and Client:GetIsVirtual() then
		return Group:lower() == "guest"
	end

	if not self.UserData then return false end
	local UserData = self.UserData.Users
	if not UserData then return false end

	local GroupTable = self.UserData.Groups and self.UserData.Groups[ Group ]
	if not GroupTable then return false end

	local ID = GetIDFromClient( Client )
	if not ID then return false end

	local User = self:GetUserData( ID )

	if User then
		return User.Group == Group
	end

	return Group:lower() == "guest"
end

--Deny vote kicks on players that are above in immunity level.
Shine.Hook.Add( "NS2StartVote", "ImmunityCheck", function( VoteName, Client, Data )
	if VoteName ~= "VoteKickPlayer" then return end

	local Target = Data.kick_client
	if not Target then return end

	local TargetClient = GetClientById( Target )
	if not TargetClient then return end

	if not Shine:CanTarget( Client, TargetClient ) then
		return false
	end
end )
