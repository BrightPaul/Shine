--[[
Shine ns2stats plugin.
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = Plugin
local tostring = tostring
local Decode = json.decode 

Plugin.Version = "0.42"

Plugin.HasConfig = true

Plugin.ConfigName = "Ns2Stats.json"
Plugin.DefaultConfig =
{
    Statsonline = true, // Upload stats?
    Statusreport = true, // send Status to NS2Stats every min
    WebsiteUrl = "http://ns2stats.com", //this is url which is shown in player private messages, so its for advertising
    WebsiteDataUrl = "http://ns2stats.com/api/sendlog", //this is url where posted data is send and where it is parsed into database
    WebsiteStatusUrl="http://ns2stats.com/api/sendstatus", //this is url where posted data is send on status sends
    WebsiteApiUrl = "http://ns2stats.com/api",
    Assists = true, // Give Points (50%) for assists?
    Awards = true, //show award (todo)
    LogChat = true, //log the chat?
    ServerKey = "",
    IngameBrowser = true, // use ingame browser or Steamoverlay 
    Tags = {}, //Tags added to log  
    SendTime = 5, //Send after how many min?
}

Plugin.CheckConfig = true

//TODO: add all Hooks here
//Shine.Hook.SetupClassHook( string Class, string Method, string HookName, "PassivePost" )

Shine.Hook.SetupClassHook( "DamageMixin", "DoDamage", "OnDamageDealt", "PassivePost" )
Shine.Hook.SetupClassHook("ResearchMixin","TechResearched","OnTechResearched","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","SetResearching","OnTechStartResearch","PassivePre")
Shine.Hook.SetupClassHook("Player","addHealth","OnPlayerGetHealed","PassivePost")
Shine.Hook.SetupClassHook("ConstructMixin","SetConstructionComplete","OnFinishedBuilt","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","OnResearchCancel","addUpgradeAbortedToLog","PassivePost")
Shine.Hook.SetupClassHook("UpgradableMixin","RemoveUpgrade","addUpgradeLostToLog","PassivePost")
Shine.Hook.SetupClassHook("PlayingTeam","AddTeamResources","OnTeamGetResources","PassivePost") 
Shine.Hook.SetupClassHook("DropPack","OnCreate","OnPickableItemCreated","PassivePost") 
Shine.Hook.SetupClassHook("DropPack","OnTouch","OnPickableItemPicked","PassivePost")
Shine.Hook.SetupClassHook("PlayerBot","UpdateName","OnBotRenamed","PassivePost")
Shine.Hook.SetupClassHook("Player","SetName","PlayerNameChange","PassivePost")
Shine.Hook.SetupClassHook("Player","OnEntityChange","OnLifeformChanged","PassivePost")
 
   
//Score datatable 
Plugin.Assists = {}
Plugin.Players = {}

//values needed by NS2Stats
logInit = false
RBPSlogPartNumber = 1
RBPSsuccessfulSends = 0
RBPSresendCount = 0
Gamestarted = 0
RBPSgameFinished = 0
//Game started yet?
GameHasStarted = false
//Gamestate
Currentgamestate = 0

function Plugin:Initialise()
    self.Enabled = true
    
    if self.Config.ServerKey == "" then
        Shared.SendHTTPRequest(Plugin.Config.WebsiteUrl .. "/api/generateKey/?s=7g94389u3r89wujj3r892jhr9fwj", "GET",
            function(response) Plugin:acceptKey(response) end)
    end
    
    //register Commands
     Plugin:CreateCommands()
    //toget all Player into scorelist
    
    
    if GameHasStarted then
        local allPlayers = Shared.GetEntitiesWithClassname("Player")
        for index, fromPlayer in ientitylist(allPlayers) do
            local client = fromPlayer:GetClient()
            Plugin:addPlayerToTable(client)
            Plugin:UpdatePlayerInTable(client)
        end
    else Plugin:addLog({action="game_reset"}) end
    //Timers
    //every 1 sec
    //to update Weapondatas
    Shine.Timer.Create( "WeaponUpdate", 1, -1, function()
       if not GameHasStarted then return end
       local allPlayers = Shared.GetEntitiesWithClassname("Player")
       for index, fromPlayer in ientitylist(allPlayers) do
            local client = Server.GetOwner(fromPlayer)
            Plugin:updateWeaponData(Plugin:getPlayerByClient(client))
       end
    end)
    
    // every 1 min send Server Status 
    
     Shine.Timer.Create("SendStatus" , 60, -1, function() if not GameHasStarted then return end if Plugin.Config.Statusreport then Plugin:sendServerStatus(Currentgamestate) end end)

    //every x min x(Sendtime at config)
    //send datas to NS2StatsServer
    Shine.Timer.Create( "SendStats", 60 * Plugin.Config.SendTime, -1, function()
        if not GameHasStarted then return end
        if Plugin.Config.Statsonline then Plugin:sendData() end
    end)
    return true //finished loading
end

//All the Damage/Player Stuff

//Damage Dealt
function Plugin:OnDamageDealt(DamageMixin, damage, target, point, direction, surface, altMode, showtracer)
    local attacker = DamageMixin:GetParent()
    local damageType = kDamageType.Normal
    if DamageMixin.GetDamageType then
            damageType = DamageMixin:GetDamageType() end
    local doer = attacker:GetActiveWeapon()
    if damage>0 then 
    Plugin:addHitToLog(target, attacker, doer, damage, damageType)
    else Plugin:addMissToLog(attacker) end
end

//Chatlogging
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

//Entity Killed
function Plugin:OnEntityKilled(Gamerules, TargetEntity, Attacker, Inflictor, Point, Direction)
    /* use old function for now //Structures
    if TargetEntity:isa("Structure") then
        local strloc = TargetEntity:GetOrigin()
        local death=
            {
            id = TargetEntity:GetID(),
            structure_team = TargetEntity:GetTeamNumber(),
            structure_cost= TargetEntity:GetCost(),
            structure_name = TargetEntity:GetMapName(),
            structure_x = tostring(strloc.x),
            structure_y = tostring(strloc.y),
            structure_z = tostring(strloc.z)        
            }
        if Attacker == nil then
            death.action = "structure_suicide"
        else
            death.killerid = Attacker:GetUserId() 
            death.killer_lifeform = Attacker:GetMapName()
            death.killer_team = Attacker:GetTeamNumber()
        end       
        

    //Players
    elseif TargetEntity:isa("Player") then
        local targetloc = TargetEntity:GetOrigin()
        local death={
            action = "death",
            target_steamId = TargetEntity:GetUserId(),
            target_team = TargetEntity:GetTeamNumber(),
            target_weapon = TargetEntity:GetActiveWeaponName(),
            target_lifeform = TargetEntity:GetMapName(),
            //Why this values? Dead ppl alive?
            target_hp = 0,
            target_armor = 0,
            targetx = tostring(targetloc.x) ,
            targety = tostring(targetloc.y) ,
            targetz = tostring(targetloc.z),
            target_lifetime = tostring(Shared.GetTime() - TargetEntity:GetCreationTime())
        }
        if TargetEntity == Attacker then 
            death.attacker_weapon = "self"
            //natural Cause = nil?
        elseif TargetEntity == nil then
            death.attacker_weapon = "natural cause"
        elseif Attacker:isa("Player")
            local atloc = Attacker:GetOrigin()
            death.attacker_steamId = Attacker:GetUserId()
            death.attacker_team = Attacker:GetTeamNumber()
            death.attacker_weapon = Attacker:GetActiveWeaponName()
            death.attacker_hp = Attacker:GetHealth()
            death.attacker_amor = Attacker:GetArmor()
            death.attackerx = atloc.x
            death.attackery = atloc.y
            death.attaclerz = atloc.z
            Plugin:addKill(death.attacker_steamid,death.target_steamid)
        //Whips etc here.
        end
    end
    self:addLog(death)
    */
    if TargetEntity:isa("DropPack") then Plugin:OnPickableItemDestroyed(TargetEntity) 
    elseif TargetEntity:isa("Player") then Plugin:addDeathToLog(TargetEntity, Attacker, Inflictor) end       
end

//Player gets heal
function Plugin:OnPlayerGetHealed( Player )
    // player Backed Up?
     if Player:getHealth() >= 0.8 * Player:getmaxHealth() then
        table.Empty(Plugin.Assists[Plugin:GetId(Player:GetClient())]) //drop Assists
    end 
end

//Team

//Resource gathered
function Plugin:OnTeamGetResources(PlayingTeam, amount)
    //only get ress towers atm    
    if amount >= 3 then amount = 1 end //shouldnt get more than 3 res from towers at same tick
    
    local newResourceGathered =
    {
        team = PlayingTeam:GetTeamNumber(),
        action = "resources_gathered",
        amount = amount
    }

    Plugin:addLog(newResourceGathered)
end
//Building Stuff

//Building Dropped
function Plugin:OnConstructInit( Building )
    local ID = Building:GetId()
    local Name = Building:GetClassName()
    local Team = Building:GetTeam()

    if not Team then return end

    local Owner = Building:GetOwner()
    Owner = Owner or Team:GetCommander()

    if not Owner then return end

    local Client = Server.GetOwner( Owner )
    local techId = Building:GetTechId()
    local strloc = Building:GetOrigin()
    local build=
    {
        action = "structure_dropped",
        id = Building:GetId(),
        steamId = Plugin:GetId(Client),
        team = Building:GetTeamNumber(),
        structure_cost = GetCostForTech(techId),
        structure_name = EnumToString(kTechId, techId),
        structure_x = string.format("%.4f",strloc.x),
        structure_y = string.format("%.4f",strloc.y),
        structure_z = string.format("%.4f",strloc.z),
    }
    Plugin:addLog(build)
end

//Building built
function  Plugin:OnFinishedBuilt(ConstructMixin, builder)
    //fix logging before round has started
    local techId = ConstructMixin:GetTechId()
    local strloc = ConstructMixin:GetOrigin()
    local client = Server.GetOwner(builder)
    local team = ConstructMixin:GetTeamNumber()
    local steamId = Plugin:getTeamCommanderSteamid(team)
    local buildername = ""

    if client ~= nil then
        steamId = Plugin:GetId(client)
        buildername = builder:GetName()
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

//Building recyled
function Plugin:OnBuildingRecycled( Building, ResearchID )
    //Todo
end

//Upgrade Stuff
//todo
//UpgradesStarted
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

//temp to fix Uprades loged multiple times

OldUpgrade = -1
//Upgradefinished
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
// Game events 

function Plugin:SetGameState( Gamerules, NewState, OldState )
    Currentgamestate = NewState
    //Gamestart
    if NewState == kGameState.Started then
         GameHasStarted = true     
         Gamestarted = Shared.GetTime()
         Plugin:addLog({action = "game_start"})  
         //to reset PlayerList
         Plugin:clearPlayersTable()
         local allPlayers = Shared.GetEntitiesWithClassname("Player")
            for index, fromPlayer in ientitylist(allPlayers) do
                local client = fromPlayer:GetClient()
                Plugin:addPlayerToTable(client)
                //call lifeform_changed
                Plugin:OnLifeformChanged(fromPlayer,nil,nil)
            end
         //send Playerlist            
         Plugin:addPlayersToLog(0)
         
    end
end
 //Gameend
function Plugin:EndGame( Gamerules, WinningTeam )     
       local allPlayers = Shared.GetEntitiesWithClassname("Player")
        //to get last Kills
        for index, fromPlayer in ientitylist(allPlayers) do
            local client = Server.GetOwner(fromPlayer)
            Plugin:UpdatePlayerInTable(client)
        end	
        
        RBPSgameFinished = 1
        Plugin:addPlayersToLog(1)
      
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
        if Plugin.Config.Statsonline then Plugin:sendData()  end //senddata also clears log
        GameHasStarted = false
        //Resets all Stats
        RBPSgameFinished = 0
        RBPSlogPartNumber = 1
        RBPSsuccessfulSends = 0
        Plugin:addLog({action="game_reset"})       
    
end

//PlayerConnected
function Plugin:ClientConfirmConnect( Client )
    if not Client then return end   
    Plugin:addPlayerToTable(Client)
end

//PlayerDisconnect
function Plugin:ClientDisconnect(Client)
    if not Client then return end
    local Player = Client:GetPlayer()
    if not Player then return end
    local connect={
            action = "disconnect",
            steamId = Plugin:GetId(Client),
            score = Player.score
    }
    Plugin:addLog(connect)
end
//Bots renamed
function Plugin:OnBotRenamed(Bot)
    if Plugin:getPlayerByClient(Bot:GetPlayer():GetClient()) == nil then
    Plugin:ClientConfirmConnect(Bot:GetPlayer():GetClient()) end       
end

// Player joins a team
function Plugin:PostJoinTeam( Gamerules, Player, NewTeam, Force )
    if not Player then return end
    local Client = Player:GetClient()
    Plugin:addPlayerJoinedTeamToLog(Player)
     
    Plugin:UpdatePlayerInTable(Client)
end

//player changes Name
function Plugin:PlayerNameChange( Player, Name, OldName )
    if not Player then return end
    local Client = Player:GetClient()
    if Client == nil then return end
    if Client:GetIsVirtual() then return end
    Plugin:UpdatePlayerInTable(Client)
end

//Player become Comm
function Plugin:CommLoginPlayer( Chair, Player )
    if not Player then return end
    local Client = Player:GetClient()
    if Client:GetIsVirtual() then return end
    Plugin:UpdatePlayerInTable(Client)
    Plugin:OnLifeformChanged(Player, nil, nil)
end

//Player log out CC
function Plugin:CommLogout( Chair, Player )
    if not Player then return end
    local Client = Player:GetClient()
    if Client:GetIsVirtual() then return end
    Plugin:UpdatePlayerInTable(Client)
    Plugin:OnLifeformChanged(Player, nil, nil)
end

//Pickubla Stuff

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

function Plugin:OnPickableItemPicked(item, player)

    local techId = item:GetTechId()
    local structureOrigin = item:GetOrigin()

    local client = Server.GetOwner(player)
    local steamId = 0

    if client ~= nil then
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

//all the send Stuff

function Plugin:initLog ()
    logInit = true
    RBPSlog = ""
end

function Plugin:addLog(tbl)
 
    if logInit == false then self:initLog() end
    
    if tbl == nil then
        return
    end
    tbl.time = Shared.GetGMTString(false)
    tbl.gametime = Shared.GetTime() - Gamestarted
    RBPSlog = RBPSlog .. json.encode(tbl) .."\n"	
    //local data = RBPSlibc:CompressHuffman(RBPSlog)
    //Notify("compress size: " .. string.len(data) .. "decompress size: " .. string.len(RBPSlibc:Decompress(data)))        
end


function Plugin:sendData()
    local params =
    {
        key = self.Config.ServerKey,
        roundlog = RBPSlog,
        part_number = RBPSlogPartNumber,
        last_part = RBPSgameFinished,
        map = Shared.GetMapName(),
    }
    
    RBPSlastGameFinished = RBPSgameFinished
    if RBPSlastLog == nil then
    RBPSlastLogPartNumber = RBPSlogPartNumber	
    RBPSlastLog = RBPSlog
    Plugin:initLog() //clears log	
    else //if we still have data in last log, we wont send data normally, since it would be duplicated data
        
            local totalLength = string.len(RBPSlastLog) + string.len(RBPSlog)
            
            if totalLength>500000 then //we dont want to have more than 500 000 characters since that seems to crash the server
                RBPSlastLog = nil //basicly log fails here, but continue anyway
                Notify ("Log too long")
            else
                RBPSlastLog = RBPSlastLog .. RBPSlog //save log in memory if we need to resend, keep last log also in memory if send failed	
            end	
                            
            Plugin:initLog() //clears log
            return
    end	

    Shared.SendHTTPRequest(self.Config.WebsiteDataUrl, "POST", params, function(response,status) Plugin:onHTTPResponseFromSend(client,"send",response,status) end)	
    RBPSsendStartTime = Shared.GetSystemTime()
end

function Plugin:onHTTPResponseFromSend(client,action,response,status)	
        local message = json.decode(response)        
        if message then
        
            if string.len(response)>0 then //if we got somedata, that means send was completed
                RBPSlastLog = nil
                RBPSsuccessfulSends = RBPSsuccessfulSends +1
                 if string.find(response,"Server log empty",nil, true) == nill then RBPSlogPartNumber = RBPSlogPartNumber + 1 end
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
                local playerList = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
                //todo safe link and enable Votemenu for it
            end	
        elseif response then //if message = nil, json parse failed prob or timeout
            if string.len(response)>0 then //if we got somedata, that means send was completed
                RBPSlastLog = nil
                RBPSsuccessfulSends = RBPSsuccessfulSends +1
                if string.find(response,"Server log empty",nil, true) == nill then RBPSlogPartNumber = RBPSlogPartNumber + 1 end
            end
            Notify("NS2Stats.org: (" .. response .. ")")
    end

end

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
    //Maybe add Log notice
end

function Plugin:UpdatePlayerInTable(client)
    if not client then return end
    local player = client:GetPlayer()
    
    if player == nil then return end
    
    local steamId = Plugin:GetId(client)
    local origin = player:GetOrigin()
    local weapon = "none"
   
    for key,taulu in pairs(Plugin.Players) do
        --Jos taulun(pelaajan) steamid on sama kuin etsittävä niin päivitetään tiedot.
        if  taulu["steamId"] == steamId  then
            taulu.teamnumber = player:GetTeam():GetTeamNumber()
            taulu.lifeform = player:GetMapName()  
            if player:GetIsAlive() == false then
                taulu.damageTaken = {}
                taulu.killstreak = 0
                taulu.lifeform = "dead"
            end

            //weapon table>>
                if player.GetActiveWeapon and player:GetActiveWeapon() then
                    weapon = player:GetActiveWeapon():GetMapName()
                end
                
                taulu["weapon"] = weapon
                Plugin:updateWeaponData(taulu)
            //weapon table<<

            
            taulu["steamId"] = Plugin:GetId(client)
            taulu["name"] = player:GetName()
            if HasMixin(player, "Scoring") then taulu["score"] = player:GetScore() end
            taulu["ping"] = client:GetPing()
            taulu["teamnumber"] = player:GetTeamNumber()
            taulu["isbot"] = client:GetIsVirtual()	
            taulu["isCommander"] = player:GetIsCommander()
            if taulu["isCommander"] == true then
                if taulu["teamnumber"] == 1 then
                    taulu.lifeform = "marine_commander"
                else taulu.lifeform = "alien_commander" end
            end

            for k,d in pairs(taulu.damageTaken) do	
                d.time = d.time +1
                /*todo if d.time > RBPSassistTime then
                                    table.remove(taulu.damageTaken,k)	
                end*/
            end
        end
    //<<
    end
end
// Stat add Functions

function Plugin:addKill(attacker_steamId,target_steamId)
    for key,taulu in pairs(Plugin.Players) do	
        if taulu["steamId"] == attacker_steamId then	
            taulu["killstreak"] = taulu["killstreak"] +1	
            Plugin:checkForMultiKills(taulu["name"],taulu["killstreak"])	
            taulu.kills = taulu.kills +1	
            if taulu.killstreak > taulu.highestKillstreak then
                taulu.highestKillstreak = taulu.killstreak
            end
        //add Assists
        elseif  Plugin.Assists[target_steamId] ~= nil then            
            if Plugin.Assists[target_steamId][taulu.steamId] ~= nil then
                if Plugin.Assists[target_steamId][taulu.steamId] == true then
                    Plugin:addAssists(taulu.steamId,target_steamId) end
            end
        end      
        
        if taulu["steamId"] == target_steamId then	
            taulu.deaths = taulu.deaths +1	
        end
        
    end
end

//Todo: Multikills ?

function Plugin:checkForMultiKills(name,streak)
    //add sounds?
end

//assists called by addkill()
function Plugin:addAssists(attacker_steamId,target_steamId)
    local player  = Plugin:getPlayerBySteamId(attacker_steamId)  
    local pointValue = Plugin:getPlayerClientBySteamId(target_steamId):GetPlayer():GetPointValue()         
    if Plugin.Config.Assists == true then
        /* todo add points pointValue = pointValue / 2
        player.score = Clamp(player.score + pointValue, 0,100)
        player:SetScoreboardChanged(true) */
        //Add Assist to Players stats
        for key,taulu in pairs(Plugin.Players) do
            if taulu.steamId == attacker_steamId then
                taulu.assists = taulu.assists + 1
                break
            end
        end          
        Plugin.Assists[target_steamId][attacker_steamId] = false 
    end
end

//Damagetaken
function Plugin:playerAddDamageTaken(attacker_steamId,target_steamId)
    for key,taulu in pairs(Plugin.Players) do	
        if taulu["steamId"] == target_steamId then
        //if steamid already in table then update, else add
            for k,d in pairs(taulu.damageTaken) do	
                if attacker_steamId == d.steamId then //reset timer	
                d.time = 0
                                    return
                end	
             end

            //if we are still here we need to insert steamid into damageTaken
            table.insert(taulu.damageTaken,
            {
                steamId = attacker_steamId,
                time = 0
            })
            return
        end
    end            
end



function Plugin:addPlayerToTable(client)
    if not client then return end
    if string.find(client:GetPlayer().name,"Bot",nil,true) ~= nil and client:GetIsVirtual() then return end
    if Plugin:IsClientInTable(client) == false then	
        table.insert(Plugin.Players, Plugin:createPlayerTable(client))          
    else
        Plugin:setConnected(client)
end

end
function Plugin:setConnected(client)
    //player disconnected and came back
    local RBPSplayer = Plugin:getPlayerByClient(client)
    
    if RBPSplayer then
        RBPSplayer["dc"]=false
    end
end
function Plugin:getNumberOfConnectedPlayers()
    local num=0
    for p = 1, #Plugin.Players do	
        local player = Plugin.Players[p]	
        if not player.dc then
            num = num +1
        end
    end
    return num
end

function Plugin:createPlayerTable(client)	
    local player = client:GetPlayer()
    if player == nil then
        Notify("Tried to update nil player")
    return
    end

    local newPlayer =
    {   	
        isbot = client:GetIsVirtual(),
        steamId = Plugin:GetId(client),
        name = player:GetName(),
        score = HasMixin(player, "Scoring") and player:GetScore() or 0,
        teamnumber = player:GetTeamNumber(),
        x=0,
        y=0,
        z=0,
        lx=0,
        ly=0,
        lz=0,
        unstuck = false,
        unstuckCounter = 0,
        lastCoords =0,
        index=0,	
        lifeform = "",
        weapon = "",
        lastCommand = 0,
        dc = false,
        total_constructed=0,
        code=0,
        votedMap = 0,
        hasVoted = false,
        afkCount = 0,
        isCommander = false,
        weapons = {},
        damageTaken = {},
        kills = 0,
        deaths = 0,
        assists =0,
        killstreak =0,
        highestKillstreak =0,
        jumps = 0,
        walked = 0, //not used
        alien_ELO = 0,
        marine_ELO = 0,
        marine_commander_ELO = 0,
        alien_commander_ELO = 0,
    }
    //for bots
    if newPlayer.isbot == true then
        newPlayer.ping = 0
        newPlayer.ipaddress = "127.0.0.1"
    else
        newPlayer.ping = client:GetPing()
        newPlayer.ipaddress = IPAddressToString(Server.GetClientAddress(client))
    end
    return newPlayer
end

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
    else //add new weapon
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

function Plugin:weaponsAddHit(player,weapon, damage)
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
        
    else //add new weapon
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

    else //add new weapon
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

function Plugin:updateWeaponData(RBPSplayer)
    // Happens every second,
    // checks if current weapon exists in weapons table,
    // if it does increases it by 1, if it doesnt its added
    // Test to use Think() Hook with this
    
    local foundId = false
    if RBPSplayer == nil then return end
    for i=1, #RBPSplayer.weapons do
        if RBPSplayer.weapons[i].name == RBPSplayer.weapon then foundId=i end
    end
    
    if foundId then
        RBPSplayer.weapons[foundId].time = RBPSplayer.weapons[foundId].time + 1
    else //add new weapon
        table.insert(RBPSplayer.weapons,
        {
            name = RBPSplayer.weapon,
            time = 1,
            miss = 0,
            player_hit = 0,
            structure_hit = 0,
            player_damage = 0,
            structure_damage = 0
        })
    end

end

function Plugin:OnLifeformChanged(Player, oldEntityId, newEntityId)
   if not GameHasStarted then return end
   // search for playername in players table if its there player is real and lifeform change should be tracked
   if tostring(Player.name) ~= nil and tostring(Player.name) ~= "NSPlayer" then
     for key,taulu in pairs(Plugin.Players) do
        if taulu["name"] == Player.name then
            local Currentlifeform = Player:GetMapName()
            if not Player:GetIsAlive() then Currentlifeform = "dead" end
            if taulu["isCommander"] == true then
                if taulu["teamnumber"] == 1 then
                    Currentlifeform = "marine_commander"
                else Currentlifeform = "alien_commander" end
            end
            if taulu["lifeform"] ~= Currentlifeform then                
                taulu["lifeform"] = Currentlifeform
                Plugin:addLog({action = "lifeform_change", name = taulu["name"], lifeform = taulu["lifeform"], steamId = taulu["steamId"]})
                break                  
            else
                return
            end 
        end
     end
   end   
end

function Plugin:IsClientInTable(client)

    if not client then return false end

    local steamId = Plugin:GetId(client)

    for p = 1, #Plugin.Players do	
        local player = Plugin.Players[p]	

        if player.steamId == steamId then
            return true
        end	
    end
        
    return false
end

function Plugin:getAmountOfPlayersPerTeam(team)
local amount = 0
    for key,taulu in pairs(Plugin.Players) do
        if team == taulu.teamnumber and taulu.dc == false then
            amount = amount +1
        end
    end
    
    return amount
end

function Plugin:getPlayerClientBySteamId(steamId)
    if not steamId then return nil end        
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
    if client == nil then return end
    local steamId = Plugin:GetId(client)


    for key,taulu in pairs(Plugin.Players) do	
        if steamId then
            if taulu["steamId"] == steamId then return taulu end
        end	
    end
    return nil
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
   for key,taulu in pairs(Plugin.Players) do  
        if steamId then
            if tostring(taulu.steamId) == tostring(steamId)  then return taulu end
        end	
   end

   return nil
end

function Plugin:getPlayerByName(name)
    for key,taulu in pairs(Plugin.Players) do	
        if name then
            if taulu["name"] == name then return taulu end
        end	
    end

    return nil
end

function Plugin:getPlayerByClient(client)
    if client == nil then return end
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

function Plugin:addPlayerJoinedTeamToLog(player)
    local client = player:GetClient()
    if string.find(player.name,"Bot",nil,true) ~= nil and client:GetIsVirtual()then return end
    local playerJoin =
    {
        action="player_join_team",
        name = player.name,
        team = player:GetTeam():GetTeamNumber(),
        steamId = Plugin:GetId(client),
        score = player.score
    }
        Plugin:addLog(playerJoin)

        //if newTeamNumber ~=0 then removed for now, caused quite a lot of load on ns2stats.org
            //RBPSstats(client, "stats", newTeamNumber, "nil")
        //end

end

function Plugin:findPlayerScoreFromTable(client)

local steamId = Plugin:GetId(client)

    for key,taulu in pairs(Plugin.Players) do	
        if steamId then
            if taulu["steamId"] == steamId then return taulu["score"] end
        end
    end

    return 0
end

function Plugin:addPlayersToLog(type)
 
    local tmp = {}
    
    if type == 0 then
        tmp.action = "player_list_start"
    else
        tmp.action = "player_list_end"
    end
    
    //reset codes
    for p = 1, #Plugin.Players do	
        local player = Plugin.Players[p]	
        player.code = 0
    end
    
    tmp.list = Plugin.Players
    
    Plugin:addLog(tmp)
end

function Plugin:clearPlayersTable()
    Plugin.Players = { }
end

function Plugin:PrintTable(tbl)
    for k,v in pairs(tbl) do
        print(k,v)
    end
end

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

function Plugin:getServerInfoTable()
    local max = 0
    local highestTable = nil
    for key,taulu in pairs(RBPSserverInfo) do
        if max < taulu.count then
            max = taulu.count
            highestTable = taulu
        end
    end
    
    if max == 0 then
        return {IP = "n/a", password = "n/a"}
    end
    
    return highestTable
end

function Plugin:addMissToLog(attacker)
    if not Server then return end
    
    local weapon = "none"
    local RBPSplayer = nil
             
    if attacker and attacker:isa("Player") and attacker:GetName() then
    
        RBPSplayer = Plugin:getPlayerByName(attacker:GetName())
        if not RBPSplayer then return end

    if attacker.GetActiveWeapon and attacker:GetActiveWeapon() then
        weapon = attacker:GetActiveWeapon():GetMapName()
    end
        
        --local missLog =
        --{
            
        -- //general
        -- action = "miss",
            
        -- //Attacker
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
        
        --//Lisätään data json-muodossa logiin.
        --Plugin:addLog(missLog)
        //gorge fix
        if weapon == "spitspray" then
            weapon = "spit"
        end
        
        Plugin:weaponsAddMiss(RBPSplayer,weapon)
    end
    

end

function Plugin:addHitToLog(target, attacker, doer, damage, damageType) 
    if not attacker or not doer or not target then return end  
    if target:isa("Player") and attacker:isa("Player") then
        local aOrigin = attacker:GetOrigin()
        local tOrigin = target:GetOrigin()
        local weapon = "none"
        if target:GetActiveWeapon() then
            weapon = target:GetActiveWeapon():GetMapName() end        
        local hitLog =
        {
            //general
            action = "hit_player",	
            
            //Attacker
            attacker_steamId = Plugin:GetId(attacker:GetClient()),
            attacker_team = attacker:GetTeam():GetTeamNumber(),
            attacker_weapon = doer:GetMapName(),
            attacker_lifeform = attacker:GetMapName(),
            attacker_hp = attacker:GetHealth(),
            attacker_armor = attacker:GetArmorAmount(),
            attackerx = string.format("%.4f", aOrigin.x),
            attackery = string.format("%.4f", aOrigin.y),
            attackerz = string.format("%.4f", aOrigin.z),
            
            //Target
            target_steamId = Plugin:GetId(target:GetClient()),
            target_team = target:GetTeam():GetTeamType(),
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
        local attacker_id = Plugin:GetId(attacker:GetClient())
        local target_id = Plugin:GetId(target:GetClient())
        //fix for some bugs todo: track these bugs
        if target_id == nil or attacker_id == nil then return end           
        Plugin:playerAddDamageTaken(Plugin:GetId(attacker:GetClient()), Plugin:GetId(target:GetClient()))     
        if Plugin.Assists[target_id] == nil then Plugin.Assists[target_id] = {} end
        Plugin.Assists[target_id][attacker_id] = true
        
    else //target is a structure
        local structureOrigin = target:GetOrigin()
        local aOrigin = attacker:GetOrigin()
        local hitLog =
        {
            
            //general
            action = "hit_structure",	
            
            //Attacker
            attacker_steamId =  Plugin:GetId(attacker:GetClient()),
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

function Plugin:addDeathToLog(target, attacker, doer)
    if attacker ~= nil and doer ~= nil then
        local attackerOrigin = attacker:GetOrigin()
        local targetWeapon = "none"
        local targetOrigin = target:GetOrigin()
        local attacker_client = attacker:GetClient()
        local target_client = target:GetClient()
        
        if target:GetActiveWeapon() then
                targetWeapon = target:GetActiveWeapon():GetMapName()
        end

        //Jos on quitannu servulta justiin ennen tjsp niin ei ole clienttiä ja erroria pukkaa. (uwelta kopsasin)
        if attacker_client and target_client then
            local deathLog =
            {
                
                //general
                action = "death",	
                
                //Attacker
                attacker_steamId = Plugin:GetId(attacker_client),
                attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
                attacker_weapon = doer:GetMapName(),
                attacker_lifeform = attacker:GetMapName(), //attacker:GetPlayerStatusDesc(),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f", attackerOrigin.x),
                attackery = string.format("%.4f", attackerOrigin.y),
                attackerz = string.format("%.4f", attackerOrigin.z),
                
                //Target
                target_steamId = Plugin:GetId(target_client),
                target_team = target:GetTeamType(),
                target_weapon = targetWeapon,
                target_lifeform = target:GetMapName(), //target:GetPlayerStatusDesc(),
                target_hp = target:GetHealth(),
                target_armor = target:GetArmorAmount(),
                targetx = string.format("%.4f", targetOrigin.x),
                targety = string.format("%.4f", targetOrigin.y),
                targetz = string.format("%.4f", targetOrigin.z),
                target_lifetime = string.format("%.4f", Shared.GetTime() - target:GetCreationTime())
            }
            
                //Lisätään data json-muodossa logiin.
                Plugin:addLog(deathLog)
            
                if attacker:GetTeamNumber() ~= target:GetTeamNumber() then                   
                    //addkill + assists
                    Plugin:addKill(Plugin:GetId(attacker_client), Plugin:GetId(target_client))                  
                end
            
            else
                --natural causes death
                if target:isa("Player") then

                if target.GetActiveWeapon and target:GetActiveWeapon() then
                                targetWeapon = target:GetActiveWeapon():GetMapName()
                end
                local deathLog =
                {
                    //general
                    action = "death",

                    //Attacker
                    attacker_weapon	= "natural causes",

                    //Target
                    target_steamId = Plugin:GetId(target_client),
                    target_team = target:GetTeamType(),
                    target_weapon = targetWeapon,
                    target_lifeform = target:GetMapName(), //target:GetPlayerStatusDesc(),
                    target_hp = target:GetHealth(),
                    target_armor = target:GetArmorAmount(),
                    targetx = string.format("%.4f", targetOrigin.x),
                    targety = string.format("%.4f", targetOrigin.y),
                    targetz = string.format("%.4f", targetOrigin.z),
                    target_lifetime = string.format("%.4f", Shared.GetTime() - target:GetCreationTime())	
                }
                Plugin:addLog(deathLog)
        --Structure kill
        else //todo Plugin:addStructureKilledToLog(target, attacker, doer)
        end
    end
    else //suicide
        local target_client = target:GetClient()       
        local targetWeapon = "none"
        local targetOrigin = target:GetOrigin()
        local attacker_client = Server.GetOwner(target) //easy way out
        if attacker_client == nil then
        --Structure suicide
            Plugin:addStructureKilledToLog(target, attacker_client, doer)
            return
        end
        local attackerOrigin = targetOrigin
        local attacker = target
         local deathLog =
            {
                
                //general
                action = "death",	
                
                //Attacker

                attacker_weapon = "self",
               /* attacker_lifeform = attacker:GetMapName(),
                attacker_steamId = attacker_client:GetUserId(),
                attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f", attackerOrigin.x),
                attackery = string.format("%.4f", attackerOrigin.y),
                attackerz = string.format("%.4f", attackerOrigin.z),*/
                
                //Target
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
    end
end

//Adds server infos
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
    params.awards = {} //added later
    params.tags = self.Config.Tags
    params.private = false
    params.autoarrange = false //use Shine plugin settings later?
    params.serverInfo =
    {
        password = "",
        IP = IPAddressToString(Server.GetIpAddress()),
        count = 30 //servertick?
    }
    Plugin:addLog(params)

end

//Cleanup


//Commands
function Plugin:CreateCommands()
    
    local ShowPStats = self:BindCommand( "sh_showplayerstats", {"showplayerstats","showstats" }, function(Client)
        Shared.SendHTTPRequest( self.Config.WebsiteApiUrl .. "/player?ns2_id=" .. tostring(Plugin:GetId(Client)), "GET",function( Response, Status)   
            local Data = Decode(Response)
            if Data == nil then return end
            local playerid = Data.player_page_id or ""
            local url = self.Config.WebsiteUrl .. "/player/player/" .. playerid
            if self.Config.IngameBrowser then Server.SendNetworkMessage( Client, "Shine_Web", { URL = url }, true )
            else Client.ShowWebpage(url)
            end
        end)      
    end)
    // ShowPStats:AddParam{ Type = "string",Optimal = true ,TakeRestOfLine = true,Default ="", MaxLength = kMaxChatLength}
    ShowPStats:Help("Shows stats of given <player> or if no given <player> from yourself")
    
    local ShowSStats = self:BindCommand( "sh_showserverstats", "showserverstats", function(Client)
        Shared.SendHTTPRequest( self.Config.WebsiteApiUrl .. "/server?key=" .. self.Config.ServerKey,"GET",function( Response, Status)
            local Data = Decode( Response )
            if Data == nil then return end
            local serverid = Data.id or ""             
            local url= self.Config.WebsiteUrl .. "/server/server/" .. serverid
    	    if self.Config.IngameBrowser then Server.SendNetworkMessage( Client, "Shine_Web", { URL = url }, true )
    	    else Client.ShowWebpage(url) end
        end)        
    end)
    ShowSStats:Help("Shows server stats")
    
    local Verify = self:BindCommand( "sh_verify", {"verifystats","verify"},function(Client)
        if Shine:HasAccess( Client, "sh_verify" ) then
            Shared.SendHTTPRequest(self.Config.WebsiteUrl .. "/api/verifyServer/" .. Plugin:GetId(Client) .. "?s=479qeuehq2829&key=" .. self.Config.ServerKey, "GET",
            function(response) ServerAdminPrint(Client,response) end)
        end
    end)
    Verify:Help ("Sets yourself as serveradmin at NS2Stats.com")
end
//Get NS2 IDs

//For Bots
function Plugin:GetIdbyName(Name)
    if not Name then return end
    local newId=""
    local letters = " (){}[]/.,+-=?!*1234567890aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ"
    local input = tostring(Name)
    input = input:sub(6,#input)
    //to differ between e.g. name and name (2)
    input = string.reverse(input)
    for i=1, #input do
        local char = input:sub(i,i)
        local num = string.find(letters,char,nil,true)
        newId = newId .. tostring(num)        
    end
    while #newId < 10 do
        newId = newId .. "0"
    end       
    newId = string.sub(newId, 1 , 10)  
    //make a int
    newId = tonumber(newId)
    return newId
end

function Plugin:GetId(Client)
    if not Client:GetIsVirtual() then return Client:GetUserId() end
    return Plugin:GetIdbyName(Client:GetPlayer():GetName())    
end

//Awards

function Plugin:processAwards()
   RBPSawards = {}
   Plugin:makeAwardsList()
   Plugin:sendAwardListToClients()
      
   return RBPSawards
end

function Plugin:makeAwardsList()

    //DO NOT CHANGE ORDER HERE
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

    //send highest 10 rating awards
    table.sort(RBPSawards, function (a, b)
          return a.rating > b.rating
        end)

   local playerList = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
   for a=1,#RBPSawards do
        for p = 1, #playerList do
            // todo Cout:SendMessageToClient(playerList[p], "awards",{award = RBPSawards[a].message})
            
            /*if a == #RBPSawards or a == RBPSadvancedConfig.awardsMax then
                Cout:SendMessageToClient(playerList[p], "showAwards",{msg = "no msg"})
            end */
        end
        
        /*if a == #RBPSawards or a == RBPSadvancedConfig.awardsMax then
            break
        end*/
   end
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
    else //marine or ready room
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

//Cleanup
function Plugin:Cleanup()
    self.Enabled = false
    Shine.Timer.Destroy("WeaponUpdate")
    Shine.Timer.Destroy("SendStats")
    Shine.Timer.Destroy("SendStatus")
end    