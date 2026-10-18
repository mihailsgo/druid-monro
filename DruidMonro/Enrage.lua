local ADDON_NAME, ns = ...

-- Enrage panel: lists the enemies that carry an enrage you can Soothe, so you know which mob to cast it on.
--
-- Since Midnight the client hides aura details on enemies in combat, but it still evaluates aura *filters* itself.
-- "HELPFUL|RAID_PLAYER_DISPELLABLE" matches the buffs on a hostile unit that the player's class can remove (for a Druid
-- that is an enrage, Soothe's only target), and the list of aura instance IDs it returns is not secret. A non-empty
-- list therefore means "this mob is enraged" without reading a single hidden value. Where the client does let us read
-- the buff, its dispel type is checked too, to drop anything that is plainly not an enrage.
-- Mobs are found through their nameplates, so enemy nameplates have to be on.

local SOOTHE = 2908
-- INCLUDE_NAME_PLATE_ONLY adds the buffs the client flags to show on nameplates only, which many mob abilities are.
local SOOTHE_FILTER = "HELPFUL|RAID_PLAYER_DISPELLABLE|INCLUDE_NAME_PLATE_ONLY"
local SOOTHE_FALLBACK_ICON = "Interface\\Icons\\Ability_Hunter_BeastSoothe"
local MARK_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local SAY = "Soothe"
local MAX_ROWS = 6
local ROW_H = 24
local HEADER_H = 22
local MAX_PLATES = 40
local ALERT_DEBOUNCE = 1.5 -- several mobs enraging together are one callout

-- Dispel types that are plainly not an enrage, used to drop false matches when the client lets us read the type.
local OTHER_TYPES = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }

-- What the panel shows while positioning or styling it.
local SAMPLES = {
	{ name = "Enraged Brute", mark = 8, pct = 62, secs = 7 },
	{ name = "Furious Whelp", mark = 7, pct = 35, secs = 3 },
}

local frame, headerCount
local rows = {}
local markers = {} -- unit token -> marker shown above that unit's nameplate
local mobs = {} -- unit token -> { since = GetTime() } while that unit carries an enrage
local plateTokens = {}
for i = 1, MAX_PLATES do
	plateTokens[i] = "nameplate" .. i
end
local knowsSoothe = true
local lastAlert = 0
local voiceErrorShown = false

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function SootheIcon()
	return C_Spell.GetSpellTexture(SOOTHE) or SOOTHE_FALLBACK_ICON
end

local function ReadKnowsSoothe()
	if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
		local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, SOOTHE)
		if ok then
			return known == true
		end
	end
	return not IsPlayerSpell or IsPlayerSpell(SOOTHE)
end

function ns.KnowsSoothe()
	return knowsSoothe
end

-- Detection -------------------------------------------------------------------

local function AurasRestricted()
	return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() or false
end

-- The aura instance IDs on `unit` that match `filter` and how many there are; nil plus a reason when the client will not say.
local function AuraIDs(unit, filter)
	local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter)
	if not ok then
		return nil, tostring(ids)
	end
	if type(ids) ~= "table" then
		return nil, "no list returned"
	end
	local okCount, n = pcall(function()
		return #ids
	end)
	if not okCount or type(n) ~= "number" or IsSecret(n) then
		return nil, "count is hidden"
	end
	return ids, n
end

-- True when the buff is readable and plainly some other dispel type (a Magic buff another class could purge).
local function IsOtherDispelType(unit, auraInstanceID)
	local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
	if not ok or type(data) ~= "table" then
		return false
	end
	local dispel = data.dispelName
	if IsSecret(dispel) then
		return false
	end
	return dispel ~= nil and OTHER_TYPES[dispel] == true
end

-- Fallback for a client without the filter: look for an "Enrage" buff by hand. Needs readable auras.
local function ScanByIndex(unit)
	if AurasRestricted() then
		return nil
	end
	for i = 1, 40 do
		local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL|INCLUDE_NAME_PLATE_ONLY")
		if not ok then
			return nil
		end
		if type(data) ~= "table" then
			return false
		end
		local dispel = data.dispelName
		if IsSecret(dispel) then
			return nil
		end
		if dispel == "Enrage" then
			return true
		end
	end
	return false
