local ADDON_NAME, ns = ...

-- Bone Shield tracker (Blood Death Knight): the icon with the time left on it and the stacks under it.
--
-- In combat the client hides Bone Shield from addons altogether (not even "found", see /mtr bonedebug), so nothing can be
-- read and formatted by Lua. Since 12.1 the engine can draw a hidden aura itself, though: an aura container holding one slot
-- for Bone Shield builds the icon, the stack count and the countdown from the real buff, in or out of combat, and only the
-- Lua styling of those parts is ours. The styling is done once, while the button is being built (the button is closed to
-- addon code afterwards), so changing a font size or a toggle builds a fresh container a moment later.
--
-- The "no Bone Shield" warning needs no reading either: it is our own icon lying under the engine's one. The engine shows its
-- button only while the buff is up and that button covers the warning completely, so the warning is seen exactly while the
-- buff is down. Lua only decides the part it can know: whether you are in combat.
--
-- The preventive "REFRESH" message (little time left, or few stacks) is a second engine slot on the same buff. Its two texts
-- go through number formatters whose breakpoints print the message below a limit and nothing from the limit on, so the
-- comparison with the hidden time and the hidden stack count is made by the engine. The voice for the same moments is in
-- Reminders.lua and works differently: the engine only plays a sound when a buff is added, gains stacks or is removed.
local BONE_SHIELD = 195181
local LOW_TEXT = "REFRESH"
local WARNING_MARK = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew" -- the yellow "!" triangle of the game's alert popups
local MARROWREND = 195182 -- Blood-only, so knowing it means Blood spec
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local REBUILD_DELAY = 0.5 -- seconds a changed style must stay put before the display is rebuilt (sliders fire on every step)

local frame, unlockBg, preview, previewIcon, previewStack, previewTimer
local warning, warningIcon, warningMark
local lowHolder, previewLow
local lowActive -- { container, button, signature, note } of the live "REFRESH" slot
local lowBuilt = {} -- signature -> entry, as `built`
local lowPending, lowFailed, lowError
local active -- { container, button, signature } of the live engine display
local built = {} -- signature -> { container, button }: displays already made, reused instead of making more
local pendingSignature
local lastError

local function IsBlood()
	if not ns.IsDeathKnight() then
		return false
	end
	local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
	return (getSpec and getSpec() == 1) or (IsPlayerSpell ~= nil and IsPlayerSpell(MARROWREND)) or false
end

ns.IsBlood = IsBlood -- also asked by the voice in Reminders.lua

local function IconTexture()
	return C_Spell.GetSpellTexture(BONE_SHIELD) or FALLBACK_ICON
end

-- Everything the engine display bakes in; a change in any of it needs a new display.
local function StyleSignature()
	local db = ns.db
	return table.concat({
		db.bsSwipe and 1 or 0,
		db.bsShowStacks and 1 or 0,
		db.bsStackFontSize,
		db.bsShowTimer and 1 or 0,
		db.bsTimerFontSize,
		db.bsTimerDecimals,
		db.bsLowSeconds,
	}, "|")
end

-- Engine-side number formatting (the values are hidden, so Lua cannot format them) --------------------------------

local function CountFormatter()
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then
		return nil
	end
	local f = C_StringUtil.CreateNumericRuleFormatter()
	-- Without a formatter the engine only shows counts above 1.
	local ok = pcall(f.SetBreakpoints, f, { { threshold = 0, format = "%d", step = 1, rounding = Enum.NumericRuleFormatRounding.Down } })
	return ok and f or nil
end

