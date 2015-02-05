--[[
	Shine GUI system.

	I'm sorry UWE, but I don't like your class system.
]]

Shine.GUI = Shine.GUI or {}

local SGUI = Shine.GUI
local Hook = Shine.Hook
local IsType = Shine.IsType
local Map = Shine.Map

local assert = assert
local Clock = os.clock
local getmetatable = getmetatable
local include = Script.Load
local next = next
local pairs = pairs
local setmetatable = setmetatable
local StringFormat = string.format
local TableInsert = table.insert
local TableRemove = table.remove
local xpcall = xpcall

--Useful functions for colours.
include "lua/shine/lib/colour.lua"

SGUI.Controls = {}

SGUI.ActiveControls = Map()
SGUI.Windows = {}

--Used to adjust the appearance of all elements at once.
SGUI.Skins = {}

--Base visual layer.
SGUI.BaseLayer = 20

--Global control meta-table.
local ControlMeta = {}

--[[
	Adds Get and Set functions for a property name, with an optional default value.
]]
function SGUI.AddProperty( Table, Name, Default )
	Table[ "Set"..Name ] = function( self, Value )
		self[ Name ] = Value
	end

	Table[ "Get"..Name ] = function( self )
		return self[ Name ] or Default
	end
end

local WideStringToString

function SGUI.GetChar( Char )
	WideStringToString = WideStringToString or ConvertWideStringToString
	return WideStringToString( Char )
end

SGUI.SpecialKeyStates = {
	Ctrl = false,
	Alt = false,
	Shift = false
}

Hook.Add( "PlayerKeyPress", "SGUICtrlMonitor", function( Key, Down )
	if Key == InputKey.LeftControl or Key == InputKey.RightControl then
		SGUI.SpecialKeyStates.Ctrl = Down or false
	elseif Key == InputKey.LeftAlt then
		SGUI.SpecialKeyStates.Alt = Down or false
	elseif Key == InputKey.LeftShift or Key == InputKey.RightShift then
		SGUI.SpecialKeyStates.Shift = Down or false
	end
end, -20 )

function SGUI:GetCtrlDown()
	return self.SpecialKeyStates.Ctrl
end

