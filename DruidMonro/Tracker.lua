local ADDON_NAME, ns = ...

ns.MAX_TRACKERS = 10

local GCD_THRESHOLD = 1.5 -- cooldowns up to this long are treated as the global cooldown

local frames = {}

function ns.NewTracker()
	local trackers = ns.db.trackers
	if #trackers >= ns.MAX_TRACKERS then
		return nil
	end
	local n = #trackers
	trackers[n + 1] = {
		enabled = true,
		spellID = nil,
		text = "NO CHARGE",
		fontPath = ns.DEFAULT_FONT,
		fontSize = 28,
		outline = true,
		color = { r = 1, g = 0.8, b = 0 },
		x = 0,
		y = 100 - n * 40, -- staggered so new trackers do not overlap
	}
	return n + 1
end

-- Accepts a spell name or ID; returns spellID, name, icon (or nil when not found).
function ns.ResolveSpell(input)
	input = strtrim(tostring(input or ""))
	if input == "" then
		return nil
	end
	local info = C_Spell.GetSpellInfo(tonumber(input) or input)
	if info then
		return info.spellID, info.name, info.iconID
	end
end

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

-- What the client says about an ability, or nil when it hides the answer (in combat, since Midnight, it hides most
-- cooldowns or reports them as ready). Charge abilities give { max, cur, start, dur }, the others { start, dur, gcd }.
local function Read(spellID)
	local c = C_Spell.GetSpellCharges(spellID)
	if c then
		local cur, max, start, dur = c.currentCharges, c.maxCharges, c.cooldownStartTime, c.cooldownDuration
		if IsSecret(cur) or IsSecret(max) or IsSecret(start) or IsSecret(dur) then
			return nil
		end
		return { max = max, cur = cur, start = start or 0, dur = dur or 0 }
	end
	local cd = C_Spell.GetSpellCooldown(spellID)
	if not cd then
		return { start = 0, dur = 0, gcd = false }
	end
	if IsSecret(cd.duration) or IsSecret(cd.startTime) or IsSecret(cd.isOnGCD) then
		return nil
	end
	return { start = cd.startTime or 0, dur = cd.duration or 0, gcd = cd.isOnGCD and true or false }
end

-- What the addon believes about each ability, so a hidden or untruthful reading cannot lose track of it:
--   readyAt   - GetTime() at which a plain cooldown ends (nil = unknown, 0 = ready)
--   trusted   - the client has shown this cooldown running since the last cast, so a "ready" reading is believed
--   max, charges, rechargeAt, rechargeDur - the same for a charge ability
--   castAt    - when the player last cast it; cast - it has been cast (so it is known)
local state = {}

local function GetState(spellID)
	local s = state[spellID]
	if not s then
		s = {}
		state[spellID] = s
	end
	return s
end

local STALE_WINDOW = 1 -- seconds after a cast in which a reading that shows the spent charge back is not believed

-- The longest cooldown (the recharge, for charge abilities) and the most charges seen, kept between sessions for when
-- the client hides them.
local function Remember(key, value)
	local memo = ns.db.cooldownMemory
	if value and value > 0 and (not memo[key] or value > memo[key]) then
		memo[key] = value
	end
end

local function BaseCooldown(spellID)
	local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
	return (ms and not IsSecret(ms) and ms > 0) and ms / 1000 or nil
end

local function Cooldown(spellID)
	return ns.db.cooldownMemory["spell:" .. spellID] or BaseCooldown(spellID)
end

-- True while the client may hide cooldowns or report them as ready (in combat, and in restricted content such as a
-- Mythic+ run). Readings taken then can only be believed when they show the ability on cooldown / short of charges.
local function Restricted()
	if UnitAffectingCombat("player") or InCombatLockdown() then
		return true
	end
	local secrets = C_Secrets
	if secrets and secrets.HasSecretRestrictions then
		local ok, restricted = pcall(secrets.HasSecretRestrictions)
		return ok and restricted == true
	end
	return false
