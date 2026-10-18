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
			if ns.db.heartEnabled and ns.IsDruid() then
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
		baseCooldown = function(id)
			local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(id)
			return (ms and not IsSecret(ms) and ms > 0) and ms / 1000 or nil
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

local voiceErrorShown = false

local function Check(w)
	local id = w.id()
	if id ~= w.lastID then
		w.lastID, w.readyAt, w.cooling, w.trusted = id, nil, nil, nil
	end
	if not id then
		return
	end
	local now = GetTime()
	local ok, at = pcall(ReadyAt, w, id)
	w.lastRead = ok and at or "hidden" -- for /druidm cddebug
	-- In combat the client can hide a cooldown or report it as ready. After a cast (see OnCast) a "ready" reading is
	-- only believed once the client has shown this cooldown running, which proves it is reporting truthfully.
	if ok and at ~= nil then
		if at > now then
			w.trusted = true
		end
		if at > now or w.trusted or not (w.readyAt and w.readyAt > now) then
			w.readyAt = at
		end
	end
	-- otherwise keep the last known end time
	local cooling = w.readyAt ~= nil and now < w.readyAt
	if w.cooling and not cooling and w.speak() then
		local spoke, err = ns.Speak(w.text)
		if not spoke and not voiceErrorShown then
			voiceErrorShown = true
			ns.Print(("could not say \"%s\": %s"):format(w.text, tostring(err)))
		end
	end
	w.cooling = cooling
end

local function IsCastOf(w, id, spellID)
	local castID = w.castSpell(id)
	if not castID then
		return false
	end
	if castID == spellID then
		return true
	end
	-- Same name catches form-specific or overridden versions of the spell.
	local a, b = C_Spell.GetSpellName(castID), C_Spell.GetSpellName(spellID)
	return a ~= nil and not IsSecret(a) and not IsSecret(b) and a == b
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

-- Since 12.1 addons cannot see auras appear, but the engine can play a sound file when a given aura lands on a unit.
-- So "Apex" is a baked clip (Zira voice) the engine plays itself; the text-to-speech path below is only the fallback
-- for clients without C_UnitAuras.AddAuraSound.
ns.APEX_SOUND = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Sounds\\Apex.ogg"
local apexHandles = {}

local function HasAuraSoundAPI()
	return C_UnitAuras and C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound and Enum
		and Enum.UnitAuraSoundTrigger and true or false
end

-- AddAuraSound is a blocked action in combat inside instanced PvE.
local function CanRegisterAuraSound()
	local _, instanceType = IsInInstance()
	return instanceType == "none" or instanceType == "pvp" or instanceType == "arena" or not InCombatLockdown()
end

local function RemoveApexSound()
	for i = #apexHandles, 1, -1 do
		pcall(C_UnitAuras.RemoveAuraSound, apexHandles[i])
		apexHandles[i] = nil
	end
end

-- Registers or removes the engine sound to match the setting; cheap when nothing changes. Called from ns.Apply, which
-- also runs when combat ends, so a registration refused in combat is retried then.
function ns.ApplyApexSound()
	if not (ns.db and HasAuraSoundAPI()) then
		return
	end
	local want = ns.IsDruid() and ns.db.apexEnabled and true or false
	if want == (#apexHandles > 0) or not CanRegisterAuraSound() then
		return
	end
	if not want then
		RemoveApexSound()
		return
	end
	local ok, handle = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Added, {
		unitToken = "player",
		spellID = ANSWERED_CALLING_BUFF,
		soundFileName = ns.APEX_SOUND,
		outputChannel = "Master",
	})
	if ok and handle then
		apexHandles[#apexHandles + 1] = handle
	end
end

function ns.ApexSoundRegistered()
	return #apexHandles > 0
end

local function AnnounceApex()
	local now = GetTime()
	if ns.db.apexEnabled and not ns.ApexSoundRegistered() and now - apexSpokenAt > APEX_DEBOUNCE then
		apexSpokenAt = now
		ns.Speak("Apex")
	end
end

-- The buff appearing catches procs even if the summon cast is not reported. Aura details can be hidden in instances.
local function CheckApex()
	if not ns.IsDruid() then
		return
	end
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
	if ns.IsDruid() and IsApexSpell(spellID) then
		AnnounceApex()
	end
	-- A successful use starts the remembered (or base) cooldown, for when the client hides or misreports it.
	local now = GetTime()
	for _, w in ipairs(watchers) do
		local id = w.lastID
		if id and IsCastOf(w, id, spellID) and not (w.readyAt and w.readyAt > now) then
			local duration = ns.db.cooldownMemory[w.memoKey .. id] or (w.baseCooldown and w.baseCooldown(id))
			if duration then
				w.readyAt = now + duration
				w.trusted = false
				w.cooling = true
			end
		end
	end
end

-- /druidm cddebug: what each reminder sees right now.
function ns.CooldownDebug()
	ns.Print("voice reminder debug")
	local now = GetTime()
	for _, w in ipairs(watchers) do
		local id = w.id()
		local line = ("  %s: watching %s"):format(w.text, tostring(id))
		if id then
			local read = w.lastRead
			if type(read) == "number" then
				read = read == 0 and "ready" or read == math.huge and "waiting" or ("%.0fs left"):format(read - now)
			end
			line = line .. ("; client says %s; addon thinks %s; trusted=%s; remembered %ss"):format(tostring(read),
				w.cooling and ("on cooldown, %.0fs left"):format((w.readyAt or now) - now) or "ready", tostring(w.trusted),
				tostring(ns.db.cooldownMemory[w.memoKey .. id]))
		end
		print(line)
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
		ns.Print(("spy on - printing your casts and new buffs (Apex looks for %d / %d, or the name \"%s\"; " ..
			"engine sound %s). Run /druidm spy again to stop."):format(ANSWERED_CALLING_BUFF, ANSWERED_CALLING_SUMMON,
			ApexName(), ns.ApexSoundRegistered() and "registered" or "NOT registered"))
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
		elseif event == "PLAYER_ENTERING_WORLD" and CanRegisterAuraSound() then
			-- Start clean after a loading screen in case the engine dropped the registration.
			RemoveApexSound()
			ns.ApplyApexSound()
		end
		CheckAll()
	end)
	-- Safety net: a cooldown ending is not always announced by an event.
	C_Timer.NewTicker(0.25, CheckAll)
end
