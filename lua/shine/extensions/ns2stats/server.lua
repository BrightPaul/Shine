--[[
Shine ns2stats plugin.
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = Plugin
local tostring = tostring

Plugin.Version = "0.42"

Plugin.HasConfig = true

Plugin.ConfigName = "Ns2Stats.json"
Plugin.DefaultConfig =
{
    Statsonline = true, -- Upload stats?
    SendMapData = false, --Send Mapdata, only set true if minimap is missing at website or is incorrect
    Statusreport = true, -- send Status to NS2Stats every min
    WebsiteUrl = "http://dev.ns2stats.com", --this is url which is shown in player private messages, so its for advertising
    WebsiteDataUrl = "http://dev.ns2stats.com/api/sendlog", --this is url where posted data is send and where it is parsed into database
    WebsiteStatusUrl="http://dev.ns2stats.com/api/sendstatus", --this is url where posted data is send on status sends
    WebsiteApiUrl = "http://dev.ns2stats.com/api",
    Awards = true, --show award
    ShowNumAwards = 4, --how many awards should be shown at the end of the game?
    AwardMsgTime = 20, -- secs to show awards
    LogChat = false, --log the chat?
    ServerKey = "",
    IngameBrowser = true, -- use ingame browser or Steamoverlay 
    Tags = {}, --Tags added to log 
    Competitive = false, -- tag round as Competitive
    SendTime = 5, --Send after how many min?
    Lastroundlink = "", --Link of last round
}

Plugin.CheckConfig = true

--All needed Hooks

Shine.Hook.SetupClassHook( "DamageMixin", "DoDamage", "OnDamageDealt", "PassivePost" )
Shine.Hook.SetupClassHook("ResearchMixin","TechResearched","OnTechResearched","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","SetResearching","OnTechStartResearch","PassivePre")
Shine.Hook.SetupClassHook("ConstructMixin","SetConstructionComplete","OnFinishedBuilt","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","OnResearchCancel","addUpgradeAbortedToLog","PassivePost")
Shine.Hook.SetupClassHook("UpgradableMixin","RemoveUpgrade","addUpgradeLostToLog","PassivePost")
Shine.Hook.SetupClassHook("ResourceTower","CollectResources","OnTeamGetResources","PassivePost") 
Shine.Hook.SetupClassHook("DropPack","OnCreate","OnPickableItemCreated","PassivePost") 
Shine.Hook.SetupClassHook("DropPack","OnTouch","OnPickableItemPicked","PassivePost")
Shine.Hook.SetupClassHook("PlayerBot","UpdateName","OnBotRenamed","PassivePost")
Shine.Hook.SetupClassHook("Player","SetName","PlayerNameChange","PassivePost")
Shine.Hook.SetupClassHook("Player","OnEntityChange","OnLifeformChanged","PassivePost")
Shine.Hook.SetupClassHook("Player","OnJump","OnPlayerJump","PassivePost")
Shine.Hook.SetupClassHook("Player","SetScoreboardChanged","OnPlayerScoreChanged","PassivePost")
Shine.Hook.SetupClassHook("GhostStructureMixin","SetScoreboardChanged","OnGhostCreated","PassivePost")
Shine.Hook.SetupClassHook("GhostStructureMixin","PerformAction","OnGhostDestroyed","PassivePost")
--Global hooks
Shine.Hook.SetupGlobalHook("RemoveAllObstacles","OnGameReset","PassivePost")  
   
--Score datatable 
Plugin.Players = {}

--values needed by NS2Stats

Plugin.Log = {}
Plugin.LogPartNumber = 1
RBPSsuccessfulSends = 0
Gamestarted = 0
Plugin.gameFinished = 0
RBPSnextAwardId= 0
RBPSawards = {}
GameHasStarted = false
Currentgamestate = 0
Buildings = {}

--avoids overload at gameend
stoplogging = false

function Plugin:Initialise()
    self.Enabled = true
    
    --create Commands
    Plugin:CreateCommands()
    
    if self.Config.ServerKey == "" then
        Shared.SendHTTPRequest(Plugin.Config.WebsiteUrl .. "/api/generateKey/?s=7g94389u3r89wujj3r892jhr9fwj", "GET",
            function(response) Plugin:acceptKey(response) end)
    end   
    
    --Timers
    
    --every 1 sec
    --to update Weapondatas
    Shine.Timer.Create( "WeaponUpdate", 1, -1, function()
       if not GameHasStarted then return end
       local allPlayers = Shared.GetEntitiesWithClassname("Player")
       for index, fromPlayer in ientitylist(allPlayers) do            
            Plugin:updateWeaponData(fromPlayer)
       end
    end)
    
    -- every 1 min send Server Status    
     Shine.Timer.Create("SendStatus" , 60, -1, function() if not GameHasStarted then return end if Plugin.Config.Statusreport then Plugin:sendServerStatus(Currentgamestate) end end)

    --every x min (Sendtime at config)
    --send datas to NS2StatsServer
    Shine.Timer.Create( "SendStats", 60 * Plugin.Config.SendTime, -1, function()
        if not GameHasStarted then return end
        if Plugin.Config.Statsonline then Plugin:sendData() end
    end)
    
    return true 
end

-- Events

--Game Events

--Game reset
function Plugin:OnGameReset()

    --Resets all Stats
        Plugin.LogPartNumber = 1
        RBPSsuccessfulSends = 0
        Gamestarted = 0
        Plugin.gameFinished = 0
        RBPSnextAwardId= 0
        RBPSawards = {}
        GameHasStarted = false
        Currentgamestate = 0
        Plugin.Players = {}
        Buildings = {}
  
    Plugin:addLog({action="game_reset"})
end

--Gamestart
function Plugin:SetGameState( Gamerules, NewState, OldState )
    Currentgamestate = NewState    
    if NewState == kGameState.Started then        
        GameHasStarted = true             
        Gamestarted = Shared.GetTime()
        Plugin:addLog({action = "game_start"})
        local allPlayers = Shared.GetEntitiesWithClassname("Player")
        for index, fromPlayer in ientitylist(allPlayers) do
            local client = fromPlayer:GetClient()
            if client then Plugin:UpdatePlayerInTable(client) end          
       end
       
         --send Playerlist            
         Plugin:addPlayersToLog(0)    
    end
end

--Gameend
function Plugin:EndGame( Gamerules, WinningTeam )     
        if Plugin.Config.Awards then Plugin:sendAwardListToClients() end
        Plugin:addPlayersToLog(1)
        stoplogging = true      
        local initialHiveTechIdString = "None"            
        if Gamerules.initialHiveTechId then
                initialHiveTechIdString = EnumToString(kTechId, Gamerules.initialHiveTechId)
        end        
        local params =
            {
                version = ToString(Shared.GetBuildNumber()),
                winner = WinningTeam:GetTeamNumber(),
                length = string.format("%.2f", Shared.GetTime() - Gamerules.gameStartTime),
                map = Shared.GetMapName(),
                start_location1 = Gamerules.startingLocationNameTeam1,
                start_location2 = Gamerules.startingLocationNameTeam2,
                start_path_distance = Gamerules.startingLocationsPathDistance,
                start_hive_tech = initialHiveTechIdString,
            }       
        Plugin:AddServerInfos(params)
        Plugin.gameFinished = 1
        if Plugin.Config.Statsonline then Plugin:sendData()  end --senddata also clears log         
end

--Player Events

--PlayerConnected
function Plugin:ClientConnect( Client )
    if not Client then return end 
    local Config = {}
    Config.WebsiteApiUrl = self.Config.WebsiteApiUrl
    Config.SendMapData = self.Config.SendMapData    
    Server.SendNetworkMessage(Client,"Shine_StatsConfig",Config,true)    
    Plugin:UpdatePlayerInTable(Client)
    --player disconnected and came back
    local RBPSplayer = Plugin:getPlayerByClient(Client)
    
    if RBPSplayer then
        RBPSplayer.dc=false
    end
    
    local connect={
            action = "connect",
            steamId = Plugin:GetId(Client)
    }
    Plugin:addLog(connect)
end

--PlayerDisconnect
function Plugin:ClientDisconnect(Client)
    if not Client then return end
    local Player = Client:GetPlayer()
    if not Player then return end 

    local RBPSplayer = Plugin:getPlayerByClient(Client)    
    if RBPSplayer then
        RBPSplayer.dc=true
    end
    
    local connect={
            action = "disconnect",
            steamId = Plugin:GetId(Client),
            score = Player.score
    }
    Plugin:addLog(connect)
end

--Bots renamed
function Plugin:OnBotRenamed(Bot)
    if Plugin:getPlayerByClient(Bot:GetPlayer():GetClient()) == nil then
    Plugin:ClientConnect(Bot:GetPlayer():GetClient()) end       
end

-- Player joins a team
function Plugin:PostJoinTeam( Gamerules, Player, NewTeam, Force )
    if not Player then return end
    local client = Player:GetClient()
    Plugin:addPlayerJoinedTeamToLog(Player)     
    Plugin:UpdatePlayerInTable(client)
end

--add player joined a team to log
function Plugin:addPlayerJoinedTeamToLog(player)
    if not player then return end
    local client = Server.GetOwner(player)
    if not client then return end
    if not Plugin:getPlayerByName(player.name) then return end 
    local playerJoin =
    {
        action="player_join_team",
        name = player.name,
        team = player:GetTeam():GetTeamNumber(),
        steamId = Plugin:GetId(client),
        score = player.score
    }
        Plugin:addLog(playerJoin)

end

--Player changes Name
function Plugin:PlayerNameChange( Player, Name, OldName )
    if not Player then return end
    local client = Player:GetClient()
    if client == nil then return end
    if client:GetIsVirtual() then return end
    Plugin:UpdatePlayerInTable(client)
end

--Player changes lifeform
function Plugin:OnLifeformChanged(Player, oldEntityId, newEntityId)
   -- search for playername in players table if its there player is real and lifeform change should be tracked
    local taulu = Plugin:getPlayerByName(Player.name)
    if not taulu then return end
    Currentlifeform = Player:GetMapName()
    if not Player:GetIsAlive() then Currentlifeform = "dead" end
    if taulu.isCommander == true then
        if taulu.teamnumber == 1 then
            Currentlifeform = "marine_commander"
        else Currentlifeform = "alien_commander" end
    end
    if taulu.lifeform ~= Currentlifeform then
        taulu.lifeform = Currentlifeform
        Plugin:addLog({action = "lifeform_change", name = taulu.name, lifeform = taulu.lifeform, steamId = taulu.steamId})
    end     
end

--Player become Comm
function Plugin:CommLoginPlayer( Chair, Player )
    if not Player then return end
    local client = Player:GetClient()
    if client:GetIsVirtual() then return end
    Plugin:UpdatePlayerInTable(client)
    Plugin:OnLifeformChanged(Player, nil, nil)
end

--Player log out CC
function Plugin:CommLogout( Chair, Player )
    if not Player then return end
    local client = Player:GetClient()
    if client:GetIsVirtual() then return end
    Plugin:UpdatePlayerInTable(client)
    Plugin:OnLifeformChanged(Player, nil, nil)
end

--score changed
function Plugin:OnPlayerScoreChanged(Player,state)
    if not Player:GetIsAlive() then return end -- player is dead or spectating other player
    if not Plugin:getPlayerByClient(Player:GetClient()) then return end --Player not in Table
    if state and Player:GetClient() then Plugin:UpdatePlayerInTable(Player:GetClient()) end
end

--Player shoots weapon
function Plugin:OnDamageDealt(DamageMixin, damage, target, point, direction, surface, altMode, showtracer)
   
    local attacker = DamageMixin
    if DamageMixin:GetParent() and DamageMixin:GetParent():isa("Player") then
            attacker = DamageMixin:GetParent()
    elseif HasMixin(DamageMixin, "Owner") and DamageMixin:GetOwner() and DamageMixin:GetOwner():isa("Player") then
            attacker = DamageMixin:GetOwner()
    end
    
    if not attacker:isa("Player") then return end 
    
    if damage == 0 or not target then Plugin:addMissToLog(attacker) return end
    if target:isa("Ragdoll") then Plugin:addMissToLog(attacker) return end
    
    local damageType = kDamageType.Normal
    if DamageMixin.GetDamageType then
            damageType = DamageMixin:GetDamageType() end
            
    local doer = attacker:GetActiveWeapon() 
    if not doer then doer = attacker end    
    Plugin:addHitToLog(target, attacker, doer, damage, damageType)
end

--add Hit
function Plugin:addHitToLog(target, attacker, doer, damage, damageType)
    if attacker:isa("Player") then
        if target:isa("Player") then
            local attacker_id = Plugin:GetId(Server.GetOwner(attacker))
            local target_id = Plugin:GetId(Server.GetOwner(target))
            if not attacker_id or not target_id then return end            
            local aOrigin = attacker:GetOrigin()
            local tOrigin = target:GetOrigin()
            local weapon = "none"
            if target:GetActiveWeapon() then
                weapon = target:GetActiveWeapon():GetMapName() end        
            local hitLog =
            {
                --general
                action = "hit_player",	
                
                --Attacker
                attacker_steamId = attacker_id,
                attacker_team = attacker:GetTeam():GetTeamNumber(),
                attacker_weapon = doer:GetMapName(),
                attacker_lifeform = attacker:GetMapName(),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f", aOrigin.x),
                attackery = string.format("%.4f", aOrigin.y),
                attackerz = string.format("%.4f", aOrigin.z),
                
                --Target
                target_steamId = target_id,
                target_team = target:GetTeam():GetTeamNumber(),
                target_weapon = weapon,
                target_lifeform = target:GetMapName(),
                target_hp = target:GetHealth(),
                target_armor = target:GetArmorAmount(),
                targetx = string.format("%.4f", tOrigin.x),
                targety = string.format("%.4f", tOrigin.y),
                targetz = string.format("%.4f", tOrigin.z),
                
                damageType = damageType,
                damage = damage
                
            }

            Plugin:addLog(hitLog)
            Plugin:weaponsAddHit(attacker, doer:GetMapName(), damage)                
            
        else --target is a structure
            local structureOrigin = target:GetOrigin()
            local aOrigin = attacker:GetOrigin()
            local hitLog =
            {
                
                --general
                action = "hit_structure",	
                
                --Attacker
                attacker_steamId =  attacker_id,
                attacker_team = attacker:GetTeam():GetTeamNumber(),
                attacker_weapon = doer:GetMapName(),
                attacker_lifeform = attacker:GetMapName(),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f",  aOrigin.x),
                attackery = string.format("%.4f",  aOrigin.y),
                attackerz = string.format("%.4f",  aOrigin.z),
                            
                structure_id = target:GetId(),
                structure_name = target:GetMapName(),	
                structure_x = string.format("%.4f", structureOrigin.x),
                structure_y = string.format("%.4f", structureOrigin.y),
                structure_z = string.format("%.4f", structureOrigin.z),	

                damageType = damageType,
                damage = damage
            }
            
            Plugin:addLog(hitLog)
            Plugin:weaponsAddStructureHit(attacker, doer:GetMapName(), damage)
            
        end
    end         
end

--Add miss
function Plugin:addMissToLog(attacker)

    local weapon = "none"
    local RBPSplayer = nil
             
    if attacker and attacker:isa("Player") and attacker.name then
    
        RBPSplayer = Plugin:getPlayerByName(attacker.name)
        if not RBPSplayer then return end

    if attacker.GetActiveWeapon and attacker:GetActiveWeapon() then
        weapon = attacker:GetActiveWeapon():GetMapName()
    end
        
        --local missLog =
        --{
            
        -- --general
        -- action = "miss",
            
        -- --Attacker
        -- attacker_steamId = RBPSplayer.steamId,
        -- attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
        -- attacker_weapon = attackerWeapon,
        -- attacker_lifeform = attacker:GetMapName(),
        -- attacker_hp = attacker:GetHealth(),
        -- attacker_armor = attacker:GetArmorAmount(),
        -- attackerx = RBPSplayer.x,
        -- attackery = RBPSplayer.y,
        -- attackerz = RBPSplayer.z
        --}
        
        ----Lisätään data json-muodossa logiin.
        --Plugin:addLog(missLog)
        --gorge fix
        if weapon == "spitspray" then
            weapon = "spit"
        end
        
        Plugin:weaponsAddMiss(RBPSplayer,weapon)
    end
end

--weapon add miss
function Plugin:weaponsAddMiss(RBPSplayer,weapon)
        
    if not RBPSplayer then return end
            
    local foundId = false
      
    for i=1, #RBPSplayer.weapons do
        if RBPSplayer.weapons[i].name == weapon then
            foundId=i
            break
        end
    end

    if foundId then
        RBPSplayer.weapons[foundId].miss = RBPSplayer.weapons[foundId].miss + 1
    else --add new weapon
        table.insert(RBPSplayer.weapons,
        {
            name = weapon,
            time = 0,
            miss = 1,
            player_hit = 0,
            structure_hit = 0,
            player_damage = 0,
            structure_damage = 0
        })
    end        
end

--weapon addhit to player
function Plugin:weaponsAddHit(player, weapon, damage)

    local RBPSplayer = Plugin:getPlayerByName(player:GetName())   
    if not RBPSplayer then return end
    
    local foundId = false
      
    for i=1, #RBPSplayer.weapons do
        if RBPSplayer.weapons[i].name == weapon then
            foundId=i
            break
        end
    end

    if foundId then
        RBPSplayer.weapons[foundId].player_hit = RBPSplayer.weapons[foundId].player_hit + 1
        RBPSplayer.weapons[foundId].player_damage = RBPSplayer.weapons[foundId].player_damage + damage
        
    else --add new weapon
        table.insert(RBPSplayer.weapons,
        {
            name = weapon,
            time = 0,
            miss = 0,
            player_hit = 1,
            structure_hit = 0,
            player_damage = damage,
            structure_damage = 0
        })
    end        
end

--weapon addhit to structure
function Plugin:weaponsAddStructureHit(player,weapon, damage)
    local RBPSplayer = Plugin:getPlayerByName(player:GetName())      
    if not RBPSplayer then return end
    
    local foundId = false
      
    for i=1, #RBPSplayer.weapons do
        if RBPSplayer.weapons[i].name == weapon then
            foundId=i
            break
        end
    end

    if foundId then
        RBPSplayer.weapons[foundId].structure_hit = RBPSplayer.weapons[foundId].structure_hit + 1
        RBPSplayer.weapons[foundId].structure_damage = RBPSplayer.weapons[foundId].structure_damage + damage

    else --add new weapon
        table.insert(RBPSplayer.weapons,
        {
            name = weapon,
            time = 0,
            miss = 0,
            player_hit = 0,
            structure_hit = 1,
            player_damage = 0,
            structure_damage = damage
        })
    end
        
end

--OnDamagedealt end

--Player jumps
function Plugin:OnPlayerJump(Player)
    local taulu = Plugin:getPlayerByName(Player.name)
    taulu.jumps = taulu.jumps + 1   
end

--Chatlogging
function Plugin:PlayerSay( Client, Message )

    if not Plugin.Config.LogChat then return end
    
    Plugin:addLog({
        action = "chat_message",
        team = Client:GetPlayer():GetTeamNumber(),
        steamid = Plugin:GetId(Client),
        name = Client:GetPlayer():GetName(),
        message = Message.message,
        toteam = Message.teamOnly
    })
end

--Team Events

--Pickable Stuff

--Item is dropped
function Plugin:OnPickableItemCreated(item)

    local techId = item:GetTechId()
    local structureOrigin = item:GetOrigin()
    local steamid = Plugin:getTeamCommanderSteamid(item:GetTeamNumber())
    local newItem =
    {
        commander_steamid = steamid,
        instanthit = false,
        id = item:GetId(),
        cost = GetCostForTech(techId),
        team = item:GetTeamNumber(),
        name = EnumToString(kTechId, techId),
        action = "pickable_item_dropped",
        x = string.format("%.4f", structureOrigin.x),
        y = string.format("%.4f", structureOrigin.y),
        z = string.format("%.4f", structureOrigin.z)
    }

    Plugin:addLog(newItem)	

end

--Item is picked
function Plugin:OnPickableItemPicked(item, player)

    local techId = item:GetTechId()
    local structureOrigin = item:GetOrigin()

    local client = player:GetClient()
    local steamId = 0

    if client then
    steamId = client:GetUserId()
    end

    local newItem =
    {
        steamId = SteamId,
        id = item:GetId(),
        cost = GetCostForTech(techId),
        team = player:GetTeamNumber(),
        name = EnumToString(kTechId, techId),
        action = "pickable_item_picked",
        x = string.format("%.4f", structureOrigin.x),
        y = string.format("%.4f", structureOrigin.y),
        z = string.format("%.4f", structureOrigin.z)
    }

    Plugin:addLog(newItem)	

end

--Item gets destroyed
function Plugin:OnPickableItemDestroyed(item)

    local techId = item:GetTechId()
    local structureOrigin = item:GetOrigin()

    local newItem =
    {
        id = item:GetId(),
        cost = GetCostForTech(techId),
        team = item:GetTeamNumber(),
        name = EnumToString(kTechId, techId),
        action = "pickable_item_destroyed",
        x = string.format("%.4f", structureOrigin.x),
        y = string.format("%.4f", structureOrigin.y),
        z = string.format("%.4f", structureOrigin.z)
    }

    Plugin:addLog(newItem)	

end

--Pickable Stuff end

--Resource gathered
function Plugin:OnTeamGetResources(ResourceTower)
    
    local newResourceGathered =
    {
        team = ResourceTower:GetTeam():GetTeamNumber(),
        action = "resources_gathered",
        amount = kTeamResourcePerTick
    }

    Plugin:addLog(newResourceGathered)
end

--Structure Events

--Building Dropped
function Plugin:OnConstructInit( Building )
    local ID = Building:GetId()      
    local Team = Building:GetTeam()

    if not Team then return end

    local Owner = Building:GetOwner()
    Owner = Owner or Team:GetCommander()

    if not Owner then return end

    local Client = Server.GetOwner( Owner )
    local techId = Building:GetTechId()
    local name = EnumToString(kTechId, techId)
    if name == "Hydra" or name == "GorgeTunnel" then return end --Gorge Buildings
    local strloc = Building:GetOrigin()
    local build=
    {
        action = "structure_dropped",
        id = Building:GetId(),
        steamId = Plugin:GetId(Client),
        team = Building:GetTeamNumber(),
        structure_cost = GetCostForTech(techId),
        structure_name = name,
        structure_x = string.format("%.4f",strloc.x),
        structure_y = string.format("%.4f",strloc.y),
        structure_z = string.format("%.4f",strloc.z),
    }
    Plugin:addLog(build)
end

--Building built
function  Plugin:OnFinishedBuilt(ConstructMixin, builder)    
    local techId = ConstructMixin:GetTechId()
    Buildings[ConstructMixin:GetId()] = true  
    local strloc = ConstructMixin:GetOrigin()
    local client = Server.GetOwner(builder)
    local team = ConstructMixin:GetTeamNumber()
    local steamId = Plugin:getTeamCommanderSteamid(team)
    local buildername = ""

    if client then
        steamId = Plugin:GetId(client)
        buildername = builder:GetName()
        for key,taulu in pairs(Plugin.Players) do 
            if taulu.steamId == steamId then
                taulu.total_constructed = taulu.total_constructed + 1
                break
            end
        end        
    end
    
    local build=
    {
        action = "structure_built",
        id = ConstructMixin:GetId(),
        builder_name = buildername,
        steamId = steamId,
        structure_cost = GetCostForTech(techId),
        team = team,
        structure_name = EnumToString(kTechId, techId),
        structure_x = string.format("%.4f",strloc.x),
        structure_y = string.format("%.4f",strloc.y),
        structure_z = string.format("%.4f",strloc.z),
    }
    Plugin:addLog(build)
end

--Ghost Buildings (Blueprints)

function Plugin:OnGhostCreated(GhostStructureMixin)
     Plugin:ghostStructureAction("ghost_create",GhostStructureMixin,nil)
end

function Plugin:OnGhostDestroyed(GhostStructureMixin,techNode, position)
    if techNode.techId == kTechId.Cancel and GhostStructureMixin:GetIsGhostStructure() then
        Plugin:ghostStructureAction("ghost_destroy",GhostStructureMixin,nil)
    end
end

--addfunction

function Plugin:ghostStructureAction(action,structure,doer)
        
    if not structure then return end
    local techId = structure:GetTechId()
    local structureOrigin = structure:GetOrigin()
    
    local log = nil
    
    log =
    {
        action = action,
        structure_name = EnumToString(kTechId, techId),
        team = structure:GetTeamNumber(),
        id = structure:GetId(),
        structure_x = string.format("%.4f", structureOrigin.x),
        structure_y = string.format("%.4f", structureOrigin.y),
        structure_z = string.format("%.4f", structureOrigin.z)
    }
    
    if action == "ghost_remove" then
        --something extra here? we can use doer here
    end
    Plugin:addLog(log)    
end

--Upgrade Stuff

--UpgradesStarted
function Plugin:OnTechStartResearch(ResearchMixin, researchNode, player)
    if player:isa("Commander") then
    	local client = Server.GetOwner(player)
        local steamId = ""
        if client ~= nil then steamId = Plugin:GetId(client) end
        local techId = researchNode:GetTechId()

        local newUpgrade =
        {
        structure_id = ResearchMixin:GetId(),
        commander_steamid = steamId,
        team = player:GetTeamNumber(),
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId),
        action = "upgrade_started"
        }

        Plugin:addLog(newUpgrade)
    end
end

--temp to fix Uprades loged multiple times
OldUpgrade = -1

--Upgradefinished
function Plugin:OnTechResearched( ResearchMixin,structure,researchId)
    local researchNode = ResearchMixin:GetTeam():GetTechTree():GetTechNode(researchId)
    local techId = researchNode:GetTechId()
    if  techId == OldUpgrade then return end
    OldUpgrade = techId
    local newUpgrade =
    {
        structure_id = structure:GetId(),
        team = structure:GetTeamNumber(),
        commander_steamid = Plugin:getTeamCommanderSteamid(structure:GetTeamNumber()),
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId),
        action = "upgrade_finished"
    }

    Plugin:addLog(newUpgrade)