end

-- Charges the ability has regained by now.
local function Regenerate(s, now)
	while s.max and s.charges and s.charges < s.max and s.rechargeAt and now >= s.rechargeAt do
		s.charges = s.charges + 1
		s.rechargeAt = (s.charges < s.max and s.rechargeDur) and (s.rechargeAt + s.rechargeDur) or nil
	end
end

-- Folds a reading into what the addon believes.
local function Absorb(spellID, s, r, now)
	local restricted = Restricted()
	if r.max then
		s.max = r.max
		ns.db.cooldownMemory["charges:" .. spellID] = r.max
		Remember("spell:" .. spellID, r.dur)
		if r.dur > 0 then
			s.rechargeDur = r.dur
		end
		Regenerate(s, now)
		-- A reading that shows more charges than the addon counted is not believed while restricted, nor right after a
		-- cast (the client can still show the spent charge); regaining charges is counted from the recharge time.
		if not (s.charges and r.cur > s.charges and (restricted or (s.castAt and now - s.castAt < STALE_WINDOW))) then
			s.charges = r.cur
			s.rechargeAt = (r.cur < r.max and r.dur > 0) and (r.start + r.dur) or nil
		end
		return
	end
	if restricted and s.max then
		return -- a charge ability the client now answers about as a plain cooldown: not believed
	end
	s.max, s.charges, s.rechargeAt = nil, nil, nil
	ns.db.cooldownMemory["charges:" .. spellID] = nil
	local at = 0
	if not r.gcd and r.start > 0 and r.dur > GCD_THRESHOLD then
		at = r.start + r.dur
		Remember("spell:" .. spellID, r.dur)
	end
	if at > now then
		s.readyAt = at
		s.trusted = s.trusted or not restricted
	elseif not (s.readyAt and s.readyAt > now) or (s.trusted and not restricted) then
		-- "Ready" overrides a running cooldown only once the client has shown that cooldown running, and never while
		-- restricted: the cooldown can be started out of combat and then reported ready as soon as combat begins.
		s.readyAt = at
	end
end

local lastError

local function Poll(spellID)
	local ok, err = pcall(function()
		local r = Read(spellID)
		if r then
			Absorb(spellID, GetState(spellID), r, GetTime())
		end
		-- otherwise keep what the addon believes
	end)
	if not ok then
		lastError = err
	end
end