end

-- True when `unit` carries an enrage the player can Soothe, false when it does not, nil when the client will not say.
local function ReadEnrage(unit)
	local ids, n = AuraIDs(unit, SOOTHE_FILTER)
	if not ids then
		return ScanByIndex(unit)
	end
	for i = 1, n do
		if not IsOtherDispelType(unit, ids[i]) then
			return true
		end
	end
	return false
end

-- Refreshes what is known about one nameplate unit. Returns true when it has just become enraged.
local function ScanUnit(unit, now)
	if not UnitExists(unit) then
		mobs[unit] = nil
		return false
	end
	local attackable, dead = UnitCanAttack("player", unit), UnitIsDead(unit)
	if (not IsSecret(attackable) and not attackable) or (not IsSecret(dead) and dead) then
		mobs[unit] = nil
		return false
	end
	local enraged = ReadEnrage(unit)
	if enraged == nil then
		return false -- the client will not say: keep what we knew
	end
	if not enraged then
		mobs[unit] = nil
		return false
	end
	if mobs[unit] then
		return false
	end
	mobs[unit] = { since = now }
	return true
end

-- Display ---------------------------------------------------------------------

-- Sets a raid-target icon texture; hides it when the unit has none or the client hides which one.
local function SetMark(tex, index)
	if IsSecret(index) then
		tex:SetTexture(MARK_TEXTURE)
		tex:SetTexCoord(0, 1, 0, 1)
		if pcall(SetRaidTargetIconTexture, tex, index) then
			tex:Show()
		else
			tex:Hide()
		end
		return
	end
	if type(index) ~= "number" or index < 1 or index > 8 then
		tex:Hide()
		return
	end
	local col, line = (index - 1) % 4, math.floor((index - 1) / 4)
	tex:SetTexture(MARK_TEXTURE)
	tex:SetTexCoord(col * 0.25, (col + 1) * 0.25, line * 0.25, (line + 1) * 0.25)
	tex:Show()
end

-- Health as a percentage; the value may be hidden, in which case it is only passed to the widget.
local function SetHealthPercent(fs, unit)
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		if pcall(function()
			fs:SetFormattedText("%d%%", UnitHealthPercent(unit, false, CurveConstants.ScaleTo100))
		end) then
			return
		end
	end
	local ok = pcall(function()
		local cur, max = UnitHealth(unit), UnitHealthMax(unit)
		if IsSecret(cur) or IsSecret(max) or not max or max == 0 then
			error("hidden")
		end
		fs:SetFormattedText("%d%%", cur / max * 100)
	end)
	if not ok then
		fs:SetText("")
	end
end

local function FillRow(row, unit, since, now)
	row.unit = unit
	row.soothe:SetTexture(SootheIcon())
	local mark = GetRaidTargetIndex(unit)
	SetMark(row.mark, mark)
	row.soothe:SetShown(not row.mark:IsShown())
	if not pcall(row.name.SetText, row.name, (UnitName(unit))) then
		row.name:SetText("?")
	end
	-- StatusBar setters accept values the client hides, so no arithmetic on them here.
	if not pcall(function()
		row:SetMinMaxValues(0, UnitHealthMax(unit))
		row:SetValue(UnitHealth(unit))
	end) then
		row:SetMinMaxValues(0, 1)
		row:SetValue(1)
	end
	SetHealthPercent(row.pct, unit)
	row.time:SetFormattedText("%ds", math.max(0, now - since))
end

local function FillSample(row, sample)
	row.unit = nil
	row.soothe:SetTexture(SootheIcon())
	SetMark(row.mark, sample.mark)
	row.soothe:SetShown(not row.mark:IsShown())
	row.name:SetText(sample.name)
	row:SetMinMaxValues(0, 100)
	row:SetValue(sample.pct)
	row.pct:SetFormattedText("%d%%", sample.pct)
	row.time:SetFormattedText("%ds", sample.secs)
