local ADDON_NAME, ns = ...

ns.MAX_TRACKERS = 10

local GCD_THRESHOLD = 1.5 -- cooldowns up to this long are treated as the global cooldown

local frames = {}
local state = {} -- spellID -> true when the ability has no charge / is on cooldown

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

-- Returns true if unavailable, false if available, nil if the client hides the answer.
local function Query(spellID)
	local charges = C_Spell.GetSpellCharges(spellID)
	if charges then
		local current = charges.currentCharges
		if IsSecret(current) then
			return nil
		end
		return current == 0
	end
	local cd = C_Spell.GetSpellCooldown(spellID)
	if not cd then
		return false
	end
	if IsSecret(cd.duration) or IsSecret(cd.startTime) or IsSecret(cd.isOnGCD) then
		return nil
	end
	if cd.isOnGCD then
		return false
	end
	return cd.duration > GCD_THRESHOLD and cd.startTime > 0
end

local function Poll(spellID)
	local ok, result = pcall(Query, spellID)
	if ok and result ~= nil then
		state[spellID] = result
	end
	-- otherwise keep the last known state
end

local function IsKnown(spellID)
	return not IsPlayerSpell or IsPlayerSpell(spellID)
end

local function ShouldShow(t)
	if not ns.db.trackersEnabled or not t.enabled then
		return false
	end
	if ns.IsPreview() then
		return true
	end
	return t.spellID ~= nil and IsKnown(t.spellID) and state[t.spellID] == true
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
	for i, t in ipairs(ns.db.trackers) do
		if t.spellID then
			Poll(t.spellID)
		end
		if frames[i] then
			frames[i]:SetShown(ShouldShow(t))
		end
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
	events:SetScript("OnEvent", UpdateTrackers)
	-- Safety net: a cooldown ending is not always announced by an event.
	C_Timer.NewTicker(0.5, UpdateTrackers)
end