--[[
	Sets the current in-focus window.
	Inputs: Window object, windows index.
]]
function SGUI:SetWindowFocus( Window, i )
	local Windows = self.Windows

	if Window ~= self.FocusedWindow and not i then
		for j = 1, #Windows do
			local CurWindow = Windows[ j ]

			if CurWindow == Window then
				i = j
				break
			end
		end
	end

	if i then
		TableRemove( Windows, i )

		Windows[ #Windows + 1 ] = Window
	end

	for i = 1, #Windows do
		local Window = Windows[ i ]

		Window:SetLayer( self.BaseLayer + i )
	end

	if self.IsValid( self.FocusedWindow ) and self.FocusedWindow.OnLoseWindowFocus then
		self.FocusedWindow:OnLoseWindowFocus( Window )
	end

	self.FocusedWindow = Window
end

local ToDebugString = table.ToDebugString
local Traceback = debug.traceback

local function OnError( Error )
	local Trace = Traceback()

	local Locals = ToDebugString( Shine.GetLocals( 1 ) )

	Shine:DebugPrint( "SGUI Error: %s.\n%s", true, Error, Trace )
	Shine:AddErrorReport( StringFormat( "SGUI Error: %s.", Error ),
		"%s\nLocals:\n%s", true, Trace, Locals )
end

function SGUI:PostCallEvent()
	local PostEventActions = self.PostEventActions
	if not PostEventActions then return end

	for i = 1, #PostEventActions do
		xpcall( PostEventActions[ i ], OnError )
	end

	self.PostEventActions = nil
end

function SGUI:AddPostEventAction( Action )
	if not self.PostEventActions then
		self.PostEventActions = {}
	end

	self.PostEventActions[ #self.PostEventActions + 1 ] = Action
end

--[[
	Passes an event to all active SGUI windows.

	If an SGUI object is classed as a window, it MUST call all events on its children.
	Then its children must call their events on their children and so on.

	Inputs: Event name, arguments.
]]
function SGUI:CallEvent( FocusChange, Name, ... )
	local Windows = SGUI.Windows
	local WindowCount = #Windows

	--The focused window is the last in the list, so we call backwards.
	for i = WindowCount, 1, - 1 do
		local Window = Windows[ i ]

		if Window and Window[ Name ] and Window:GetIsVisible() then
			local Success, Result, Control = xpcall( Window[ Name ], OnError, Window, ... )

			if Success then
				if Result ~= nil then
					if i ~= WindowCount and FocusChange and self.IsValid( Window ) then
						self:SetWindowFocus( Window, i )
					end

					self:PostCallEvent()

					return Result, Control
				end
			else
				Window:Destroy()
			end
		end
	end

	self:PostCallEvent()
end

--[[
	Calls an event on all active SGUI controls, out of order.

	Inputs: Event name, optional check function, arguments.
]]
function SGUI:CallGlobalEvent( Name, CheckFunc, ... )
	if IsType( CheckFunc, "function" ) then
		for Control in self.ActiveControls:Iterate() do
			if Control[ Name ] and CheckFunc( Control ) then
				Control[ Name ]( Control, Name, ... )
			end
		end
	else
		for Control in self.ActiveControls:Iterate() do
			if Control[ Name ] then
				Control[ Name ]( Control, Name, ... )
			end
		end
	end
end

SGUI.MouseObjects = 0

local IsCommander
local ShowMouse

--[[
	Allow for multiple windows to "enable" the mouse, without
	disabling it after one closes.
]]
function SGUI:EnableMouse( Enable )
	if not ShowMouse then
		ShowMouse = MouseTracker_SetIsVisible
		IsCommander = CommanderUI_IsLocalPlayerCommander
	end

	if Enable then
		self.MouseObjects = self.MouseObjects + 1

		if self.MouseObjects == 1 then
			if not ( IsCommander and IsCommander() ) then
				ShowMouse( true )
				self.EnabledMouse = true
			end
		end

		return
	end

	if self.MouseObjects <= 0 then return end

	self.MouseObjects = self.MouseObjects - 1

	if self.MouseObjects == 0 then
		if not ( IsCommander and IsCommander() ) or self.EnabledMouse then
			ShowMouse( false )
			self.EnabledMouse = false
		end
	end
end

--[[
	Registers a skin.
	Inputs: Skin name, table of colour/texture/font/size values.
]]
function SGUI:RegisterSkin( Name, Values )
	self.Skins[ Name ] = Values
end

local function CheckIsSchemed( Control )
	return Control.UseScheme
end

--[[
	Sets the current skin. This will reskin all active globally skinned objects.
	Input: Skin name registered with SGUI:RegisterSkin()
]]
function SGUI:SetSkin( Name )
	local SchemeTable = self.Skins[ Name ]

	assert( SchemeTable, "[SGUI] Attempted to set a non-existant skin!" )

	self.ActiveSkin = Name
	--Notify all elements of the change.
	return SGUI:CallGlobalEvent( "OnSchemeChange", CheckIsSchemed, SchemeTable )
end

--[[
	Returns the active colour scheme data table.
]]
function SGUI:GetSkin()
	local SchemeName = self.ActiveSkin
	local SchemeTable = SchemeName and self.Skins[ SchemeName ]

	assert( SchemeTable, "[SGUI] No active skin!" )

	return SchemeTable
end

--[[
	Reloads all skin files and calls the scheme change SGUI event.
	Consistency checking will hate you and kick you if you use this with Lua files being checked.
]]
function SGUI:ReloadSkins()
	local Skins = {}
	Shared.GetMatchingFileNames( "lua/shine/lib/gui/skins/*.lua", false, Skins )

	for i = 1, #Skins do
		include( Skins[ i ], true )
	end

	if self.ActiveSkin then
		self:SetSkin( self.ActiveSkin )
	end

	Shared.Message( "[SGUI] Skins reloaded successfully." )
end

--[[
	Registers a control meta-table.
	We'll use this to create instances of it (instead of loading a script
	file every time like UWE).

	Inputs:
		1. Control name
		2. Control meta-table.
		3. Optional parent name. This will make the object inherit the parent's table keys.
]]
function SGUI:Register( Name, Table, Parent )
	--If we have set a parent, then we want to setup a slightly different __index function.
	if Parent then
		--This may not be defined yet, so we get it when needed.
		local ParentTable
		function Table:__index( Key )
			ParentTable = ParentTable or SGUI.Controls[ Parent ]

			if Table[ Key ] then return Table[ Key ] end
			if ParentTable and ParentTable[ Key ] then return ParentTable[ Key ] end
			if ControlMeta[ Key ] then return ControlMeta[ Key ] end

			return nil
		end
	else
		--No parent means only look in its meta-table and the base meta-table.
		function Table:__index( Key )
			if Table[ Key ] then return Table[ Key ] end

			if ControlMeta[ Key ] then return ControlMeta[ Key ] end

			return nil
		end
	end

	--Used to call base class functions for things like :MoveTo()
	Table.BaseClass = ControlMeta

	self.Controls[ Name ] = Table
end

--[[
	Destroys a classic GUI script.
	Input: GUIItem script.
]]
function SGUI.DestroyScript( Script )
	return GetGUIManager():DestroyGUIScript( Script )
end

--[[
	Creates an SGUI control.
	Input: SGUI control class name, optional parent object.
	Output: SGUI control object.
]]
function SGUI:Create( Class, Parent )
	local MetaTable = self.Controls[ Class ]

	assert( MetaTable, "[SGUI] Invalid SGUI class passed to SGUI:Create!" )

	local Table = {}

	local Control = setmetatable( Table, MetaTable )
	Control.Class = Class
	Control:Initialise()

	self.ActiveControls:Add( Control, true )

	--If it's a window then we give it focus.
	if MetaTable.IsWindow and not Parent then
		local Windows = self.Windows

		Windows[ #Windows + 1 ] = Control

		self:SetWindowFocus( Control )

		Control.IsAWindow = true
	end

	if not Parent then return Control end

	Control:SetParent( Parent )

	return Control
end

--[[
	Destroys an SGUI control, leaving the table in storage for use as a new object later.

	This runs the control's cleanup function then empties its table.
	The cleanup function should remove all GUI elements, this will not do it.

	Input: SGUI control object.
]]
function SGUI:Destroy( Control )
	self.ActiveControls:Remove( Control )

	if self.IsValid( Control.Tooltip ) then
		Control.Tooltip:Destroy()
	end

	--SGUI children, not GUIItems.
	if Control.Children then
		for Control in Control.Children:Iterate() do
			Control:Destroy()
		end
	end

	local DeleteOnRemove = Control.__DeleteOnRemove

	if DeleteOnRemove then
		for i = 1, #DeleteOnRemove do
			local Control = DeleteOnRemove[ i ]

			if self.IsValid( Control ) then
				Control:Destroy()
			end
		end
	end

	Control:Cleanup()

	local CallOnRemove = Control.__CallOnRemove

	if CallOnRemove then
		for i = 1, #CallOnRemove do
			CallOnRemove[ i ]( Control )
		end
	end

	--If it's a window, then clean it up.
	if Control.IsAWindow then
		local Windows = self.Windows

		for i = 1, #Windows do
			local Window = Windows[ i ]

			if Window == Control then
				TableRemove( Windows, i )
				break
			end
		end

		self:SetWindowFocus( Windows[ #Windows ] )
	end
end

--[[
	Combines a nil and validity check into one.

	Input: SGUI control to check for existence and validity.
	Output: Existence and validity.
]]
function SGUI.IsValid( Control )
	return Control and Control.IsValid and Control:IsValid()
end

Hook.Add( "Think", "UpdateSGUI", function( DeltaTime )
	SGUI:CallEvent( false, "Think", DeltaTime )
end )

Hook.Add( "PlayerKeyPress", "UpdateSGUI", function( Key, Down )
	if SGUI:CallEvent( false, "PlayerKeyPress", Key, Down ) then
		return true
	end
end )

Hook.Add( "PlayerType", "UpdateSGUI", function( Char )
	if SGUI:CallEvent( false, "PlayerType", SGUI.GetChar( Char ) ) then
		return true
	end
end )

local function NotifyFocusChange( Element, ClickingOtherElement )
	if not Element then
		SGUI.FocusedControl = nil
	end

	for Control in SGUI.ActiveControls:Iterate() do
		if Control.OnFocusChange then
			if Control:OnFocusChange( Element, ClickingOtherElement ) then
				break
			end
		end
	end
end

--[[
	If we don't load after everything, things aren't registered properly.
]]
Hook.Add( "OnMapLoad", "LoadGUIElements", function()
	local Controls = {}
	Shared.GetMatchingFileNames( "lua/shine/lib/gui/objects/*.lua", false, Controls )

	for i = 1, #Controls do
		include( Controls[ i ] )
	end

	local Skins = {}
	Shared.GetMatchingFileNames( "lua/shine/lib/gui/skins/*.lua", false, Skins )

	for i = 1, #Skins do
		include( Skins[ i ] )
	end

	--Apparently this isn't loading for some people???
	if not SGUI.Skins.Default then
		local Skin = next( SGUI.Skins )
		--If there's a different skin, load it.
		--Otherwise whoever's running this is missing the skin file, I can't fix that.
		if Skin then
			SGUI:SetSkin( Skin )
		end
	else
		SGUI:SetSkin( "Default" )
	end

	local Listener = {
		OnMouseMove = function( _, LMB )
			SGUI:CallEvent( false, "OnMouseMove", LMB )
		end,
		OnMouseWheel = function( _, Down )
			return SGUI:CallEvent( false, "OnMouseWheel", Down )
		end,
		OnMouseDown = function( _, Key, DoubleClick )
			local Result, Control = SGUI:CallEvent( true, "OnMouseDown", Key )

			if Result and Control then
				if not Control.UsesKeyboardFocus then
					NotifyFocusChange( nil, true )
				end

				if Control.OnMouseUp then
					SGUI.MouseDownControl = Control
				end
			end

			return Result
		end,
		OnMouseUp = function( _, Key )
			local Control = SGUI.MouseDownControl
			if not SGUI.IsValid( Control ) then return end

			local Success, Result = xpcall( Control.OnMouseUp, OnError, Control, Key )

			SGUI.MouseDownControl = nil

			return Result
		end
	}

	MouseTracker_ListenToMovement( Listener )
	MouseTracker_ListenToButtons( Listener )

	if Shine.IsNS2Combat then
		--Combat has a userdata listener at the top which blocks SGUI scrolling.
		--So we're going to put ourselves above it.
		local Listeners = Shine.GetUpValue( MouseTracker_ListenToWheel,
			"gMouseWheelMovementListeners" )

		TableInsert( Listeners, 1, Listener )
	else
		MouseTracker_ListenToWheel( Listener )
	end
end )

--------------------- BASE CLASS ---------------------
--[[
	Base initialise. Be sure to override this!
	Though you should call it in your override if you want to be schemed.
]]
function ControlMeta:Initialise()
	self.UseScheme = true
end

--[[
	Generic cleanup, for most controls this is adequate.
]]
function ControlMeta:Cleanup()
	if self.Parent then return end

	if self.Background then
		GUI.DestroyItem( self.Background )
	end
end

--[[
	Destroys a control.
]]
function ControlMeta:Destroy()
	return SGUI:Destroy( self )
end

--[[
	Sets a control to be destroyed when this one is.
]]
function ControlMeta:DeleteOnRemove( Control )
	self.__DeleteOnRemove = self.__DeleteOnRemove or {}

	local Table = self.__DeleteOnRemove

	Table[ #Table + 1 ] = Control
end

function ControlMeta:CallOnRemove( Func )
	self.__CallOnRemove = self.__CallOnRemove or {}

	local Table = self.__CallOnRemove

	Table[ #Table + 1 ] = Func
end

--[[
	Sets up a control's properties using a table.
]]
function ControlMeta:SetupFromTable( Table )
	for Property, Value in pairs( Table ) do
		local Method = "Set"..Property

		if self[ Method ] then
			self[ Method ]( self, Value )
		end
	end
end

--[[
	Sets a control's parent manually.
]]
function ControlMeta:SetParent( Control, Element )
	if self.Parent then
		self.Parent.Children:Remove( self )
		self.ParentElement:RemoveChild( self.Background )
	end

	if not Control then
		self.Parent = nil
		return
	end

	--Parent to a specific part of a control.
	if Element then
		self.Parent = Control
		self.ParentElement = Element

		Control.Children = Control.Children or Map()
		Control.Children:Add( self, true )

		Element:AddChild( self.Background )

		return
	end

	if not Control.Background or not self.Background then return end

	self.Parent = Control
	self.ParentElement = Control.Background

	Control.Children = Control.Children or Map()
	Control.Children:Add( self, true )

	Control.Background:AddChild( self.Background )
end

--[[
	Calls an SGUI event on every child of the object.

	Ignores children with the _CallEventsManually flag.
]]
function ControlMeta:CallOnChildren( Name, ... )
	if not self.Children then return nil end

	--Call the event on every child of this object, no particular order.
	for Child in self.Children:Iterate() do
		if Child[ Name ] and not Child._CallEventsManually then
			local Result, Control = Child[ Name ]( Child, ... )

			if Result ~= nil then
				return Result, Control
			end
		end
	end

	return nil
end

--[[
	Add a GUIItem as a child.
]]
function ControlMeta:AddChild( GUIItem )
	if not self.Background then return end

	self.Background:AddChild( GUIItem )
end

function ControlMeta:SetLayer( Layer )
	if not self.Background then return end

	self.Background:SetLayer( Layer )
end

--[[
	Override to get child elements inheriting stencil settings from their background.
]]
function ControlMeta:SetupStencil()
	self.Background:SetInheritsParentStencilSettings( false )
	self.Background:SetStencilFunc( GUIItem.NotEqual )

	self.Stencilled = true
end

--[[
	Determines if the given control should use the global skin.
]]
function ControlMeta:SetIsSchemed( Bool )
	self.UseScheme = Bool and true or false
end

--[[
	Sets visibility of the control.
]]
function ControlMeta:SetIsVisible( Bool )
	if not self.Background then return end
	if self.Background.GetIsVisible and self.Background:GetIsVisible() == Bool then return end

	self.Background:SetIsVisible( Bool )

	if self.IsAWindow then
		if Bool then --Take focus on show.
			if SGUI.FocusedWindow == self then return end
			local Windows = SGUI.Windows

			for i = 1, #Windows do
				local Window = Windows[ i ]

				if Window == self then
					SGUI:SetWindowFocus( self, i )
					break
				end
			end
		else --Give focus to the next window down on hide.
			if SGUI.WindowFocus ~= self then return end

			local Windows = SGUI.Windows
			local NextDown = #Windows - 1

			if NextDown > 0 then
				SGUI:SetWindowFocus( Windows[ NextDown ], NextDown )
			end
		end
	end
end

--[[
	Override this for stencilled stuff.
]]
function ControlMeta:GetIsVisible()
	if not self.Background.GetIsVisible then return false end

	return self.Background:GetIsVisible()
end

--[[
	Sets the size of the control (background).
]]
function ControlMeta:SetSize( SizeVec )
	if not self.Background then return end

	self.Background:SetSize( SizeVec )
end

function ControlMeta:GetSize()
	if not self.Background then return end

	return self.Background:GetSize()
end

--[[
	Sets the position of an SGUI control.

	Controls may override this.
]]
function ControlMeta:SetPos( Vec )
	if not self.Background then return end

	self.Background:SetPosition( Vec )
end

function ControlMeta:GetPos()
	if not self.Background then return end

	return self.Background:GetPosition()
end

local ScrW, ScrH

function ControlMeta:GetScreenPos()
	if not self.Background then return end

	ScrW = ScrW or Client.GetScreenWidth
	ScrH = ScrH or Client.GetScreenHeight

	return self.Background:GetScreenPosition( ScrW(), ScrH() )
end

local Anchors = {
	TopLeft = { GUIItem.Left, GUIItem.Top },
	TopMiddle = { GUIItem.Middle, GUIItem.Top },
	TopRight = { GUIItem.Right, GUIItem.Top },

	CentreLeft = { GUIItem.Left, GUIItem.Center },
	CentreMiddle = { GUIItem.Middle, GUIItem.Center },
	CentreRight = { GUIItem.Right, GUIItem.Center },

	CenterLeft = { GUIItem.Left, GUIItem.Center },
	CenterMiddle = { GUIItem.Middle, GUIItem.Center },
	CenterRight = { GUIItem.Right, GUIItem.Center },

	BottomLeft = { GUIItem.Left, GUIItem.Bottom },
	BottomMiddle = { GUIItem.Middle, GUIItem.Bottom },
	BottomRight = { GUIItem.Right, GUIItem.Bottom }
}

--[[
	Sets the origin anchors for the control.
]]
function ControlMeta:SetAnchor( X, Y )
	if not self.Background then return end

	if IsType( X, "string" ) then
		local Anchor = Anchors[ X ]

		if Anchor then
			self.Background:SetAnchor( Anchor[ 1 ], Anchor[ 2 ] )
		end
	else
		self.Background:SetAnchor( X, Y )
	end
end

function ControlMeta:GetAnchor()
	local X = self.Background:GetXAnchor()
	local Y = self.Background:GetYAnchor()

	return X, Y
end

--We call this so many times it really needs to be local, not global.
local MousePos

--[[
	Gets whether the mouse cursor is inside the bounds of a GUIItem.
	The multiplier will increase or reduce the size we use to calculate this.
]]
function ControlMeta:MouseIn( Element, Mult, MaxX, MaxY )
	if not Element then return end

	MousePos = MousePos or Client.GetCursorPosScreen
	ScrW = ScrW or Client.GetScreenWidth
	ScrH = ScrH or Client.GetScreenHeight

	local X, Y = MousePos()

	local Pos = Element:GetScreenPosition( ScrW(), ScrH() )
	local Size = Element:GetSize()

	if Element.GetIsScaling and Element:GetIsScaling() and Element.scale then
		Size = Size * Element.scale
	end

	if Mult then
		if IsType( Mult, "number" ) then
			Size = Size * Mult
		else
			Size.x = Size.x * Mult.x
			Size.y = Size.y * Mult.y
		end
	end

	MaxX = MaxX or Size.x
	MaxY = MaxY or Size.y

	local InX = X >= Pos.x and X <= Pos.x + MaxX
	local InY = Y >= Pos.y and Y <= Pos.y + MaxY

	local PosX = X - Pos.x
	local PosY = Y - Pos.y

	if InX and InY then
		return true, PosX, PosY, Size, Pos
	end

	return false, PosX, PosY
end

--[[
	Sets an SGUI control to move from its current position.

	TODO: Refactor to behave like FadeTo to allow multiple elements moving at once.

	Inputs:
		1. New position vector.
		2. Time delay before starting
		3. Duration of movement.
		4. Easing function (math.EaseIn, math.EaseOut, math.EaseInOut).
		5. Easing power (higher powers are more 'sticky', they take longer to start and stop).
		6. Callback function to run once movement is complete.
		7. Optional element to apply movement to.
]]
function ControlMeta:MoveTo( NewPos, Delay, Time, EaseFunc, Power, Callback, Element )
	self.MoveData = self.MoveData or {}

	local StartPos = Element and Element:GetPosition() or self.Background:GetPosition()

	self.MoveData.NewPos = NewPos
	self.MoveData.StartPos = StartPos
	self.MoveData.Dir = NewPos - StartPos

	self.MoveData.EaseFunc = EaseFunc or math.EaseOut
	self.MoveData.Power = Power or 3
	self.MoveData.Callback = Callback

	local CurTime = Clock()

	self.MoveData.StartTime = CurTime + Delay
	self.MoveData.Duration = Time
	self.MoveData.Elapsed = 0
	--self.MoveData.EndTime = CurTime + Delay + Time

	self.MoveData.Element = Element or self.Background

	self.MoveData.Finished = false
end

--[[
	Processes a control's movement. Internally called.
	Input: Current game time.
]]
function ControlMeta:ProcessMove()
	local MoveData = self.MoveData

	local Duration = MoveData.Duration
	local Progress = MoveData.Elapsed / Duration

	local LerpValue = MoveData.EaseFunc( Progress, MoveData.Power )

	local EndPos = MoveData.StartPos + LerpValue * MoveData.Dir

	MoveData.Element:SetPosition( EndPos )
end

--[[
	Fades an element from one colour to another.

	You can fade as many GUIItems in an SGUI control as you want at once.

	Inputs:
		1. GUIItem to fade.
		2. Starting colour.
		3. Final colour.
		4. Delay from when this is called to wait before starting the fade.
		5. Duration of the fade.
		6. Callback function to run once the fading has completed.
]]
function ControlMeta:FadeTo( Element, Start, End, Delay, Duration, Callback )
	self.Fades = self.Fades or Map()

	local Fade = self.Fades:Get( Element )
	if not Fade then
		self.Fades:Add( Element, {} )
		Fade = self.Fades:Get( Element )
	end

	Fade.Obj = Element

	Fade.Started = true
	Fade.Finished = false

	local Time = Clock()

	local Diff = SGUI.ColourSub( End, Start )
	local CurCol = SGUI.CopyColour( Start )

	Fade.Diff = Diff
	Fade.CurCol = CurCol

	Fade.StartCol = Start
	Fade.EndCol = End

	Fade.StartTime = Time + Delay
	Fade.Duration = Duration
	Fade.Elapsed = 0
	--Fade.EndTime = Time + Delay + Duration

	Fade.Callback = Callback
end

function ControlMeta:StopFade( Element )
	if not self.Fades then return end

	self.Fades:Remove( Element )
end

--[[
	Resizes an element from one size to another.

	Inputs:
		1. GUIItem to resize.
		2. Starting size, leave nil to use the element's current size.
		3. Ending size.
		4. Delay before resizing should start.
		5. Duration of resizing.
		6. Callback to run when resizing is complete.
		7. Optional easing function to use.
		8. Optional power to pass to the easing function.
]]
function ControlMeta:SizeTo( Element, Start, End, Delay, Duration, Callback, EaseFunc, Power )
	self.SizeAnims = self.SizeAnims or Map()
	local Sizes = self.SizeAnims

	local Size = Sizes:Get( Element )
	if not Size then
		self.SizeAnims:Add( Element, {} )
		Size = self.SizeAnims:Get( Element )
	end

	Size.Obj = Element

	Size.Started = true
	Size.Finished = false

	Size.EaseFunc = EaseFunc or math.EaseOut
	Size.Power = Power or 3

	local Time = Clock()

	Start = Start or Element:GetSize()

	local Diff = End - Start
	local CurSize = Start

	Size.Diff = Diff
	Size.CurSize = Vector( CurSize.x, CurSize.y, 0 )

	Size.Start = CurSize
	Size.End = End

	Size.StartTime = Time + Delay
	Size.Duration = Duration
	Size.Elapsed = 0
	--Size.EndTime = Time + Delay + Duration

	Size.Callback = Callback
end

function ControlMeta:StopResizing( Element )
	if not self.SizeAnims then return end

	self.SizeAnims:Remove( Element )
end

--[[
	Sets an SGUI control to highlight on mouse over automatically.

	Requires the values:
		self.ActiveCol - Colour when highlighted.
		self.InactiveCol - Colour when not highlighted.

	Will set the value:
		self.Highlighted - Will be true when highlighted.

	Only applies to the background.

	Inputs:
		1. Boolean should hightlight.
		2. Muliplier to the element's size when determining if the mouse is in the element.
]]
function ControlMeta:SetHighlightOnMouseOver( Bool, Mult, TextureMode )
	self.HighlightOnMouseOver = Bool and true or false
	self.HighlightMult = Mult
	self.TextureHighlight = TextureMode
end

function ControlMeta:SetTooltip( Text )
	if Text == nil then
		self.TooltipText = nil

		self.OnHover = nil
		self.OnLoseHover = nil

		return
	end

	self.TooltipText = Text

	self.OnHover = self.ShowTooltip
	self.OnLoseHover = self.HideTooltip
end

function ControlMeta:HandleMovement( Time, DeltaTime )
	if not self.MoveData or self.MoveData.StartTime > Time or self.MoveData.Finished then
		return
	end

	if self.MoveData.Elapsed <= self.MoveData.Duration then
		self.MoveData.Elapsed = self.MoveData.Elapsed + DeltaTime

		self:ProcessMove()
	else
		self.MoveData.Element:SetPosition( self.MoveData.NewPos )
		if self.MoveData.Callback then
			self.MoveData.Callback( self )
		end

		self.MoveData.Finished = true
	end

	--We call this to update highlighting if the control is moving and the mouse is not.
	self.BaseClass.OnMouseMove( self, false )
end

function ControlMeta:HandleFading( Time, DeltaTime )
	if not self.Fades or self.Fades:IsEmpty() then return end

	for Element, Fade in self.Fades:Iterate() do
		local Start = Fade.StartTime
		local Duration = Fade.Duration

		Fade.Elapsed = Fade.Elapsed + DeltaTime

		local Elapsed = Fade.Elapsed

		if Start <= Time then
			if Elapsed <= Duration then
				local Progress = Elapsed / Duration
				local CurCol = Fade.CurCol

				--Linear progress.
				SGUI.ColourLerp( CurCol, Fade.StartCol, Progress, Fade.Diff )

				Element:SetColor( CurCol )
			elseif not Fade.Finished then
				Element:SetColor( Fade.EndCol )

				Fade.Finished = true

				self.Fades:Remove( Element )

				if Fade.Callback then
					Fade.Callback( Element )
				end
			end
		end
	end
end

function ControlMeta:HandleResizing( Time, DeltaTime )
	if not self.SizeAnims or self.SizeAnims:IsEmpty() then return end

	for Element, Size in self.SizeAnims:Iterate() do
		local Start = Size.StartTime
		local Duration = Size.Duration

		Size.Elapsed = Size.Elapsed + DeltaTime

		local Elapsed = Size.Elapsed

		if Start <= Time then
			if Elapsed <= Duration then
				local Progress = Elapsed / Duration
				local CurSize = Size.CurSize

				local LerpValue = Size.EaseFunc( Progress, Size.Power )

				CurSize.x = Size.Start.x + LerpValue * Size.Diff.x
				CurSize.y = Size.Start.y + LerpValue * Size.Diff.y

				if Element == self.Background then
					self:SetSize( CurSize )
				else
					Element:SetSize( CurSize )
				end
			elseif not Size.Finished then
				if Element == self.Background then
					self:SetSize( Size.End )
				else
					Element:SetSize( Size.End )
				end

				Size.Finished = true

				self.SizeAnims:Remove( Element )

				if Size.Callback then
					Size.Callback( Element )
				end
			end
		end
	end
end

function ControlMeta:HandleHovering( Time )
	if not self.OnHover then return end

	local MouseIn, X, Y = self:MouseIn( self.Background )
	if MouseIn then
		if not self.MouseHoverStart then
			self.MouseHoverStart = Time
		else
			if Time - self.MouseHoverStart > 1 and not self.MouseHovered then
				self:OnHover( X, Y )

				self.MouseHovered = true
			end
		end
	else
		self.MouseHoverStart = nil
		if self.MouseHovered then
			self.MouseHovered = nil

			if self.OnLoseHover then
				self:OnLoseHover()
			end
		end
	end
end

--[[
	Global update function. Called on client update.

	You must call this inside a control's custom Think function with:
		self.BaseClass.Think( self, DeltaTime )
	if you want to use MoveTo, FadeTo, SetHighlightOnMouseOver etc.

	Alternatively, call only the functions you want to use.
]]
function ControlMeta:Think( DeltaTime )
	local Time = Clock()

	self:HandleMovement( Time, DeltaTime )
	self:HandleFading( Time, DeltaTime )
	self:HandleResizing( Time, DeltaTime )
	self:HandleHovering( Time )
end

function ControlMeta:ShowTooltip( X, Y )
	local SelfPos = self:GetScreenPos()

	X = SelfPos.x + X
	Y = SelfPos.y + Y

	local Tooltip = SGUI.IsValid( self.Tooltip ) and self.Tooltip or SGUI:Create( "Tooltip" )
	Tooltip:SetText( self.TooltipText )

	Y = Y - Tooltip:GetSize().y - 4

	Tooltip:SetPos( Vector( X, Y, 0 ) )
	Tooltip:FadeIn()

	self.Tooltip = Tooltip
end

function ControlMeta:HideTooltip()
	if not SGUI.IsValid( self.Tooltip ) then return end

	self.Tooltip:FadeOut( function()
		self.Tooltip = nil
	end )
end

function ControlMeta:OnMouseMove( Down )
	--Basic highlight on mouse over handling.
	if not self.HighlightOnMouseOver then
		return
	end

	if self:MouseIn( self.Background, self.HighlightMult ) then
		if not self.Highlighted then
			self.Highlighted = true

			if not self.TextureHighlight then
				self:FadeTo( self.Background, self.InactiveCol,
				self.ActiveCol, 0, 0.1, function( Background )
					Background:SetColor( self.ActiveCol )
				end )
			else
				self.Background:SetTexture( self.HighlightTexture )
			end
		end
	else
		if self.Highlighted and not self.ForceHighlight then
			self.Highlighted = false

			if not self.TextureHighlight then
				self:FadeTo( self.Background, self.ActiveCol,
				self.InactiveCol, 0, 0.1, function( Background )
					Background:SetColor( self.InactiveCol )
				end )
			else
				self.Background:SetTexture( self.Texture )
			end
		end
	end
end

--[[
	Requests focus, for text entry controls.
]]
function ControlMeta:RequestFocus()
	SGUI.FocusedControl = self

	NotifyFocusChange( self )
end

--[[
	Returns whether the current control has focus.
]]
function ControlMeta:HasFocus()
	return SGUI.FocusedControl == self
end

--[[
	Drops focus on the given element.
]]
function ControlMeta:LoseFocus()
	if not self:HasFocus() then return end

	NotifyFocusChange()
end

--[[
	Returns whether the current object is still in use.
	Output: Boolean valid.
]]
function ControlMeta:IsValid()
	return SGUI.ActiveControls:Get( self ) ~= nil
end