end

local function SortedMobs()
	local list = {}
	for unit, m in pairs(mobs) do
		list[#list + 1] = { unit = unit, since = m.since }
	end
	table.sort(list, function(a, b)
		if a.since ~= b.since then
			return a.since < b.since -- longest enraged first
		end
		return a.unit < b.unit
	end)
	return list
end

local function GetMarker(unit)
	local m = markers[unit]
	if m then
		return m
	end
	m = CreateFrame("Frame", nil, UIParent)
	m:SetFrameStrata("HIGH")
	m.icon = m:CreateTexture(nil, "ARTWORK")
	m.icon:SetAllPoints()
	m.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	m.glow = m:CreateTexture(nil, "OVERLAY")
	m.glow:SetPoint("CENTER")
	m.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	m.glow:SetBlendMode("ADD")
	m.anim = m.glow:CreateAnimationGroup()
	m.anim:SetLooping("BOUNCE")
	local fade = m.anim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.4)
	fade:SetSmoothing("IN_OUT")
	m:SetScript("OnShow", function(self)
		self.anim:Play()
	end)
	m:SetScript("OnHide", function(self)
		self.anim:Stop()
	end)
	m:Hide()
	markers[unit] = m
	return m
end

-- Anchors the marker over the unit's nameplate. A nameplate the client will not let us anchor to simply gets no marker.
local function PlaceMarker(m, unit)
	local size = ns.db.enrageMarkerSize
	m:SetSize(size, size)
	m.glow:SetSize(size * 1.8, size * 1.8)
	m.icon:SetTexture(SootheIcon())
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate then
		m:Hide()
		m.plate = nil
		return
	end
	if m.plate ~= plate then
		m:ClearAllPoints()
		if not pcall(m.SetPoint, m, "BOTTOM", plate, "TOP", 0, 10) then
			m:Hide()
			m.plate = nil
			return
		end
		m.plate = plate
	end
	m:Show()
end

local function Render()
	if not frame then
		return
	end
	local db = ns.db
	local active = db.enrageEnabled and ns.IsDruid()
	local list = active and knowsSoothe and SortedMobs() or {}
	local preview = active and ns.IsPreview()
	local sampled = preview and #list == 0
	local total = sampled and #SAMPLES or #list

	frame:SetShown(active and (preview or total > 0))
	if frame:IsShown() then
		local now = GetTime()
		local shown = math.min(total, db.enrageRows)
		for i, row in ipairs(rows) do
			if i <= shown then
				if sampled then
					FillSample(row, SAMPLES[i])
				else
					FillRow(row, list[i].unit, mobs[list[i].unit].since, now)
				end
				row:Show()
			else
				row:Hide()
			end
		end
		frame.body:SetHeight(HEADER_H + shown * ROW_H + 2)
		headerCount:SetText(total > 0 and tostring(total) or "")
	end

	-- A marker over every enraged mob, even the ones that no longer fit in the list.
	local wantMarkers = active and knowsSoothe and db.enrageMarker
	for unit, m in pairs(markers) do
		if not (wantMarkers and mobs[unit]) then
			m:Hide()
			m.plate = nil
		end
	end
	if wantMarkers then
		for unit in pairs(mobs) do
			PlaceMarker(GetMarker(unit), unit)
		end
	end
end

local function Announce()
	local spoke, err = ns.Speak(SAY)
	if not spoke and not voiceErrorShown then
		voiceErrorShown = true
		ns.Print(("could not say \"%s\": %s"):format(SAY, tostring(err)))
	end
end

-- Speaks when a mob has just enraged; several at once count as one callout.
local function Alert(now)
	if ns.db.enrageSay and not ns.IsPreview() and now - lastAlert > ALERT_DEBOUNCE then
		lastAlert = now
		Announce()
	end
end

local function CanScan()
	return frame ~= nil and ns.db.enrageEnabled and ns.IsDruid() and knowsSoothe
end

