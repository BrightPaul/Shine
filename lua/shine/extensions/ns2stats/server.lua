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
    Statsonline = true, // Upload stats?
    WebsiteUrl = "http://ns2stats.org", //this is url which is shown in player private messages, so its for advertising
    WebsiteDataUrl = "http://ns2stats.org/api/sendlog", //this is url where posted data is send and where it is parsed into database
    WebsiteStatusUrl="http://ns2stats.org/api/sendstatus", //this is url where posted data is send on status sends
    WebsiteApiUrl = "http://ns2stats.org/api",
    Assists = true, // Track assists?
    Awards = true, //show award (todo)
    ServerKey = "",
    IngameBrowser = true, // use ingame browser or Steamoverlay 
    Tags = {}, //Tags added to log  
    SendTime = 10, //Send after how many min?
}

Plugin.CheckConfig = true

Plugin.Commands = {}

//TODO: add all Hooks here
//Shine.Hook.SetupClassHook( string Class, string Method, string HookName, "PassivePost" )

Shine.Hook.SetupClassHook( "DamageMixin", "DoDamage", "OnDamageDealt", "PassivePost" )
Shine.Hook.SetupClassHook("ResearchMixin","TechResearched","OnTechResearched","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","SetResearching","OnTechStartResearch","PassivePre")
Shine.Hook.SetupClassHook("Player","addHealth","OnPlayerGetHealed","PassivePost")
Shine.Hook.SetupClassHook("ConstructMixin","SetConstructionComplete","OnFinishedBuilt","PassivePost")
Shine.Hook.SetupClassHook("ResearchMixin","OnResearchCancel","addUpgradeAbortedToLog","PassivePost")
Shine.Hook.SetupClassHook("UpgradableMixin","RemoveUpgrade","addUpgradeLostToLog","PassivePost")    
   
//Score datatable 
local Assists={}
Plugin.Players = {}

//values needed by NS2Stats
logInit = false
RBPSlogPartNumber = 1
RBPSsuccessfulSends = 0
RBPSresendCount = 0
Gamestarted = 0
RBPSgameFinished = 0
//Gamer started yet?
GameStarted = false

function Plugin:Initialise()
    self.Enabled = true
  
    if self.Config.ServerKey == "" then
        Shared.SendHTTPRequest(Plugin.Config.WebsiteUrl .. "/api/generateKey/?s=7g94389u3r89wujj3r892jhr9fwj", "GET",
            function(response) Plugin:acceptKey(response) end)
    end
    Plugin:CreateCommands()
    //toget all Player into scorelist
    local allPlayers = Shared.GetEntitiesWithClassname("Player")
    for index, fromPlayer in ientitylist(allPlayers) do
        local client = Server.GetOwner(fromPlayer)
        Plugin:addPlayerToTable(client)
    end
    //Timers
    //every 1 sec
    //to update Weapondatas
    Shine.Timer.Create( "WeaponUpdate", 1, -1, function()
       local allPlayers = Shared.GetEntitiesWithClassname("Player")
       for index, fromPlayer in ientitylist(allPlayers) do
            local client = Server.GetOwner(fromPlayer)
            Plugin:updateWeaponData(Plugin:getPlayerByClient(client))
       end
    end)

    //every 10 min maybe add config later
    //send datas to NS2StatsServer
    Shine.Timer.Create( "SendStats", 60 * Plugin.Config.SendTime, -1, function()
        Plugin:sendData()
    end)
    return true //finished loading
end

//All the Damage/Player Stuff

//Damage Dealt Todo
function Plugin:OnDamageDealt(DamageMixin, damage, target, point, direction, surface, altMode, showtracer)
    //Debug Notify("damage Dealt called")
    local attacker = DamageMixin:GetParent()
    local damageType = kDamageType.Normal
    if DamageMixin.GetDamageType then
            damageType = DamageMixin:GetDamageType() end
    local doer = attacker:GetActiveWeapon() 
    Plugin:addHitToLog(target, attacker, doer, damage, damageType)
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
    Plugin:addDeathToLog(TargetEntity, Attacker, Inflictor)       
