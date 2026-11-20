local ADDON_NAME, ns = ...

local BEAR_FORM_ID = 5
local CAT_FORM_ID = 1

ns.unlocked = false -- session only: frames are draggable and always shown
ns.configOpen = false -- set by the config panel while it is visible

local frame, text, bg

function ns.IsDruid()
	return select(2, UnitClass("player")) == "DRUID"
end

function ns.IsDeathKnight()
	return select(2, UnitClass("player")) == "DEATHKNIGHT"
end

-- True while the user is positioning or styling: elements show regardless of game state.
function ns.IsPreview()
	return ns.unlocked or ns.configOpen
end

-- Combat as the REGEN events report it, so nothing depends on UnitAffectingCombat having caught up inside the event
-- itself. Before the first such event (login, /reload, a loading screen) the unit is asked directly.
local combatFlag

function ns.InCombat()
	if combatFlag == nil then
		return UnitAffectingCombat("player") and true or false
	end
	return combatFlag
end

local function OnEvent(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		combatFlag = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		combatFlag = false
	elseif event == "PLAYER_ENTERING_WORLD" then
		combatFlag = nil
	end
	ns.Apply()
end

local function DefaultStore()
	return ns.db
end

-- Makes `f` draggable while ns.unlocked, saving its offset from the screen center
-- into store()[xKey] / store()[yKey]. `store` defaults to the saved-variables table. `onMoved` (optional) runs after a drag.
function ns.MakeDraggable(f, xKey, yKey, store, onMoved)
	store = store or DefaultStore
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if ns.unlocked then
			self:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local t = store()
		if not t then
			return
		end
		local cx, cy = self:GetCenter()
		local ux, uy = UIParent:GetCenter()
		t[xKey] = math.floor(cx - ux + 0.5)
		t[yKey] = math.floor(cy - uy + 0.5)
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", t[xKey], t[yKey])
		if onMoved then
			onMoved()
		end
	end)
end

function ns.PlaceFrame(f, xKey, yKey, t)
	t = t or ns.db
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", t[xKey], t[yKey])
end

function ns.IsFeral()
	local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
	return getSpec ~= nil and getSpec() == 2
end

-- Bear Form is always fine (Guardian's form); Cat Form is fine for a Feral druid.
local function InExpectedForm()
	local form = GetShapeshiftFormID()
	if form == BEAR_FORM_ID then
		return true
	end
	return form == CAT_FORM_ID and ns.IsFeral()
end

local function ApplyText()
	if not frame then
		return
	end
	local db = ns.db
	local flags = db.outline and "OUTLINE" or ""
	if not text:SetFont(db.fontPath, db.fontSize, flags) then
		text:SetFont(ns.DEFAULT_FONT, db.fontSize, flags)
	end
	text:SetTextColor(db.color.r, db.color.g, db.color.b, 1)
	text:SetText(db.text)
	frame:SetSize(math.max(text:GetStringWidth() + 16, 60), math.max(text:GetStringHeight() + 12, 24))
	ns.PlaceFrame(frame, "x", "y")

	frame:EnableMouse(ns.unlocked)
	bg:SetShown(ns.unlocked)

	local show
	if not db.textEnabled or not ns.IsDruid() then
		show = false
	elseif ns.IsPreview() then
		show = true
	else
		show = (not db.textCombatOnly or UnitAffectingCombat("player"))
				and (not db.textDungeonOnly or select(2, IsInInstance()) == "party")
				and not InExpectedForm()
				and strtrim(db.text) ~= ""
	end
	frame:SetShown(show)
end

function ns.Apply()
	ApplyText()
	if ns.ApplyIndicator then
		ns.ApplyIndicator()
	end
	if ns.ApplyTrackers then
		ns.ApplyTrackers()
	end
	if ns.ApplyRage then
		ns.ApplyRage()
	end
	if ns.ApplyComboPoints then
		ns.ApplyComboPoints()
	end
	if ns.ApplyEnergy then
		ns.ApplyEnergy()
	end
	if ns.ApplyRunicPower then
		ns.ApplyRunicPower()
	end
	if ns.ApplyBoneShield then
		ns.ApplyBoneShield()
	end
	if ns.ApplyExtDef then
		ns.ApplyExtDef()
	end
	if ns.ApplyAbsorb then
		ns.ApplyAbsorb()
	end
	if ns.ApplyEnrage then
		ns.ApplyEnrage()
	end
	if ns.ApplyDispel then
		ns.ApplyDispel()
	end
	if ns.UpdateGlows then
		ns.UpdateGlows()
	end
	if ns.ApplyMinimap then
		ns.ApplyMinimap()
	end
	if ns.ApplyAuraSounds then
		ns.ApplyAuraSounds()
	end
end

function ns.SetUnlocked(value)
	ns.unlocked = value and true or false
	ns.Apply()
	if ns.RefreshConfig then
		ns.RefreshConfig()
	end
end

function ns.InitDisplay()
	frame = CreateFrame("Frame", "MonroTrackerText", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "x", "y")

	bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.8, 0.3, 0.35)
	bg:Hide()

	text = frame:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetFont(ns.DEFAULT_FONT, 32, "OUTLINE") -- a font must be set before SetText

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", OnEvent)

	-- Bear text, Moonfire indicator, rage panel, combo point and energy bars and enrage panel are Druid-only; on other classes their frames are never created
	-- (their Apply functions do nothing without a frame). Trackers, absorb, voice reminders and trinket glow work for any class.
	if ns.IsDruid() and ns.InitIndicator then
		ns.InitIndicator()
	end
	if ns.InitTrackers then
		ns.InitTrackers()
	end
	if ns.IsDruid() and ns.InitRage then
		ns.InitRage()
	end
	if ns.IsDruid() and ns.InitComboPoints then
		ns.InitComboPoints()
	end
	if ns.IsDruid() and ns.InitEnergy then
		ns.InitEnergy()
	end
	if ns.IsDruid() and ns.InitEnrage then
		ns.InitEnrage()
	end
	if ns.IsDruid() and ns.InitDispel then
		ns.InitDispel()
	end
	if ns.IsDeathKnight() and ns.InitRunicPower then
		ns.InitRunicPower()
	end
	if ns.IsDeathKnight() and ns.InitBoneShield then
		ns.InitBoneShield()
	end
	if ns.InitExtDef then
		ns.InitExtDef()
	end
	if ns.InitAbsorb then
		ns.InitAbsorb()
	end
	if ns.InitReminders then
		ns.InitReminders()
	end
	if ns.InitTrinketGlow then
		ns.InitTrinketGlow()
	end
	if ns.InitMinimap then
		ns.InitMinimap()
	end
	ns.Apply()
end
