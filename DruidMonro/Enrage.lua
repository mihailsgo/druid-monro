local ADDON_NAME, ns = ...

-- Enrage panel: shows which enemies carry an enrage you can Soothe, so you know which mob to cast it on.
--
-- How an enrage is recognised. The engine can tell us each buff's dispel type, but only as a colour: the buff list on a
-- nameplate gives the aura instance IDs, and C_UnitAuras.GetAuraDispelTypeColor(unit, id, curve) maps the buff's dispel
-- type through a colour curve (the same technique the Plater "Purge & Soothe" mod uses). Our curve is opaque white for
-- the Enrage type and fully transparent for everything else. Two situations follow:
--   * Readable (out of combat, open world, any time the client does not restrict auras): the colour's alpha can be read,
--     so the addon knows exactly which mobs are enraged. It lists them in the panel and says "Soothe".
--   * Hidden (combat inside a dungeon or Mythic+, where the alpha is a secret value): the addon cannot know, only draw.
--     The colour goes straight into a texture's vertex colour, so the marker over a mob's nameplate shows up for an
--     enraged mob and stays invisible for the rest. The panel list and the callout need the value, so they stay off.
-- Mobs are found through their nameplates, so enemy nameplates have to be on.

local SOOTHE = 2908
-- Only used by /druidm enragedebug, to show what the engine's own dispel filters say about each mob.
local SOOTHE_FILTER = "HELPFUL|RAID_PLAYER_DISPELLABLE|INCLUDE_NAME_PLATE_ONLY"
local SOOTHE_FALLBACK_ICON = "Interface\\Icons\\Ability_Hunter_BeastSoothe"
local MARK_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local SAY = "Soothe"
local MAX_ROWS = 6
local ROW_H = 24
local HEADER_H = 22
local MAX_PLATES = 40
local ALERT_DEBOUNCE = 1.5 -- several mobs enraging together are one callout

-- INCLUDE_NAME_PLATE_ONLY adds the buffs the client flags to show on nameplates only, which many mob abilities are.
local BUFF_FILTER = "HELPFUL|INCLUDE_NAME_PLATE_ONLY"
local MAX_BUFFS = 20 -- looked at per nameplate; more than any mob carries
local ENRAGE_DISPEL_TYPE = Enum and Enum.SpellDispelType and Enum.SpellDispelType.Enrage or 9

-- Where the Soothe marker sits relative to the nameplate: { marker point, plate point, x, y }. Raid markers are drawn on
-- the nameplate too, usually above or at the left, so the marker defaults to the side clear of them.
ns.MARKER_SIDES = {
	{ key = "right", name = "Right of the nameplate" },
	{ key = "left", name = "Left of the nameplate" },
	{ key = "above", name = "Above the nameplate" },
	{ key = "below", name = "Below the nameplate" },
}
local MARKER_ANCHORS = {
	right = { "LEFT", "RIGHT", 6, 0 },
	left = { "RIGHT", "LEFT", -6, 0 },
	above = { "BOTTOM", "TOP", 0, 10 },
	below = { "TOP", "BOTTOM", 0, -10 },
}

-- What the panel shows while positioning or styling it.
local SAMPLES = {
	{ name = "Enraged Brute", mark = 8, pct = 62, secs = 7 },
	{ name = "Furious Whelp", mark = 7, pct = 35, secs = 3 },
}

local frame, headerCount
local rows = {}
local mobs = {} -- unit token -> { since = GetTime() } while that unit carries an enrage
local plateTokens = {}
for i = 1, MAX_PLATES do
	plateTokens[i] = "nameplate" .. i