-- Tenths below `decimals` seconds (0 = none), then whole seconds, then m:ss. Whole seconds round down, so the number is the
-- full seconds left and carries on from the tenths without a jump (rounding up read a second high, and went 6 -> 4.9).
local function TimeFormatter(decimals)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then
		return nil
	end
	local Nearest, Down, Up = Enum.NumericRuleFormatRounding.Nearest, Enum.NumericRuleFormatRounding.Down,
		Enum.NumericRuleFormatRounding.Up
	local points
	if decimals > 0 then
		points = {
			{ threshold = 0, format = "%.1f", rounding = Nearest },
			{ threshold = decimals, format = "%d", rounding = Down, step = 1 },
		}
	else
		points = { { threshold = 0, format = "%d", rounding = Down, step = 1 } }
	end
	points[#points + 1] = { threshold = 59.0001, format = "%d:%02d", rounding = Up, step = 1, components = { { div = 60 }, { mod = 60 } } }
	local f = C_StringUtil.CreateNumericRuleFormatter()
	local ok = pcall(f.SetBreakpoints, f, points)
	return ok and f or nil
end

-- Red below `low` seconds left, white from there on; evaluated by the engine against the hidden remaining time.
local function TimeColor(low)
	if low <= 0 or not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum.LuaCurveType) then
		return nil
	end
	local ok, curve = pcall(function()
		local c = C_CurveUtil.CreateColorCurve()
		c:SetType(Enum.LuaCurveType.Step)
		c:AddPoint(0, CreateColor(1, 0.15, 0.15, 1))
		c:AddPoint(low, CreateColor(1, 1, 1, 1))
		return c
	end)
	if not ok then
		return nil
	end
	local property = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration
	if property == nil then
		property = 0
	end
	return { curve = curve, property = property }
end

-- SetDurationText options: the formatter, refreshed often enough for tenths, and the colour curve. A failed registration
-- degrades step by step (an error inside it would abort the whole button build).
local function RegisterTimerText(button, fontString, decimals, low)
	local formatter = TimeFormatter(decimals)
	local color = TimeColor(low)
	local function register(withColor)
		local opts
		if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
			local binding = C_DurationUtil.CreateDurationTextBinding()
			if formatter then
				binding:SetFormatter(formatter)
			end
			binding:SetUpdateInterval(0.1)
			opts = { binding = binding }
		else
			opts = { textFormatter = formatter }
		end
		if withColor then
			opts.textColor = color
		end
		return pcall(button.SetDurationText, button, fontString, opts)
	end
	if register(true) then
		return true
	end
	if color and register(false) then
		return true
	end
	return pcall(button.SetDurationText, button, fontString, {})
end

ns.RegisterTimerText = RegisterTimerText -- also used by ExternalDefensives.lua

-- The engine display ---------------------------------------------------------------------------------------------------

-- Runs once per button, while the engine still lets addon code touch it. `entry` receives the button.
local function InitButton(entry, button, style)
	entry.button = button
	button:SetAllPoints(frame) -- sized by anchors from here on; all moving and resizing goes through `frame`
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

	local carrier = CreateFrame("Frame", nil, button)
	carrier:SetAllPoints(button)
	carrier:SetFrameLevel(cooldown:GetFrameLevel() + 5)
	carrier:EnableMouse(false)

	-- Fonts are set before the strings are handed to the engine, which writes text into them at once.
	local stack, timer
	if style.showStacks then
		stack = carrier:CreateFontString(nil, "OVERLAY")
		stack:SetFont(ns.DEFAULT_FONT, style.stackFontSize, "OUTLINE")
		stack:SetPoint("TOP", button, "BOTTOM", 0, -2)
	end
	if style.showTimer then
		timer = carrier:CreateFontString(nil, "OVERLAY")
		timer:SetFont(ns.DEFAULT_FONT, style.timerFontSize, "OUTLINE")
		timer:SetPoint("CENTER", button, "CENTER", 0, 0)
	end

	button:SetIcon(icon)
	button:SetDurationCooldown(cooldown)
	if stack then
		local formatter = CountFormatter()
		pcall(button.SetApplicationCount, button, stack, formatter and { formatter = formatter } or {})
	end
	if timer then
		RegisterTimerText(button, timer, style.decimals, style.low)
	end
end

