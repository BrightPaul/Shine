--[[
Shine crusader mode
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = Plugin
Plugin.Version = "0.2"

Plugin.HasConfig = true
Plugin.ConfigName = "Crusadermode.json"
Plugin.DefaultConfig =
{   Startmap = "ns2_summit",
    MapCycle = {"ns2_mineshaft" ,"ns2_summit","ns2_descent"}, 
    MsgDelay = 5, // Delay in secounds before plugin shows infomessage after connect
    ForceTeams = false, //force teams to stay the same
    Team1 = {},
    Team2 = {},
    Winningmsgaliens = "The swarm has dominated",
    Winningmsgmarines = "So we have finally smashed all these bugs",
    Winningmeassagetime = 20, //time the mesage i shown
}

Plugin.CheckConfig = true


function Plugin:Initialise()
     self.Enabled = true     
          
     //loads Commands
     Plugin:CreateCommands()
     return true
end

//Player connects
function Plugin:ClientConfirmConnect(Client)
    if Client:GetIsVirtual() then return end
    Shine.Timer.Simple( self.Config.MsgDelay, function()
	    Shine:Notify( Client, "", "", "Crusadermode is enabled!. Choose your side")
    end )
    if self.Config.ForceTeams then
        local id = Client:GetUserId()
        if Plugin:TableFind(self.Config.Team1, id) then
            Gamerules:JoinTeam( Client:GetPlayer(), 1, nil, true )
        elseif Plugin:TableFind(self.Config.Team2, id) then
            Gamerules:JoinTeam( Client:GetPlayer(), 2, nil, true )      
        end
    end
end

//Force players back into teams
function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
    local client= Player:GetClient()
    
    //block f4 if forceteams is true
    if self.Config.ForceTeams then
        if NewTeam == kTeamReadyRoom then return false end 
    end 
    
    //cases in which jointeam is not limited
    if not self.Config.ForceTeams or ShineForce then
        if NewTeam == 1 then
            table.insert(self.Config.Team1, client:GetUserId())
            self:SaveConfig()
        elseif NewTeam == 2 then
            table.insert(self.Config.Team2, client:GetUserId())
            self:SaveConfig()
        end
    return end    
    return false
end

//determ next map
function Plugin:EndGame(Gamerules, WinningTeam)    
        -Prevent time based cycling from passing.
        if Gamerules then
            Gamerules.timeToCycleMap = nil
        end
        local i = Plugin:TableFind(self.Config.MapCycle, Shared.GetMapName())
        if i == nil then return end //map not in config
        local WinningMessage = {}
        WinningMessage.message = ""
        WinningMessage.duration = Plugin.Config.Winningmeassagetime
        if i<=1 then// aliens won
            WinningMessage.message = Winningmsgaliens
            Server.SendNetworkMessage( "Shine_WinningMsg", WinningMessage, true )
            local mapname = Plugin.Config.Startmap
            Shine.Timer.Simple(WinningMessage.duration, function(mapname) MapCycle_ChangeMap(mapname) end
            return end
        elseif i >= #self.Config.MapCycle then //marines won
            WinningMessage.message = Winningmsgmarines
            Server.SendNetworkMessage( "Shine_WinningMsg", WinningMessage, true )            
            local mapname = Plugin.Config.Startmap
            Shine.Timer.Simple(WinningMessage.duration, function(mapname) MapCycle_ChangeMap(mapname) end
            return end
        end
        local Winnernr = WinningTeam:GetTeamNumber()
        if Winnernr == 1 then //marines won round
            local mapname = self.Config.MapCycle[i-1]
            Shine.Timer.Simple(10, function(mapname) MapCycle_ChangeMap(mapname) end)
        else
            local mapname = self.Config.MapCycle[i-1]
            Shine.Timer.Simple(10, function(mapname) MapCycle_ChangeMap(mapname) end )
        end 
end

function Plugin:TableFind(table ,find)
    for i=1, #table do
        if table[i] == find then return i end
    end
    return nil
end

// commands
function Plugin:CreateCommands()
    
    local Clearteams = self:BindCommand( "sh_resetteams","resetteams" ,function()
        Plugin.Config.Team1 = {}
        Plugin.Config.Team2 = {}
        self:SaveConfig()
    end)
    Clearteams:Help("Removes all players from teams in config ")
end

function Plugin:Cleanup()
    self.Enabled = false
end