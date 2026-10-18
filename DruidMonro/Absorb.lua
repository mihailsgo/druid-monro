local ADDON_NAME, ns = ...

local FRENZIED_REGENERATION = 22842
local SHIELD_SPELL = 17 -- Power Word: Shield, only borrowed for its icon
local FALLBACK_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"
local PREVIEW_TEXT = "315081"

local frame, shield, text

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

-- True while the player carries the Frenzied Regeneration aura. Aura details can be hidden in instances.
local function HasFrenzied()
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, FRENZIED_REGENERATION)
	return ok and aura ~= nil
end

-- In Mythic+ and other restricted content the client hides the absorb value: it cannot be compared or formatted by
-- us, but it can still be handed to widgets. So the icon is a StatusBar with range 0..1 that is full for any absorb and
-- empty (invisible) for none, and the number is passed to the text as is.
local function UpdateShield()
	local total = UnitGetTotalAbsorbs("player")
	if ns.IsPreview() then
		shield:SetValue(1)
		text:SetText(PREVIEW_TEXT)
		return
	end
	shield:SetValue(total)
	if not IsSecret(total) then
		text:SetText(total > 0 and string.format("%d", total) or "")
		return
	end
	local ok = pcall(function()
		if C_StringUtil and C_StringUtil.TruncateWhenZero then
			text:SetText(C_StringUtil.TruncateWhenZero(total)) -- empty string while there is no absorb
		else
			text:SetFormattedText("%d", total)
		end
	end)
	if not ok then
		text:SetText("")
	end
end

local function ShouldShow()
	local db = ns.db
	if not db.absorbEnabled then
		return false
	end
	if ns.IsPreview() then
		return true
	end
	-- Frenzied Regeneration is a Druid spell, so that option only applies to Druids.
	return not (db.absorbFrenziedOnly and ns.IsDruid()) or HasFrenzied()
end

-- Cheap pass for aura / absorb events.
local function Update()
	if not frame then
		return
	end
	local show = ShouldShow()
	frame:SetShown(show)
	if show then
		UpdateShield()
	end
end

-- Re-styles the frame (settings changed) and refreshes it.
function ns.ApplyAbsorb()
	if not frame then
		return
	end
	local db = ns.db
	frame:SetSize(db.absorbSize, db.absorbSize)
	ns.PlaceFrame(frame, "absorbX", "absorbY")
	frame:EnableMouse(ns.unlocked)
	frame.unlockBg:SetShown(ns.unlocked)
	shield:SetStatusBarTexture(C_Spell.GetSpellTexture(SHIELD_SPELL) or FALLBACK_ICON)
	text:SetFont(ns.DEFAULT_FONT, db.absorbFontSize, "OUTLINE")
	Update()
end

-- /druidm absorbdebug: shows what the client lets us read, to diagnose a missing icon.
function ns.AbsorbDebug()
	ns.Print("absorb debug (run while you have an absorb)")
	local ok, v = pcall(UnitGetTotalAbsorbs, "player")
	local secret = ok and IsSecret(v)
	print(string.format("  UnitGetTotalAbsorbs: ok=%s type=%s secret=%s value=%s", tostring(ok), type(v), tostring(secret),
		(ok and not secret) and tostring(v) or "?"))
	local ok2, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, FRENZIED_REGENERATION)
	print(string.format("  Frenzied Regeneration aura (%d): ok=%s found=%s", FRENZIED_REGENERATION, tostring(ok2),
		tostring(ok2 and aura ~= nil)))
	print(string.format("  TruncateWhenZero available=%s", tostring(C_StringUtil and C_StringUtil.TruncateWhenZero ~= nil)))
	print(string.format("  enabled=%s frenziedOnly=%s druid=%s frame=%s shown=%s text='%s'", tostring(ns.db.absorbEnabled),
		tostring(ns.db.absorbFrenziedOnly), tostring(ns.IsDruid()), tostring(frame ~= nil), tostring(frame and frame:IsShown()),
		(text and not IsSecret(text:GetText())) and tostring(text:GetText()) or "?"))
end

function ns.InitAbsorb()
	frame = CreateFrame("Frame", "DruidMonroAbsorb", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "absorbX", "absorbY")

	frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND")
	frame.unlockBg:SetAllPoints()
	frame.unlockBg:SetColorTexture(0.1, 0.8, 0.3, 0.35)

	shield = CreateFrame("StatusBar", nil, frame)
	shield:SetAllPoints()
	shield:SetStatusBarTexture(FALLBACK_ICON)
	shield:SetMinMaxValues(0, 1)
	shield:SetValue(0)

	-- The number sits on its own frame so it draws above the icon.
	local textHolder = CreateFrame("Frame", nil, frame)
	textHolder:SetAllPoints()
	textHolder:SetFrameLevel(shield:GetFrameLevel() + 2)
	text = textHolder:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetFont(ns.DEFAULT_FONT, 20, "OUTLINE") -- a font must be set before SetText

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterUnitEvent("UNIT_AURA", "player")
	events:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
	events:SetScript("OnEvent", Update)
	-- Safety net: absorb changes are not always announced while the client restricts data.
	C_Timer.NewTicker(0.5, Update)
end
