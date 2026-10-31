local ADDON_NAME, ns = ...

-- External defensives on you: a row of icons with the time left for the big defensive buffs other players put on you
-- (Pain Suppression, Ironbark, Blessing of Sacrifice ...).
--
-- In combat the client hides other players' buffs from addons, so like the Bone Shield tracker this is drawn by the game
-- itself: an aura container on "player" with the engine filter HELPFUL|EXTERNAL_DEFENSIVE, which only lets buffs the game
-- flags as external defensives through. Which of them are shown is a candidate filter (a spell-ID list) the engine
-- evaluates too, so the choice made on the settings page keeps working in combat. The game does not tell an addon who cast
-- a buff, so "healers only" means "the spells healers cast" (ns.EXTDEF_CATALOG, `healer = true`).
local FILTER = "HELPFUL|EXTERNAL_DEFENSIVE"
local GROUP = "extdef"
local SPACING = 4
local MAX_ICONS = 8
local TIMER_DECIMALS = 5 -- tenths of a second below this many seconds
local REBUILD_DELAY = 0.5 -- seconds a changed style must stay put before the display is rebuilt (sliders fire on every step)
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local PREVIEW_COUNT = 3

-- Spell lists: `ids` are the aura's spell IDs (the first one keys the saved choice), `healer` marks what healers cast.
ns.EXTDEF_CATALOG = {
	{ class = "PRIEST", healer = true, name = "Pain Suppression", ids = { 33206 } },
	{ class = "PRIEST", healer = true, name = "Guardian Spirit", ids = { 47788 } },
	{ class = "DRUID", healer = true, name = "Ironbark", ids = { 102342 } },
	{ class = "MONK", healer = true, name = "Life Cocoon", ids = { 116849 } },
	{ class = "EVOKER", healer = true, name = "Time Dilation", ids = { 357170 } },
	{ class = "PALADIN", healer = true, name = "Blessing of Protection", ids = { 1022, 1309794 } },
	{ class = "PALADIN", healer = true, name = "Blessing of Sacrifice", ids = { 6940 } },
	{ class = "PALADIN", healer = false, name = "Blessing of Spellwarding", ids = { 204018 } },
	{ class = "HUNTER", healer = false, name = "Roar of Sacrifice", ids = { 53480 } },
	{ class = "DEATHKNIGHT", healer = false, name = "Lesser Anti-Magic Shell", ids = { 454863 } },
}
local CATALOG = ns.EXTDEF_CATALOG

local frame, unlockBg, preview
local previewButtons = {}
local active -- { container, signature, selection } of the live engine display
local built = {} -- signature -> entry: displays already made, reused instead of making more
local pendingSignature
local lastError

-- Choice of spells ------------------------------------------------------------------------------------------------------

-- Spell IDs the player has switched on and off (every alias of a catalog entry follows its first ID).
local function Selection()
	local off = ns.db.edOff
	local on, hidden = {}, {}
	for _, e in ipairs(CATALOG) do
		local target = off[e.ids[1]] and hidden or on
		for _, id in ipairs(e.ids) do
			target[id] = true
		end
	end
	return on, hidden
end

-- With "also show the unlisted ones" everything the engine flags passes except what was switched off; without it only the
-- switched-on list does. A fresh table each time: the engine keeps the reference it is handed.
local function CandidateFilters()
	local on, hidden = Selection()
	if ns.db.edOthers then
		return { excludeSpellIDs = hidden }
	end
	return { includeSpellIDs = on }
end

local function HasSelection()
	if ns.db.edOthers then
		return true
	end
	return next((Selection())) ~= nil
end

local function SelectionSignature()
	local ids = {}
	for id in pairs(ns.db.edOff) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return table.concat({ ns.db.edOthers and 1 or 0, ns.db.edMax, table.concat(ids, ",") }, "|")
end

-- Select all / Deselect all / Healers only. Anything that is not a preset is a hand-picked list.
function ns.ExtDefPreset(which)
	local db = ns.db
	wipe(db.edOff)
	if which == "all" then
		db.edOthers = true
	else
		db.edOthers = false
		for _, e in ipairs(CATALOG) do
			if which == "none" or not e.healer then
				db.edOff[e.ids[1]] = true
			end
		end
	end
	ns.Apply()
	if ns.RefreshConfig then
		ns.RefreshConfig()
	end
end

-- The engine display ---------------------------------------------------------------------------------------------------

