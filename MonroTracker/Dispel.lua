local ADDON_NAME, ns = ...

-- Dispel callouts: says "Dispel poison" (or "Dispel curse") when someone in your group carries one and your dispel is
-- ready. Guardian's Remove Corruption (Restoration's Nature's Cure) removes poison and curse.
--
-- How a poisoned member is recognised. Each debuff reports its dispel type, and the engine's "RAID" debuff filter keeps
-- only the debuffs you can remove (DandersFrames uses exactly this for its "dispellable by you" borders; the
-- "RAID_PLAYER_DISPELLABLE" token is not relied on). Two situations follow:
--   * Readable (out of combat, open world, any time the client does not restrict auras): the debuff's dispel type is read
--     straight from its aura data (or through a colour curve) and the addon knows exactly what is on whom.
--   * Hidden (combat inside a dungeon or Mythic+, where the type is a secret value): Lua cannot look at the debuff, but the
--     engine can filter it. A tiny, invisible aura container per member and type (filter above, candidate filter
--     includeDispelTypes) holds an icon exactly while a matching debuff is there, and the container's width is readable.
--     This is the same width witness the enrage marker uses; whether the width stays readable in combat is what
--     /mtr dispeldebug shows.

local LIST_FILTER = "HARMFUL" -- every debuff; the type is checked on each, so a filter that matches nothing cannot silence the callout
local WITNESS_FILTER = "HARMFUL|RAID" -- the debuffs you can dispel, as DandersFrames asks for them
local DISPEL_SPELLS = { 88423, 2782 } -- Nature's Cure (Restoration), Remove Corruption
local DEFAULT_SPELL = 2782
local DEFAULT_COOLDOWN = 8
local GCD_THRESHOLD = 1.5 -- cooldowns up to this long are the global cooldown
local REPEAT_SECONDS = 6 -- how often the callout repeats while the debuff stays and the dispel is ready
local TICK = 0.5
local EVENT_THROTTLE = 0.1
local MAX_AURAS = 20 -- looked at per unit; more than anyone carries
local MAX_RAID = 40
local WITNESS_BUILDS_PER_TICK = 2
local WITNESS_RETRY = 5 -- seconds before a refused container is tried again
local WITNESS_GROUP = "dispel"
local WITNESS_ELEMENT = 8
local WITNESS_MIN_WIDTH = 4 -- an empty container is 1x1; with an icon in it, it is as wide as the icon
local NO_UNIT = "none"

-- In priority order: when both are present, poison is announced first, then curse on the next repeat.
-- `index` is the engine's dispel-type enum value (1 Magic, 2 Curse, 3 Disease, 4 Poison).
local TYPES = {
	{ key = "Poison", index = 4, setting = "dispelPoison", say = "Dispel poison" },
	{ key = "Curse", index = 2, setting = "dispelCurse", say = "Dispel curse" },
}

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local spellID -- the dispel spell the player knows, nil when none
local cooldownUntil = 0 -- GetTime() until which our own timer says the dispel is on cooldown
local active = {} -- type key -> true while a group member carries it (last scan)
local lastSay = 0 -- GetTime() of the last callout; one gate for both types so they alternate instead of overlapping
local lastScan = 0
local voiceErrorShown = false
local scanReport = {} -- per unit, for /mtr dispeldebug

-- Spell -------------------------------------------------------------------------

local function AskSpellBook(id)
	local book = C_SpellBook
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	if book and book.IsSpellKnownOrInSpellBook then
		local ok, known = pcall(book.IsSpellKnownOrInSpellBook, id, bank)
		if ok then
			return known == true
		end
	end
	if IsPlayerSpell then
		return IsPlayerSpell(id) and true or false
	end
end

local function FindSpell()
	local unanswered = false
	for _, id in ipairs(DISPEL_SPELLS) do
		local known = AskSpellBook(id)
		if known then
			return id
		elseif known == nil then
			unanswered = true
		end
	end
	-- A client that answers neither way is assumed to have it: hiding the feature on a failed query would look like a bug.
	return unanswered and DEFAULT_SPELL or nil
