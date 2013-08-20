--[[
Shine crusader mode
]]

local Plugin = {}
local Shine = Shine

local WinningMessage = {
message = "string (255)",
duration = "integer (0 to 1800)"
}

Shared.RegisterNetworkMessage( "Shine_WinningMsg", WinningMessage )

Shine:RegisterExtension( "crusadermode", Plugin )

if Server then return end
function Plugin:Initialise()
    self.Enabled = true
   return true
end

Client.HookNetworkMessage( "Shine_WinningMsg", function( Message )
    local AwardMessage = Message.message
    local Duration = Message.duration
    local ScreenText = Shine:AddMessageToQueue( 1, 0.5, 0.5, AwardMessage, Duration, 255, 0, 0, 2 )
    ScreenText.Obj:SetText(ScreenText.Text)
end)

function Plugin:Cleanup()
    self.Enabled = false
end
