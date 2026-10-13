local ADDON_NAME, ns = ...

local RAGE = Enum.PowerType.Rage

local frame, bar, text
local glow, glowAnim
local glowActive = false

local function InBearForm()
	return GetShapeshiftFormID() == 5
end

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

-- Cheap pass for power events: only the bar value and text change.
local function UpdateRage()
	if not frame or not frame:IsShown() then
		SetGlow(false)
		return
	end
	local max = UnitPowerMax("player", RAGE)
	local cur = UnitPower("player", RAGE)
	if ns.db.rageGlow then
		-- Comparison fails if the client hides the values; treat that as "not full".
		local ok, full = pcall(function()
			return max > 0 and cur >= max
		end)
		SetGlow((ns.IsPreview() or (ok and full)) and true or false)
	else
		SetGlow(false)
	end
	-- StatusBar setters accept values the client hides, so no arithmetic on them here.
	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
	if ns.db.rageShowText then
		-- Formatting fails if the client hides the value; the bar still shows it.
		if not pcall(function()
			text:SetFormattedText("%d", cur)
		end) then
			text:SetText("")
		end
	end
end

local function ShouldShow()
	local db = ns.db
	if not db.rageEnabled then
		return false
	end
	if ns.IsPreview() then
		return true
	end
	if not ns.IsDruid() or not InBearForm() then
		return false
	end
	return not db.rageCombatOnly or UnitAffectingCombat("player")
end

-- Re-styles the panel (settings changed) and refreshes visibility.
function ns.ApplyRage()
	if not frame then
		return
	end
	local db = ns.db
	frame:SetSize(db.rageWidth, db.rageHeight)
	ns.PlaceFrame(frame, "rageX", "rageY")
	bar:SetStatusBarColor(db.rageColor.r, db.rageColor.g, db.rageColor.b, 1)

	local size = math.max(8, math.floor(db.rageHeight * 0.7))
	text:SetFont(ns.DEFAULT_FONT, size, "OUTLINE")
	text:SetShown(db.rageShowText)

	frame:EnableMouse(ns.unlocked)
	frame.unlockBg:SetShown(ns.unlocked)
	frame:SetShown(ShouldShow())
	UpdateRage()
end

function ns.InitRage()
	frame = CreateFrame("Frame", "DruidMonroRage", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "rageX", "rageY")

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

	text = bar:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetFont(ns.DEFAULT_FONT, 14, "OUTLINE") -- a font must be set before SetText

	-- Full-rage glow: a pulsing golden frame just outside the panel.
	glow = CreateFrame("Frame", nil, frame)
	glow:SetAllPoints()
	glow:SetFrameLevel(bar:GetFrameLevel() + 2)
	glow:Hide()
	local function Edge(p1, x1, y1, p2, x2, y2, w, h)
		local t = glow:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 0.85, 0.2, 1)
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
	events:SetScript("OnEvent", UpdateRage)
end
