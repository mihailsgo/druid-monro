local ADDON_NAME, ns = ...

local MOONFIRE_DEBUFF = 164812
local MOONFIRE_CAST = 8921
local FALLBACK_ICON = "Interface\\Icons\\Spell_Nature_StarFall"
local MAX_PLATES = 40
local MOONFIRE_DURATION = 22 -- seconds a cast Moonfire is assumed to last when the real aura cannot be read
local PREVIEW_TEXT = "3/5"

local frame, icon, text
local have, total = 0, 0

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

-- In combat the client hides the spell IDs of auras on enemy units, so reading "is this Moonfire?" fails.
-- Two layers: (1) read the player's own debuffs on the unit; if their spell IDs are readable the answer is exact;
-- (2) otherwise remember when and on which unit we cast Moonfire, and trust that for its duration as long as the
-- unit still carries some debuff of ours.
local castAt = {} -- key (GUID, or nameplate token if the GUID is hidden) -> GetTime() of the last Moonfire cast

local function UnitKey(unit)
	local guid = UnitGUID(unit)
	if guid and not IsSecret(guid) then
		return guid
	end
	return unit
end

local function MyAuras(unit)
	local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, "HARMFUL|PLAYER")
	if ok and type(list) == "table" then
		return list
	end
end

-- Returns true / false when the aura data is readable, nil when it is hidden.
local function ReadMoonfire(unit)
	local list = MyAuras(unit)
	if not list then
		return nil
	end
	local hidden = false
	for _, aura in ipairs(list) do
		local id = aura.spellId
		if IsSecret(id) then
			hidden = true
		elseif id == MOONFIRE_DEBUFF or id == MOONFIRE_CAST then
			return true
		end
	end
	if hidden then
		return nil
	end
	return false
end

local function HasMyMoonfire(unit)
	local read = ReadMoonfire(unit)
	if read ~= nil then
		return read
	end
	local t = castAt[UnitKey(unit)] or castAt[unit]
	if not t or GetTime() - t > MOONFIRE_DURATION then
		return false
	end
	local list = MyAuras(unit)
	return list == nil or #list > 0
end

-- The unit a Moonfire lands on is not known from the cast event (mouseover / focus macros cast on a unit that is
-- not the target), so a cast only opens a short window: the nameplate whose debuffs change inside it got the Moonfire.
local CAST_WINDOW = 0.6 -- seconds after a cast during which a nameplate aura change is credited to it
local castWindowEnd = 0

local recentCasts = {} -- last few player casts, for /druidm moondebug
local MAX_RECENT = 8

-- A Moonfire cast is recognised by spell ID or by name: the proc'd (free, empowered) Moonfire may go out under a
-- different ID than the normal one.
local function IsMoonfireSpell(spellID)
	if IsSecret(spellID) or not spellID then
		return false
	end
	if spellID == MOONFIRE_CAST or spellID == MOONFIRE_DEBUFF then
		return true
	end
	local name = C_Spell.GetSpellName(spellID)
	return name ~= nil and name == C_Spell.GetSpellName(MOONFIRE_CAST)
end

local function NoteCast()
	castWindowEnd = GetTime() + CAST_WINDOW
end

local function LogCast(event, spellID, isMoonfire)
	table.insert(recentCasts, 1, string.format("%s id=%s %s", event == "UNIT_SPELLCAST_SENT" and "sent" or "done",
		tostring(IsSecret(spellID) and "?" or spellID), isMoonfire and "(moonfire)" or ""))
	recentCasts[MAX_RECENT + 1] = nil
end