end
//Player gets heal
function Plugin:OnPlayerGetHealed( Player )
    // player Backed Up?
    if Player:getHealth() >= 0.8 * Player:getmaxHealth() then
        table.Empty(Assists[Player:getUserId()]) //drop Assists
    end
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
        steamId = Client:GetUserId(),
        team = Building:GetTeamNumber(),
        structure_cost = GetCostForTech(techId),
        name = EnumToString(kTechId, techId),
        structure_x = string.format("%.4f",strloc.x),
        structure_y = string.format("%.4f",strloc.y),
        structure_z = string.format("%.4f",strloc.z),
    }
    Plugin:addLog(build)
end

//Building built
function  Plugin:OnFinishedBuilt(ConstructMixin, builder)
    //fix logging before round has started
    if not GameStarted then return end
    local techId = ConstructMixin:GetTechId()
    local strloc = ConstructMixin:GetOrigin()
    local client = Server.GetOwner(builder)
    local steamId = -1
    local buildername = ""

    if client ~= nil then
        steamId = client:GetUserId()
        buildername = builder:GetName()
    end
    
    local build=
    {
        action = "structure_built",
        id = ConstructMixin:GetId(),
        builder_name = buildername,
        steamId = steamId,
        structure_cost = GetCostForTech(techId),
        team = ConstructMixin:GetTeamNumber(),
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
        if client ~= nil then steamId = client:GetUserId() end
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
        structure_id = ResearchMixin:GetId(),
        team = structure:GetTeamNumber(),
        commander_steamid = -1,
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

    RBPS:addLog(newUpgrade)

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
    //Gamestart
    if NewState == 4 and OldState == 3 then   
         Plugin:addLog({action = "game_start"})
         Plugin:addPlayersToLog(0)
         RBPSgameFinished = 0
         GameStarted = true
    end
    //Gameend
    if OldState == 4 and (NewState == 5 or NewState == 6) then       
       local NS2GR = nil
       local entityList = Shared.GetEntitiesWithClassname("NS2Gamerules")
       if entityList:GetSize() > 0 then
            NS2GR = entityList:GetEntityAtIndex(0)
            //debug Notify("NS2GR set")
       else return end
       local allPlayers = Shared.GetEntitiesWithClassname("Player")
        //to update ScoreList
       for index, fromPlayer in ientitylist(allPlayers) do
            local client = Server.GetOwner(fromPlayer)
            Plugin:UpdatePlayerInTable(client)
        end	
        RBPSgameFinished = 1
        GameStarted = false
        Plugin:addPlayersToLog(1)
        local winningTeam = 0
        //Todo 
        if NewState == 5 then
                    winningTeam = 2
        elseif NewState == 6 then
                    winningTeam = 1
        end
        //debug
        Notify("Winning Team: " .. winningTeam)
        local initialHiveTechIdString = "None"
            
            if NS2GR.initialHiveTechId then
                    initialHiveTechIdString = EnumToString(kTechId, NS2GR.initialHiveTechId)
            end
            
            local params =
                {
                    version = ToString(Shared.GetBuildNumber()),
                    winner = ToString(winningTeam),
                    length = string.format("%.2f", Shared.GetTime() - NS2GR.gameStartTime),
                    map = Shared.GetMapName(),
                    start_location1 = NS2GR.startingLocationNameTeam1,
                    start_location2 = NS2GR.startingLocationNameTeam2,
                    start_path_distance = NS2GR.startingLocationsPathDistance,
                    start_hive_tech = initialHiveTechIdString,
                }
        Plugin:AddServerInfos(params)
        // if self.Config.Statsonline then Plugin:sendData() end //senddata also clears log
        Plugin:sendData() 
    end
    
end

//PlayerConnected
function Plugin:ClientConnect( Client )
    if not Client then return end
    Plugin:addPlayerToTable(Client)
    Plugin:setConnected(Client)
end

//PlayerDisconnect
function Plugin:ClientDisconnect(Client)
    if not Client then return end
    local Player = Client:GetControllingPlayer()
    if not Player then return end
    local connect={
            action = "disconnect",
            steamId = Client:GetUserId(),
            score = Player.score
    }
    self:addLog(connect)
end

// Player joins a team
function Plugin:PostJoinTeam( Gamerules, Player, NewTeam, Force )
    if not Player then return end
    local Client = Player:GetClient()
    Plugin:addPlayerJoinedTeamToLog(Player, NewTeam) 
    Plugin:UpdatePlayerInTable(Client)
end

//player changes Name
function Plugin:PlayerNameChange( Player, Name, OldName )
    if not Player then return end
    local Client = Player:GetClient()
    Plugin:UpdatePlayerInTable(Client)
end

//Player become Comm
function Plugin:CommLoginPlayer( Chair, Player )
    if not Player then return end
    local Client = Player:GetClient()
    if Client:GetIsVirtual() then return end
    Plugin:UpdatePlayerInTable(Client)
end

//Player log out CC
function Plugin:CommLogout( Chair, Player )
    if not Player then return end
    local Client = Player:GetClient()
    if Client:GetIsVirtual() then return end
    Plugin:UpdatePlayerInTable(Client)
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
            else
                RBPSlastLog = RBPSlastLog .. RBPSlog //save log in memory if we need to resend, keep last log also in memory if send failed	
            end	
                            
    Plugin:initLog() //clears log
    //since we do not send log part we dont need to increase part count
    RBPSlogPartNumber = RBPSlogPartNumber - 1 //is increased after this function happens
    return
    end	

    Shared.SendHTTPRequest(self.Config.WebsiteDataUrl, "POST", params, function(response,status) Plugin:onHTTPResponseFromSend(client,"send",response,status) end)	
    Notify ("Log is send")
    RBPSsendStartTime = Shared.GetSystemTime()
    RBPSlogPartNumber = RBPSlogPartNumber + 1
end
 
function Plugin:resendData()
         
        local params =
        {
            key = self.Config.ServerKey,
            roundlog = RBPSlastLog,
            part_number = RBPSlastLogPartNumber,
            last_part = RBPSlastGameFinished
        }
        
        

    Shared.SendHTTPRequest(Plugin.WebsiteDataUrl, "POST", params, function(response,status) Plugin:onHTTPResponseFromSend(client,"send",response,status) end)	

        RBPSsendStartTime = Shared.GetSystemTime()
        RBPSresendCount = RBPSresendCount + 1
    end

 function Plugin:onHTTPResponseFromSend(client,action,response,status)	
        // local message = json.decode(response)        
        if message then
        
            if string.len(response)>0 then //if we got somedata, that means send was completed
                RBPSlastLog = nil
                RBPSsuccessfulSends = RBPSsuccessfulSends +1
            end
        
            if message.other then
                Plugin:messageAll(message.other)
            end
        
            if message.error == "NOT_ENOUGH_PLAYERS" then
                   local playerList = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
               /* for p = 1, #playerList do
                
                    
                    Cout:SendMessageToClient(playerList[p], "lastRoundNotEnoughPlayers",{lastRound = nil})
                      
                end */
                return
            end	

            if message.link then	
                local playerList = EntityListToTable(Shared.GetEntitiesWithClassname("Player"))
                /*for p = 1, #playerList do
                    
                    Cout:SendMessageToClient(playerList[p], "lastRoundLink",{lastRound = self.Config.websiteUrl .. message.link})
                      
                end*/
            end	
        elseif response then //if message = nil, json parse failed prob or timeout
            if string.len(response)>0 then //if we got somedata, that means send was completed
                RBPSlastLog = nil
                RBPSsuccessfulSends = RBPSsuccessfulSends +1
            end
            Notify("NS2Stats.org: (" .. response .. ")")
    end

end

function Plugin:sendServerStatus(gameState)
    local stime = Shared.GetGMTString(false)
    local gameTime = Shared.GetTime() - Gamerules.gameStartTime
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
function Plugin:UpdatePlayerInTable(client)
    if not client then return end
    local player = client:GetControllingPlayer()
    local steamId = client:GetUserId()
    local origin = player:GetOrigin()
    local weapon = "none"
   
    for key,taulu in pairs(Plugin.Players) do
        --Jos taulun(pelaajan) steamid on sama kuin etsittävä niin päivitetään tiedot.
        if (taulu["isbot"] == false and taulu["steamId"] == steamId) or (taulu["isbot"] == true and taulu["name"] == player:GetName()) then
            taulu = Plugin:checkTeamChange(taulu,player)
            taulu = Plugin:checkLifeformChange(taulu,player)

            if taulu.lifeform == "dead" then //TODO optimize, happens many times when dead
            taulu.damageTaken = {}
            taulu.killstreak = 0
            end	

                        //weapon table>>
                            if player.GetActiveWeapon and player:GetActiveWeapon() then
                                weapon = player:GetActiveWeapon():GetMapName()
                            end
                            
                            taulu["weapon"] = weapon
                            Plugin:updateWeaponData(taulu)
            //weapon table<<

            if client:GetUserId() ~= 0 then
            taulu["steamId"] = client:GetUserId()
            end
            taulu["name"] = player:GetName()
            if HasMixin(player, "Scoring") then taulu["score"] = player:GetScore() end
            taulu["ping"] = client:GetPing()
            taulu["teamnumber"] = player:GetTeamNumber()
            taulu["isbot"] = client:GetIsVirtual()	
            taulu["isCommander"] = player:GetIsCommander()

            for k,d in pairs(taulu.damageTaken) do	
                d.time = d.time +1
                if d.time > RBPSassistTime then
                                    table.remove(taulu.damageTaken,k)	
                end
            end
        end
    //<<
    end
end
// Stat add Functions

function Plugin:addKill(attacker_steamId,target_steamId)
    //target_steamId not used yet
    for key,taulu in pairs(Plugin.Players) do	
        if taulu["steamId"] == attacker_steamId then	
            taulu["killstreak"] = taulu["killstreak"] +1	
            Plugin:checkForMultiKills(taulu["name"],taulu["killstreak"])	
            taulu.kills = taulu.kills +1	
            if taulu.killstreak > taulu.highestKillstreak then
                taulu.highestKillstreak = taulu.killstreak
            end
        end

        if taulu["steamId"] == target_steamId then	
            taulu.deaths = taulu.deaths +1	
        end
    end
    
        if Assists[target_steamId] ~= nil then
            table.remove(Assists[target_steamId], attacker_steamId)
            if Assists[target_steamId] ~= nil then
                for i = 1,#Assists[target_steamId] do
                    Plugin:addAssists(Assists[target_steamid][i],target_steamId,"0")    
                end
            end
        end
end

//Todo: Multikills ?

function Plugin:checkForMultiKills(name,streak)
    //add sounds?
end

//To redo: assists
function Plugin:addAssists(attacker_steamId,target_steamId, value)
    for key,taulu in pairs(Plugin.Players) do
        if taulu["steamId"] == target_steamId then
            for k,d in pairs(taulu.damageTaken) do	
                if d.steamId ~= attacker_steamId then
                    //add assist
                    local client = Plugin:getPlayerClientBySteamId(d.steamId)
                    if client then //player might have disconnected
                        local player = client:GetControllingPlayer()
                        
                        if player then
                            local pointValue = Plugin:getPlayerClientBySteamId(target_steamId):GetControllingPlayer():GetPointValue()*0.5
                            // player:AddAssist() //RBPSplayer entity should update 1 second later automatically
                            player:AddScore(pointValue)
                            if  Assists[d.steamId] == nil then Assists[d.steamId] = 0 end
                            Assists[d.steamId]= Assists[d.steamId] + 1
                            taulu["assists"] = Assists[d.steamId]
                        end
                    end
                end
            end
            
            return
        end
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

function Plugin:getVotersOnMapId(id)
    local num=0
    for p = 1, #Plugin.Players do	
        local player = Plugin.Players[p]	
        if player.votedMap == id then
            num = num +1
        end
    end
    
    return num
end

function Plugin:createPlayerTable(client)	
    local player = client:GetControllingPlayer()
    if player == nil then
        Notify("Tried to update nil player")
    return
    end

    local newPlayer =
    {   	
        isbot = client:GetIsVirtual(),
        steamId = client:GetUserId(),
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
        lifeform="",
        weapon = "none",
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

function Plugin:weaponsAddHit(RBPSplayer,weapon, damage)
       
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


function Plugin:weaponsAddStructureHit(RBPSplayer,weapon, damage)
       
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

function Plugin:checkLifeformChange(player, newPlayer)
local currentLifeform = newPlayer:GetMapName()
    local previousLifeform = player.lifeform
    
    if newPlayer:GetIsAlive() == false then
        currentLifeform = "dead"
    end
    
    if previousLifeform ~= currentLifeform then
    player.lifeform = currentLifeform
    Plugin:addLog({action = "lifeform_change", name = player.name, lifeform = currentLifeform, steamId = player.steamId})
    end
    
    return player
end


function Plugin:checkTeamChange(player, newPlayer)
local currentTeam = newPlayer:GetTeamNumber()
    local previousTeam = player.teamnumber
    
    if previousTeam ~= currentTeam then
        player.teamnumber = currentTeam
         Plugin:addPlayerJoinedTeamToLog(player, currentTeam)
    end
    
    return player
end


function Plugin:IsClientInTable(client)

if not client then return false end

    local steamId = client:GetUserId()

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
            
    local client = Server.GetOwner(victim)
    if client and client:GetUserId() then

    if client:GetUserId() == tonumber(steamId) and client:GetIsVirtual() == false then	
    return client	
    end
    end
                
            end
            
            return nil
                            
end

function Plugin:getPlayerByClientId(client)
    if client == nil then return end
    local steamId = client:GetUserId()


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
if taulu["steamId"] .. "" == steamId .. "" then return taulu end
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
        steamId = client:GetUserId()
    else
        if type(client["GetControllingPlayer"]) ~= "nil" then
                local player = client:GetControllingPlayer()
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


function Plugin:areSameCoordinates(a,b) //first parameter needs to be Plugin.Player
 local ax = string.format("%.1f", a.x)
 local ay = string.format("%.1f", a.y)
 local az = string.format("%.1f", a.z)
 local bx = string.format("%.1f", b.x)
 local by = string.format("%.1f", b.y)
 local bz = string.format("%.1f", b.z)
 
 if ax == bx and az == bz and ay == by then
    return true
 end
 
 return false
end

function Plugin:addPlayerJoinedTeamToLog(player, newTeamNumber)

    //	local client = Server.GetOwner(player)

            
    local playerJoin =
    {
        action="player_join_team",
        name = player.name,
        team=newTeamNumber,
        steamId = player.steamId,
        score = player.score
    }
        Plugin:addLog(playerJoin)

        //if newTeamNumber ~=0 then removed for now, caused quite a lot of load on ns2stats.org
            //RBPSstats(client, "stats", newTeamNumber, "nil")
        //end

end

function Plugin:findPlayerScoreFromTable(client)

local steamId = client:GetUserId()

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
                newAdvancedSettingAdded = true
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
    if not Server then return end
    if not attacker or not doer or not target then return end
        
   
    local targetWeapon = "none"
    local RBPSplayer = nil
    local RBPStargetPlayer = nil
    
    if attacker:isa("Player") and attacker:GetName() then
        RBPSplayer = Plugin:getPlayerByName(attacker:GetName())
    end
    
    if not RBPSplayer then return end
   
    if target:isa("Player") and target:GetName() then //target is a player
                                    
        RBPStargetPlayer = Plugin:getPlayerByName(target:GetName())
        
        if not RBPStargetPlayer then return end
               
        if target.GetActiveWeapon and target:GetActiveWeapon() then
            targetWeapon = target:GetActiveWeapon():GetMapName()
        end
        
        local hitLog =
        {
            //general
            action = "hit_player",	
            
            //Attacker
            attacker_steamId = RBPSplayer.steamId,
            attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
            attacker_weapon = doer:GetMapName(),
            attacker_lifeform = attacker:GetMapName(),
            attacker_hp = attacker:GetHealth(),
            attacker_armor = attacker:GetArmorAmount(),
            attackerx = RBPSplayer.x,
            attackery = RBPSplayer.y,
            attackerz = RBPSplayer.z,
            
            //Target
            target_steamId = RBPStargetPlayer.steamId,
            target_team = target:GetTeamType(),
            target_weapon = targetWeapon,
            target_lifeform = target:GetMapName(),
            target_hp = target:GetHealth(),
            target_armor = target:GetArmorAmount(),
            targetx = RBPStargetPlayer.x,
            targety = RBPStargetPlayer.y,
            targetz = RBPStargetPlayer.z,
            
            damageType = damageType,
            damage = damage
            
        }

        //Lisätään data json-muodossa logiin.
        Plugin:addLog(hitLog)

        Plugin:weaponsAddHit(RBPSplayer, doer:GetMapName(), damage)
        
        Plugin:playerAddDamageTaken(RBPSplayer.steamId,RBPStargetPlayer.steamId)
        // Add Attacker as possible Assist
        table.insert( Assists[hit.target_steamId] , hit.attacker_steamId)
        
    else //target is a structure
        local structureOrigin = target:GetOrigin()
        
        local hitLog =
        {
            //general
            action = "hit_structure",	
            
            //Attacker
            attacker_steamId = RBPSplayer.steamId,
            attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
            attacker_weapon = doer:GetMapName(),
            attacker_lifeform = attacker:GetMapName(),
            attacker_hp = attacker:GetHealth(),
            attacker_armor = attacker:GetArmorAmount(),
            attackerx = RBPSplayer.x,
            attackery = RBPSplayer.y,
            attackerz = RBPSplayer.z,
                        
            structure_id = target:GetId(),
            structure_name = target:GetMapName(),	
            structure_x = string.format("%.4f", structureOrigin.x),
            structure_y = string.format("%.4f", structureOrigin.y),
            structure_z = string.format("%.4f", structureOrigin.z),	

            damageType = damageType,
            damage = damage
        }
        
        Plugin:addLog(hitLog)
        Plugin:weaponsAddStructureHit(RBPSplayer, doer:GetMapName(), damage)
        
    end
           
end

function Plugin:addDeathToLog(target, attacker, doer)
    if attacker ~= nil and doer ~= nil then
        local attackerOrigin = attacker:GetOrigin()
        local targetWeapon = "none"
        local targetOrigin = target:GetOrigin()
        local attacker_client = Server.GetOwner(attacker)
        local target_client = Server.GetOwner(target)
        
        if target.GetActiveWeapon and target:GetActiveWeapon() then
                targetWeapon = target:GetActiveWeapon():GetMapName()
        end

        //Jos on quitannu servulta justiin ennen tjsp niin ei ole clienttiä ja erroria pukkaa. (uwelta kopsasin)
        if attacker_client and target_client then
            local deathLog =
            {
                
                //general
                action = "death",	
                
                //Attacker
                attacker_steamId = attacker_client:GetUserId(),
                attacker_team = ((HasMixin(attacker, "Team") and attacker:GetTeamType()) or kNeutralTeamType),
                attacker_weapon = doer:GetMapName(),
                attacker_lifeform = attacker:GetMapName(), //attacker:GetPlayerStatusDesc(),
                attacker_hp = attacker:GetHealth(),
                attacker_armor = attacker:GetArmorAmount(),
                attackerx = string.format("%.4f", attackerOrigin.x),
                attackery = string.format("%.4f", attackerOrigin.y),
                attackerz = string.format("%.4f", attackerOrigin.z),
                
                //Target
                target_steamId = target_client:GetUserId(),
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
                    //add assists
                    Plugin:addAssists(attacker_client:GetUserId(),target_client:GetUserId(), string.format("%d", (target:GetPointValue()/2)))
                    
                    //addkill / display killstreaks
                    Plugin:addKill(attacker_client:GetUserId(),target_client:GetUserId())
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
                target_steamId = target_client:GetUserId(),
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
        local target_client = Server.GetOwner(target)
        
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
                target_steamId = target_client:GetUserId(),
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
            
            //Lisätään data json-muodossa logiin.
            Plugin:addLog(deathLog)
    
    end
end

//Adds server infos
function Plugin:AddServerInfos(params)
    local mods = "" 
    for i = 1, Server.GetNumMods() do
        // if Server.GetIsModActive(i) then maybe in future
        mods = mods ..Server.GetModTitle(i) .. ","
        //end
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

//Command Methods

//open Ingame_Browser with given Player Stats
function Plugin:ShowPlayerStats(Client)
    local playerid = Client:GetUserID()
    local url = self.Config.Websiteurl .. "/player/player/" .. tostring(playerid)
    if self.Config.IngameBrowser then Server.SendNetworkMessage( Client, "Shine_Web", { URL = url }, true )
    else Client.ShowWebpage(url)
    end
end

//open Ingame_Browser with Server Stats
function Plugin:ShowServerStats(Client)
        local url= self.Config.Websiteurl .. "/server/server/" // + to string(self.Config.serverid)
    	if self.Config.IngameBrowser then Server.SendNetworkMessage( Client, "Shine_Web", { URL = url }, true )
    	else Client.ShowWebpage(url) end
end

// set commanduser as admin at ns2stats
function Plugin:SetAdminAtNS2Stats(Client)
if Shine:HasAccess( Client, "sh_verify" ) then
    Shared.SendHTTPRequest(self.Config.WebsiteUrl .. "/api/verifyServer/" .. Client:GetUserId() .. "?s=479qeuehq2829&key=" .. self.Config.ServerKey, "GET",
        function(response) ServerAdminPrint(Client,response) end) end
end

//register Commands
//Commands
function Plugin:CreateCommands()
    local function PlayerStats(Client)
        if not Client then return end
        Plugin:ShowPlayerStats( Client )
    end
    local ShowPStats = Plugin:BindCommand( "sh_showplayerstats", {"showplayerstats","showstats" }, PlayerStats , true)
    // ShowPStats:AddParam{ Type = "string",Optimal = true ,TakeRestOfLine = true,Default ="", MaxLength = kMaxChatLength}
    ShowPStats:Help("Shows stats of given <player> or if no given <player> from yourself")
    local function ServerStats(Client)
        if not Client then return end
        Plugin:ShowServerStats(Client)
    end
    local ShowSStats = Plugin:BindCommand( "sh_showserverstats", "showserverstats", ServerStats,true)
    ShowSStats:Help("Shows server stats")
    local function AdminAtNS2Stats (Client)
        if not Client then return end
        Plugin:SetAdminAtNS2Stats(Client)
    end
    local Verify = Plugin:BindCommand( "sh_verify", {"verifystats","verify"},AdminAtNS2Stats)
    Verify:Help ("Sets yourself as serveradmin at NS2Stats.com")
end

//Cleanup

function Plugin:Cleanup()
    self.Enabled = false
    Shine.Timer.Destroy("WeaponUpdate")
    Shine.Timer.Destroy("SendStats")
end