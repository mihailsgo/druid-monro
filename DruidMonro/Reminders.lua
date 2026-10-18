local ADDON_NAME, ns = ...

-- Voice reminders: says "Trinket ready" / "Heart of the Wild ready" when the cooldown comes back, and "Apex" when
-- Wild Guardian procs.

local HEART_OF_THE_WILD_IDS = {
	1261867, -- Midnight
	319454, -- The War Within and earlier
}

-- The Heart of the Wild spell ID the player knows, or nil when it is not talented.
function ns.KnownHeartOfTheWild()
	for _, id in ipairs(HEART_OF_THE_WILD_IDS) do
		if not IsPlayerSpell or IsPlayerSpell(id) then
			return id
		end
	end
end

local TRINKET_SLOTS = { INVSLOT_TRINKET1 or 13, INVSLOT_TRINKET2 or 14 }
local GCD_THRESHOLD = 1.5 -- cooldowns up to this long are treated as the global cooldown

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

-- On-use trinkets ------------------------------------------------------------

-- Returns { itemID, name, icon, where } or nil when the item has no Use: effect.
local function OnUseInfo(itemID, where)
	local _, spellID = C_Item.GetItemSpell(itemID)
	if not spellID then
		-- Uncached items report no Use: effect yet; ask for the data so the next listing has it.
		if not C_Item.IsItemDataCachedByID(itemID) then
			C_Item.RequestLoadItemDataByID(itemID)
		end
		return nil
	end
	return {
		itemID = itemID,
		name = C_Item.GetItemNameByID(itemID) or ("item " .. itemID),
		icon = C_Item.GetItemIconByID(itemID),
		where = where,
	}
end

-- On-use trinkets on the character: equipped first, then bags.
function ns.GetUseTrinkets()
	local list, seen = {}, {}
	local function add(itemID, where)
		if itemID and not seen[itemID] then
			seen[itemID] = true
			local info = OnUseInfo(itemID, where)
			if info then
				list[#list + 1] = info
			end
		end
	end
	for _, slot in ipairs(TRINKET_SLOTS) do
		add(GetInventoryItemID("player", slot), "equipped")
	end
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local id = C_Container.GetContainerItemID(bag, slot)
			if id and select(4, C_Item.GetItemInfoInstant(id)) == "INVTYPE_TRINKET" then
				add(id, "bags")
			end
		end
	end
	return list
end

-- Watchers -------------------------------------------------------------------

-- Each watcher: `id()` returns what to watch (nil while disabled / not applicable), `cooldown(id)` returns
-- start, duration, enabled, onGCD, and `castSpell(id)` the spell a successful use casts. `speak()` says whether to
-- announce. Cooldowns of `minDuration` seconds or less are not announced.
local watchers = {
	{
		text = "Trinket ready",
		memoKey = "item:",
		minDuration = 30, -- the 30s lockout after equipping, and the ~20s one shared with your other on-use trinket
		id = function()
			local db = ns.db
			local id = db.trinketItemID
			-- Also watched for the action-bar glow. Only while equipped: a trinket in the bags cannot be used anyway.
			if (db.trinketEnabled or db.trinketGlow) and id and C_Item.IsEquippedItem(id) then
				return id
			end
		end,
		speak = function()
			return ns.db.trinketEnabled
		end,
		cooldown = function(id)
			return C_Item.GetItemCooldown(id)
		end,
		castSpell = function(id)
			return select(2, C_Item.GetItemSpell(id))
		end,
	},
	{
		text = "Heart of the Wild ready",
		memoKey = "spell:",
		minDuration = GCD_THRESHOLD,
		id = function()
			if ns.db.heartEnabled then
				return ns.KnownHeartOfTheWild()
			end
		end,
		speak = function()
			return true
		end,
		cooldown = function(id)
			local cd = C_Spell.GetSpellCooldown(id)
			if cd then
				return cd.startTime, cd.duration, cd.isEnabled, cd.isOnGCD
			end
		end,
		castSpell = function(id)
			return id
		end,
	},
}

-- GetTime() at which the cooldown ends (0 = ready now), or nil when the client hides the answer.
local function ReadyAt(w, id)
	local start, duration, enabled, onGCD = w.cooldown(id)
	if IsSecret(start) or IsSecret(duration) or IsSecret(enabled) or IsSecret(onGCD) then
		return nil
	end
	if onGCD then
		return 0
	end
	if enabled == false or enabled == 0 then
		return math.huge -- the cooldown only starts once some condition ends
	end
	if not start or start == 0 or not duration or duration <= w.minDuration then
		return 0
	end
	-- Remember the longest cooldown seen, for when the client hides cooldowns later, e.g. in restricted content.
	local memo = ns.db.cooldownMemory
	local key = w.memoKey .. id
	if not memo[key] or duration > memo[key] then
		memo[key] = duration
	end
	return start + duration
end

local function Check(w)
	local id = w.id()
	if id ~= w.lastID then
		w.lastID, w.readyAt, w.cooling = id, nil, nil
	end
	if not id then
		return
	end
	local ok, at = pcall(ReadyAt, w, id)
	if ok and at ~= nil then
		w.readyAt = at
	end
	-- otherwise keep the last known end time
	local cooling = w.readyAt ~= nil and GetTime() < w.readyAt
	if w.cooling and not cooling and w.speak() then
		ns.Speak(w.text)
	end
	w.cooling = cooling
end

-- The voice watcher's view of the selected trinket: true on cooldown, false ready, nil unknown / not watched.
function ns.TrinketCooling()
	local w = watchers[1]
	if w.lastID and w.lastID == ns.db.trinketItemID then
		return w.cooling
	end
end

-- Apex proc: says "Apex" when Wild Guardian (Guardian apex talent) awakens a spirit -------------------------

local ANSWERED_CALLING_BUFF = 1308647 -- "Accompanied by a guardian spirit", 8 sec
local ANSWERED_CALLING_SUMMON = 1308399 -- hidden spell that summons the spirit
local APEX_DEBOUNCE = 1 -- the summon cast and the buff arrive together; speak once

local apexActive = false
local apexSpokenAt = 0

-- Both spells are named "Answered Calling"; matching by name too survives the IDs changing between patches.
local function ApexName()
	return C_Spell.GetSpellName(ANSWERED_CALLING_BUFF) or "Answered Calling"
end

local function IsApexSpell(spellID)
	if spellID == ANSWERED_CALLING_SUMMON or spellID == ANSWERED_CALLING_BUFF then
		return true
	end
	local name = C_Spell.GetSpellName(spellID)
	return name ~= nil and not IsSecret(name) and name == ApexName()
end

local function HasApexBuff()
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ANSWERED_CALLING_BUFF)
	if ok and aura ~= nil then
		return true
	end
	if C_UnitAuras.GetAuraDataBySpellName then
		ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", ApexName(), "HELPFUL")
		return ok and aura ~= nil
	end
	return false