end
-- The Season 2 enrage spells (docs/midnight-s2-enrages.md). Neither their names nor their IDs can be read off an enemy buff in
-- combat, but two things can ask about them by ID: GetUnitAuraBySpellID, which answers "is it there" for a spell the client
-- classes as readable, and the aura list in a UNIT_AURA payload when it is not hidden.
local ENRAGE_SPELLS = {
	1306308, -- Ravenous (Altar of Fangs)
	1214922, 1216970, 1213658, -- Fel Rage, Back to Work!, Unsatisfied Customer (Murder Row)
	1238053, 1246865, -- Mother's Wrath, Bestial Wrath (Den of Nalorakk)
	1249661, 1310319, 1254826, -- Feral Rage, Bolster, Bloodsurge (Voidscar Arena)
	269976, 1297763, -- Ancestral Fury, Bestial Berserk (Kings' Rest)
}
local ENRAGE_SPELL_SET = {}
for _, id in ipairs(ENRAGE_SPELLS) do
	ENRAGE_SPELL_SET[id] = true
end
local EVENT_WITNESS_SECONDS = 60 -- an enrage seen in a UNIT_AURA payload counts at most this long if its removal is missed

local spellSeen = {} -- unit token -> { [auraInstanceID] = GetTime() } for enrage spells seen added on that unit
local knowsSoothe = true
local lastScan = {} -- unit token -> GetTime() of its last event-driven scan
local SCAN_THROTTLE = 0.1
local lastAlert = 0
local voiceErrorShown = false

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function SootheIcon()
	return C_Spell.GetSpellTexture(SOOTHE) or SOOTHE_FALLBACK_ICON
end

-- What one spellbook query says about Soothe: true / false, or nil when the query does not exist or errors.
local function AskSpellBook(fn)
	if not fn then
		return nil
	end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	local ok, known = pcall(fn, SOOTHE, bank)
	if ok then
		return known == true
	end
end

-- Either spellbook query saying yes is enough; a client that answers neither way is assumed to know it, since every
-- Druid has Soothe and hiding the whole panel on a failed query would look exactly like a bug.
local function ReadKnowsSoothe()
	local book = C_SpellBook
	local inBook = AskSpellBook(book and book.IsSpellKnownOrInSpellBook)
	local known = AskSpellBook(book and book.IsSpellKnown)
	if inBook or known then
		return true
	end
	if inBook ~= nil or known ~= nil then
		return false
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

-- The buffs on `unit`: their aura instance IDs and how many, nil when the client will not say. Tries the plain ID list
-- first and GetUnitAuras (what Plater reads) second.
local function BuffIDs(unit)
	local ids, n = AuraIDs(unit, BUFF_FILTER)
	if ids then
		return ids, math.min(n, MAX_BUFFS)
	end
	if C_UnitAuras.GetUnitAuras then
		local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, BUFF_FILTER)
		if ok and type(list) == "table" then
			local out = {}
			for i = 1, math.min(#list, MAX_BUFFS) do
				local id = type(list[i]) == "table" and list[i].auraInstanceID
				if id and not IsSecret(id) then
					out[#out + 1] = id
				end
			end
			return out, #out
		end
	end
	return nil, n
end

-- Opaque white for the Enrage dispel type, fully transparent for every other type (and for none).
local enrageCurve

local function EnrageCurve()
	if enrageCurve ~= nil then
		return enrageCurve or nil
	end
	enrageCurve = false
	if C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType and CreateColor then
		local ok, curve = pcall(function()
			local c = C_CurveUtil.CreateColorCurve()
			c:SetType(Enum.LuaCurveType.Step)
			c:AddPoint(0, CreateColor(0, 0, 0, 0))
			c:AddPoint(ENRAGE_DISPEL_TYPE, CreateColor(1, 1, 1, 1))
			c:AddPoint(ENRAGE_DISPEL_TYPE + 1, CreateColor(0, 0, 0, 0))
			return c
		end)
		if ok and curve then
			enrageCurve = curve
		end
	end
	return enrageCurve or nil
end

-- One buff's colour through the curve: the colour, whether its alpha is hidden, whether it is opaque (enrage).
local function BuffColor(unit, auraInstanceID, curve)
	local ok, color, hidden, opaque = pcall(function()
		local c = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
		if not c then
			return nil
		end
		local a = c.a
		if IsSecret(a) then
			return c, true, false
		end
		return c, false, (a or 0) > 0.5
	end)
	if ok and color then
		return color, hidden, opaque
	end
end

-- Looks at every buff on `unit` through the curve. Returns the verdict:
--   "yes"     an enrage is there, and the client lets us read that
--   "no"      readable, none
--   "hidden"  the client hides the values (combat in a dungeon)
--   nil       the buff list cannot be read at all
local function Evaluate(unit)
	local curve = EnrageCurve()
	if not curve then
		return nil
	end
	local ids, n = BuffIDs(unit)
	if not ids then
		return nil
	end
	local anyHidden, found = false, false
	for i = 1, n do
		local color, hidden, opaque = BuffColor(unit, ids[i], curve)
		if color then
			if hidden then
				anyHidden = true
			elseif opaque then
				found = true
			end
		end
	end
	if found then
		return "yes"
	end
	return anyHidden and "hidden" or "no"
end

local ShowMarker, HideMarker, MarkerShowsAura -- the engine marker, defined below
local Record -- the diagnostics recorder, defined with the debug command

-- Asks the client directly whether any Season 2 enrage spell is on the unit. A non-nil answer proves presence even when the
-- aura's fields are hidden, but the client only answers for spells it classes as readable, so this may never fire in combat.
-- Returns the spell ID that was found.
local function EnrageBySpell(unit)
	if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then
		return nil
	end
	for _, id in ipairs(ENRAGE_SPELLS) do
		local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
		if ok and aura then
			return id
		end
	end
end

-- Whether a UNIT_AURA payload has told us an enrage spell is on the unit (and not yet gone).
local function EnrageByEvent(unit, now)
	local seen = spellSeen[unit]
	if not seen then
		return false
	end
	for iid, at in pairs(seen) do
		if now - at > EVENT_WITNESS_SECONDS then
			seen[iid] = nil
		end
	end
	if next(seen) == nil then
		spellSeen[unit] = nil
		return false
	end
	return true
end

-- Reads one UNIT_AURA payload for enrage spells being added or removed. Everything is checked for being hidden first.
local function ReadAuraUpdate(unit, info, now)
	if type(info) ~= "table" or IsSecret(info) then
		return
	end
	local full = info.isFullUpdate
	if not IsSecret(full) and full then
		spellSeen[unit] = nil
	end
	local added = info.addedAuras
	if type(added) == "table" and not IsSecret(added) then
		for i = 1, #added do
			local a = added[i]
			if type(a) == "table" and not IsSecret(a) then
				local spellID, iid = a.spellId, a.auraInstanceID
				if not IsSecret(spellID) and not IsSecret(iid) and ENRAGE_SPELL_SET[spellID] then
					spellSeen[unit] = spellSeen[unit] or {}
					spellSeen[unit][iid] = now
				end
			end
		end
	end
	local removed = info.removedAuraInstanceIDs
	if spellSeen[unit] and type(removed) == "table" and not IsSecret(removed) then
		for i = 1, #removed do
			local iid = removed[i]
			if not IsSecret(iid) then
				spellSeen[unit][iid] = nil
			end
		end
		if next(spellSeen[unit]) == nil then
			spellSeen[unit] = nil
		end
	end
end

-- Refreshes what is known about one nameplate unit and keeps its marker up. Returns true when it has just become enraged
-- (only known while the addon can tell, which is when the client lets it read the buffs or the marker holds an icon).
local function ScanUnit(unit, now)
	if not UnitExists(unit) then
		mobs[unit] = nil
		HideMarker(unit)
		return false
	end
	local attackable, dead = UnitCanAttack("player", unit), UnitIsDead(unit)
	if (not IsSecret(attackable) and not attackable) or (not IsSecret(dead) and dead) then
		mobs[unit] = nil
		HideMarker(unit)
		return false
	end
	ShowMarker(unit) -- the engine draws it, whatever we can read
	-- Four ways to know, from the most direct: the buff's dispel type read as a colour, the spell looked up by ID, an enrage
	-- spell seen in a UNIT_AURA payload, and the marker having grown to hold an icon (the engine's own filter matched).
	local via
	if Evaluate(unit) == "yes" then
		via = "colour"
	elseif EnrageBySpell(unit) then
		via = "spell"
	elseif EnrageByEvent(unit, now) then
		via = "event"
	elseif MarkerShowsAura(unit) then
		via = "marker"
	end
	-- No witness clears the mob. That includes "cannot read at all", which in a dungeon is the normal state: keeping the
	-- last answer would leave a mob in the list long after its enrage ended.
	if not via then
		mobs[unit] = nil
		return false
	end
	if mobs[unit] then
		mobs[unit].via = via
		return false
	end
	mobs[unit] = { since = now, via = via }
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

-- Engine marker -----------------------------------------------------------------
-- Everything above needs the client to let us read buffs. Inside a dungeon in combat it does not, but it still lets the
-- *engine* draw them: an aura container bound to a nameplate unit shows the buffs that match a filter string, and the
-- filter is evaluated by the engine, not by us (this is how Plater, EllesmereUI and MiniAuras draw enemy buffs there).
-- So each nameplate gets a container that shows only the dispellable buffs, as the buff's own icon with an orange pulsing
-- border, next to the plate. "mine" is the buffs your group can dispel (enrages, for a Druid with Soothe); "any" is every
-- dispellable buff, Magic ones included.
ns.MARKER_FILTERS = {
	{ key = "mine", name = "Enrages I can Soothe" },
	{ key = "any", name = "Any dispellable buff" },
}
local MARKER_FILTER_STRINGS = {
	mine = "HELPFUL|RAID_PLAYER_DISPELLABLE|INCLUDE_NAME_PLATE_ONLY",
	any = "HELPFUL|DISPELLABLE|INCLUDE_NAME_PLATE_ONLY",
}
local MARKER_GROUP = "enrage"
local MARKER_MAX_ICONS = 2
local MARKER_MIN_WIDTH = 4 -- an empty container is 1x1; with an icon in it, it is as wide as the icon
local NO_UNIT = "none"

local containers = {} -- unit token -> the aura container drawing that nameplate's marker
local markerError -- why the engine marker could not be built, for /druidm enragedebug
local markerFailedAt = -math.huge
local MARKER_RETRY = 5 -- seconds before a refused container is tried again
-- Declaring a group makes the engine build a batch of buttons (several milliseconds), so a pull that shows ten nameplates at
-- once gets its markers over a few ticks instead of in one hitch.
local MARKER_BUILDS_PER_TICK = 3
local markerBuilds = 0

local function MarkerFilter()
	return MARKER_FILTER_STRINGS[ns.db.enrageMarkerFilter] and ns.db.enrageMarkerFilter or "mine"
end

-- A fresh table every time: the engine keeps the reference it is handed.
local function GroupLayout(size)
	return {
		elementWidth = size,
		elementHeight = size,
		elementSpacing = 2,
		lineSpacing = 2,
		elementSpacingX = 2,
		elementSpacingY = 2,
	}
end

-- Runs once for every button the engine creates, and it is the only moment regions can be added to one. The icon is
-- registered first because it is the part that matters; the border is decoration and may fail without costing the icon.
local function InitMarkerButton(button)
	pcall(button.SetFlattensRenderLayers, button, true)
	local icon = button:CreateTexture(nil, "BACKGROUND", nil, 1)
	icon:SetAllPoints(button)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button:SetIcon(icon)
	-- Engine buttons take mouse clicks, and on a nameplate that swallows the clicks that switch target.
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
	pcall(function()
		local ring = CreateFrame("Frame", nil, button)
		ring:SetAllPoints(button)
		ring:EnableMouse(false)
		local function edge(p1, p2, w, h)
			local t = ring:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(1, 0.35, 0.1, 1)
			t:SetPoint(p1)
			t:SetPoint(p2)
			if w then
				t:SetWidth(w)
			end
			if h then
				t:SetHeight(h)
			end
		end
		edge("TOPLEFT", "TOPRIGHT", nil, 3)
		edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 3)
		edge("TOPLEFT", "BOTTOMLEFT", 3, nil)
		edge("TOPRIGHT", "BOTTOMRIGHT", 3, nil)
		local pulse = ring:CreateAnimationGroup()
		pulse:SetLooping("BOUNCE")
		local fade = pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.3)
		fade:SetDuration(0.4)
		fade:SetSmoothing("IN_OUT")
		-- Blizzard plays the group while the button shows an aura (12.1.5); an older client just runs it.
		if not (button.AddAuraShownAnimation and pcall(button.AddAuraShownAnimation, button, pulse)) then
			pulse:Play()
		end
	end)
end

local function CreateContainer(unit)
	if GetTime() - markerFailedAt < MARKER_RETRY or markerBuilds >= MARKER_BUILDS_PER_TICK then
		return nil
	end
	markerBuilds = markerBuilds + 1
	local ok, container = pcall(function()
		if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
			C_AddOns.LoadAddOn("Blizzard_AuraContainer")
		end
		local c = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
		c:SetFrameStrata("HIGH")
		c:Hide() -- a container parses the moment it is visible, so only once its group is declared
		c:SetSize(1, 1)
		c:SetUnit(unit)
		local size, filter = ns.db.enrageMarkerSize, MarkerFilter()
		c:AddAuraGroup(MARKER_GROUP, MARKER_FILTER_STRINGS[filter], {
			maxFrameCount = MARKER_MAX_ICONS,
			sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly,
			sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal,
			initializeFrame = InitMarkerButton,
			layout = GroupLayout(size),
		})
		c.size, c.filterKey = size, filter
		return c
	end)
	if ok then
		markerError = nil
		return container
	end
	markerError = tostring(container)
	markerFailedAt = GetTime()
end

-- Makes sure the unit's nameplate has its marker container, anchored to the plate and shown. What it draws is up to the
-- engine: nothing, until a buff matches the filter.
function ShowMarker(unit)
	if not ns.db.enrageMarker then
		HideMarker(unit)
		return
	end
	local c = containers[unit] or CreateContainer(unit)
	if not c then
		return
	end
	containers[unit] = c
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate then
		c:Hide()
		c.plate = nil
		return
	end
	local size, filter = ns.db.enrageMarkerSize, MarkerFilter()
	if c.size ~= size then
		pcall(c.SetAuraGroupLayout, c, MARKER_GROUP, GroupLayout(size))
		c.size = size
	end
	if c.filterKey ~= filter then
		pcall(c.SetAuraGroupFilterString, c, MARKER_GROUP, MARKER_FILTER_STRINGS[filter])
		c.filterKey = filter
	end
	local side = MARKER_ANCHORS[ns.db.enrageMarkerSide] and ns.db.enrageMarkerSide or "right"
	if c.plate ~= plate or c.side ~= side then
		local a = MARKER_ANCHORS[side]
		c:ClearAllPoints()
		if not pcall(c.SetPoint, c, a[1], plate, a[2], a[3], a[4]) then
			c:Hide()
			c.plate = nil
			return
		end
		c.plate, c.side = plate, side
	end
	if not c:IsShown() then
		c:Show()
	end
end

function HideMarker(unit)
	local c = containers[unit]
	if c then
		c:Hide()
		c.plate = nil
	end
end

-- A nameplate token now belongs to a different mob: the container only sees the token string, which has not changed, so
-- it has to be pointed at nobody and back to notice.
local function RefreshMarker(unit)
	local c = containers[unit]
	if c then
		pcall(function()
			c:SetUnit(NO_UNIT)
			c:SetUnit(unit)
		end)
		c.plate = nil
	end
end

-- Whether the unit's marker is currently holding an icon, judged by its size (an empty container is 1x1). Only trusted for
-- "mine", where an icon means a Soothe-able buff; "any" would also count Magic buffs. Whether the size is readable and
-- kept current in combat is what /druidm enragedebug shows.
function MarkerShowsAura(unit)
	local c = containers[unit]
	if not c or MarkerFilter() ~= "mine" or not c:IsShown() then
		return false
	end
	local ok, width = pcall(c.GetWidth, c)
	return ok and type(width) == "number" and not IsSecret(width) and width > MARKER_MIN_WIDTH
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

	-- The markers are drawn by the scan; when the feature or the markers are off, they all go.
	if not (active and knowsSoothe and db.enrageMarker) then
		for unit in pairs(containers) do
			HideMarker(unit)
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
		wipe(spellSeen)
		Render()
		return
	end
	local now = GetTime()
	local fresh = false
	markerBuilds = 0
	for i = 1, MAX_PLATES do
		if ScanUnit(plateTokens[i], now) then
			fresh = true
		end
	end
	if fresh then
		Alert(now)
	end
	Render()
	if Record then
		pcall(Record, now)
	end
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
	local verdict = Evaluate(unit)
	local ids, n = BuffIDs(unit)
	print(("  %s: hostile=%s dead=%s | buffs=%s | verdict=%s | in panel=%s"):format(unit, Shown(attackable), Shown(dead),
		ids and tostring(n) or ("ERR " .. tostring(n)), tostring(verdict), tostring(mobs[unit] ~= nil)))
	-- The engine marker: its container, and its size, which grows past 1x1 when it holds a buff icon.
	local c = containers[unit]
	if c then
		local okW, w = pcall(c.GetWidth, c)
		local okH, h = pcall(c.GetHeight, c)
		print(("      marker container: shown=%s anchored=%s size=%sx%s filter=%s holds an icon=%s"):format(tostring(c:IsShown()),
			tostring(c.plate ~= nil), okW and Shown(w) or "ERR", okH and Shown(h) or "ERR", tostring(c.filterKey),
			tostring(MarkerShowsAura(unit))))
	else
		print("      marker container: none")
	end
	print(("      engine filters: Soothe filter=%s | any dispellable=%s"):format(Report(unit, SOOTHE_FILTER),
		Report(unit, "HELPFUL|DISPELLABLE|INCLUDE_NAME_PLATE_ONLY")))
	-- Each buff: what its dispel-type colour says (the thing the panel and marker run on) and, where the client lets us
	-- read it, which spell it is. Compare with docs/midnight-s2-enrages.md.
	local curve = EnrageCurve()
	for i = 1, ids and math.min(n, 12) or 0 do
		local color, hidden, opaque = BuffColor(unit, ids[i], curve)
		local colorText = "no colour"
		if color and hidden then
			colorText = "colour hidden"
		elseif color then
			colorText = ("colour alpha %.1f%s"):format(color.a or 0, opaque and " = ENRAGE" or "")
		end
		local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, ids[i])
		data = ok and type(data) == "table" and data or {}
		local spell, dispel = data.spellId, data.dispelName
		local spellText = "spell ?"
		if IsSecret(spell) then
			spellText = "spell hidden"
		elseif spell then
			spellText = ("spell %s %s"):format(tostring(spell), C_Spell.GetSpellName(spell) or "?")
		end
		print(("      buff %d: %s | %s, dispel name %s"):format(i, colorText, spellText,
			(dispel == nil or dispel == false) and "(none)" or Shown(dispel)))
	end
