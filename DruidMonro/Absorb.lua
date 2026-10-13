local ADDON_NAME, ns = ...

local FRENZIED_REGENERATION = 22842
local SHIELD_SPELL = 17 -- Power Word: Shield, only borrowed for its icon
local FALLBACK_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"
local PREVIEW_TEXT = "315081"

local frame, icon, text

-- True while the player carries the Frenzied Regeneration aura.
local function HasFrenzied()
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, FRENZIED_REGENERATION)
	return ok and aura ~= nil
end

-- Returns the total absorb on the player, or nil when the client hides it.
local function TotalAbsorb()
	local ok, total = pcall(function()
		local v = UnitGetTotalAbsorbs("player")
		return v > 0 and v or 0 -- comparison fails if the client hides the value
	end)
	if ok then
		return total
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
	if not ns.IsDruid() then
		return false
	end
	if HasFrenzied() then
		return true
	end
	if db.absorbAny then
		local total = TotalAbsorb()
		return total ~= nil and total > 0
	end
	return false
end

local function UpdateText()
	if ns.IsPreview() and not HasFrenzied() then
		text:SetText(PREVIEW_TEXT)
		return
	end
	-- The number is the final total, so absorbs from other sources are included.
	-- Formatting fails if the client hides the value.
	local ok = pcall(function()
		text:SetFormattedText("%d", UnitGetTotalAbsorbs("player"))
	end)
	if not ok then
		text:SetText("")
	end
end

-- Cheap pass for aura / absorb events.
local function Update()
	if not frame then
		return
	end
	local show = ShouldShow()
	frame:SetShown(show)
	if show then
		UpdateText()
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
	icon:SetTexture(C_Spell.GetSpellTexture(SHIELD_SPELL) or FALLBACK_ICON)
	text:SetFont(ns.DEFAULT_FONT, db.absorbFontSize, "OUTLINE")
	Update()
end

function ns.InitAbsorb()
	frame = CreateFrame("Frame", "DruidMonroAbsorb", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "absorbX", "absorbY")

	icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND")
	frame.unlockBg:SetAllPoints()
	frame.unlockBg:SetColorTexture(0.1, 0.8, 0.3, 0.35)

	text = frame:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetFont(ns.DEFAULT_FONT, 16, "OUTLINE") -- a font must be set before SetText

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterUnitEvent("UNIT_AURA", "player")
	events:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
	events:SetScript("OnEvent", Update)
end
