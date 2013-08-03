--[[
Shine ns2stats plugin.
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = {}

Plugin.Version = "0.1"

//TODO: add Config later
Plugin.HasConfig = false
//Web stuff
self.websiteUrl = "http://ns2stats.org" //this is url which is shown in player private messages, so its for advertising
self.websiteDataUrl = "http://ns2stats.org/api/sendlog" //this is url where posted data is send and where it is parsed into database
self.websiteStatusUrl = "http://ns2stats.org/api/sendstatus" //this is url where posted data is send on status sends
self.websiteApiUrl = "http://ns2stats.org/api"

//Score datatable 
Local Assist={}
local ScoreTable ={} // ScoreTable.id.(stemid / name / ip etc)

function Plugin:Initialise()
    //TODO: add all Hooks here
    //Shine.Hook.SetupClassHook( string Class, string Method, string HookName, "PassivePost" )
    
    Shine.Hook.SetupClassHook("ConstructMixin","OnConstructionComplete","OnFinishedBuilt", "PassivPre")
    Shine.Hook.SetupClassHook( "BuildingMixin", "AttemptToBuild", "BuildingDropped", "PassivePost" )
    Shine.Hook.SetupClassHook( "DamageMixin", "DoDamage", "DealedDamage", "PassivePost" )
    Shine.Hook.SetupClassHook{ "ScoringMixin", "AddScore","ScoreChanged","PassivePost")
    Shine.Hook.SetupClassHock( "NS2Gamerules", "OnEntityDestroy","OnPlayerDeath","PassivePost")
    Shine.Hook.SetupClassHook("ResearchMixin","TechResearched","OnTechResearched","PassivePost")
    Shine.Hook.SetupClassHook("ResearchMixin","SetResearching","OnTechStartResearch","PassivePre")
    //Todo: Add all add functions + sendtoserver
    // add all Data Function to Hooks Shine.Hook.Add( string HookName, string UniqueID, function HookFunction [, int Priority ] )
    Shine.Hook.Add( "BuildingDropped", "AddBuildingdropped", function(newEnt, commander) /*add function stuff here*/ end )
    Shine.Hook.Add( "DealedDamage", "AddDamagetoS", function(target,attacker,damage)
    if attacker:isa("Player") then
        if damage > 0  then 
        local hit = {} 
        local atloc = attacker:GetOrigin()
        hit.attacker_steamId = attacker:GetUserId()
        hit.attacker_team = attacker:GetTeamNumber()
        hit.attacker_weapon = attacker:GetActiveWeaponName()
        hit.attacker_hp = attacker:GetHealth()
        hit.attacker_amor = attacker:GetArmor()
        hit.attackerx = atloc.x
        hit.attackery = atloc.y
        hit.attaclerz = atloc.z
            //Player
            if target:isa("Player") then
                local tarloc target:GetOrigin()
                hit.action = "hit_player"
                hit.target_steamId = target:GetUserId()
                hit.target_team = target:GetTeamNumber()
                hit.target_weapon = target:GetActiveWeaponName()
                hit.target_lifeform = target:GetMapName()
                target_hp = target:GetHealth()
                target_armor = target:GetArmor(),
                targetx = toString(targetloc.x) ,
                targety = toString(targetloc.y) ,
                targetz = toString(targetloc.z),    
            else target:isa("Structure")
                local strloc = target:GetOrigin()
                hit.structure_id = target:GetID(),
                hit.structure_team = target:GetTeamNumber()
                hit.structure_cost= target:GetCost()
                hit.structure_name = target:GetMapName()
                hit.structure_x = toString(strloc.x)
                hit.structure_y = toString(strloc.y)
                hit.structure_z = toString(strloc.z)  
                hit.action = "hit_structure"
            end
        self:addLog(hit)
        else then //Miss
        end
     end*/ end )
    
    Shine.Hook.Add("OnFinishedBuilt","AddBuildtoStats",function(builder) 
        local strloc = self:GetOrigin()
        local build=
        {
            id = self:GetId(), //test this self...
            builder_name = builder:GetName(),
            steamId = builder:GetUserId()
            structure_cost=self:GetCost()
            team = builder:GetTeamNumber(),
            structure_name = self:GetMapName(),
            structure_x = toString(strloc.x),
            structure_y = toString(strloc.y),
            structure_z = toString(strloc.z)
        }
        self:addLog(build)
        end)
    Shine.Hook.Add("OnTechResearched","AddStatFTech", self:OnUpgradeFinished(structure, researchId))
    Shine.Hook.Add("OnTechStartResearch","AddStatSTech", self:addUpgradeStartedToLog(researchNode, player)
end

function Plugin:OnEntityKilled(Gamerules, TargetEntity, Attacker, Inflictor, Point, Direction)
    //Structures
    if TargetEntity:isa("Structure") then
        local strloc = TargetEntity:GetOrigin()
        local death=
            {
            id = TargetEntity:GetID(),
            structure_team = TargetEntity:GetTeamNumber(),
            structure_cost= TargetEntity:GetCost(),
            structure_name = TargetEntity:GetMapName(),
            structure_x = toString(strloc.x),
            structure_y = toString(strloc.y),
            structure_z = toString(strloc.z)        
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
            targetx = toString(targetloc.x) ,
            targety = toString(targetloc.y) ,
            targetz = toString(targetloc.z),
            target_lifetime = toString(Shared.GetTime() - TargetEntity:GetCreationTime())
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
end

function Plugin:addUpgradeStartedToLog(researchNode, player)
    if player:isa("Commander") then
        local client = Server.GetOwner(commander)
        local steamId = ""
        if client ~= nil then steamId = client:GetUserId() end
        local techId = researchNode:GetTechId()

        local newUpgrade =
        {
        structure_id = researchnode:GetId(),
        commander_steamid = steamId,
        team = player:GetTeamNumber(),
        cost = GetCostForTech(techId),
        upgrade_name = EnumToString(kTechId, techId),
        action = "upgrade_started"
        }

        self:addLog(newUpgrade)
    end

end

function Plugin:OnUpgradeFinished(structure, researchId)
    local upgrade =
    {
        structure_id = structure:GetId(),
        team = structure:GetTeamNumber(),
        commander_steamid = -1,
        upgrade_name = EnumToString(kTechId, researchId),
        costs = GetCostForTech(researchId),
        action ="upgrade_finished"    
    }
    self:addLog(upgade)
end
function Plugin:OnGamestart()
    Plugin:addPlayersToLog(0)
end

//Round ends
function Plugin:EndGame()
    Plugin:addPlayersToLog(1)
    self.sendData() //senddata also clears log
end

//PlayerConnected
function Plugin:ClientConnect( Client )
    if not Client then return end
    if Client:GetIsVirtual() then return end
    local Player = Client:GetControllingPlayer()
    if not Player then return end
    Plugin:addPlayerToTable(client)
    Plugin:setConnected(client)
end

//PlayerDisconnect
function Plugin:ClientDisconnect(Client)
    if not Client then return end
    if Client:GetIsVirtual() then return end
    local Player = Client:GetControllingPlayer()
    if not Player then return end
    local connect={
            action = "disconnect"
            steamId = Player:GetUserId()
            score = Player.score
    }
    self:addLog(connect)
end
// Player joins a team
function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force )
    Plugin:sddPlayerJoinedTeamToLog(Player, NewTeamNumber)  
end

//all the send Stuff

self.logInit = false
self.log = ""
RBPSlogPartNumber = 1

function Plugin:initLog ()
    self.logInit = true
    self.log = ""
end

function Plugin:addLog(tbl)
    
    if self.logInit == false then self:initLog() end
    
    if tbl == nil then
        return
    end
    
    tbl.time = Shared.GetGMTString(false)
    tbl.gametime = Shared.GetTime() - RBPS.gamestarted
    self.log = self.log .. json.encode(tbl) .."\n"	
    //local data = RBPSlibc:CompressHuffman(RBPSlog)
    //Notify("compress size: " .. string.len(data) .. "decompress size: " .. string.len(RBPSlibc:Decompress(data)))        
    RBPSlogPartNumber = RBPSlogPartNumber + 1
    end
end


function Plugin:sendData()
 //sendata is only called at gameend,so :
 RBPSgameFinished = 1  
    local params =
    {
        key = RBPSadvancedConfig.key,
        roundlog = self.log,
        part_number = RBPSlogPartNumber,
        last_part = RBPSgameFinished,
        map = Shared.GetMapName(),
    }
    
    RBPSlastGameFinished = RBPSgameFinished
   if RBPSlastLog == nil then
    RBPSlastLogPartNumber = RBPSlogPartNumber	
    RBPSlastLog = self.log
    self.initLog() //clears log	
        else //if we still have data in last log, we wont send data normally, since it would be duplicated data
        
            local totalLength = string.len(RBPSlastLog) + string.len(RBPSlog)
            
            if totalLength>500000 then //we dont want to have more than 500 000 characters since that seems to crash the server
                RBPSlastLog = nil //basicly log fails here, but continue anyway
            else
                RBPSlastLog = RBPSlastLog .. RBPSlog //save log in memory if we need to resend, keep last log also in memory if send failed	
            end	
                            
    self.initLog() //clears log
    //since we do not send log part we dont need to increase part count
    RBPSlogPartNumber = RBPSlogPartNumber - 1 //is increased after this function happens
    return
    end	

    Shared.SendHTTPRequest(self.websiteDataUrl, "POST", params, function(response,status) self.onHTTPResponseFromSend(client,"send",response,status) end)	

        RBPSsendStartTime = Shared.GetSystemTime()
    end


 function Plugin:resendData()
         
        local params =
        {
            key = RBPSadvancedConfig.key,
            roundlog = RBPSlastLog,
            part_number = RBPSlastLogPartNumber,
            last_part = RBPSlastGameFinished
        }
        
        if RBPSdebug then
    Notify("Resending part of data to :" .. RBPS.websiteDataUrl)
    end	

    Shared.SendHTTPRequest(RBPS.websiteDataUrl, "POST", params, function(response,status) Plugin:onHTTPResponseFromSend(client,"send",response,status) end)	

        RBPSsendStartTime = Shared.GetSystemTime()
        RBPSresendCount = RBPSresendCount + 1
    end

 function Plugin:onHTTPResponseFromSend(client,action,response,status)	
        if RBPSdebug and status then
            Notify("Status: (" .. status.. ")")
        end
        local message = json.decode(response)
        if RBPSdebug then
            Notify("Sending part of round data completed (" .. (Shared.GetSystemTime() - RBPSsendStartTime) .. " seconds)")
        end
        
        if message then
        
            if string.len(response)>0 then //if we got somedata, that means send was completed
                RBPSlastLog = nil
                RBPSsuccessfulSends = RBPSsuccessfulSends +1
            end
        
            if message.other then
    Plugin:messageAll(message.other)
    end

            if RBPSdebug then
    Notify(json.encode(response))	
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
                    
                    Cout:SendMessageToClient(playerList[p], "lastRoundLink",{lastRound = self.websiteUrl .. message.link})
                      
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
    local gameTime = Shared.GetTime() - RBPS.gamestarted
        local params =
        {
            key = RBPSadvancedConfig.key,
            players = json.encode(RBPS.Players),
            state = gameState,
            time = stime,
            gametime = gameTime,
            map = Shared.GetMapName(),
        }

    Shared.SendHTTPRequest(RBPS.websiteStatusUrl, "POST", params, function(response,status) Plugin:onHTTPResponseFromSendStatus(client,"sendstatus",response,status) end)	

end


Plugin.Players = { }

function Plugin:addKill(attacker_steamId,target_steamId)
    //target_steamId not used yet
    for key,taulu in pairs(RBPS.Players) do	
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
end

//To redo: assists
function Plugin:addAssists(attacker_steamId,target_steamId, pointValue)
    for key,taulu in pairs(RBPS.Players) do
        if taulu["steamId"] == target_steamId then
            for k,d in pairs(taulu.damageTaken) do	
                if d.steamId ~= attacker_steamId then
                    //add assist
                    local client = Plugin:getPlayerClientBySteamId(d.steamId)
                    if client then //player might have disconnected
                        local player = client:GetControllingPlayer()
                        
                        if player then
                            player:AddAssist() //RBPSplayer entity should update 1 second later automatically
                            player:AddScore(pointValue)
                        end
                    end
                end
            end
            
            return
        end
    end
end

function Plugin:playerAddDamageTaken(attacker_steamId,target_steamId)

for key,taulu in pairs(RBPS.Players) do	
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
        table.insert(RBPS.Players, Plugin:createPlayerTable(client))	
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
    for p = 1, #RBPS.Players do	
        local player = RBPS.Players[p]	
        if not player.dc then
            num = num +1
        end
    end
    return num
end

function Plugin:getVotersOnMapId(id)
    local num=0
    for p = 1, #RBPS.Players do	
        local player = RBPS.Players[p]	
        if player.votedMap == id then
            num = num +1
        end
    end
    
    return num
end

function Plugin:createPlayerTable(client)	
    local player = client:GetControllingPlayer()
    if player == nil then
        Shared.Message("Tried to update nil player")
    return
    end

    local newPlayer =
    {   	
        isbot = client:GetIsVirtual(),
        steamId = client:GetUserId(),
        name = player:GetName(),
        score = HasMixin(player, "Scoring") and player:GetScore() or 0,
        ping = client:GetPing(),
        teamnumber = player:GetTeamNumber(),
        ipaddress = IPAddressToString(Server.GetClientAddress(client)),
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
        
        if RBPSdebug then
            Shared.Message(json.encode(RBPSplayer.weapons[foundId]))
        end
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
        
        
        if RBPSdebug then
            Shared.Message(json.encode(RBPSplayer.weapons[foundId]))
        end
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
        
        if RBPSdebug then
            Shared.Message(json.encode(RBPSplayer.weapons[foundId]))
        end
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
    for key,taulu in pairs(RBPS.Players) do
        if team == taulu.teamnumber and taulu.dc == false then
            amount = amount +1
        end
    end
    
    return amount
end

function Plugin:UpdatePlayerInTable(client)
    if not client then return end
    local player = client:GetControllingPlayer()
    local steamId = client:GetUserId()
    local origin = player:GetOrigin()

    if RBPSdebug and player == nil then
    Shared.Message("Trying to update nil player")
            return	
    end	

        local weapon = "none"

    for key,taulu in pairs(RBPS.Players) do
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
    taulu["assists"] = player:GetAssists()
    if HasMixin(player, "Scoring") then taulu["score"] = player:GetScore() end
    taulu["ping"] = client:GetPing()
    taulu["teamnumber"] = player:GetTeamNumber()
    taulu["isbot"] = client:GetIsVirtual()	
    taulu["isCommander"] = player:GetIsCommander()

    if RBPSconfig.afkKickEnabled and RBPSnumperOfPlayers > RBPSconfig.afkKickPlayersToEnable and Plugin:areSameCoordinates(taulu,origin) then	
    taulu["afkCount"] = taulu["afkCount"] + 1

    if taulu["afkCount"] == RBPSconfig.afkKickIdleTime and Plugin:isUserAdmin(nil,taulu["steamId"]) == false then
    taulu["afkCount"] = 0	

                        //use server.getowner for player kicking, prob same than kicking client, but there were complains about zombie players
                        local afkPlayer = client:GetControllingPlayer()
                        local afkPlayerOwner = nil
                        if afkPlayer then
                            afkPlayerOwner = Server.GetOwner(afkPlayer)
                        end
                        
                        if afkPlayerOwner then
                            Server.DisconnectClient(afkPlayerOwner)
                            Shared.Message(string.format("%s afk kicked from the server", taulu["name"]))
                        end
                                                   
    end

    if taulu["afkCount"] == RBPSconfig.afkKickIdleTime*0.8 and Plugin:isUserAdmin(nil,taulu["steamId"])==false then
    Plugin:PlayerSay(taulu["steamId"],"Move or you are going to get afk kicked soon.")
    end
    else
    taulu["afkCount"] = 0
    end

    taulu["x"] = origin.x
    taulu["y"] = origin.y
    taulu["z"] = origin.z	
    //Shared.Message("x: " .. taulu["x"] .. ", y: " .. taulu["y"] .. ", z: " .. taulu["z"])

    if string.format("%.1f", taulu.x)~=string.format("%.1f", taulu.lx) then
    if string.format("%.1f", taulu.y)~=string.format("%.1f", taulu.ly) then
    if string.format("%.1f", taulu.z)~=string.format("%.1f", taulu.lz) then
    taulu.lx=taulu.x
    taulu.ly=taulu.y
    taulu.lz=taulu.z	
    end
    end
    end

    //unstuck feature>>
    if RBPSconfig.unstuck and taulu.unstuck then
    if taulu.unstuckCounter == RBPSadvancedConfig.unstuckTime then

                        if taulu.lastCoords ~= taulu.x + taulu.y + taulu.z then
                            Plugin:PlayerSay(client:GetUserId(),"You moved during unstuck counter, not unstucking.")
                            taulu.unstuckCounter=0
                            taulu.unstuck = false
                        else //did not move
                                            
                            local sameCoords = false	
                            
                            Plugin:messageAll(player:GetName() .. " has used /unstuck.")
                            taulu.counter = 0
                            
                            if string.format("%.1f", taulu.x)==string.format("%.1f", taulu.lx) then
                                if string.format("%.1f", taulu.y)==string.format("%.1f", taulu.ly) then
                                    if string.format("%.1f", taulu.z)==string.format("%.1f", taulu.lz) then
                                        sameCoords = true
                                    end
                                end
                            end
                            
                            taulu.unstuckCounter=0
                            taulu.unstuck = false
                            local checks=0
                            if sameCoords then //add some random and test if player is colliding
                                for c=1,20 do
                                    local rx = math.random(-20,20)/100
                                    local ry = math.random(-20,20)/100
                                    local rz = math.random(-20,20)/100
                                                                                                                                    
                                    player:SetOrigin(Vector(taulu.lx+rx, taulu.ly+ry, taulu.lz+rz))
                                    if player:GetIsColliding() == false then break end
                                             
                                end
                            else
                                player:SetOrigin(Vector(taulu.lx, taulu.ly, taulu.lz))
                            end	
                        end

    else
    Plugin:PlayerSay(client:GetUserId(),"Unstucking you in " .. (RBPSadvancedConfig.unstuckTime - taulu.unstuckCounter) .. " seconds.")
    taulu.unstuckCounter = taulu.unstuckCounter +1	

    end
    end

    for k,d in pairs(taulu.damageTaken) do	
    d.time = d.time +1
    if d.time > RBPSassistTime then
                        table.remove(taulu.damageTaken,k)	
    end
    end
    //<<

    return
    end
    end

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
if client == nil then
        if RBPSdebug then
            Shared.Message("Unable to find player table using null client")
        end
        return
    end

local steamId = client:GetUserId()


for key,taulu in pairs(RBPS.Players) do	
if steamId then
if taulu["steamId"] == steamId then return taulu end
end	
end
if RBPSdebug then
Shared.Message("Unable to find player using steamId: " .. steamId)
end

return nil
end

function Plugin:getTeamCommanderSteamid(teamNumber)

    for key,taulu in pairs(RBPS.Players) do	
        if taulu["isCommander"] and taulu["teamnumber"] == teamNumber then
return taulu["steamId"]
end	
end

return -1
end

function Plugin:getPlayerBySteamId(steamId)
    for key,taulu in pairs(RBPS.Players) do	
    
        if steamId then
if taulu["steamId"] .. "" == steamId .. "" then return taulu end
end	
end

return nil
end

function Plugin:getPlayerByName(name)
    for key,taulu in pairs(RBPS.Players) do	
        if name then
if taulu["name"] == name then return taulu end
end	
end

return nil
end

function Plugin:getPlayerByClient(client)
if client == nil then
if RBPSdebug then
     Shared.Message("Unable to find player table using null client")
     end
    
        return
    end
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

for key,taulu in pairs(RBPS.Players) do	
if steamId then
if taulu["steamId"] == steamId then return taulu end
end
        
        if name then
if taulu["name"] == name then return taulu end
end	
end

if RBPSdebug then
Shared.Message("Unable to find player using name")
end

return nil
end


function Plugin:areSameCoordinates(a,b) //first parameter needs to be RBPS.Player
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

    for key,taulu in pairs(RBPS.Players) do	
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
    for p = 1, #RBPS.Players do	
        local player = RBPS.Players[p]	
        player.code = 0
    end
    
    tmp.list = RBPS.Players
    
Plugin:addLog(tmp)
end

function Plugin:clearPlayersTable()
    RBPS.Players = { }
end

function Plugin:PrintTable(tbl)
    for k,v in pairs(tbl) do
        print(k,v)
    end
end

Shine:RegisterExtension( "ns2stats", Plugin )