end

function ns.EnrageDebug()
	ns.Print("enrage debug (run in combat, or on a target dummy, with the enemy nameplates visible)")
	if not ns.IsDruid() then
		print("  the enrage panel is Druid-only")
		return
	end
	print(("  enabled=%s soothe known=%s auras restricted=%s colour curve=%s frame=%s shown=%s"):format(
		tostring(ns.db.enrageEnabled), tostring(knowsSoothe), tostring(AurasRestricted()), tostring(EnrageCurve() ~= nil),
		tostring(frame ~= nil), tostring(frame and frame:IsShown())))
	print(("  engine marker: containers=%d error=%s"):format((function()
		local n = 0
		for _ in pairs(containers) do
			n = n + 1
		end
		return n
	end)(), tostring(markerError)))
	local book = C_SpellBook
	print(("  Soothe (%d) in the spellbook: IsSpellKnownOrInSpellBook=%s IsSpellKnown=%s IsPlayerSpell=%s"):format(SOOTHE,
		tostring(AskSpellBook(book and book.IsSpellKnownOrInSpellBook)), tostring(AskSpellBook(book and book.IsSpellKnown)),
		IsPlayerSpell and tostring(IsPlayerSpell(SOOTHE)) or "(no such function)"))
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

-- Diagnostics recording --------------------------------------------------------------
-- Dungeon combat is exactly where the client hides things, so what it actually returns there cannot be worked out from
-- here. While enrageRecord is on, the addon notes it down in its own saved settings (DruidMonroDB.enrageLog), which the game
-- writes out on /reload or logout: every couple of seconds in combat a snapshot of each hostile nameplate (what each query
-- answered, whether it was hidden, what the marker container looks like) and a sample of UNIT_AURA payloads. Nothing hidden
-- is ever stored: every value goes through Safe, because a secret cannot be saved. /druidm enragelog controls it.
local LOG_INTERVAL = 2
local LOG_MAX_SNAPSHOTS = 60
local LOG_MAX_EVENTS = 40
local LOG_EVENT_EVERY = 8 -- one payload in this many is kept
local lastLog = -math.huge
local eventCount = 0