end

--Upgrade lost
function Plugin:addUpgradeLostToLog(UpgradableMixin, techId)

    local teamNumber = UpgradableMixin:GetTeamNumber()

    local newUpgrade =
    {
        team = teamNumber,
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId), 
        action = "upgrade_lost"
    }

    Plugin:addLog(newUpgrade)

end

--Research canceled
function Plugin:addUpgradeAbortedToLog(ResearchMixin, researchNode)
    local techId = researchNode:GetTechId()
    local steamid = Plugin:getTeamCommanderSteamid(ResearchMixin:GetTeamNumber())

    local newUpgrade =
    {
        structure_id = ResearchMixin:GetId(),
        team = ResearchMixin:GetTeamNumber(),
        commander_steamid = steamid,
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId),
        action = "upgrade_aborted"
    }

    Plugin:addLog(newUpgrade)

end

--Building recyled
function Plugin:OnBuildingRecycled( Building, ResearchID )
    local structure = Building
    local structureOrigin = structure:GetOrigin()
    local techId = structure:GetTechId()
    
    --from RecyleMixin.lua
        local upgradeLevel = 0
        if structure.GetUpgradeLevel then
            upgradeLevel = structure:GetUpgradeLevel()
        end        
        local amount = GetRecycleAmount(techId, upgradeLevel)
        -- returns a scalar from 0-1 depending on health the structure has (at the present moment)
        local scalar = structure:GetRecycleScalar() * kRecyclePaybackScalar
        
        -- We round it up to the nearest value thus not having weird
        -- fracts of costs being returned which is not suppose to be
        -- the case.
        local finalRecycleAmount = math.round(amount * scalar)
    --end   

    local newUpgrade =
    {
        id = structure:GetId(),
        team = structure:GetTeamNumber(),
        givenback = finalRecycleAmount,
        structure_name = EnumToString(kTechId, techId),
        action = "structure_recycled",
        structure_x = string.format("%.4f", structureOrigin.x),
        structure_y = string.format("%.4f", structureOrigin.y),
        structure_z = string.format("%.4f", structureOrigin.z)
    }

    Plugin:addLog(newUpgrade)