-- Same spell, or the same ability under another ID (form-specific versions such as Wild Charge's).
local function SameSpell(spellID, castID)
	if spellID == castID then
		return true
	end
	local a, b = C_Spell.GetSpellName(spellID), C_Spell.GetSpellName(castID)
	return a ~= nil and b ~= nil and not IsSecret(a) and not IsSecret(b) and a == b
end

-- For /druidm trackerdebug: casts the player did, how many had a hidden spell ID, and the last few casts of tracked
-- abilities.
local casts = { total = 0, hidden = 0, log = {} }

-- One use of an ability can report several casts: the trigger and the effect it fires (Charge casts Charge twice, with
-- different IDs). Casts of the same ability closer together than this are one use, or a 2-charge ability counts both.
local SAME_USE = 1

-- A use of the ability: starts the remembered (or base) cooldown, or spends a charge, for when the client hides or
-- misreports it.
local function CountUse(id, s, now)
	local dur = Cooldown(id)
	local max = s.max or ns.db.cooldownMemory["charges:" .. id]
	if max then
		s.max = max
		s.rechargeDur = s.rechargeDur or dur
		Regenerate(s, now)
		local cur = s.charges or max
		if cur > 0 then
			s.charges = cur - 1
			if not s.rechargeAt and s.rechargeDur then
				s.rechargeAt = now + s.rechargeDur
			end
		end
	elseif dur and not (s.readyAt and s.readyAt > now) then
		s.readyAt = now + dur
		s.trusted = false
	end
end

-- Every ability whose cooldown the addon follows: the trackers' and the ones set to glow (AbilityGlow.lua), each once.
local function Watched()
	local ids, seen = {}, {}
	for _, t in ipairs(ns.db.trackers) do
		if t.spellID and not seen[t.spellID] then
			seen[t.spellID] = true
			ids[#ids + 1] = t.spellID
		end
	end
	if ns.GlowSpellIDs then
		for _, id in ipairs(ns.GlowSpellIDs()) do
			if not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
	end
	return ids
end

local function OnCast(castID)
	casts.total = casts.total + 1
	if not castID or IsSecret(castID) then
		casts.hidden = casts.hidden + 1
		return
	end
	casts.lastID, casts.lastRestricted = castID, Restricted()
	local now = GetTime()
	for _, id in ipairs(Watched()) do
		if SameSpell(id, castID) then
			local s = GetState(id)
			local repeated = s.castAt ~= nil and now - s.castAt < SAME_USE
			table.insert(casts.log, ("%s %d %s%s"):format(date("%H:%M:%S"), castID, C_Spell.GetSpellName(castID) or "?",
				repeated and " (same use, not counted)" or ""))
			if #casts.log > 6 then
				table.remove(casts.log, 1)
			end
			s.cast = true
			if not repeated then
				s.castAt = now
				CountUse(id, s, now)
			end
		end
	end
end

-- True when the ability has no charge / is on cooldown.
local function Unavailable(spellID)
	local s = state[spellID]
	if not s then
		return false
	end
	local now = GetTime()
	if s.max then
		Regenerate(s, now)
		return s.charges ~= nil and s.charges <= 0
	end
	return s.readyAt ~= nil and now < s.readyAt
end

local function IsKnown(spellID)
	local s = state[spellID]
	if s and s.cast then
		return true
	end
	local checked = false
	if IsPlayerSpell then
		checked = true
		if IsPlayerSpell(spellID) then
			return true
		end
	end
	if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
		checked = true
		local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellID)
		if ok and known then
			return true
		end
	end
	return not checked
end

-- "unknown" (not in your spellbook), "cooldown" (no charge / on cooldown) or "ready"; same belief as the trackers use.
function ns.SpellState(spellID)
	if not IsKnown(spellID) then
		return "unknown"
	end
	Poll(spellID)
	return Unavailable(spellID) and "cooldown" or "ready"
end

local function ShouldShow(t)
	if not ns.db.trackersEnabled or not t.enabled then
		return false
	end
	if ns.IsPreview() then
		return true
	end
	return t.spellID ~= nil and IsKnown(t.spellID) and Unavailable(t.spellID)
end

local function GetFrame(i)
	local f = frames[i]
	if f then
		return f
	end
	f = CreateFrame("Frame", "DruidMonroTracker" .. i, UIParent)
	f:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(f, "x", "y", function()
		return ns.db.trackers[i]
	end)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.1, 0.8, 0.3, 0.35)
	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetPoint("CENTER")
	f.text:SetFont(ns.DEFAULT_FONT, 28, "OUTLINE") -- a font must be set before SetText
	frames[i] = f
	return f
end

-- Re-styles every tracker frame (settings changed) and refreshes visibility.
function ns.ApplyTrackers()
	local trackers = ns.db.trackers
	for i, t in ipairs(trackers) do
		if t.spellID then
			Poll(t.spellID)
		end
		local f = GetFrame(i)
		local flags = t.outline and "OUTLINE" or ""
		if not f.text:SetFont(t.fontPath, t.fontSize, flags) then
			f.text:SetFont(ns.DEFAULT_FONT, t.fontSize, flags)
		end
		f.text:SetTextColor(t.color.r, t.color.g, t.color.b, 1)
		f.text:SetText(t.text)
		f:SetSize(math.max(f.text:GetStringWidth() + 16, 60), math.max(f.text:GetStringHeight() + 12, 24))
		ns.PlaceFrame(f, "x", "y", t)
		f:EnableMouse(ns.unlocked)
		f.bg:SetShown(ns.unlocked)
		f:SetShown(ShouldShow(t))
	end
	for i = #trackers + 1, #frames do
		frames[i]:Hide()
	end