-- Scans every nameplate, speaks when a mob has just enraged, then redraws.
local function Update()
	if not frame then
		return
	end
	if not CanScan() then
		wipe(mobs)
		Render()
		return
	end
	local now = GetTime()
	local fresh = false
	for i = 1, MAX_PLATES do
		if ScanUnit(plateTokens[i], now) then
			fresh = true
		end
	end
	if fresh then
		Alert(now)
	end
	Render()
end

-- Re-styles the panel (settings changed) and refreshes it.
function ns.ApplyEnrage()
	if not frame then
		return
	end
	local db = ns.db
	frame:SetSize(db.enrageWidth, HEADER_H + db.enrageRows * ROW_H + 2)
	ns.PlaceFrame(frame, "enrageX", "enrageY")
	frame:EnableMouse(ns.unlocked)
	frame.unlockBg:SetShown(ns.unlocked)
	frame.icon:SetTexture(SootheIcon())
	Update()
end

-- /druidm enragedebug: shows what the client lets the addon read on each nameplate, to diagnose a missing mob.
local function Shown(v)
	return IsSecret(v) and "hidden" or tostring(v)
end

local function Report(unit, filter)
	local ids, n = AuraIDs(unit, filter)
	return ids and tostring(n) or ("ERR " .. tostring(n))
end

local function DebugUnit(unit)
	local attackable, dead = UnitCanAttack("player", unit), UnitIsDead(unit)
	print(("  %s: hostile=%s dead=%s | Soothe filter=%s (without nameplate-only buffs: %s) | all buffs=%s | any dispellable=%s | in panel=%s")
		:format(unit, Shown(attackable), Shown(dead), Report(unit, SOOTHE_FILTER),
			Report(unit, "HELPFUL|RAID_PLAYER_DISPELLABLE"), Report(unit, "HELPFUL|INCLUDE_NAME_PLATE_ONLY"),
			Report(unit, "HELPFUL|DISPELLABLE|INCLUDE_NAME_PLATE_ONLY"), tostring(mobs[unit] ~= nil)))
	-- Where the client lets us read the buffs, name the dispel type of what the filter matched.
	local ids, n = AuraIDs(unit, SOOTHE_FILTER)
	for i = 1, ids and n or 0 do
		local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, ids[i])
		local dispel = ok and type(data) == "table" and data.dispelName
		print(("      matched buff %d: dispel type %s"):format(i, (dispel == nil or dispel == false) and "(none)" or Shown(dispel)))
	end
end

function ns.EnrageDebug()
	ns.Print("enrage debug (run in combat, or on a target dummy, with the enemy nameplates visible)")
	if not ns.IsDruid() then
		print("  the enrage panel is Druid-only")
		return
	end
	print(("  enabled=%s soothe known=%s auras restricted=%s frame=%s shown=%s"):format(tostring(ns.db.enrageEnabled),
		tostring(knowsSoothe), tostring(AurasRestricted()), tostring(frame ~= nil), tostring(frame and frame:IsShown())))
	local any = false
	for i = 1, MAX_PLATES do
		if UnitExists(plateTokens[i]) then
			any = true
			DebugUnit(plateTokens[i])
		end
	end
	if UnitExists("target") then
		DebugUnit("target")
	elseif not any then
		print("  no enemy nameplates found - turn them on (default key: V) and stand near the mobs")
	end
end