end

--Structure gets killed
function Plugin:OnStructureKilled(structure, attacker , doer)
    Buildings[structure:GetId()] = nil                
        local structureOrigin = structure:GetOrigin()
        local techId = structure:GetTechId()
        if not doer then doer = "none" end
        --Structure killed
        if attacker then 
            local player = attacker         
            local client = Server.GetOwner(player)
            local steamId = 0
            local weapon = ""

            if client then steamId = Plugin:GetId(client) end

            if not doer then weapon = "self"
            else weapon = doer:GetMapName()
            end

            local newStructure =
            {
            id = structure:GetId(),
            killer_steamId = steamId,
            killer_lifeform = player:GetMapName(),
            killer_team = player:GetTeamNumber(),
            structure_team = structure:GetTeamNumber(),
            killerweapon = weapon,
            structure_cost = GetCostForTech(techId),
            structure_name = EnumToString(kTechId, techId),
            action = "structure_killed",
            structure_x = string.format("%.4f", structureOrigin.x),
            structure_y = string.format("%.4f", structureOrigin.y),
            structure_z = string.format("%.4f", structureOrigin.z)
            }
            Plugin:addLog(newStructure)
                
        --Structure suicide
        else
            local newStructure =
            {
                id = structure:GetId(),
                structure_team = structure:GetTeamNumber(),
                structure_cost = GetCostForTech(techId),
                structure_name = EnumToString(kTechId, techId),
                action = "structure_suicide",
                structure_x = string.format("%.4f", structureOrigin.x),
                structure_y = string.format("%.4f", structureOrigin.y),
                structure_z = string.format("%.4f", structureOrigin.z)
            }
            Plugin:addLog(newStructure)
        end 
