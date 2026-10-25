local ADDON_NAME, ns = ...

local RUNIC_POWER = Enum.PowerType.RunicPower

local frame, bar, text, split
local glow, glowAnim
local glowBars = {}

-- The runic power value (of `max`, normally 100) that rpPercent of the bar stands for.
local function ThresholdValue(max)
	local pct = ns.db.rpPercent
	local ok, value = pcall(function()
		return max * pct / 100
	end)
	if not ok or not value then
		value = pct -- the client hides the max; it is 100 unless a talent raises it
	end
	return value
end

-- The glow is a set of status bars (a border, an outer halo and a wash over the bar) whose range is just below the
-- threshold up to the threshold: they fill (and so show) exactly when runic power is at or above it. The bar's own
-- setters accept values the client hides in combat, so this never has to read or compare the number.
local function UpdateGlow(cur, max)
	local db = ns.db
	if not db.rpGlow then
		glow:Hide()
		return
	end
	glow:Show()
	if not glowAnim:IsPlaying() then
		glowAnim:Play()
	end
	local thr = ThresholdValue(max)
	for _, g in ipairs(glowBars) do
		g:SetMinMaxValues(thr - 0.5, thr)
		g:SetValue(ns.IsPreview() and thr or cur)
	end
end

-- Puts the split line at rpPercent of the bar's width.
local function PlaceSplit()
	local db = ns.db
	local x = (db.rpWidth - 2) * db.rpPercent / 100
	split:ClearAllPoints()
	split:SetPoint("TOP", bar, "TOPLEFT", x, 0)
	split:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x, 0)
end

-- Cheap pass for power events: only the bar value, text, glow and split line change.
local function UpdateRP()
	if not frame or not frame:IsShown() then
		return
	end
	local db = ns.db
	local max = UnitPowerMax("player", RUNIC_POWER)
	local cur = UnitPower("player", RUNIC_POWER)
	UpdateGlow(cur, max)
	PlaceSplit()
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

function ns.RunicPowerDebug()
	if not frame then
		ns.Print("runic power bar: only created on a Death Knight")
		return
	end
	local cur = UnitPower("player", RUNIC_POWER)
	local max = UnitPowerMax("player", RUNIC_POWER)
	local secret = issecretvalue ~= nil and issecretvalue(cur)
	local thr = ThresholdValue(max)
	local ok, high = pcall(function()
		return cur >= thr
	end)
	ns.Print(("runic power bar: shown=%s glowOn=%s glowShown=%s split/glow at %s%% (= %s) value secret=%s, readable compare=%s%s"):format(
		tostring(frame:IsShown()), tostring(ns.db.rpGlow), tostring(glow:IsShown()), tostring(ns.db.rpPercent), tostring(thr),
		tostring(secret), tostring(ok), ok and (" (at/above: " .. tostring(high) .. ")") or ""))
	for i, g in ipairs(glowBars) do
		local lo, hi = g:GetMinMaxValues()
		print(("  glow bar %d: min=%s max=%s shown=%s"):format(i, tostring(lo), tostring(hi), tostring(g:IsShown())))
	end
end

function ns.InitRunicPower()
	frame = CreateFrame("Frame", "MonroTrackerRunicPower", UIParent)
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

	-- Glow at or above the threshold: a pulsing frame just outside the panel (see UpdateGlow).
	glow = CreateFrame("Frame", nil, frame)
	glow:SetAllPoints()
	glow:SetFrameLevel(bar:GetFrameLevel() + 2)
	glow:Hide()
	local function GateBar()
		local g = CreateFrame("StatusBar", nil, glow)
		g:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		g:GetStatusBarTexture():SetBlendMode("ADD")
		g:SetMinMaxValues(0, 1)
		g:SetValue(0)
		glowBars[#glowBars + 1] = g
		return g
	end
	-- A border `t` thick whose outer edge is `o` outside the panel, in the given color.
	local function Ring(o, t, r, g, b, a)
		local function Edge(p1, x1, y1, p2, x2, y2, w, h)
			local s = GateBar()
			s:SetStatusBarColor(r, g, b, a)
			s:SetPoint(p1, frame, p1, x1, y1)
			s:SetPoint(p2, frame, p2, x2, y2)
			if w then
				s:SetWidth(w)
			end
			if h then
				s:SetHeight(h)
			end
		end
		Edge("TOPLEFT", -o, o, "TOPRIGHT", o, o, nil, t)
		Edge("BOTTOMLEFT", -o, -o, "BOTTOMRIGHT", o, -o, nil, t)
		Edge("TOPLEFT", -o, o, "BOTTOMLEFT", -o, -o, t, nil)
		Edge("TOPRIGHT", o, o, "BOTTOMRIGHT", o, -o, t, nil)
	end
	Ring(9, 4, 0.3, 0.85, 1, 0.45) -- soft outer halo
	Ring(5, 5, 0.55, 0.95, 1, 1) -- bright border
	local wash = GateBar() -- the bar itself lights up
	wash:SetStatusBarColor(0.7, 1, 1, 0.35)
	wash:SetPoint("TOPLEFT", bar)
	wash:SetPoint("BOTTOMRIGHT", bar)
	glowAnim = glow:CreateAnimationGroup()
	glowAnim:SetLooping("BOUNCE")
	local fade = glowAnim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.35)
	fade:SetDuration(0.4)
	fade:SetSmoothing("IN_OUT")

	local events = CreateFrame("Frame")
	events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	events:SetScript("OnEvent", UpdateRP)
end