local function NoteAuraChange(unit, info)
	if GetTime() > castWindowEnd or not info or info.isFullUpdate then
		return
	end
	local changed = (info.addedAuras and #info.addedAuras > 0) or (info.updatedAuraInstanceIDs and #info.updatedAuraInstanceIDs > 0)
	if not changed or not UnitCanAttack("player", unit) then
		return
	end
	-- Unreadable auras (nil) count as a change too; otherwise require one of our own debuffs to be present.
	local list = MyAuras(unit)
	if list == nil or #list > 0 then
		castAt[UnitKey(unit)] = GetTime()
	end
end

-- /druidm moondebug: shows what the client lets us read, to diagnose miscounts.
function ns.MoonfireDebug()
	ns.Print("Moonfire count debug (run in combat)")
	print("  last casts (newest first):")
	for _, line in ipairs(recentCasts) do
		print("    " .. line)
	end
	local first
	for i = 1, MAX_PLATES do
		if UnitExists("nameplate" .. i) then
			first = "nameplate" .. i
			break
		end
	end
	if first then
		-- Try other ways of reading the first plate and show exactly what the client answers.
		local function Try(label, fn, ...)
			local ok, a, b = pcall(fn, ...)
			print(string.format("  try %s: ok=%s type=%s secret=%s %s", label, tostring(ok), type(a),
				tostring(ok and IsSecret(a) or false), (not ok) and tostring(a) or ""))
		end
		Try("GetUnitAuras", C_UnitAuras.GetUnitAuras, first, "HARMFUL|PLAYER")
		Try("GetUnitAuras(all)", C_UnitAuras.GetUnitAuras, first, "HARMFUL")
		if C_UnitAuras.GetUnitAuraInstanceIDs then
			Try("GetUnitAuraInstanceIDs", C_UnitAuras.GetUnitAuraInstanceIDs, first, "HARMFUL|PLAYER")
		end
		Try("BySpellID", C_UnitAuras.GetUnitAuraBySpellID, first, MOONFIRE_DEBUFF)
		if C_UnitAuras.GetAuraDataBySpellName then
			Try("BySpellName", C_UnitAuras.GetAuraDataBySpellName, first, C_Spell.GetSpellName(MOONFIRE_DEBUFF) or "Moonfire", "HARMFUL|PLAYER")
		end
	end
	for i = 1, MAX_PLATES do
		local unit = "nameplate" .. i
		if UnitExists(unit) then
			local list = MyAuras(unit)
			local secret = 0
			for _, aura in ipairs(list or {}) do
				if IsSecret(aura.spellId) then
					secret = secret + 1
				end
			end
			local key = UnitKey(unit)
			local age = castAt[key] and string.format("%.1fs", GetTime() - castAt[key]) or "-"
			print(string.format("  %s: myDebuffs=%s hiddenIds=%d read=%s lastCast=%s counted=%s", unit,
				list and #list or "n/a", secret, tostring(ReadMoonfire(unit)), age, tostring(HasMyMoonfire(unit))))
		end
	end
end

-- Counts hostile nameplate mobs that are in combat, and how many of them carry the player's Moonfire.
-- Only mobs that currently have a nameplate (enemy nameplates must be enabled) can be counted.
local function Recount()
	local n, m = 0, 0
	if ns.IsDruid() and UnitAffectingCombat("player") then
		for i = 1, MAX_PLATES do
			local unit = "nameplate" .. i
			if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) and UnitAffectingCombat(unit) then
				n = n + 1
				if HasMyMoonfire(unit) then
					m = m + 1
				end
			end
		end
	end
	return m, n
end

-- The counter shows while mobs are in combat; the icon also shows (without the counter) for a Moonfire proc.
local function CounterShown()
	if not ns.db.moonCountEnabled then
		return false
	end
	return ns.IsPreview() or (ns.IsDruid() and total > 0)
end

local function ShouldShow()
	return CounterShown() or (ns.IsProcShown and ns.IsProcShown()) or false
end

local function UpdateText()
	local db = ns.db
	text:SetShown(CounterShown())
	if total == 0 and ns.IsPreview() then
		text:SetText(PREVIEW_TEXT)
		text:SetTextColor(db.moonCountColor.r, db.moonCountColor.g, db.moonCountColor.b, 1)
		return
	end
	text:SetFormattedText("%d/%d", have, total)
	if total > 0 and have >= total then
		text:SetTextColor(0.2, 1, 0.3, 1) -- every mob covered
	else
		text:SetTextColor(db.moonCountColor.r, db.moonCountColor.g, db.moonCountColor.b, 1)
	end
end

-- Cheap pass for aura / nameplate / combat changes: only the numbers and visibility change.
local function Update()
	if not frame then
		return
	end
	have, total = Recount()
	UpdateText()
	frame:SetShown(ShouldShow())
	if ns.ApplyIndicator then
		ns.ApplyIndicator()
	end
end

-- Re-styles the frame (settings changed) and refreshes it.
function ns.ApplyMoonfireCount()
	if not frame then
		return
	end
	local db = ns.db
	local s = db.moonCountSize
	frame:SetSize(s, s)
	ns.PlaceFrame(frame, "moonCountX", "moonCountY")
	frame:EnableMouse(ns.unlocked)
	frame.unlockBg:SetShown(ns.unlocked)

	local tex = C_Spell.GetSpellTexture(MOONFIRE_CAST)
	icon:SetTexture(tex or FALLBACK_ICON)

	if not text:SetFont(ns.DEFAULT_FONT, db.moonCountFontSize, "OUTLINE") then
		text:SetFont("Fonts\\FRIZQT__.TTF", db.moonCountFontSize, "OUTLINE")
	end
	Update()
end

function ns.InitMoonfireCount()
	frame = CreateFrame("Frame", "DruidMonroMoonfireCount", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "moonCountX", "moonCountY")

	icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND")
	frame.unlockBg:SetAllPoints()
	frame.unlockBg:SetColorTexture(0.1, 0.8, 0.3, 0.35)

	text = frame:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetFont(ns.DEFAULT_FONT, 20, "OUTLINE") -- a font must be set before SetText

	-- The Moonfire proc glow is drawn on this same icon.
	if ns.InitIndicator then
		ns.InitIndicator(frame)
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	events:RegisterEvent("UNIT_AURA")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	events:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
		if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
			-- SENT: (unit, target, castGUID, spellID); SUCCEEDED: (unit, castGUID, spellID)
			local spellID = event == "UNIT_SPELLCAST_SENT" and arg4 or arg3
			local isMoonfire = IsMoonfireSpell(spellID)
			LogCast(event, spellID, isMoonfire)
			if isMoonfire then
				NoteCast()
			end
			return
		elseif event == "NAME_PLATE_UNIT_REMOVED" and unit then
			castAt[unit] = nil -- token-keyed entries die with the plate
		elseif event == "UNIT_AURA" then
			if not (unit and unit:find("^nameplate")) then
				return
			end
			NoteAuraChange(unit, arg2)
		end
		Update()
	end)
	-- Safety net: mobs entering/leaving combat is not announced for nameplate units.
	C_Timer.NewTicker(0.5, Update)
end
