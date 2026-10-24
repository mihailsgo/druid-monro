local ADDON_NAME, ns = ...

local RUNIC_POWER = Enum.PowerType.RunicPower

local frame, bar, text, split
local glow, glowAnim
local glowActive = false

local function SetGlow(on)
	if on == glowActive then
		return
	end
	glowActive = on
	glow:SetShown(on)
	if on then
		glowAnim:Play()
	else
		glowAnim:Stop()
	end
end

-- Puts the split line at the threshold's share of the bar (the bar's max is 100, or more with some talents).
local function PlaceSplit(max)
	local db = ns.db
	local ok, frac = pcall(function()
		return math.min(1, db.rpThreshold / max)
	end)
	if not ok or not frac then
		frac = math.min(1, db.rpThreshold / 100)
	end
	split:ClearAllPoints()
	split:SetPoint("TOP", bar, "TOPLEFT", (db.rpWidth - 2) * frac, 0)
	split:SetPoint("BOTTOM", bar, "BOTTOMLEFT", (db.rpWidth - 2) * frac, 0)
end

-- Cheap pass for power events: only the bar value, text, glow and split line change.
local function UpdateRP()
	if not frame or not frame:IsShown() then
		SetGlow(false)
		return
	end
	local db = ns.db
	local max = UnitPowerMax("player", RUNIC_POWER)
	local cur = UnitPower("player", RUNIC_POWER)
	if db.rpGlow then
		-- Comparison fails if the client hides the values; treat that as "below the threshold".
		local ok, high = pcall(function()
			return cur >= db.rpThreshold
		end)
		SetGlow((ns.IsPreview() or (ok and high)) and true or false)
	else
		SetGlow(false)
	end
	PlaceSplit(max)
	-- StatusBar setters accept values the client hides, so no arithmetic on them here.
	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
	if db.rpShowText then
		if not pcall(function()
			text:SetFormattedText("%d", cur)
		end) then
			text:SetText("")
		end
	end
end

local function ShouldShow()
	local db = ns.db
	if not db.rpEnabled then
		return false
	end
	if ns.IsPreview() then
		return true
	end
	if not ns.IsDeathKnight() then
		return false
	end
	return not db.rpCombatOnly or UnitAffectingCombat("player")
end

-- Re-styles the panel (settings changed) and refreshes visibility.
function ns.ApplyRunicPower()
	if not frame then
		return
	end
	local db = ns.db
	frame:SetSize(db.rpWidth, db.rpHeight)
	ns.PlaceFrame(frame, "rpX", "rpY")
	bar:SetStatusBarColor(db.rpColor.r, db.rpColor.g, db.rpColor.b, 1)

	local size = math.max(8, math.floor(db.rpHeight * 0.7))
	text:SetFont(ns.DEFAULT_FONT, size, "OUTLINE")
	text:SetShown(db.rpShowText)

	frame:EnableMouse(ns.unlocked)
	frame.unlockBg:SetShown(ns.unlocked)
	frame:SetShown(ShouldShow())
	UpdateRP()
end

function ns.InitRunicPower()
	frame = CreateFrame("Frame", "DruidMonroRunicPower", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "rpX", "rpY")

	local back = frame:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.6)

	frame.unlockBg = frame:CreateTexture(nil, "BORDER")
	frame.unlockBg:SetAllPoints()
	frame.unlockBg:SetColorTexture(0.1, 0.8, 0.3, 0.35)

	bar = CreateFrame("StatusBar", nil, frame)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMRIGHT", -1, 1)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetMinMaxValues(0, 100)
	bar:SetValue(0)

	-- The split line sits on its own frame above the bar so the fill never covers it.
	local splitFrame = CreateFrame("Frame", nil, frame)
	splitFrame:SetAllPoints()
	splitFrame:SetFrameLevel(bar:GetFrameLevel() + 1)
	split = splitFrame:CreateTexture(nil, "OVERLAY")
	split:SetColorTexture(1, 1, 1, 0.9)
	split:SetWidth(2)

	text = bar:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetFont(ns.DEFAULT_FONT, 14, "OUTLINE") -- a font must be set before SetText

	-- Glow at or above the threshold: a pulsing frame just outside the panel.
	glow = CreateFrame("Frame", nil, frame)
	glow:SetAllPoints()
	glow:SetFrameLevel(bar:GetFrameLevel() + 2)
	glow:Hide()
	local function Edge(p1, x1, y1, p2, x2, y2, w, h)
		local t = glow:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0.3, 0.85, 1, 1)
		t:SetBlendMode("ADD")
		t:SetPoint(p1, frame, p1, x1, y1)
		t:SetPoint(p2, frame, p2, x2, y2)
		if w then
			t:SetWidth(w)
		end
		if h then
			t:SetHeight(h)
		end
	end
	Edge("TOPLEFT", -3, 3, "TOPRIGHT", 3, 3, nil, 3)
	Edge("BOTTOMLEFT", -3, -3, "BOTTOMRIGHT", 3, -3, nil, 3)
	Edge("TOPLEFT", -3, 3, "BOTTOMLEFT", -3, -3, 3, nil)
	Edge("TOPRIGHT", 3, 3, "BOTTOMRIGHT", 3, -3, 3, nil)
	glowAnim = glow:CreateAnimationGroup()
	glowAnim:SetLooping("BOUNCE")
	local fade = glowAnim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.5)
	fade:SetSmoothing("IN_OUT")

	local events = CreateFrame("Frame")
	events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	events:SetScript("OnEvent", UpdateRP)
end