end

-- Cheap pass for cooldown events: only visibility can change.
local function UpdateTrackers()
	for _, id in ipairs(Watched()) do
		Poll(id)
	end
	for i, t in ipairs(ns.db.trackers) do
		if frames[i] then
			frames[i]:SetShown(ShouldShow(t))
		end
	end
end

-- /druidm trackerdebug: what the client says about each tracked ability and what the addon makes of it.
local function Hidden(v)
	return IsSecret(v) and "hidden" or tostring(v)
end

function ns.TrackerDebug()
	ns.Print("tracker debug")
	local trackers = ns.db.trackers
	if #trackers == 0 then
		print("  no trackers")
	end
	local now = GetTime()
	print(("  restricted right now: %s; casts seen %d (%d with the spell ID hidden)%s"):format(tostring(Restricted()),
		casts.total, casts.hidden,
		casts.lastID and ("; last cast %d %s, restricted then: %s"):format(casts.lastID, C_Spell.GetSpellName(casts.lastID) or "?",
			tostring(casts.lastRestricted)) or ""))
	for _, line in ipairs(casts.log) do
		print("  cast: " .. line)
	end
	for i, t in ipairs(trackers) do
		local id = t.spellID
		if not id then
			print(("  %d. no ability set"):format(i))
		else
			local ok, err = pcall(function()
				local name = C_Spell.GetSpellName(id)
				print(("  %d. %s (%d): %s, known=%s"):format(i, name or "?", id, t.enabled and "on" or "off",
					tostring(IsKnown(id))))
				local c = C_Spell.GetSpellCharges(id)
				if c then
					print(("     client: charges %s/%s, recharge started %s, duration %s"):format(Hidden(c.currentCharges),
						Hidden(c.maxCharges), Hidden(c.cooldownStartTime), Hidden(c.cooldownDuration)))
				end
				local cd = C_Spell.GetSpellCooldown(id)
				if cd then
					print(("     client: cooldown started %s, duration %s, on GCD %s"):format(Hidden(cd.startTime),
						Hidden(cd.duration), Hidden(cd.isOnGCD)))
				else
					print("     client: no cooldown info")
				end
				local s = state[id] or {}
				local belief
				if s.max then
					belief = ("%s of %s charges"):format(tostring(s.charges), tostring(s.max))
					if s.rechargeAt then
						belief = belief .. (", next in %.0fs"):format(s.rechargeAt - now)
					end
				elseif s.readyAt and s.readyAt > now then
					belief = ("on cooldown, %.0fs left"):format(s.readyAt - now)
				else
					belief = "no cooldown"
				end
				print(("     addon: %s -> %s; trusted=%s; remembered cooldown %s, charges %s; base cooldown %s"):format(belief,
					Unavailable(id) and "SHOWING" or "hidden", tostring(s.trusted),
					tostring(ns.db.cooldownMemory["spell:" .. id]), tostring(ns.db.cooldownMemory["charges:" .. id]),
					tostring(BaseCooldown(id))))
			end)
			if not ok then
				print(("  %d. error: %s"):format(i, tostring(err)))
			end
		end
	end
	if lastError then
		print("  last polling error: " .. tostring(lastError))
	end
end

function ns.InitTrackers()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	events:RegisterEvent("SPELL_UPDATE_CHARGES")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	events:SetScript("OnEvent", function(_, event, _, _, spellID)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			OnCast(spellID)
		end
		UpdateTrackers()
	end)
	-- Safety net: a cooldown ending is not always announced by an event.
	C_Timer.NewTicker(0.25, UpdateTrackers)
end
