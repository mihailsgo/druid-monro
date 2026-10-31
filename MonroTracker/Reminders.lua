local ADDON_NAME, ns = ...

-- Voice reminders: says "Trinket ready" / "Heart of the Wild ready" when the cooldown comes back, "Apex" when
-- Wild Guardian procs and "Weapon" when Dancing Rune Weapon comes up.

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
	w.lastRead = ok and at or "hidden" -- for /mtr cddebug
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

-- Proc callouts: "Apex" (Druid) and "Weapon" (Blood Death Knight) ---------------------------------------------

-- Since 12.1 addons cannot see auras appear, but the engine can play a sound file when a given aura lands on a unit.
-- So each callout is a baked clip (Zira voice) the engine plays itself; the text-to-speech path below is only the
-- fallback for clients without C_UnitAuras.AddAuraSound. The spells in `casts` share their name with the buff, and
-- matching by name too survives the IDs changing between patches.
local SOUND_DIR = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Sounds\\"
ns.APEX_SOUND = SOUND_DIR .. "Apex.ogg"
ns.WEAPON_SOUND = SOUND_DIR .. "Weapon.ogg"

local PROC_DEBOUNCE = 1 -- the summon cast and the buff arrive together; speak once

local procs = {
	{
		-- Wild Guardian (Guardian apex talent) awakens a spirit. The summon is a hidden spell.
		text = "Apex",
		file = ns.APEX_SOUND,
		buff = 1308647, -- "Answered Calling": "Accompanied by a guardian spirit", 8 sec
		casts = { 1308399 },
		enabled = function()
			return ns.IsDruid() and ns.db.apexEnabled
		end,
	},
	{
		-- Dancing Rune Weapon, cast by you or triggered by another talent; both put the same buff on you.
		text = "Weapon",
		file = ns.WEAPON_SOUND,
		buff = 81256,
		casts = { 49028 },
		enabled = function()
			return ns.IsDeathKnight() and ns.db.weaponEnabled
		end,
	},
}

local function ProcName(p)
	return C_Spell.GetSpellName(p.buff) or p.text
end

local function IsProcSpell(p, spellID)
	if spellID == p.buff then
		return true
	end
	for _, id in ipairs(p.casts) do
		if spellID == id then
			return true
		end
	end
	local name = C_Spell.GetSpellName(spellID)
	return name ~= nil and not IsSecret(name) and name == ProcName(p)
end

local function HasProcBuff(p)
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, p.buff)
	if ok and aura ~= nil then
		return true
	end
	if C_UnitAuras.GetAuraDataBySpellName then
		ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", ProcName(p), "HELPFUL")
		return ok and aura ~= nil
	end
	return false
end

local function HasAuraSoundAPI()
	return C_UnitAuras and C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound and Enum
		and Enum.UnitAuraSoundTrigger and true or false
end

-- AddAuraSound is a blocked action in combat inside instanced PvE.
local function CanRegisterAuraSound()
	local _, instanceType = IsInInstance()
	return instanceType == "none" or instanceType == "pvp" or instanceType == "arena" or not InCombatLockdown()
end

local function RemoveProcSound(p)
	if p.handle then
		pcall(C_UnitAuras.RemoveAuraSound, p.handle)
		p.handle = nil
	end
end

-- Registers or removes each engine sound to match its setting; cheap when nothing changes. Called from ns.Apply, which
-- also runs when combat ends, so a registration refused in combat is retried then.
function ns.ApplyAuraSounds()
	if not (ns.db and HasAuraSoundAPI()) or not CanRegisterAuraSound() then
		return
	end
	for _, p in ipairs(procs) do
		local want = p.enabled() and true or false
		if want and not p.handle then
			local ok, handle = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Added, {
				unitToken = "player",
				spellID = p.buff,
				soundFileName = p.file,
				outputChannel = "Master",
			})
			if ok and handle then
				p.handle = handle
			end
		elseif not want then
			RemoveProcSound(p)
		end
	end
end

local function AnnounceProc(p)
	local now = GetTime()
	if p.enabled() and not p.handle and now - (p.spokenAt or 0) > PROC_DEBOUNCE then
		p.spokenAt = now
		ns.Speak(p.text)
	end
end

-- The buff appearing catches procs even if the cast is not reported. Aura details can be hidden in instances.
local function CheckProcs()
	for _, p in ipairs(procs) do
		if p.enabled() then
			local active = HasProcBuff(p)
			if active and not p.active then
				AnnounceProc(p)
			end
			p.active = active
		else
			p.active = false
		end
	end
end

local function CheckAll()
	for _, w in ipairs(watchers) do
		Check(w)
	end
	CheckProcs()
end

local function OnCast(spellID)
	if not spellID or IsSecret(spellID) then
		return
	end
	-- A new spirit while one is already out only refreshes the buff, so the cast is what catches it.
	for _, p in ipairs(procs) do
		if p.enabled() and IsProcSpell(p, spellID) then
			AnnounceProc(p)
		end
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

-- /mtr cddebug: what each reminder sees right now.
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

-- /mtr spy: prints your casts and gained buffs, to find the spell IDs of a proc.
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
		local parts = {}
		for _, p in ipairs(procs) do
			parts[#parts + 1] = ("%s looks for %d, or the name \"%s\" (engine sound %s)"):format(p.text, p.buff, ProcName(p),
				p.handle and "registered" or "NOT registered")
		end
		ns.Print("spy on - printing your casts and new buffs. " .. table.concat(parts, "; ") .. ". Run /mtr spy again to stop.")
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
			for _, p in ipairs(procs) do
				RemoveProcSound(p)
			end
			ns.ApplyAuraSounds()
		end
		CheckAll()
	end)
	-- Safety net: a cooldown ending is not always announced by an event.
	C_Timer.NewTicker(0.25, CheckAll)
end