local function BuildDisplay(signature)
	if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		C_AddOns.LoadAddOn("Blizzard_AuraContainer")
	end
	local db = ns.db
	local style = {
		swipe = db.bsSwipe,
		showStacks = db.bsShowStacks,
		stackFontSize = db.bsStackFontSize,
		showTimer = db.bsShowTimer,
		timerFontSize = db.bsTimerFontSize,
		decimals = db.bsTimerDecimals,
		low = db.bsLowSeconds,
	}
	local entry = { signature = signature }
	local ok, err = pcall(function()
		local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
		container:SetPoint("CENTER", frame, "CENTER", 0, 0)
		container:SetSize(1, 1)
		container:AddAuraSlot("boneshield", "HELPFUL", {
			candidateFilters = { includeSpellIDs = { [BONE_SHIELD] = true } },
			initializeFrame = function(button)
				local okInit, errInit = pcall(InitButton, entry, button, style)
				if not okInit then
					lastError = errInit
				end
			end,
		})
		container:SetUnit("player")
		container:UpdateAllAuras()
		container:SetFrameLevel(frame:GetFrameLevel() + 3)
		entry.container = container
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
	end
	if active and active ~= entry and active.container then
		active.container:Hide()
	end
	active = entry
	if entry.container then
		entry.container:SetShown(not ns.IsPreview())
	end
end

-- The "REFRESH" slot ---------------------------------------------------------------------------------------------------

local function LowWanted()
	local db = ns.db
	return db.bsLowWarn and (db.bsLowSeconds > 0 or db.bsLowStacks > 0) and true or false
end

-- The message scales with the icon.
local function LowFontSize()
	return math.max(12, math.floor(ns.db.bsSize * 0.34 + 0.5))
end

local function LowSignature()
	local db = ns.db
	return table.concat({ db.bsLowSeconds, db.bsLowStacks, LowFontSize() }, "|")
end

-- Prints LOW_TEXT while the number is under `limit` and nothing from `limit` on. Nil when there is no limit, or when the
-- client refuses the rule (then the text is not registered at all: without a formatter it would show the bare number).
local function LowFormatter(limit)
	if limit <= 0 or not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
		return nil
	end
	local f = C_StringUtil.CreateNumericRuleFormatter()
	local ok = pcall(f.SetBreakpoints, f, { { threshold = 0, format = LOW_TEXT }, { threshold = limit, format = "" } })
	return ok and f or nil
end

-- Runs once, in the engine's creation window. Both texts sit on the same spot and say the same, so either limit shows it.
local function InitLowButton(entry, button, style)
	entry.button = button
	button:SetAllPoints(frame)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)

	local carrier = CreateFrame("Frame", nil, button)
	carrier:SetAllPoints(button)
	carrier:EnableMouse(false)
	local function Text()
		local fs = carrier:CreateFontString(nil, "OVERLAY")
		fs:SetFont(ns.DEFAULT_FONT, style.fontSize, "THICKOUTLINE") -- before the engine writes into it
		fs:SetTextColor(1, 0.15, 0.15)
		fs:SetPoint("BOTTOM", button, "TOP", 0, 4)
		return fs
	end

	if style.stacksFormatter then
		local ok, err = pcall(button.SetApplicationCount, button, Text(), { formatter = style.stacksFormatter })
		if not ok then
			entry.note = "stack text refused: " .. tostring(err)
		end
	end
	if style.timeFormatter then
		-- The button takes its duration from a registered cooldown, as on the tracker itself; this one draws nothing.
		local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints(button)
		cooldown:SetDrawEdge(false)
		cooldown:SetHideCountdownNumbers(true)
		if cooldown.SetDrawSwipe then
			cooldown:SetDrawSwipe(false)
		end
		if cooldown.SetDrawBling then
			cooldown:SetDrawBling(false)
		end
		cooldown:SetAlpha(0)
		button:SetDurationCooldown(cooldown)
		local ok, err = pcall(function()
			local opts
			if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
				local binding = C_DurationUtil.CreateDurationTextBinding()
				binding:SetFormatter(style.timeFormatter)
				binding:SetUpdateInterval(0.1)
				opts = { binding = binding }
			else
				opts = { textFormatter = style.timeFormatter }
			end
			button:SetDurationText(Text(), opts)
		end)
		if not ok then
			entry.note = "time text refused: " .. tostring(err)
		end
	end
