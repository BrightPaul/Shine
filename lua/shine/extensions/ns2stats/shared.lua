--[[
Shared stuff.
]]

local Plugin = {}
local Shine = Shine

Shine:RegisterExtension( "ns2stats", Plugin )

local AwardMessage = {
message = "string (255)",
duration = "integer (0 to 1800)"
}
Shared.RegisterNetworkMessage( "Shine_StatsAwards", AwardMessage )

local Config = {
    WebsiteUrl = "string (255)",
    WebsiteDataUrl = "string (255)",
    WebsiteStatusUrl= "string (255)",
    WebsiteApiUrl = "string (255)",
    SendMapData = "boolean",
}
Shared.RegisterNetworkMessage( "Shine_StatsConfig", Config )

if Server then return end

local VoteMenu = Shine.VoteMenu

function Plugin:Initialise()
   self.Enabled = true
   return true 
end


//get Config
Client.HookNetworkMessage( "Shine_StatsAwards", function( Message )
     self.WebsiteUrl = Meassage.WebsiteUrl
     self.WebsiteDataUrl = Message.WebsiteDataUrl
     self.WebsiteStatusUrl = Message.WebsiteStatusUrl 
     self.WebsiteApiUrl = Message.WebsiteApiUrl
     self.SendMapData = Message.SendMapData
end)

//Get Mapdata
Shine.Hook.SetupClassHook( "GUIMinimap", "InitializeBackground", "Mapdata", "PassivePost" )

function Plugin:Mapdata(GUIMinimap)
    if self.SendMapData then
        local jsonvalues = {
            scaleX = Client.minimapExtentScale.x,
            scaleY = Client.minimapExtentScale.y,
            scaleZ = Client.minimapExtentScale.z,
            originX = Client.minimapExtentOrigin.x,
            originY = Client.minimapExtentOrigin.y,
            originZ = Client.minimapExtentOrigin.z,
            plotToMapLin_X = GUIMinimap.plotToMapLinX,
            plotToMapLin_Y = GUIMinimap.plotToMapLinY,
            plotToMapConst_x = GUIMinimap.plotToMapConstX,
            plotToMapConst_y = GUIMinimap.plotToMapConstY,
            backgroundWidth = GUIMinimap.kBackgroundWidth,
            backgroundHeight = GUIMinimap.kBackgroundHeight,
            scale = self.scale
        }
        
        local params =
        {
            secret = "jokukovasalasana",
            mapName = Shared.GetMapName(),
            jsonvalues = json.encode(jsonvalues)
        }
        Shared.SendHTTPRequest(self.WebsiteApiUrl .."/updatemapdata", "POST", params, function(response,status) if RBPSdebug then Shared.Message(response) end end)	
        self.SendMapData = false
    end
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
    local ScreenText = Shine:AddMessageToQueue( 1, 0.95, 0.4, AwardMessage, Duration, 255, 0, 0, 2 )
    ScreenText.Obj:SetText(ScreenText.Text)
end)

function Plugin:Cleanup()
    self.Enabled = false
end