function ns.InitEnrage()
	frame = CreateFrame("Frame", "DruidMonroEnrage", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "enrageX", "enrageY")

	frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND")
	frame.unlockBg:SetAllPoints()
	frame.unlockBg:SetColorTexture(0.1, 0.8, 0.3, 0.35)

	-- Dark backing that grows with the number of rows shown; the frame itself keeps a fixed size so it does not jump.
	frame.body = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	frame.body:SetPoint("TOPLEFT")
	frame.body:SetPoint("TOPRIGHT")
	frame.body:SetColorTexture(0, 0, 0, 0.6)

	local headerBg = frame:CreateTexture(nil, "BORDER")
	headerBg:SetPoint("TOPLEFT")
	headerBg:SetPoint("TOPRIGHT")
	headerBg:SetHeight(HEADER_H)
	headerBg:SetColorTexture(0.55, 0.08, 0.08, 0.9)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(HEADER_H - 4, HEADER_H - 4)
	frame.icon:SetPoint("TOPLEFT", 4, -2)
	frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local title = frame:CreateFontString(nil, "OVERLAY")
	title:SetFont(ns.DEFAULT_FONT, 13, "OUTLINE")
	title:SetPoint("LEFT", frame.icon, "RIGHT", 6, 0)
	title:SetText("ENRAGE - SOOTHE")

	headerCount = frame:CreateFontString(nil, "OVERLAY")
	headerCount:SetFont(ns.DEFAULT_FONT, 13, "OUTLINE")
	headerCount:SetPoint("TOPRIGHT", -6, -4)

	for i = 1, MAX_ROWS do
		-- A row is a status bar, so the mob's health fills the row behind its text.
		local row = CreateFrame("StatusBar", nil, frame)
		row:SetPoint("TOPLEFT", 2, -(HEADER_H + (i - 1) * ROW_H))
		row:SetPoint("TOPRIGHT", -2, -(HEADER_H + (i - 1) * ROW_H))
		row:SetHeight(ROW_H - 2)
		row:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		row:SetStatusBarColor(0.75, 0.15, 0.15, 0.6)
		row:SetMinMaxValues(0, 1)
		row:SetValue(1)

		row.back = row:CreateTexture(nil, "BACKGROUND")
		row.back:SetAllPoints()
		row.back:SetColorTexture(0.12, 0.12, 0.12, 0.7)

		-- The raid marker tells identical mobs apart; the Soothe icon stands in for a mob without one.
		row.mark = row:CreateTexture(nil, "OVERLAY")
		row.mark:SetSize(16, 16)
		row.mark:SetPoint("LEFT", 4, 0)
		row.soothe = row:CreateTexture(nil, "OVERLAY")
		row.soothe:SetSize(16, 16)
		row.soothe:SetPoint("LEFT", 4, 0)
		row.soothe:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		row.time = row:CreateFontString(nil, "OVERLAY")
		row.time:SetFont(ns.DEFAULT_FONT, 12, "OUTLINE")
		row.time:SetPoint("RIGHT", -4, 0)
		row.time:SetWidth(30)
		row.time:SetJustifyH("RIGHT")
		row.pct = row:CreateFontString(nil, "OVERLAY")
		row.pct:SetFont(ns.DEFAULT_FONT, 12, "OUTLINE")
		row.pct:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
		row.pct:SetWidth(36)
		row.pct:SetJustifyH("RIGHT")
		row.name = row:CreateFontString(nil, "OVERLAY")
		row.name:SetFont(ns.DEFAULT_FONT, 12, "OUTLINE")
		row.name:SetPoint("LEFT", 24, 0)
		row.name:SetPoint("RIGHT", row.pct, "LEFT", -4, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)

		row:Hide()
		rows[i] = row
	end

	knowsSoothe = ReadKnowsSoothe()

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	events:RegisterEvent("UNIT_AURA")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("TRAIT_CONFIG_UPDATED")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_AURA" then
			-- Fires many times a second in a big pull: only that mob is rescanned here and the ticker redraws.
			if type(unit) == "string" and unit:sub(1, 9) == "nameplate" and CanScan() then
				local now = GetTime()
				if ScanUnit(unit, now) then
					Alert(now)
				end
			end
			return
		elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
			-- The token now belongs to a different mob (or none), so whatever was known about it is stale.
			mobs[unit] = nil
		elseif event == "PLAYER_ENTERING_WORLD" then
			wipe(mobs)
			knowsSoothe = ReadKnowsSoothe()
		else
			knowsSoothe = ReadKnowsSoothe()
		end
		Update()
	end)
	-- Safety net: aura changes on enemies are not always announced while the client restricts data.
	C_Timer.NewTicker(0.25, Update)
end