end

local function BuildLow(signature)
	if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		C_AddOns.LoadAddOn("Blizzard_AuraContainer")
	end
	local db = ns.db
	local style = {
		fontSize = LowFontSize(),
		stacksFormatter = LowFormatter(db.bsLowStacks),
		timeFormatter = LowFormatter(db.bsLowSeconds),
	}
	if not (style.stacksFormatter or style.timeFormatter) then
		lowError = "the client has no number rule formatter, or refused the message rule"
		return nil
	end
	local entry = { signature = signature }
	local ok, err = pcall(function()
		local container = CreateFrame("AuraContainer", nil, lowHolder, "CustomAuraContainerTemplate")
		container:SetPoint("CENTER", frame, "CENTER", 0, 0)
		container:SetSize(1, 1)
		container:AddAuraSlot("boneshieldlow", "HELPFUL", {
			candidateFilters = { includeSpellIDs = { [BONE_SHIELD] = true } },
			initializeFrame = function(button)
				local okInit, errInit = pcall(InitLowButton, entry, button, style)
				if not okInit then
					entry.note = tostring(errInit)
				end
			end,
		})
		container:SetUnit("player")
		container:UpdateAllAuras()
		entry.container = container
	end)
	if not ok then
		lowError = tostring(err)
		return nil
	end
	lowError = nil
	return entry
end

-- Switches to the slot for the current limits, making it when there is none yet. A failed build is not retried until
-- the limits change.
local function ActivateLow(signature)
	local entry = lowBuilt[signature]
	if not entry then
		if lowFailed == signature then
			return
		end
		entry = BuildLow(signature)
		if not entry then
			lowFailed = signature
			return
		end
		lowBuilt[signature] = entry
	end
	if lowActive and lowActive ~= entry then
		lowActive.container:Hide()
	end
	lowActive = entry
	lowError = nil -- a problem with other limits is not this slot's
	entry.container:Show()
end