-- Everything the engine buttons bake in; a change in any of it needs a new display.
local function StyleSignature()
	local db = ns.db
	return table.concat({ db.edSize, db.edSwipe and 1 or 0, db.edShowTimer and 1 or 0, db.edTimerFontSize }, "|")
end

-- Runs once per button, while the engine still lets addon code touch it.
local function InitButton(style, button)
	button:SetSize(style.size, style.size)
	pcall(button.SetMouseClickEnabled, button, false) -- a display only: it must not swallow clicks meant for the world
	pcall(button.SetMouseMotionEnabled, button, false)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- The cooldown is also the button's duration source, so the timer text needs it even with the swipe off.
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints(button)
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	if cooldown.SetDrawSwipe then
		cooldown:SetDrawSwipe(style.swipe)
	end

	local timer
	if style.showTimer then
		local carrier = CreateFrame("Frame", nil, button)
		carrier:SetAllPoints(button)
		carrier:SetFrameLevel(cooldown:GetFrameLevel() + 5)
		carrier:EnableMouse(false)
		timer = carrier:CreateFontString(nil, "OVERLAY")
		timer:SetFont(ns.DEFAULT_FONT, style.timerFontSize, "OUTLINE")
		timer:SetPoint("CENTER", button, "CENTER", 0, 0)
	end

	button:SetIcon(icon)
	button:SetDurationCooldown(cooldown)
	if timer then
		ns.RegisterTimerText(button, timer, TIMER_DECIMALS, 0)
	end
end

local function GroupLayout(size)
	return {
		elementWidth = size,
		elementHeight = size,
		elementSpacing = SPACING,
		lineSpacing = SPACING,
		elementSpacingX = SPACING,
		elementSpacingY = SPACING,
	}
end

local function BuildDisplay(signature)
	if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		C_AddOns.LoadAddOn("Blizzard_AuraContainer")
	end
	local db = ns.db
	local style = {
		size = db.edSize,
		swipe = db.edSwipe,
		showTimer = db.edShowTimer,
		timerFontSize = db.edTimerFontSize,
	}
	local entry = { signature = signature }
	local ok, err = pcall(function()
		local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
		container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		container:SetSize(1, 1)
		container:AddAuraGroup(GROUP, FILTER, {
			maxFrameCount = db.edMax,
			candidateFilters = CandidateFilters(),
			sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly,
			sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal,
			initializeFrame = function(button)
				local okInit, errInit = pcall(InitButton, style, button)
				if not okInit then
					lastError = errInit
				end
			end,
			layout = GroupLayout(style.size),
		})
		container:SetUnit("player")
		container:UpdateAllAuras()
		container:SetFrameLevel(frame:GetFrameLevel() + 3)
		entry.container = container
		entry.selection = SelectionSignature()
	end)
	if not ok then
		lastError = err
		return nil
	end
	lastError = nil
	return entry
end

-- Switches to the display for the current style, making it when there is none yet.
local function ActivateDisplay(signature)
	local entry = built[signature]
	if not entry then
		entry = BuildDisplay(signature)
		if not entry then
			return
		end
		built[signature] = entry
	else
		entry.selection = nil -- the choice may have changed while this display was idle
	end
	if active and active ~= entry and active.container then
		active.container:Hide()
	end
	active = entry
end

-- Hands the engine the current choice of spells. A live group keeps serving the set it parsed; hiding and showing the
-- container makes it parse again (the caller shows it). A refusal (e.g. in combat) leaves the old choice and is retried on
-- the next Apply.
local function PushSelection(entry)
	local container = entry.container
	local selection = SelectionSignature()
	if not container or entry.selection == selection then
		return
	end
	local ok, err = pcall(function()
		container:Hide()
		container:SetAuraGroupCandidateFilters(GROUP, CandidateFilters())
		container:SetAuraGroupMaxFrameCount(GROUP, ns.db.edMax)
	end)
	if ok then
		entry.selection = selection
	else
		lastError = err
	end
end

-- Sample row shown while positioning or styling; the engine only draws while a defensive is on you.
local function StylePreview()
	local db = ns.db
	for i = 1, PREVIEW_COUNT do
		local b = previewButtons[i]
		local spell = CATALOG[i]
		b:SetSize(db.edSize, db.edSize)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (db.edSize + SPACING), 0)
		b.icon:SetTexture(spell and C_Spell.GetSpellTexture(spell.ids[1]) or FALLBACK_ICON)
		b.timer:SetFont(ns.DEFAULT_FONT, db.edTimerFontSize, "OUTLINE")
		b.timer:SetShown(db.edShowTimer)
		b:SetShown(i <= db.edMax)
	end
