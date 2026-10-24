local ADDON_NAME, ns = ...

-- The abilities (per class) whose action-bar buttons glow while the ability can be used. Drawing the glow and finding the
-- buttons is TrinketGlow.lua; the cooldown / charge belief is Tracker.lua's.

local function ClassToken()
	return select(2, UnitClass("player"))
end

-- This class's list: { { spellID = n, enabled = bool }, ... }. Kept per class so alts of other classes start empty.
function ns.GlowList()
	local all = ns.db.glowSpells
	local class = ClassToken()
	if not all[class] then
		all[class] = {}
	end
	return all[class]
end

-- Adds an ability by name or ID. Returns spellID, or nil plus a reason.
function ns.AddGlowSpell(input)
	local id = ns.ResolveSpell(input)
	if not id then
		return nil, "notfound"
	end
	local list = ns.GlowList()
	for _, entry in ipairs(list) do
		if entry.spellID == id then
			return id, "duplicate"
		end
	end
	list[#list + 1] = { spellID = id, enabled = true }
	return id
end

function ns.GlowSpellIDs()
	local ids = {}
	for _, entry in ipairs(ns.GlowList()) do
		ids[#ids + 1] = entry.spellID
	end
	return ids
end

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

-- Blood Death Knight: Heart Strike hits up to 5 targets while the Death and Decay buff (188290) is on you, so it glows then.
local HEART_STRIKE = 206930
local DND_BUFF = 188290
local DND_CAST = 43265
local DND_DURATION = 10
local dndUntil = 0 -- end of the last Death and Decay we cast, for when the client will not show the buff
local dndAuraSeen = false -- the buff has been readable at least once, so its absence can be believed

local dndEvents = CreateFrame("Frame")
dndEvents:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
dndEvents:SetScript("OnEvent", function(_, _, _, _, spellID)
	if not IsSecret(spellID) and spellID == DND_CAST then
		dndUntil = GetTime() + DND_DURATION
	end
end)

-- true/false, plus where the answer came from (for /druidm glowdebug).
function ns.InDeathAndDecay()
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, DND_BUFF)
		if ok and aura then
			dndAuraSeen = true
			return true, "buff"
		end
	end
	if dndAuraSeen then
		return false, "no buff"
	end
	if GetTime() < dndUntil then
		return true, "cast timer (the buff is not readable)"
	end
	return false, "no buff"
end

local function HeartStrikeInDecay()
	if IsPlayerSpell and not IsPlayerSpell(HEART_STRIKE) then
		return false
	end
	if C_Spell.IsSpellUsable then
		local ok, usable = pcall(C_Spell.IsSpellUsable, HEART_STRIKE)
		if ok and not IsSecret(usable) and usable == false then
			return false -- no rune or runic power for it
		end
	end
	return (ns.InDeathAndDecay())
end

local function AddSpell(ids, names, id)
	ids[id] = true
	local override = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(id)
	if override and not IsSecret(override) then
		ids[override] = true
	end
	local name = C_Spell.GetSpellName(id)
	if name and not IsSecret(name) then
		names[name] = true
	end
end

-- What a bar button must hold to count as one of the abilities that should glow now: `ids` (the spell and its current
-- override) and `names` (another ID of the same spell, e.g. a form-specific version). Nil when nothing should glow.
function ns.ReadyGlowSpells()
	local db = ns.db
	if not db.glowEnabled then
		return nil
	end
	local preview = ns.IsPreview()
	local ids, names, any = {}, {}, false
	for _, entry in ipairs(ns.GlowList()) do
		if entry.enabled and (preview or ns.SpellState(entry.spellID) == "ready") then
			any = true
			AddSpell(ids, names, entry.spellID)
		end
	end
	if db.dkHeartStrikeDecay and ns.IsDeathKnight() and (preview or HeartStrikeInDecay()) then
		any = true
		AddSpell(ids, names, HEART_STRIKE)
	end
	if any then
		return ids, names
	end
end