end

function ns.KnowsDispel()
	return spellID ~= nil
end

local function BaseCooldown(id)
	local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(id)
	return (ms and not IsSecret(ms) and ms > 0) and ms / 1000 or DEFAULT_COOLDOWN
end

-- Whether the dispel can be cast now. Spell cooldowns are hidden in combat, so a cast of ours starts a timer (see OnCast)
-- and a readable cooldown is only used when there is one to read.
local function DispelReady()
	if not spellID then
		return false
	end
	if GetTime() < cooldownUntil then
		return false
	end
	local ok, cd = pcall(C_Spell.GetSpellCooldown, spellID)
	if ok and type(cd) == "table" then
		local start, duration, onGCD = cd.startTime, cd.duration, cd.isOnGCD
		if not (IsSecret(start) or IsSecret(duration) or IsSecret(onGCD)) then
			if onGCD then
				return true
			end
			if start and start > 0 and duration and duration > GCD_THRESHOLD then
				return GetTime() >= start + duration
			end
		end
	end
	return true
end

-- Group ---------------------------------------------------------------------------

local function Flag(fn, ...)
	local ok, v = pcall(fn, ...)
	if not ok or IsSecret(v) then
		return nil
	end
	return v and true or false
end

-- The units to look at: yourself (optionally) and the others in the group. In a raid the tokens already include you.
local function GroupUnits()
	local list = {}
	if IsInRaid() then
		for i = 1, math.min(GetNumGroupMembers(), MAX_RAID) do
			list[#list + 1] = "raid" .. i
		end
	else
		if ns.db.dispelSelf then
			list[1] = "player"
		end
		for i = 1, 4 do
			list[#list + 1] = "party" .. i
		end
	end
	return list
end

-- A unit worth announcing for: there, alive, friendly and in range. A hidden answer counts as yes, so a client that hides
-- these only costs an occasional callout for someone out of range.
local function Usable(unit)
	if Flag(UnitExists, unit) == false or Flag(UnitIsConnected, unit) == false then
		return false
	end
	if Flag(UnitIsDeadOrGhost, unit) == true or Flag(UnitCanAssist, "player", unit) == false then
		return false
	end
	if Flag(UnitInRange, unit) == false then
		return false
	end
	if not ns.db.dispelSelf and Flag(UnitIsUnit, unit, "player") == true then
		return false
	end
	return true
end

-- Detection -------------------------------------------------------------------------

-- Opaque for one dispel type, transparent for every other (and for none), like the enrage panel's curve.
local curves = {}

local function TypeCurve(t)
	if curves[t.key] ~= nil then
		return curves[t.key] or nil
	end
	curves[t.key] = false
	if C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType and CreateColor then
		local ok, curve = pcall(function()
			local c = C_CurveUtil.CreateColorCurve()
			c:SetType(Enum.LuaCurveType.Step)
			c:AddPoint(0, CreateColor(0, 0, 0, 0))
			c:AddPoint(t.index, CreateColor(1, 1, 1, 1))
			c:AddPoint(t.index + 1, CreateColor(0, 0, 0, 0))
			return c
		end)
		if ok and curve then
			curves[t.key] = curve
		end
	end
	return curves[t.key] or nil
end

-- Reads one debuff's dispel type. Returns true when the client let us read it (`found[type] = true` is set for a wanted type).
local function ReadAura(unit, id, wanted, found)
	local okData, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
	if okData and type(data) == "table" and not IsSecret(data) then
		local name = data.dispelName
		if not IsSecret(name) then
			if name and wanted[name] then
				found[name] = true
			end
			return true
		end
	end
	-- The type itself is hidden; the colour curve may still be readable.
	local readable = false
	for _, t in ipairs(TYPES) do
		local curve = wanted[t.key] and TypeCurve(t)
		if curve then
			local okColor, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, id, curve)
			if okColor and color then
				local a = color.a
				if not IsSecret(a) then
					readable = true
					if (a or 0) > 0.5 then
						found[t.key] = true
					end
				end
			end
		end
	end
	return readable
end

-- The engine witness: one invisible container per unit and type that shows an icon while a matching debuff is there.
local witnesses = {}
local witnessFailedAt = -math.huge
local witnessBuilds = 0
local witnessError

local function WitnessInit(button)
	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetAllPoints(button)
	icon:SetColorTexture(1, 1, 1, 1)
	button:SetIcon(icon)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
end

local function GetWitness(unit, t)
	local key = unit .. ":" .. t.key
	local c = witnesses[key]
	if c then
		return c
	end
	if GetTime() - witnessFailedAt < WITNESS_RETRY or witnessBuilds >= WITNESS_BUILDS_PER_TICK then
		return nil
	end
	witnessBuilds = witnessBuilds + 1
	local ok, container = pcall(function()
		if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
			C_AddOns.LoadAddOn("Blizzard_AuraContainer")
		end
		local f = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
		f:Hide() -- a container parses the moment it is visible, so only once its group is declared
		f:SetAlpha(0)
		f:SetSize(1, 1)
		f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
		f:SetUnit(unit)
		f:AddAuraGroup(WITNESS_GROUP, WITNESS_FILTER, {
			maxFrameCount = 1,
			candidateFilters = { includeDispelTypes = { [t.key] = true } },
			sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly,
			sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal,
			initializeFrame = WitnessInit,
			layout = {
				elementWidth = WITNESS_ELEMENT,
				elementHeight = WITNESS_ELEMENT,
				elementSpacing = 0,
				lineSpacing = 0,
				elementSpacingX = 0,
				elementSpacingY = 0,
			},
		})
		f:Show()
		return f
	end)
	if ok then
		witnessError = nil
		witnesses[key] = container
		return container
	end
	witnessError = tostring(container)
	witnessFailedAt = GetTime()
end

local function WitnessWidth(unit, t)
	local c = GetWitness(unit, t)
	if not c then
		return nil
	end
	local ok, width = pcall(c.GetWidth, c)
	if ok and type(width) == "number" and not IsSecret(width) then
		return width
	end
end

-- A member's roster slot can change hands while the token stays; the container only sees the token string.
local function RefreshWitnesses()
	for key, c in pairs(witnesses) do
		local unit = key:match("^(.-):")
		pcall(function()
			c:SetUnit(NO_UNIT)
			c:SetUnit(unit)
		end)
	end
end

-- Which wanted types `unit` carries. Returns the found set and whether the client hid anything (so the witness was used).
local function ScanUnit(unit, wanted)
	local found, report = {}, { witness = {} }
	scanReport[unit] = report
	local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, LIST_FILTER)
	local n
	if ok and type(ids) == "table" then
		local okN, count = pcall(function()
			return #ids
		end)
		if okN and type(count) == "number" and not IsSecret(count) then
			n = count
		end
	end
	report.count = n
	local unresolved = n == nil
	for i = 1, math.min(n or 0, MAX_AURAS) do
		local id = ids[i]
		if IsSecret(id) or not ReadAura(unit, id, wanted, found) then
			unresolved = true
		end
	end
	report.hidden = unresolved
	if unresolved then
		for _, t in ipairs(TYPES) do
			if wanted[t.key] and not found[t.key] then
				local width = WitnessWidth(unit, t)
				report.witness[t.key] = width or "unreadable"
				if width and width > WITNESS_MIN_WIDTH then
					found[t.key] = true
				end
			end
		end
	end
	return found