end

-- Re-styles and re-places the row (settings changed, combat started or ended).
function ns.ApplyExtDef()
	if not frame then
		return
	end
	local db = ns.db
	local signature = StyleSignature()
	-- Made even while hidden: building a display is not allowed in every combat situation.
	if db.edEnabled and not active then
		ActivateDisplay(signature)
	end

	local size, count = db.edSize, db.edMax
	frame:SetSize(size * count + SPACING * (count - 1), size)
	ns.PlaceFrame(frame, "edX", "edY")
	frame:EnableMouse(ns.unlocked)
	unlockBg:SetShown(ns.unlocked)

	local previewing = ns.IsPreview()
	local show = db.edEnabled and (previewing or not db.edCombatOnly or UnitAffectingCombat("player"))
	frame:SetShown(show and true or false)
	if not show then
		return
	end

	StylePreview()
	preview:SetShown(previewing)
	if not active then
		return
	end

	-- A style that differs from the live display's is applied a moment later, once the sliders have stopped moving.
	if active.signature ~= signature and pendingSignature ~= signature then
		pendingSignature = signature
		C_Timer.After(REBUILD_DELAY, function()
			pendingSignature = nil
			if frame and frame:IsShown() and StyleSignature() == signature then
				ActivateDisplay(signature)
				ns.ApplyExtDef()
			end
		end)
	end
	if active.container then
		PushSelection(active)
		active.container:SetShown(not previewing and HasSelection())
	end
end

-- /mtr extdefdebug
function ns.ExtDefDebug()
	local db = ns.db
	ns.Print("External defensives debug")
	print(("  tracker %s; shown: %s; in combat: %s; showing unlisted ones: %s"):format(db.edEnabled and "on" or "off",
		tostring(frame and frame:IsShown() or false), tostring(UnitAffectingCombat("player") and true or false),
		tostring(db.edOthers and true or false)))
	local on, hidden = Selection()
	local nOn, nHidden = 0, 0
	for _ in pairs(on) do
		nOn = nOn + 1
	end
	for _ in pairs(hidden) do
		nHidden = nHidden + 1
	end
	print(("  filter %s; spells switched on: %d, off: %d"):format(FILTER, nOn, nHidden))
	local displays = 0
	for _ in pairs(built) do
		displays = displays + 1
	end
	print(("  engine display: %s (style %s, %d built); last error: %s"):format(active and "live" or "NOT built",
		active and active.signature or "-", displays, tostring(lastError)))
	-- What Lua itself can read (nothing in combat; out of combat the buffs are listed by name).
	local names, hiddenCount = {}, 0
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, FILTER)
		if not ok or not aura then
			break
		end
		local okName, name = pcall(function()
			if issecretvalue and issecretvalue(aura.name) then
				return nil
			end
			return aura.name
		end)
		if okName and name then
			names[#names + 1] = name
		else
			hiddenCount = hiddenCount + 1
		end
	end
	print(("  external defensives on you right now (as Lua sees them): %s%s"):format(
		#names > 0 and table.concat(names, ", ") or "none", hiddenCount > 0 and (" + %d hidden"):format(hiddenCount) or ""))
end

function ns.InitExtDef()
	frame = CreateFrame("Frame", "MonroTrackerExternalDefensives", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "edX", "edY")

	unlockBg = frame:CreateTexture(nil, "BACKGROUND")
	unlockBg:SetAllPoints()
	unlockBg:SetColorTexture(0.1, 0.8, 0.3, 0.35)

	preview = CreateFrame("Frame", nil, frame)
	preview:SetAllPoints()
	preview:SetFrameLevel(frame:GetFrameLevel() + 6)
	preview:Hide()
	for i = 1, PREVIEW_COUNT do
		local b = CreateFrame("Frame", nil, preview)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.timer = b:CreateFontString(nil, "OVERLAY")
		b.timer:SetFont(ns.DEFAULT_FONT, 16, "OUTLINE")
		b.timer:SetPoint("CENTER")
		b.timer:SetText(({ "12.3", "8", "1:05" })[i])
		previewButtons[i] = b
	end
end
