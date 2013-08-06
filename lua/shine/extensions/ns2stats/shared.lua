--[[
Shared stuff.
]]

local Plugin = {}

Shine:RegisterExtension( "ns2stats", Plugin )

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