end

--Mixed Events 

--Entity Killed
function Plugin:OnEntityKilled(Gamerules, TargetEntity, Attacker, Inflictor, Point, Direction)    
    
    if TargetEntity:isa("Player") then Plugin:addDeathToLog(TargetEntity, Attacker, Inflictor)
    elseif TargetEntity:isa("DropPack") then Plugin:OnPickableItemDestroyed(TargetEntity) 
    elseif Buildings[TargetEntity:GetId()] then Plugin:OnStructureKilled(TargetEntity, Attacker, Inflictor)       
    end   
end

--add Player death to Log
function Plugin:addDeathToLog(target, attacker, doer)
    if attacker  and doer and target then
        local attackerOrigin = attacker:GetOrigin()
        local targetWeapon = "none"
        local targetOrigin = target:GetOrigin()
        local attacker_client = Server.GetOwner(attacker)
        local target_client = Server.GetOwner(target)
        if not target_client or attacker_client then return end
        Plugin:UpdatePlayerInTable(target_client)  
        if target:GetActiveWeapon() then
                targetWeapon = target:GetActiveWeapon():GetMapName()
        end

        --Jos on quitannu servulta justiin ennen tjsp niin ei ole clienttiä ja erroria pukkaa. (uwelta kopsasin)
        if attacker:isa("Player") then
            local deathLog =
            {
                
                --general
                action = "death",	
                
                --Attacker
                attacker_steamId = Plugin:GetId(attacker_client),
                attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
                attacker_weapon = doer:GetMapName(),
                attacker_lifeform = attacker:GetMapName(), --attacker:GetPlayerStatusDesc(),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f", attackerOrigin.x),
                attackery = string.format("%.4f", attackerOrigin.y),
                attackerz = string.format("%.4f", attackerOrigin.z),
                
                --Target
                target_steamId = Plugin:GetId(target_client),
                target_team = target:GetTeamType(),
                target_weapon = targetWeapon,
                target_lifeform = target:GetMapName(), --target:GetPlayerStatusDesc(),
                target_hp = target:GetHealth(),
                target_armor = target:GetArmorAmount(),
                targetx = string.format("%.4f", targetOrigin.x),
                targety = string.format("%.4f", targetOrigin.y),
                targetz = string.format("%.4f", targetOrigin.z),
                target_lifetime = string.format("%.4f", Shared.GetTime() - target:GetCreationTime())
            }
            
                --Lisätään data json-muodossa logiin.
                Plugin:addLog(deathLog)
            
                if attacker:GetTeamNumber() ~= target:GetTeamNumber() then                   
                    --addkill
                    Plugin:addKill(Plugin:GetId(attacker_client), Plugin:GetId(target_client))                  
                end
            
            else
                --natural causes death
                local deathLog =
                {
                    --general
                    action = "death",

                    --Attacker
                    attacker_weapon	= "natural causes",

                    --Target
                    target_steamId = Plugin:GetId(target_client),
                    target_team = target:GetTeamType(),
                    target_weapon = targetWeapon,
                    target_lifeform = target:GetMapName(), --target:GetPlayerStatusDesc(),
                    target_hp = target:GetHealth(),
                    target_armor = target:GetArmorAmount(),
                    targetx = string.format("%.4f", targetOrigin.x),
                    targety = string.format("%.4f", targetOrigin.y),
                    targetz = string.format("%.4f", targetOrigin.z),
                    target_lifetime = string.format("%.4f", Shared.GetTime() - target:GetCreationTime())	
                }
                Plugin:addLog(deathLog)       
    end
    elseif target then --suicide
        local target_client = Server.GetOwner(target)       
        local targetWeapon = "none"
        local targetOrigin = target:GetOrigin()
        local attacker_client = Server.GetOwner(target) --easy way out        
        local attackerOrigin = targetOrigin
        local attacker = target
         local deathLog =
            {
                
                --general
                action = "death",	
                
                --Attacker (

                attacker_weapon = "self",
                attacker_lifeform = attacker:GetMapName(),
                attacker_steamId = attacker_client:GetUserId(),
                attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f", attackerOrigin.x),
                attackery = string.format("%.4f", attackerOrigin.y),
                attackerz = string.format("%.4f", attackerOrigin.z),
                
                --Target
                target_steamId = Plugin:GetId(target_client),
                target_team = target:GetTeamType(),
                target_weapon = targetWeapon,
                target_lifeform = target:GetMapName(),
                target_hp = target:GetHealth(),
                target_armor = target:GetArmorAmount(),
                targetx = string.format("%.4f", targetOrigin.x),
                targety = string.format("%.4f", targetOrigin.y),
                targetz = string.format("%.4f", targetOrigin.z),
                target_lifetime = string.format("%.4f", Shared.GetTime() - target:GetCreationTime())
            }
            
            Plugin:addLog(deathLog)
            Plugin:UpdatePlayerInTable(target_client)  
    end    
end

--Check Killstreaks
function Plugin:addKill(attacker_steamId,target_steamId)
    for key,taulu in pairs(Plugin.Players) do	
        if taulu.steamId == attacker_steamId then	
            taulu.killstreak = taulu.killstreak +1	
            Plugin:checkForMultiKills(taulu.name,taulu.killstreak)
            if taulu.killstreak > taulu.highestKillstreak then
                taulu.highestKillstreak = taulu.killstreak
            end 
        end            
    end
end

--Todo: Multikills ?
function Plugin:checkForMultiKills(name,streak)
    --add sounds?
end

--Events end

--Log functions

--add to log
function Plugin:addLog(tbl)

    if stoplogging and tbl.action ~= "game_ended" then return end 
    stoplogging = false   
    if not Plugin.Log then Plugin.Log = {} end
    if not Plugin.Log[Plugin.LogPartNumber] then Plugin.Log[Plugin.LogPartNumber] = "" end
    if not tbl then return end 
    tbl.time = Shared.GetGMTString(false)
    tbl.gametime = Shared.GetTime() - Gamestarted
    Plugin.Log[Plugin.LogPartNumber] = Plugin.Log[Plugin.LogPartNumber] .. json.encode(tbl) .."\n"	
    
    --avoid that log gets too long also do resend by this way
    if string.len(Plugin.Log[Plugin.LogPartNumber]) > 160000 then
    
        if Plugin.Config.Statsonline then 
            -- don't reach critical length of 500 000
            if string.len(Plugin.Log[Plugin.LogPartNumber]) > 490000 then
                Notify("[NS2Stats]: The Log has reached a critical size we will stop logging now. This is probably because the NS2Stats Servers are offline at the moment")
                
                --disable online stats
                Plugin.Config.Statsonline= false
                Plugin.LogPartNumber = Plugin.LogPartNumber + 1 
             
           else Plugin:sendData() end
        else Plugin.LogPartNumber = Plugin.LogPartNumber + 1 end
    end
    --local data = RBPSlibc:CompressHuffman(Plugin.Log)
    --Notify("compress size: " .. string.len(data) .. "decompress size: " .. string.len(RBPSlibc:Decompress(data)))        
end

--add playerlist to log
function Plugin:addPlayersToLog(type)
 
    local tmp = {}
    
    if type == 0 then
        tmp.action = "player_list_start"
    else
        tmp.action = "player_list_end"
    end
  
    --reset codes
    for p = 1, #Plugin.Players do	
        local player = Plugin.Players[p]	
        player.code = 0
    end
    
    tmp.list = Plugin.Players
    
    Plugin:addLog(tmp)
end

--Add server infos
function Plugin:AddServerInfos(params)
    local mods = ""
    local GetMod = Server.GetActiveModId
    for i = 1, Server.GetNumActiveMods() do
        local Mod = GetMod( i )
        for i = 1, Server.GetNumMods() do
            if Server.GetModId(i) == Mod then
                mods = mods .. Server.GetModTitle(i) .. ","
                break
            end
        end 
    end 
    params.action = "game_ended"
    params.statsVersion = Plugin.Version
    params.serverName = Server.GetName()
    params.successfulSends = RBPSsuccessfulSends
    params.resendCount = RBPSresendCount
    params.mods = mods
    params.awards = RBPSawards
    params.tags = self.Config.Tags
    params.private = self.Config.Competitive
    params.autoarrange = false --use Shine plugin settings later?
    local ip = IPAddressToString(Server.GetIpAddress()) 
    if not string.find(ip,":") then ip = ip .. ":27015" end
    params.serverInfo =
    {
        password = "",
        IP = ip,
        count = 30 --servertick?
    }
    Plugin:addLog(params)
end

-- avoid that sendata is runned to often
local working = false

--send Log to NS2Stats Server
function Plugin:sendData()

    -- one senddata already running?
    if working then return end
    
    --sendata is working now
    working = true
    
    local params =
    {
        key = self.Config.ServerKey,
        roundlog = Plugin.Log[Plugin.LogPartNumber],
        part_number = Plugin.LogPartNumber,
        last_part = Plugin.gameFinished,
        map = Shared.GetMapName(),
    }    
    Shared.SendHTTPRequest(self.Config.WebsiteDataUrl, "POST", params, function(response,status,params) Plugin:onHTTPResponseFromSend(client,"send",response,status,params) end)
end

local resendtimes = 0

--Analyze the answer of server
function Plugin:onHTTPResponseFromSend(client,action,response,status,params)	
        local message = json.decode(response)        
        if message then
        
            if string.len(response)>0 then --if we got somedata, that means send was completed
                RBPSsuccessfulSends = RBPSsuccessfulSends +1
                 if not string.find(response,"Server log empty",nil, true) then
                     Plugin.Log[Plugin.LogPartNumber] = nil
                     resendtimes = 0
                     Plugin.LogPartNumber = Plugin.LogPartNumber + 1  
                end
            end
        
            if message.other then
                Notify("[NSStats]: ".. message.other)
            end
        
            if message.error == "NOT_ENOUGH_PLAYERS" then
                   local playerList = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
                Notify("[NS2Stats]: Send failed because of too less players ")
                return
            end	

            if message.link then
                local link = Plugin.Config.WebsiteUrl .. message.link	
                local playerList = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
                Shine:Notify( nil, "", "", "Round has been safed to NS2Stats : " .. link)
                Plugin.Config.Lastroundlink = link
                self:SaveConfig()                
            end	
        elseif response then --if message = nil, json parse failed prob or timeout
            if string.len(response)>0 then --if we got somedata, that means send was completed
                RBPSsuccessfulSends = RBPSsuccessfulSends +1
                if not string.find(response,"Server log empty",nil, true) then
                     Plugin.Log[Plugin.LogPartNumber] = nil
                     resendtimes = 0
                     Plugin.LogPartNumber = Plugin.LogPartNumber + 1                      
                end
            end
            Notify("NS2Stats.org: (" .. response .. ")")
       elseif not response then --we couldn't reach the NS2Stats Servers
            if params then            
                -- try to resend log in the next 5 min once per min
                if params.last_part == 0 then return end
                if resendtimes >= 5 then return end
                resendtimes = resendtimes + 1              
                Shine.Timer.Simple(60, function(client,response,status,params) Shared.SendHTTPRequest(self.Config.WebsiteDataUrl, "POST", params, function(response,status,params) Plugin:onHTTPResponseFromSend(client,"send",response,status,params) end) end)               
            end
    end
    
    -- senddata was finished
    working = false
    
end

--Log end 

--Player table functions

--add Player to table
function Plugin:addPlayerToTable(client)
    if not client then return end
    if not Plugin:GetId(client) then return end
    table.insert(Plugin.Players, Plugin:createPlayerTable(client))    
end

--create new entry
function Plugin:createPlayerTable(client)	
    local player = client:GetPlayer()
    if player == nil then
        Notify("Tried to update nil player")
    return
    end

    local taulu= {}   
    taulu.teamnumber = player:GetTeam():GetTeamNumber() or 0
    taulu.lifeform = player:GetMapName() or ""
    taulu.score = player.score or 0
    taulu.assists = player.assistkills or 0
    taulu.deaths = player.deaths or 0
    taulu.kills = player.kills or 0
    taulu.totalKills = player.totalKills or 0
    taulu.totalAssists = player.totalAssists or 0
    taulu.totalDeaths = player.totalDeaths or 0
    taulu.playerSkill = player.playerSkill or 0
    taulu.totalScore = player.totalScore or 0
    taulu.totalPlayTime = player.totalPlayTime or 0
    taulu.playerLevel = player.playerLevel or 0
    
    --if player is dead
    if player:GetIsAlive() == false then
        taulu.damageTaken = {}
        taulu.killstreak = 0
        taulu.lifeform = "dead"
    end
   
    taulu.steamId = Plugin:GetId(client) or 0
    taulu.name = player:GetName() or ""
    taulu.ping = client:GetPing() or 0
    taulu.teamnumber = player:GetTeamNumber() or 0
    taulu.isbot = client:GetIsVirtual() or false	
    taulu.isCommander = player:GetIsCommander() or false
    if taulu.isCommander then
        if taulu.teamnumber == 1 then
            taulu.lifeform = "marine_commander"
        else taulu.lifeform = "alien_commander" end
    end	        
    taulu.dc = false
    taulu.total_constructed=0        
    taulu.weapons = {}
    taulu.damageTaken = {}        
    taulu.killstreak =0
    taulu.highestKillstreak =0
    taulu.jumps = 0
            
    --for bots
    if taulu.isbot == true then
        taulu.ping = 0
        taulu.ipaddress = "127.0.0.1"
    else
        taulu.ping = client:GetPing()
        taulu.ipaddress = IPAddressToString(Server.GetClientAddress(client))
    end
    return taulu
end

--Update Player Entry
function Plugin:UpdatePlayerInTable(client)
    if not client then return end    
    local player = client:GetPlayer()    
    if not player then return end
    if not player:GetTeam() then return end
    
    local steamId = Plugin:GetId(client)
   
    if not steamId then return end
    
    if not Plugin:IsClientInTable(client) then Plugin:addPlayerToTable(client) return end
    local taulu = Plugin:getPlayerByClient(client)
    taulu.teamnumber = player:GetTeam():GetTeamNumber() or 0
    taulu.lifeform = player:GetMapName() or ""
    taulu.score = player.score or 0
    taulu.assists = player.assistkills or 0
    taulu.deaths = player.deaths or 0
    taulu.kills = player.kills or 0
    taulu.totalKills = player.totalKills or 0
    taulu.totalAssists = player.totalAssists or 0
    taulu.totalDeaths = player.totalDeaths or 0
    taulu.playerSkill = player.playerSkill or 0
    taulu.totalScore = player.totalScore or 0
    taulu.totalPlayTime = player.totalPlayTime or 0
    taulu.playerLevel = player.playerLevel or 0
    
    --if player is dead
    if player:GetIsAlive() == false then
        taulu.damageTaken = {}
        taulu.killstreak = 0
        taulu.lifeform = "dead"
    end
   
    taulu.steamId = Plugin:GetId(client) or 0
    taulu.name = player:GetName() or ""
    taulu.ping = client:GetPing() or 0
    taulu.teamnumber = player:GetTeamNumber() or 0
    taulu.isbot = client:GetIsVirtual() or false	
    taulu.isCommander = player:GetIsCommander() or false
    if taulu.isCommander then
        if taulu.teamnumber == 1 then
            taulu.lifeform = "marine_commander"
        else taulu.lifeform = "alien_commander" end
    end       
end


--All search functions
function Plugin:IsClientInTable(client)

    if not client then return false end
    local steamId = Plugin:GetId(client)
    if not steamId then return false end
    
    for p = 1, #Plugin.Players do	
        local player = Plugin.Players[p]	

        if player.steamId == steamId then
            return true
        end	
    end
        
    return false
end


function Plugin:getPlayerClientBySteamId(steamId)
    if not steamId then return end        
    for list, victim in ientitylist(Shared.GetEntitiesWithClassname("Player")) do            
        local client = victim:GetClient()
        if client and Plugin:GetId(client) then
            if Plugin:GetId(client) == tonumber(steamId) then	
                return client	
            end
        end                
     end            
    return nil                            
end

function Plugin:getPlayerByClientId(client)
    if not client  then return end
    local steamId = Plugin:GetId(client)
    if not steamId then return end

    for key,taulu in pairs(Plugin.Players) do        
            if taulu["steamId"] == steamId then return taulu end
    end
end

function Plugin:getTeamCommanderSteamid(teamNumber)
    for key,taulu in pairs(Plugin.Players) do	
        if taulu["isCommander"] and taulu["teamnumber"] == teamNumber then
            return taulu["steamId"]
        end	
    end

    return -1
end

function Plugin:getPlayerBySteamId(steamId)
   if not steamId then return end
   for key,taulu in pairs(Plugin.Players) do         
            if tostring(taulu.steamId) == tostring(steamId)  then return taulu end
   end
end

function Plugin:getPlayerByName(name)
    if not name then return end
    for key,taulu in pairs(Plugin.Players) do        
        if taulu["name"] == name then return taulu end	
    end
end

function Plugin:getPlayerByClient(client)
    if not client then return end
    local steamId = nil
    local name = nil
    if type(client["GetUserId"]) ~= "nil" then
        steamId = Plugin:GetId(client)
    else
        if type(client["GetPlayer"]) ~= "nil" then
                local player = client:GetPlayer()
                local name = player:GetName()
            else
                return
        end
    end

    for key,taulu in pairs(Plugin.Players) do	
        if steamId then
            if taulu["steamId"] == steamId then return taulu end
        end
            
        if name then
            if taulu["name"] == name then return taulu end
        end	
    end
    return nil
end

--Plyer Table end

--GetIds

function Plugin:GetId(client)
    local id = -1 --placeholder
    if client then 
        id = client:GetUserId()
        if id == 0 then id = Plugin:GetIdbyName(client:GetPlayer():GetName()) end --0 = Bot
    end
    
    return id    
end

--display warning only once
local a = true

--For Bots
function Plugin:GetIdbyName(Name)

    if not Name then return -1 end
    
    --disable Onlinestats
    if a then Notify( "NS2Stats won't store game with bots. Disabling online stats now!") a=false end
    Plugin.Config.Statsonline = false
    
    local newId=""
    local letters = " (){}[]/.,+-=?!*1234567890aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ"
    
    --cut the [Bot]
    local input = tostring(Name)
    input = input:sub(6,#input)
    
    --to differ between e.g. name and name (2)   
    input = string.reverse(input)
    
    for i=1, #input do
        local char = input:sub(i,i)
        local num = string.find(letters,char,nil,true)
        newId = newId .. tostring(num)        
    end
    
    --fill up the ns2id to 12 numbers
    while string.len(newId) < 12 do
        newId = newId .. "0"
    end       
    newId = string.sub(newId, 1 , 12)
    
    --make a int
    newId = tonumber(newId)
    return newId
end

--Ids end

--Timer functions

function Plugin:updateWeaponData(player)
    -- Happens every second,
    -- checks if current weapon exists in weapons table,
    -- if it does increases it by 1, if it doesnt its added
    -- Test to use Think() Hook with this
    if not player then return end
    local RBPSplayer = Plugin:getPlayerByName(player.name)
    local foundId = false
    if not RBPSplayer then return end
    local weapon = "none"
    if player:GetActiveWeapon() then weapon = player:GetActiveWeapon():GetMapName() end
    for i=1, #RBPSplayer.weapons do
        if RBPSplayer.weapons[i].name == weapon then foundId=i end
    end
    
    if foundId then
        RBPSplayer.weapons[foundId].time = RBPSplayer.weapons[foundId].time + 1
    else --add new weapon
        table.insert(RBPSplayer.weapons,
        {
            name = weapon,
            time = 1,
            miss = 0,
            player_hit = 0,
            structure_hit = 0,
            player_damage = 0,
            structure_damage = 0
        })
    end
end

--Timer end

-- Other ns2stats functions

--generates server key
function Plugin:acceptKey(response)
        if not response or response == "" then
            Notify("NS2Stats: Unable to receive unique key from server, stats wont work yet. ")
            Notify("NS2Stats: Server restart might help.")
        else
            local decoded = json.decode(response)
            if decoded and decoded.key then
                self.Config.ServerKey = decoded.key
                Notify("NS2Stats: Key " .. self.Config.ServerKey .. " has been assigned to this server")
                Notify("NS2Stats: You may use admin command sh_verity to claim this server.")
                Notify("NS2Stats setup complete.")
                self:SaveConfig()
                                
            else
                Notify("NS2Stats: Unable to receive unique key from server, stats wont work yet. ")
                Notify("NS2Stats: Server restart might help.")
                Notify("NS2Stats: Server responded: " .. response)
            end
        end
end

--send Status report to NS2Stats
function Plugin:sendServerStatus(gameState)
    local stime = Shared.GetGMTString(false)
    local gameTime = Shared.GetTime() - Gamestarted
        local params =
        {
            key = self.Config.ServerKey,
            players = json.encode(Plugin.Players),
            state = gameState,
            time = stime,
            gametime = gameTime,
            map = Shared.GetMapName(),
        }

    Shared.SendHTTPRequest(self.Config.WebsiteStatusUrl, "POST", params, function(response,status) Plugin:onHTTPResponseFromSendStatus(client,"sendstatus",response,status) end)	
end

function Plugin:onHTTPResponseFromSendStatus(client,action,response,status)
    --Maybe add Log notice
end

--Other Ns2Stat functions end

--Commands
function Plugin:CreateCommands()
    
    local ShowPStats = self:BindCommand( "sh_showplayerstats", {"showplayerstats","showstats" }, function(Client)
        Shared.SendHTTPRequest( self.Config.WebsiteApiUrl .. "/player?ns2_id=" .. tostring(Plugin:GetId(Client)), "GET",function(response)   
            local Data = json.decode(response)
            local playerid = ""
            if Data then playerid = Data[1].player_page_id or "" end
            local url = self.Config.WebsiteUrl .. "/player/player/" .. playerid
            if self.Config.IngameBrowser then Server.SendNetworkMessage( Client, "Shine_Web", { URL = url }, true )
            else Client.ShowWebpage(url)
            end
        end)      
    end,true)
    ShowPStats:Help("Shows stats from yourself")
    
    local ShowLastRound = self:BindCommand( "sh_showlastround", {"showlastround","lastround" }, function(Client)
        if Plugin.Config.Lastroundlink == "" then Shine:Notify(Client, "", "", "[NS2Stats]: Last round was not safed at NS2Stats") return end  
        if self.Config.IngameBrowser then Server.SendNetworkMessage( Client, "Shine_Web", { URL = Plugin.Config.Lastroundlink }, true )
        else Client.ShowWebpage(url)
        end     
    end,true)   
    ShowLastRound:Help("Shows stats of last round played on this server")
    
    local ShowSStats = self:BindCommand( "sh_showserverstats", "showserverstats", function(Client)
        Shared.SendHTTPRequest( self.Config.WebsiteApiUrl .. "/server?key=" .. self.Config.ServerKey,"GET",function(response)
            local Data = json.decode( response )
            local serverid=""
            if Data then serverid = Data.id or "" end             
            local url= self.Config.WebsiteUrl .. "/server/server/" .. serverid
    	    if self.Config.IngameBrowser then Server.SendNetworkMessage( Client, "Shine_Web", { URL = url }, true )
    	    else Client.ShowWebpage(url) end
        end)        
    end,true)
    ShowSStats:Help("Shows server stats") 
    
    local Verify = self:BindCommand( "sh_verify", {"verifystats","verify"},function(Client)
            Shared.SendHTTPRequest(self.Config.WebsiteUrl .. "/api/verifyServer/" .. Plugin:GetId(Client) .. "?s=479qeuehq2829&key=" .. self.Config.ServerKey, "GET",
            function(response) ServerAdminPrint(Client,response) end)       
    end)
    Verify:Help ("Sets yourself as serveradmin at NS2Stats.com")
    
    local Tag = self:BindCommand( "sh_addtag","addtag",function(tag)
        table.insert(Plugin.Config.Tags, tag)            
        
    end)    
    Tag:AddParam{ Type = "string",TakeRestOfLine = true,MaxLength = kMaxChatLength}
    Tag:Help ("Adds the given tag to the Stats")
end

--Awards

function Plugin:makeAwardsList()

    --DO NOT CHANGE ORDER HERE
    Plugin:addAward(Plugin:awardMostDamage())
    Plugin:addAward(Plugin:awardMostKillsAndAssists())
    Plugin:addAward(Plugin:awardMostConstructed())
    Plugin:addAward(Plugin:awardMostStructureDamage())
    Plugin:addAward(Plugin:awardMostPlayerDamage())
    Plugin:addAward(Plugin:awardBestAccuracy())
    Plugin:addAward(Plugin:awardMostJumps())
    Plugin:addAward(Plugin:awardHighestKillstreak())
    
end

function Plugin:sendAwardListToClients()

    --reset and generates Awardlist
    RBPSnextAwardId = 0
    RBPSawards = {}
    Plugin:makeAwardsList()        
    --send highest 10 rating awards
    table.sort(RBPSawards, function (a, b)
          return a.rating > b.rating
        end)
    local AwardMessage = {}
    AwardMessage.message = ""    
    AwardMessage.duration = Plugin.Config.AwardMsgTime
    
    for i=1,Plugin.Config.ShowNumAwards do
        if RBPSawards[i].message == nil then break end
        AwardMessage.message = AwardMessage.message .. RBPSawards[i].message .. "\n"
    end 
    Server.SendNetworkMessage( "Shine_StatsAwards", AwardMessage, true )
 end

function Plugin:addAward(award)
    RBPSnextAwardId = RBPSnextAwardId +1
    award.id = RBPSnextAwardId
    
    RBPSawards[#RBPSawards +1] = award
end

function Plugin:awardMostDamage()
    local highestDamage = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local totalDamage = nil
    local rating = 0
    
    for key,taulu in pairs(Plugin.Players) do
        totalDamage = 0
        
        for i=1, #taulu.weapons do
            totalDamage = totalDamage + taulu.weapons[i].structure_damage
            totalDamage = totalDamage + taulu.weapons[i].player_damage
        end
        
        if math.floor(totalDamage) > math.floor(highestDamage) then
            highestDamage = totalDamage
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = (highestDamage+1)/350
    
    return {steamId = highestSteamId, rating = rating, message = "Most damage done by " .. highestPlayer .. " with total of " .. math.floor(highestDamage) .. " damage!"}
end

function Plugin:awardMostKillsAndAssists()
    local total = 0
    local rating = 0
    local highestTotal = 0
    local highestPlayer = "Nobody"
    local highestSteamId = ""
    
    for key,taulu in pairs(Plugin.Players) do
        total = taulu.kills + taulu.assists
        if total > highestTotal then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    
    end
    
    rating = highestTotal
    
    return {steamId = highestSteamId, rating = rating, message = highestPlayer .. " is deathbringer with total of " .. highestTotal .. " kills and assists!"}
end

function Plugin:awardMostConstructed()
    local highestTotal = 0
    local rating = 0
    local highestPlayer = "was not present"
    local highestSteamId = ""
    
    for key,taulu in pairs(Plugin.Players) do
        if taulu.total_constructed > highestTotal then
            highestTotal = taulu.total_constructed
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = (highestTotal+1)/30
    
    return {steamId = highestSteamId, rating = rating, message = "Bob the builder: " .. highestPlayer .. "!"}
end


function Plugin:awardMostStructureDamage()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(Plugin.Players) do
        total = 0
        
        for i=1, #taulu.weapons do
            total = total + taulu.weapons[i].structure_damage
        end
        
        if math.floor(total) > math.floor(highestTotal) then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = (highestTotal+1)/150
    
    return {steamId = highestSteamId, rating = rating, message = "Demolition man: " .. highestPlayer .. " with " .. math.floor(highestTotal) .. " structure damage."}
end


function Plugin:awardMostPlayerDamage()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(Plugin.Players) do
        total = 0
        
        for i=1, #taulu.weapons do
            total = total + taulu.weapons[i].player_damage
        end
        
        if math.floor(total) > math.floor(highestTotal) then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = (highestTotal+1)/90
    
    return {steamId = highestSteamId, rating = rating, message = highestPlayer .. " was spilling blood worth of " .. math.floor(highestTotal) .. " damage."}
end


function Plugin:awardBestAccuracy()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local highestTeam = 0
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(Plugin.Players) do
        total = 0
        
        for i=1, #taulu.weapons do
            total = total + taulu.weapons[i].player_hit/(taulu.weapons[i].miss+1)
        end
        
        if total > highestTotal then
            highestTotal = total
            highestPlayer = taulu.name
            highestTeam = taulu.teamnumber
            highestSteamId = taulu.steamId
        end
    end
    
    rating = highestTotal*10
    
    if highestTeam == 2 then
        return {steamId = highestSteamId, rating = rating, message = "Versed: " .. highestPlayer}
    else --marine or ready room
         return {steamId = highestSteamId, rating = rating, message = "Weapon specialist: " .. highestPlayer}
    end
end


function Plugin:awardMostJumps()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(Plugin.Players) do
        total = 0
        
        
        total = taulu.jumps
        
        
        if total > highestTotal then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = highestTotal/30
        
    return {steamId = highestSteamId, rating = rating, message = highestPlayer .. " is jump maniac with " .. highestTotal .. " jumps!"}
    
end


function Plugin:awardHighestKillstreak()
    local highestTotal = 0
    local highestPlayer = "nobody"
    local highestSteamId = ""
    local total = 0
    local rating = 0
    
    for key,taulu in pairs(Plugin.Players) do
                  
        total = taulu.highestKillstreak
        
        if total > highestTotal then
            highestTotal = total
            highestPlayer = taulu.name
            highestSteamId = taulu.steamId
        end
    end
    
    rating = highestTotal
        
    return {steamId = highestSteamId, rating = rating, message = highestPlayer .. " became unstoppable with streak of " .. highestTotal .. " kills!"}
end

--Cleanup
function Plugin:Cleanup()
    self.Enabled = false
    Shine.Timer.Destroy("WeaponUpdate")
    Shine.Timer.Destroy("SendStats")
    Shine.Timer.Destroy("SendStatus")
end    