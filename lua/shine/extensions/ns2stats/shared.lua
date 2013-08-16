--[[
Shared stuff.
]]

local Plugin = {}

Shine:RegisterExtension( "ns2stats", Plugin )

local AwardMessage = {
message = "string (255)",
duration = "integer (0 to 1800)"
}
Shared.RegisterNetworkMessage( "Shine_StatsAwards", AwardMessage )

if Server then return end

local Shine = Shine
local VoteMenu = Shine.VoteMenu

function Plugin:Initialise()
    self.Enabled = true
   return true 
end

//Votemenu
VoteMenu:AddPage( "Stats", function( self )
    self:AddSideButton( "Show my Stats", function()
        Shared.ConsoleCommand("sh_showplayerstats")
    end )
    self:AddSideButton( "Show Server Stats", function()
        Shared.ConsoleCommand("sh_showserverstats")
    end )
    self:AddTopButton( "Back", function()
        self:SetPage( "Main" )
    end )
end )
Shine.VoteMenu:EditPage( "Main", function( self )
    if Plugin.Enabled then
    	self:AddSideButton( "NS2Stats", function()
        self:SetPage( "Stats" ) 
        end)       
    end
end )

Client.HookNetworkMessage( "Shine_StatsAwards", function( Message )
    local AwardMessage = Message.message
    local Duration = Message.duration
    local ScreenText = Shine:AddMessageToQueue( 1, 0.95, 0.2, AwardMessage, Duration, 255, 0, 0, 2 )
    ScreenText.Obj:SetText(ScreenText.Text)
end)

function Plugin:Cleanup()
    self.Enabled = false
end