end

local function AnnounceApex()
	local now = GetTime()
	if ns.db.apexEnabled and now - apexSpokenAt > APEX_DEBOUNCE then
		apexSpokenAt = now
		ns.Speak("Apex")
	end
end

-- The buff appearing catches procs even if the summon cast is not reported. Aura details can be hidden in instances.
local function CheckApex()
	local active = HasApexBuff()
	if active and not apexActive then
		AnnounceApex()
	end
	apexActive = active
end

local function CheckAll()
	for _, w in ipairs(watchers) do
		Check(w)
	end
	CheckApex()
end

local function OnCast(spellID)
	if not spellID or IsSecret(spellID) then
		return
	end
	-- A new spirit while one is already out only refreshes the buff, so the cast is what catches it.
	if IsApexSpell(spellID) then
		AnnounceApex()
	end
	-- Fallback for when cooldowns are hidden: a successful use starts the remembered cooldown.
	local now = GetTime()
	for _, w in ipairs(watchers) do
		local id = w.lastID
		if id and w.castSpell(id) == spellID and not (w.readyAt and w.readyAt > now) then
			local duration = ns.db.cooldownMemory[w.memoKey .. id]
			if duration then
				w.readyAt = now + duration
			end
		end
	end
end

-- /druidm spy: prints your casts and gained buffs, to find the spell IDs of a proc.
local spyFrame

local function SpyLabel(id, name)
	if IsSecret(id) then
		return "(hidden by the client)"
	end
	name = name or C_Spell.GetSpellName(id)
	return ("%s %s"):format(tostring(id), (name and not IsSecret(name)) and name or "?")
end

function ns.ToggleSpy()
	if not spyFrame then
		spyFrame = CreateFrame("Frame")
		spyFrame:SetScript("OnEvent", function(_, event, _, arg2, arg3)
			if event == "UNIT_SPELLCAST_SUCCEEDED" then
				print("|cff33ff99cast|r " .. SpyLabel(arg3))
			elseif type(arg2) == "table" and arg2.addedAuras then
				for _, aura in ipairs(arg2.addedAuras) do
					if IsSecret(aura.isHelpful) or aura.isHelpful then
						print("|cff33ccffbuff|r " .. SpyLabel(aura.spellId, aura.name))
					end
				end
			end
		end)
	end
	if spyFrame:IsEventRegistered("UNIT_AURA") then
		spyFrame:UnregisterAllEvents()
		ns.Print("spy off")
	else
		spyFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		spyFrame:RegisterUnitEvent("UNIT_AURA", "player")
		ns.Print(("spy on - printing your casts and new buffs (Apex looks for %d / %d, or the name \"%s\"). " ..
			"Run /druidm spy again to stop."):format(ANSWERED_CALLING_BUFF, ANSWERED_CALLING_SUMMON, ApexName()))
	end
end

function ns.InitReminders()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	events:RegisterEvent("BAG_UPDATE_COOLDOWN")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	events:RegisterUnitEvent("UNIT_AURA", "player")
	events:SetScript("OnEvent", function(_, event, _, _, spellID)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			OnCast(spellID)
		end
		CheckAll()
	end)
	-- Safety net: a cooldown ending is not always announced by an event.
	C_Timer.NewTicker(0.25, CheckAll)
end
