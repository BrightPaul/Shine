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
self.assist={}

function Plugin:Initialise()
    //TODO: add all Hooks here
    //Shine.Hook.SetupClassHook( string Class, string Method, string HookName, "PassivePost" )

    Shine.Hook.SetupClassHook( "BuildingMixin", "AttemptToBuild", "BuildingDropped", "PassivePost" )
    Shine.Hook.SetupClassHook( "DamageMixin", "DoDamage", "DealedDamage", "PassivePost" )
    Shine.Hook.SetupClassHook{ "ScoringMixin", "AddScore","ScoreChanged","PassivePost")
    Shine.Hook.SetupClassHock( "NS2Gamerules", "OnEntityDestroy","OnPlayerDeath","PassivePost")
    //Todo: Add all add functions + sendtoserver
    // add all Data Function to Hooks Shine.Hook.Add( string HookName, string UniqueID, function HookFunction [, int Priority ] )
    Shine.Hook.Add( "BuildingDropped", "AddBuildingdropped", function(newEnt, commander) /*add function stuff here*/ end )
    Shine.Hook.Add( "DealedDamage", "AddDamagetoS", function(target,attacker,damage)
    if attacker:isa("Player") then
    local id = self.score[toString(attacker]
    if damage > 0  then 
        if target:isa("Player") then
        self.assist[toString(target:GetUserId())][toString(attacker:GetUserId())]= true
           //hit_player
    end end end )
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
            structure_name = TargetEntity.kMapName,
            structure_x = toString(strloc.x),
            structure_y = toString(strloc.y),
            structure_z = toString(strloc.z)        
            }
        if Attacker == nil then
            death.action = "structure_suicide"
        else
            death.killerid = Attacker:GetUserId() 
            death.killer_lifeform = Attacker.kMapName
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
            target_lifeform = TargetEntity.kMapName,
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
            local atloc = attacker:GetOrigin()
            death.attacker_steamId = Attacker:GetUserId()
            death.attacker_team = Attacker:GetTeamNumber()
            death.attacker_weapon = Attacker:GetActiveWeaponName()
            death.attacker_hp = Attacker:GetHealth()
            death.attacker_amor = Attacker::GetArmor()
            death.attackerx = atloc.x
            death.attackery = atloc.y
            death.attaclerz = atloc.z
        //Whips etc here.
        end
    end
    addLog(death)
    end
function OnGamestart()
    //Player Start_list
end
    //Round ends
function Plugin:EndGame()
    //Player End_List
    self.sendData() //senddata also clears log
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
    local connect={
            action = "connect"
            steamId = Client:GetUserId()
    }
addLog(connect)   
end
//PlayerDisconnect
function Plugin:ClientDisconnect(Client)
    if not Client then return end
    if Client:GetIsVirtual() then return end
    local Player = Client:GetControllingPlayer()
    if not Player then return end
    self.score[toString(Client:GetUserId())].connected = false
    local connect={
            action = "disconnect"
            steamId = Client:GetUserId()
            score = self.score[toString(Client:GetUserId())].score
    }
    addLog(connect)
end

//all the send Stuff

self.logInit = false
self.log = ""
RBPSlogPartNumber = 0

function initLog ()
    self.logInit = true
    self.log = ""
end

function addLog(tbl)
    
    if self.logInit == false then initLog() end
    
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


function sendData()
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


function resendData()
     
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

Shared.SendHTTPRequest(RBPS.websiteDataUrl, "POST", params, function(response,status) RBPS:onHTTPResponseFromSend(client,"send",response,status) end)	

    RBPSsendStartTime = Shared.GetSystemTime()
    RBPSresendCount = RBPSresendCount + 1
end

function onHTTPResponseFromSend(client,action,response,status)	
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
RBPS:messageAll(message.other)
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



function sendServerStatus(gameState)
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

Shared.SendHTTPRequest(RBPS.websiteStatusUrl, "POST", params, function(response,status) RBPS:onHTTPResponseFromSendStatus(client,"sendstatus",response,status) end)	

end


Shine:RegisterExtension( "ns2stats", Plugin )