-- Shown in combat only: the visibility is ours (the holder's alpha), what the text says is the engine's.
local function ApplyLow(inCombat, previewing)
	local wanted = LowWanted()
	lowHolder:SetAlpha((wanted and inCombat and not previewing) and 1 or 0)
	if not wanted then
		return
	end
	local signature = LowSignature()
	if not lowActive then
		ActivateLow(signature)
	elseif lowActive.signature == signature then
		lowError = nil -- the live slot is the wanted one; an earlier problem was with other limits
	elseif lowPending ~= signature then
		lowPending = signature
		C_Timer.After(REBUILD_DELAY, function()
			lowPending = nil
			if frame and frame:IsShown() and LowWanted() and LowSignature() == signature then
				ActivateLow(signature)
			end
		end)
	end
end

local function StylePreview()
	local db = ns.db
	previewLow:SetFont(ns.DEFAULT_FONT, LowFontSize(), "THICKOUTLINE")
	previewLow:SetShown(LowWanted())
	previewIcon:SetTexture(IconTexture())
	previewStack:SetFont(ns.DEFAULT_FONT, db.bsStackFontSize, "OUTLINE")
	previewStack:SetShown(db.bsShowStacks)
	previewTimer:SetFont(ns.DEFAULT_FONT, db.bsTimerFontSize, "OUTLINE")
	previewTimer:SetShown(db.bsShowTimer)
end

-- Re-styles and re-places the tracker (settings changed, spec changed, combat started or ended).
function ns.ApplyBoneShield()
	if not frame then
		return
	end
	local db = ns.db
	frame:SetSize(db.bsSize, db.bsSize)
	ns.PlaceFrame(frame, "bsX", "bsY")
	frame:EnableMouse(ns.unlocked)
	unlockBg:SetShown(ns.unlocked)

	local previewing = ns.IsPreview()
	local inCombat = ns.InCombat()
	local show = db.bsEnabled and IsBlood() and (previewing or not db.bsCombatOnly or inCombat)
	frame:SetShown(show and true or false)
	if not show then
		return
	end

	StylePreview()
	preview:SetShown(previewing)
	if active and active.container then
		active.container:SetShown(not previewing)
	end

	local signature = StyleSignature()
	if not active then
		ActivateDisplay(signature)
	end

	-- Only with a live engine display on top of it: without one nothing would ever cover the warning.
	local warn = db.bsWarnMissing and inCombat and not previewing and active ~= nil and active.container ~= nil
	warningIcon:SetTexture(IconTexture())
	warningMark:SetSize(db.bsSize * 0.6, db.bsSize * 0.6)
	warning:SetShown(warn and true or false)

	ApplyLow(inCombat, previewing)

	-- A style that differs from the live display's is applied a moment later, once the sliders have stopped moving.
	if active and active.signature ~= signature and pendingSignature ~= signature then
		pendingSignature = signature
		C_Timer.After(REBUILD_DELAY, function()
			pendingSignature = nil
			if frame and frame:IsShown() and StyleSignature() == signature then
				ActivateDisplay(signature)
				ns.ApplyBoneShield()
			end
		end)
	end
end

-- /mtr bonedebug
function ns.BoneShieldDebug()
	local db = ns.db
	ns.Print("Bone Shield tracker debug")
	print(("  Blood spec: %s; tracker %s; shown: %s; in combat: %s (the unit says %s)"):format(tostring(IsBlood() and true or false),
		db.bsEnabled and "on" or "off", tostring(frame and frame:IsShown() or false), tostring(ns.InCombat()),
		tostring(UnitAffectingCombat("player") and true or false)))
	print(("  missing-in-combat warning: %s; drawn under the engine icon now: %s"):format(db.bsWarnMissing and "on" or "off",
		tostring(warning and warning:IsShown() or false)))
	print(("  \"%s\" message: %s; under %d s or under %d stacks; engine slot: %s (%s); button: %s; visible now (in combat): %s; problem: %s"):format(
		LOW_TEXT, db.bsLowWarn and "on" or "off", db.bsLowSeconds, db.bsLowStacks, lowActive and "live" or "NOT built",
		lowActive and lowActive.signature or "-", tostring(lowActive and lowActive.button ~= nil or false),
		tostring(lowHolder and lowHolder:GetAlpha() == 1 or false), tostring((lowActive and lowActive.note) or lowError)))
	if ns.BoneVoiceStatus then
		print("  " .. ns.BoneVoiceStatus())
	end
	print(("  engine aura container API: %s; Blizzard_AuraContainer loaded: %s"):format(
		tostring(C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("Blizzard_AuraContainer")),
		tostring(C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer"))))
	local displays = 0
	for _ in pairs(built) do
		displays = displays + 1
	end
	print(("  engine display: %s (style %s, %d built); button: %s; last error: %s"):format(active and "live" or "NOT built",
		active and active.signature or "-", displays, tostring(active and active.button ~= nil or false), tostring(lastError)))
	if active and active.button then
		local ok, shown = pcall(active.button.IsShown, active.button)
		print(("  Bone Shield on you (button shown): %s"):format(not ok and "error" or (issecretvalue and issecretvalue(shown)) and "hidden by the client (the engine still draws it)" or tostring(shown)))
	end
	local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, "player", BONE_SHIELD)
	local found = ok and aura ~= nil
	local stacks, left = "-", "-"
	if found then
		local okRead = pcall(function()
			if issecretvalue and (issecretvalue(aura.applications) or issecretvalue(aura.expirationTime)) then
				stacks, left = "hidden", "hidden"
			else
				stacks, left = tostring(aura.applications), ("%.1f"):format(aura.expirationTime - GetTime())
			end
		end)
		if not okRead then
			stacks, left = "error", "error"
		end
	end
	local secrets = "no C_Secrets API"
	if C_Secrets then
		local okA, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
		local okL, level = pcall(C_Secrets.GetSpellAuraSecrecy, BONE_SHIELD)
		secrets = ("auras restricted now: %s; Bone Shield secrecy level: %s"):format(okA and tostring(issecretvalue and issecretvalue(restricted) and "secret" or restricted) or "error",
			okL and tostring(issecretvalue and issecretvalue(level) and "secret" or level) or "error")
	end
	print(("  direct read by Lua: found %s, stacks %s, seconds left %s; %s"):format(tostring(found), stacks, left, secrets))
end

function ns.InitBoneShield()
	frame = CreateFrame("Frame", "MonroTrackerBoneShield", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "bsX", "bsY")

	unlockBg = frame:CreateTexture(nil, "BACKGROUND")
	unlockBg:SetAllPoints()
	unlockBg:SetColorTexture(0.1, 0.8, 0.3, 0.35)

	-- The warning: a red, pulsing Bone Shield icon with the alert mark, kept inside the icon's bounds and below the engine
	-- display (level +3), whose own icon hides it while the buff is up.
	warning = CreateFrame("Frame", nil, frame)
	warning:SetAllPoints()
	warning:SetFrameLevel(frame:GetFrameLevel() + 1)
	warning:Hide()
	warningIcon = warning:CreateTexture(nil, "ARTWORK")
	warningIcon:SetAllPoints()
	warningIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	warningIcon:SetDesaturated(true)
	warningIcon:SetVertexColor(1, 0.25, 0.25)
	warningMark = warning:CreateTexture(nil, "OVERLAY")
	warningMark:SetTexture(WARNING_MARK)
	warningMark:SetPoint("CENTER")
	local pulse = warning:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.4)
	fade:SetDuration(0.45)
	fade:SetSmoothing("IN_OUT")
	warning:SetScript("OnShow", function()
		pulse:Play()
	end)
	warning:SetScript("OnHide", function()
		pulse:Stop()
	end)

	-- Parent of the "REFRESH" slots, above the tracker's own display; faded out while out of combat.
	lowHolder = CreateFrame("Frame", nil, frame)
	lowHolder:SetAllPoints()
	lowHolder:SetFrameLevel(frame:GetFrameLevel() + 8)
	lowHolder:SetAlpha(0)

	-- Sample shown while positioning or styling; the engine only draws while the buff is on you.
	preview = CreateFrame("Frame", nil, frame)
	preview:SetAllPoints()
	preview:SetFrameLevel(frame:GetFrameLevel() + 6)
	preview:Hide()
	previewLow = preview:CreateFontString(nil, "OVERLAY")
	previewLow:SetFont(ns.DEFAULT_FONT, 22, "THICKOUTLINE")
	previewLow:SetTextColor(1, 0.15, 0.15)
	previewLow:SetPoint("BOTTOM", preview, "TOP", 0, 4)
	previewLow:SetText(LOW_TEXT)
	previewIcon = preview:CreateTexture(nil, "ARTWORK")
	previewIcon:SetAllPoints()
	previewIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	previewStack = preview:CreateFontString(nil, "OVERLAY")
	previewStack:SetFont(ns.DEFAULT_FONT, 28, "OUTLINE")
	previewStack:SetPoint("TOP", preview, "BOTTOM", 0, -2)
	previewStack:SetText("8")
	previewTimer = preview:CreateFontString(nil, "OVERLAY")
	previewTimer:SetFont(ns.DEFAULT_FONT, 18, "OUTLINE")
	previewTimer:SetPoint("CENTER")
	previewTimer:SetText("12.3")

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("SPELLS_CHANGED")
	events:SetScript("OnEvent", ns.ApplyBoneShield)
end