end

-- Callout -------------------------------------------------------------------------

local function Wanted()
	local wanted, any = {}, false
	for _, t in ipairs(TYPES) do
		if ns.db[t.setting] then
			wanted[t.key] = true
			any = true
		end
	end
	return wanted, any
end

local function Say(text)
	local spoke, err = ns.Speak(text)
	if not spoke and not voiceErrorShown then
		voiceErrorShown = true
		ns.Print(("could not say \"%s\": %s"):format(text, tostring(err)))
	end
end

local function Enabled()
	local db = ns.db
	return db and db.dispelEnabled and spellID ~= nil and (not db.dispelCombatOnly or UnitAffectingCombat("player"))
end

local function Update()
	lastScan = GetTime()
	witnessBuilds = 0
	wipe(scanReport)
	local wanted, any = Wanted()
	if not (ns.db and ns.db.dispelEnabled and spellID and any) then
		wipe(active)
		return
	end
	local nowActive = {}
	for _, unit in ipairs(GroupUnits()) do
		if Usable(unit) then
			for key in pairs(ScanUnit(unit, wanted)) do
				nowActive[key] = true
			end
		end
	end
	if not next(nowActive) then
		lastSay = 0 -- the next appearance is announced at once
	elseif Enabled() and DispelReady() and GetTime() - lastSay >= REPEAT_SECONDS then
		for _, t in ipairs(TYPES) do
			if nowActive[t.key] then
				lastSay = GetTime()
				Say(t.say)
				break
			end
		end
	end
	active = nowActive