local function Safe(v)
	if IsSecret(v) then
		return "hidden"
	end
	return tostring(v)
end

local function LogTable()
	local db = ns.db
	db.enrageLog = db.enrageLog or { snapshots = {}, events = {} }
	return db.enrageLog
end

local function Push(list, entry, max)
	list[#list + 1] = entry
	if #list > max then
		table.remove(list, 1)
	end
end

-- What the client says about each enrage spell's aura in this very context: ShouldSpellAuraBeSecret (now) and
-- GetSpellAuraSecrecy (the classification; 0 never secret, 1 always, 2 depends on context).
local function SecrecyReport()
	local S = C_Secrets
	if not S then
		return "no C_Secrets"
	end
	local out = {}
	for _, id in ipairs(ENRAGE_SPELLS) do
		local now, class = "n/a", "n/a"
		if S.ShouldSpellAuraBeSecret then
			local ok, r = pcall(S.ShouldSpellAuraBeSecret, id)
			now = ok and Safe(r) or "ERR"
		end
		if S.GetSpellAuraSecrecy then
			local ok, r = pcall(S.GetSpellAuraSecrecy, id)
			class = ok and Safe(r) or "ERR"
		end
		out[#out + 1] = ("%d=%s/%s"):format(id, now, class)
	end
	return table.concat(out, " ")
end

local function ProbeAura(unit, id, i, curve)
	local a = { i = i }
	local color, hidden = BuffColor(unit, id, curve)
	a.colourAlpha = (not color) and "none" or hidden and "hidden" or Safe(color.a)
	local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
	data = ok and type(data) == "table" and data or {}
	a.spell, a.dispel = Safe(data.spellId), Safe(data.dispelName)
	if C_UnitAuras.IsAuraFilteredOutByInstanceID then
		local okF, f = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, id, MARKER_FILTER_STRINGS.mine)
		a.mineFilteredOut = (not okF) and "ERR" or Safe(f)
	end
	return a
end

local function PlateRecord(unit)
	local r = { unit = unit }
	local ids, n = BuffIDs(unit)
	r.buffs = ids and Safe(n) or ("ERR " .. Safe(n))
	r.mineList = Report(unit, SOOTHE_FILTER)
	r.anyList = Report(unit, "HELPFUL|DISPELLABLE|INCLUDE_NAME_PLATE_ONLY")
	r.colourVerdict = Safe(Evaluate(unit))
	r.spellLookup = Safe(EnrageBySpell(unit))
	r.eventWitness = spellSeen[unit] ~= nil
	r.inPanel = mobs[unit] and mobs[unit].via or false
	local c = containers[unit]
	if c then
		local okW, w = pcall(c.GetWidth, c)
		local okH, h = pcall(c.GetHeight, c)
		r.container = ("shown=%s anchored=%s size=%sx%s filter=%s"):format(tostring(c:IsShown()), tostring(c.plate ~= nil),
			okW and Safe(w) or "ERR", okH and Safe(h) or "ERR", tostring(c.filterKey))
	else
		r.container = "none" .. (markerError and (": " .. Safe(markerError):sub(1, 120)) or "")
	end
	r.auras = {}
	local curve = EnrageCurve()
	for i = 1, ids and math.min(n, 6) or 0 do
		r.auras[#r.auras + 1] = ProbeAura(unit, ids[i], i, curve)
	end
	return r
end

function Record(now)
	if not ns.db.enrageRecord or now - lastLog < LOG_INTERVAL or not UnitAffectingCombat("player") then
		return
	end
	local plates = {}
	for i = 1, MAX_PLATES do
		local unit = plateTokens[i]
		if UnitExists(unit) then
			local attackable = UnitCanAttack("player", unit)
			if IsSecret(attackable) or attackable then
				plates[#plates + 1] = PlateRecord(unit)
				if #plates >= 8 then
					break
				end
			end
		end
	end
	if #plates == 0 then
		return
	end
	lastLog = now
	local name, kind, difficulty, _, _, _, _, instanceID = GetInstanceInfo()
	Push(LogTable().snapshots, {
		t = date("%H:%M:%S"),
		zone = ("%s (%s) %s difficulty %s"):format(Safe(name), Safe(instanceID), Safe(kind), Safe(difficulty)),
		aurasRestricted = Safe(AurasRestricted()),
		secrecy = SecrecyReport(),
		plates = plates,
	}, LOG_MAX_SNAPSHOTS)
end

-- One UNIT_AURA payload in LOG_EVENT_EVERY, to see whether the aura lists inside them are hidden in combat.
function ns.SampleAuraEvent(unit, info, now)
	if not ns.db.enrageRecord then
		return
	end
	eventCount = eventCount + 1
	if eventCount % LOG_EVENT_EVERY ~= 1 then
		return
	end
	local e = { t = date("%H:%M:%S"), unit = unit, payload = IsSecret(info) and "hidden" or type(info) }
	if type(info) == "table" and not IsSecret(info) then
		local added = info.addedAuras
		e.full = Safe(info.isFullUpdate)
		e.added = (type(added) == "table" and not IsSecret(added)) and tostring(#added) or Safe(added)
		if type(added) == "table" and not IsSecret(added) and type(added[1]) == "table" then
			e.firstSpell, e.firstInstance = Safe(added[1].spellId), Safe(added[1].auraInstanceID)
		end
		local removed = info.removedAuraInstanceIDs
		e.removed = (type(removed) == "table" and not IsSecret(removed)) and tostring(#removed) or Safe(removed)
	end
	Push(LogTable().events, e, LOG_MAX_EVENTS)
end

-- /druidm enragelog [clear|on|off]
function ns.EnrageLogCommand(arg)
	local db = ns.db
	if arg == "clear" then
		db.enrageLog = nil
		eventCount = 0
		ns.Print("enrage log cleared")
	elseif arg == "on" or arg == "off" then
		db.enrageRecord = arg == "on"
		ns.Print("enrage recording " .. arg)
	else
		local log = db.enrageLog
		ns.Print(("enrage recording is %s: %d snapshots and %d payload samples so far. The game saves them when you /reload or log out."):format(
			db.enrageRecord and "on" or "off", log and #log.snapshots or 0, log and #log.events or 0))
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
	events:SetScript("OnEvent", function(_, event, unit, info)
		if event == "UNIT_AURA" then
			-- Fires many times a second in a big pull: only that mob is rescanned, at most ten times a second, and the
			-- ticker redraws the panel.
			if type(unit) == "string" and unit:sub(1, 9) == "nameplate" and CanScan() then
				local now = GetTime()
				ReadAuraUpdate(unit, info, now) -- every payload, so no add or removal is missed to the throttle
				ns.SampleAuraEvent(unit, info, now)
				if now - (lastScan[unit] or 0) >= SCAN_THROTTLE then
					lastScan[unit] = now
					if ScanUnit(unit, now) then
						Alert(now)
					end
				end
			end
			return
		elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
			-- The token now belongs to a different mob (or none), so whatever was known about it is stale.
			mobs[unit] = nil
			spellSeen[unit] = nil
			RefreshMarker(unit)
		elseif event == "PLAYER_ENTERING_WORLD" then
			wipe(mobs)
			wipe(spellSeen)
			knowsSoothe = ReadKnowsSoothe()
		else
			knowsSoothe = ReadKnowsSoothe()
		end
		Update()
	end)
	-- Safety net: aura changes on enemies are not always announced while the client restricts data.
	C_Timer.NewTicker(0.25, Update)
end
