--[[
Shared stuff.
]]

local Plugin = {}

function Plugin:Initialise()

    //Votemenu
    Shine.VoteMenu:AddPage( "Stats", function( self )
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

end

Shine:RegisterExtension( "ns2stats", Plugin )