end

local function OnCast(id)
	if not id or IsSecret(id) then
		return
	end
	for _, known in ipairs(DISPEL_SPELLS) do
		if id == known then
			cooldownUntil = GetTime() + BaseCooldown(id)
			return
		end
	end
end

-- /mtr dispeldebug: what the client lets the addon read on each group member right now.
function ns.DispelDebug()
	ns.Print("dispel debug")
	local db = ns.db
	print(("  spell %s, ready=%s (own timer %.1fs left), enabled=%s, poison=%s, curse=%s, self=%s, combat only=%s"):format(
		tostring(spellID), tostring(DispelReady()), math.max(0, cooldownUntil - GetTime()), tostring(db.dispelEnabled),
		tostring(db.dispelPoison), tostring(db.dispelCurse), tostring(db.dispelSelf), tostring(db.dispelCombatOnly)))
	print("  list filter " .. LIST_FILTER .. ", container filter " .. WITNESS_FILTER)
	print(("  auras restricted: %s; container error: %s"):format(
		tostring(C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() or false),
		tostring(witnessError)))
	Update()
	for _, unit in ipairs(GroupUnits()) do
		local r = scanReport[unit]
		if r then
			local parts = {}
			for key, width in pairs(r.witness) do
				parts[#parts + 1] = ("%s container width %s"):format(key, tostring(width))
			end
			print(("  %s: debuffs %s, type %s%s"):format(unit, tostring(r.count),
				r.hidden and "hidden" or "readable", #parts > 0 and (", " .. table.concat(parts, ", ")) or ""))
		else
			print(("  %s: skipped (missing, dead, out of range or yourself)"):format(unit))
		end
	end
	local list = {}
	for key in pairs(active) do
		list[#list + 1] = key
	end
	print("  announcing: " .. (#list > 0 and table.concat(list, ", ") or "nothing"))
end

function ns.ApplyDispel()
	if not ns.db or not ns.IsDruid() then
		return
	end
	spellID = FindSpell()
	if not (ns.db.dispelEnabled and spellID) then
		wipe(active)
	end
end

function ns.InitDispel()
	if not ns.IsDruid() then
		return
	end
	ns.ApplyDispel()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:RegisterEvent("GROUP_ROSTER_UPDATE")
	events:RegisterEvent("UNIT_AURA")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	events:SetScript("OnEvent", function(_, event, unit, _, castID)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			OnCast(castID)
			return
		end
		if event == "UNIT_AURA" then
			if type(unit) ~= "string" or not (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) then
				return
			end
			if GetTime() - lastScan < EVENT_THROTTLE then
				return
			end
		elseif event == "GROUP_ROSTER_UPDATE" then
			RefreshWitnesses()
		else
			ns.ApplyDispel()
		end
		Update()
	end)
	-- Repeats the callout and notices the dispel coming off cooldown; neither is announced by an event.
	C_Timer.NewTicker(TICK, Update)
end
