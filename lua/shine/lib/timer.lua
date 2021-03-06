--[[
	Shine timer library.
]]

local SharedTime = Shared.GetTime
local StringFormat = string.format
local TableRemove = table.remove
local xpcall = xpcall

local Map = Shine.Map

local Timers = Map()

Shine.Timer = {}

local TimerMeta = {}
TimerMeta.__index = TimerMeta

function TimerMeta:Destroy()
	if self.Name then
		Timers:Remove( self.Name )
	end
end

function TimerMeta:GetReps()
	return self.Reps
end

function TimerMeta:GetLastRun()
	return self.LastRun
end

function TimerMeta:GetNextRun()
	return self.NextRun
end

function TimerMeta:GetTimeUntilNextRun()
	return self.NextRun - SharedTime()
end

function TimerMeta:SetReps( Reps )
	self.Reps = Reps
end

function TimerMeta:SetDelay( Delay )
	self.Delay = Delay
end

function TimerMeta:SetFunction( Func )
	self.Func = Func
end

function TimerMeta:Pause()
	if self.Paused then return end

	self.Paused = true
	self.TimeLeft = self:GetTimeUntilNextRun()
end

function TimerMeta:Resume()
	if not self.Paused then return end

	self.Paused = nil
	self.NextRun = SharedTime() + self.TimeLeft
	self.TimeLeft = nil
end

--[[
	Creates a timer.
	Inputs: Name, delay in seconds, number of times to repeat, function to run.
	Pass a negative number to reps to have it repeat indefinitely.
]]
local function Create( Name, Delay, Reps, Func )
	local Time = SharedTime()

	local OldObject = Timers:Get( Name )

	--Edit it so it's not destroyed if it's created again inside its old function.
	if OldObject then
		OldObject.Delay = Delay
		OldObject.Reps = Reps
		OldObject.Func = Func
		OldObject.LastRun = 0
		OldObject.NextRun = Time + Delay

		return OldObject
	end

	local Timer = setmetatable( {
		Name = Name,
		Delay = Delay,
		Reps = Reps,
		Func = Func,
		LastRun = 0,
		NextRun = Time + Delay
	}, TimerMeta )

	Timers:Add( Name, Timer )

	return Timer
end
Shine.Timer.Create = Create

local SimpleCount = 1

--[[
	Creates a simple timer.
	Inputs: Delay in seconds, function to run.
	Unlike a standard timer, this will only run once.
]]
function Shine.Timer.Simple( Delay, Func )
	local Index = "Simple"..SimpleCount

	SimpleCount = SimpleCount + 1

	return Create( Index, Delay, 1, Func )
end

--[[
	Removes a timer.
	Input: Timer name to remove.
]]
function Shine.Timer.Destroy( Name )
	if Timers:Get( Name ) then
		Timers:Remove( Name )
	end
end

--[[
	Returns whether the given timer exists.
	Input: Timer name to check.
]]
local function Exists( Name )
	return Timers:Get( Name ) ~= nil
end
Shine.Timer.Exists = Exists

function Shine.Timer.Pause( Name )
	if not Exists( Name ) then return end
	
	local Timer = Timers:Get( Name )

	Timer:Pause()
end

function Shine.Timer.Resume( Name )
	if not Exists( Name ) then return end
	
	local Timer = Timers:Get( Name )
	
	Timer:Resume()
end

local Error
local StackTrace

local function OnError( Err )
	Error = Err
	StackTrace = debug.traceback()
end

--[[
	Checks and executes timers on server update.
]]
Shine.Hook.Add( "Think", "Timers", function( DeltaTime )
	local Time = SharedTime()

	--Run the timers.
	for Name, Timer in Timers:Iterate() do
		if Timer.NextRun <= Time and not Timer.Paused then
			if Timer.Reps > 0 then
				Timer.Reps = Timer.Reps - 1
			end

			local Success = xpcall( Timer.Func, OnError, Timer )

			if not Success then
				Shine:DebugPrint( "Timer %s failed: %s.\n%s", true,
					Name, Error, StackTrace )

				Shine:AddErrorReport( StringFormat( "Timer %s failed: %s.",
					Name, Error ), StackTrace )
				
				Error = nil
				StackTrace = nil

				Timer:Destroy()
			else
				if Timer.Reps == 0 then
					Timer:Destroy()
				else
					Timer.LastRun = Time
					Timer.NextRun = Time + Timer.Delay
				end
			end
		end
	end
end )
