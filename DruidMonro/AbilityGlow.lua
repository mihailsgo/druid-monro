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
			local id = entry.spellID
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
	end
	if any then
		return ids, names
	end
end
