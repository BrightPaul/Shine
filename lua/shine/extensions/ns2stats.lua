--[[
Shine ns2stats plugin.
]]

local Shine = Shine

local Notify = Shared.Message

local Plugin = {}

Plugin.Version = "0.1"

//TODO: add Config later
Plugin.HasConfig = false

//Score datatable 
self.score={}
self.assist={}
function Plugin:Initialise()

//TODO: add all Hooks here
//Shine.Hook.SetupClassHook( string Class, string Method, string HookName, "PassivePost" )

Shine.Hook.SetupClassHook( "BuildingMixin", "AttemptToBuild", "BuildingDropped", "PassivePost" )
Shine.Hook.SetupClassHook( "DamageMixin", "DoDamage", "DealedDamage", "PassivePost" )
Shine.Hook.SetupClassHook{ "ScoringMixin", "AddScore","ScoreChanged","PassivePost")
Shine.Hook.SetupClassHock( "Player", "AddKill","OnKill","PassivePost")
Shine.Hook.SetupClassHock( "NS2Gamerules", "OnEntityDestroy","OnPlayerDeath","PassivePost")

//Todo: Add all add functions + sendtoserver
// add all Data Function to Hooks Shine.Hook.Add( string HookName, string UniqueID, function HookFunction [, int Priority ] )
Shine.Hook.Add( "BuildingDropped", "AddBuildingdropped", function(newEnt, commander) /*add function stuff here*/ end )
Shine.Hook.Add( "DealedDamage", "AddDamagetoS", function(target,attacker,damage)
if attacker:isa("Player") then
local id = self.score[toString(attacker]
if damage > 0  then 
    if target:isa("Player") then
    id.pdmg = id.pdmg + damage
    self.assist[toString(target:GetUserId())][toString(attacker:GetUserId())]=
    else id.sdmg = id.sdmg + damage end
    id.hits = id.hits + 1
else id.misses = id.misses + 1
end end end )

Shine.Hook.Add("ScoreChanged","AddPointstoS",function()
    self.score[toString(self::GetUserId())].score = self.score end)
Sine.Hook.Add("OnKill","AddKilltoS",function()
    self.score[toString(self:GetUserId())].kills = self.kills end)
Sine.Hook.Add("OnPlayerDeath","AddDeathtoS",function(entity)
    if entity:isa("Player") then
        local death = self.score[toString(entity:GetUserId())].deaths
        deaths= deaths + 1
    end end)
end

function Plugin:Think()
//Send Stats every SendRystm secounds (from the config) to ns2stats server
// if Shared.GetTime % self.config.SendRythm == 0 then senddata() end
end

//PlayerConnected
function Plugin:ClientConnect( Client )
    if not Client then return end
    if Client:GetIsVirtual() then return end
    local Player = Client:GetControllingPlayer()
    if not Player then return end
    if self.score[toString(Client:GetUserId())]== nil then
        score[toString(Client:GetUserId())] = {id=toString(Client:GetUserId()),name=player:getName(),team = 0,com =false,score =0 ,kills = 0,deaths = 0, assists = 0, pdmg = 0, sdmg = 0 ,hits = 0, playedTime = 0,connected = true}
    else self.score[toString(Client:GetUserId())].connected = true     
end
//PlayerDisconnect
function Plugin:ClientDisconnect(Client)
    if not Client then return end
    if Client:GetIsVirtual() then return end
    local Player = Client:GetControllingPlayer()
    if not Player then return end
    self.score[toString(Client:GetUserId())].connected = false
end

Shine:RegisterExtension( "ns2stats", Plugin )