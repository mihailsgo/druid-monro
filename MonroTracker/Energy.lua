local ADDON_NAME, ns = ...

local ENERGY = Enum.PowerType.Energy
local DEFAULT_MAX = 100 -- used until the client lets us read the real maximum
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local frame, below, above, gate, line, text
local knownMax = DEFAULT_MAX -- last maximum energy the client showed us (it may hide it in combat)
local layoutMax, layoutSplit -- what the fill is currently laid out for

local function InCatForm()
	return GetShapeshiftFormID() == 1
end

-- `v` as a plain positive number, or nil when the client hides it or it is not usable.
local function Readable(v)
	if issecretvalue ~= nil and issecretvalue(v) then
		return nil
	end
	if type(v) ~= "number" or v <= 0 then
		return nil
	end
	return v
end

-- The energy value the split line stands for, or nil when there is no line (set to 0, or at or past the maximum).
local function SplitValue(max)
	local s = ns.db.energySplit
	if type(s) ~= "number" or s <= 0 or s >= max then
		return nil
	end
	return s
end

-- True when the bar would be shown with no preview involved, i.e. a Feral druid in Cat Form (and in combat if asked).
local function ShowsForReal()
	local db = ns.db
	if not db.energyEnabled or not ns.IsDruid() or not ns.IsFeral() or not InCatForm() then
		return false
	end
	return not db.energyCombatOnly or UnitAffectingCombat("player")
end

local function ShouldShow()
	if not ns.db.energyEnabled then
		return false
	end
	return ns.IsPreview() or ShowsForReal()
end

-- Shown while positioning or styling outside Cat Form: past the line when there is one, so both colors are visible.
local function PreviewValue(max)
	local split = SplitValue(max)
	if split then
		return math.floor((split + max) / 2)
	end
	return math.floor(max * 0.75)
end

-- With a split line the fill is two bars side by side: the left one covers energy 0 up to the line, the right one the
-- line up to the maximum, in the "past the line" color. Both are fed the raw energy, so nothing has to compare it with
-- the line (the client hides the number in combat). Without a line the left bar covers the whole width.
local function Layout(max)
	local db = ns.db
	local split = SplitValue(max)
	below:ClearAllPoints()
	below:SetPoint("TOPLEFT", 1, -1)
	if split then
		local x = (db.energyWidth - 2) * split / max
		below:SetPoint("BOTTOMLEFT", 1, 1)
		below:SetWidth(x)
		below:SetMinMaxValues(0, split)
		above:ClearAllPoints()
		above:SetPoint("TOPLEFT", 1 + x, -1)
		above:SetPoint("BOTTOMRIGHT", -1, 1)
		above:SetMinMaxValues(split, max)
		above:Show()
		gate:SetMinMaxValues(split - 0.5, split)
		gate:SetShown(db.energyAboveWhole)
		line:ClearAllPoints()
		line:SetPoint("TOP", frame, "TOPLEFT", 1 + x, -1)
		line:SetPoint("BOTTOM", frame, "BOTTOMLEFT", 1 + x, 1)
		line:Show()
	else
		below:SetPoint("BOTTOMRIGHT", -1, 1)
		below:SetMinMaxValues(0, max)
		above:Hide()
		gate:Hide()
		line:Hide()
	end
	layoutMax, layoutSplit = max, split
end

-- Cheap pass for power events: the bar values and text (and the layout when the maximum changes).
local function UpdateEnergy()
	if not frame or not frame:IsShown() then
		return
	end
	knownMax = Readable(UnitPowerMax("player", ENERGY)) or knownMax
	if knownMax ~= layoutMax then
		Layout(knownMax)
	end
	local cur = UnitPower("player", ENERGY)
	if ns.IsPreview() and not ShowsForReal() then
		cur = PreviewValue(knownMax)
	end
	-- StatusBar setters accept values the client hides, so no arithmetic or comparison on them here.
	below:SetValue(cur)
	above:SetValue(cur)
	gate:SetValue(cur)
	if ns.db.energyShowText then
		if not pcall(function()
			text:SetFormattedText("%d", cur)
		end) then
			text:SetText("")
		end
	end
end

-- Re-styles the panel (settings changed) and refreshes visibility.
function ns.ApplyEnergy()
	if not frame then
		return
	end
	local db = ns.db
	frame:SetSize(db.energyWidth, db.energyHeight)
	ns.PlaceFrame(frame, "energyX", "energyY")
	below:SetStatusBarColor(db.energyColor.r, db.energyColor.g, db.energyColor.b, 1)
	above:SetStatusBarColor(db.energyAboveColor.r, db.energyAboveColor.g, db.energyAboveColor.b, 1)
	gate:SetStatusBarColor(db.energyAboveColor.r, db.energyAboveColor.g, db.energyAboveColor.b, 1)

	local size = math.max(8, math.floor(db.energyHeight * 0.7))
	text:SetFont(ns.DEFAULT_FONT, size, "OUTLINE")
	text:SetShown(db.energyShowText)

	frame:EnableMouse(ns.unlocked)
	frame.unlockBg:SetShown(ns.unlocked)
	frame:SetShown(ShouldShow())
	knownMax = Readable(UnitPowerMax("player", ENERGY)) or knownMax
	Layout(knownMax)
	UpdateEnergy()
end

function ns.EnergyDebug()
	if not frame then
		ns.Print("energy bar: only created on a Druid")
		return
	end
	local cur = UnitPower("player", ENERGY)
	local max = UnitPowerMax("player", ENERGY)
	local secretCur = issecretvalue ~= nil and issecretvalue(cur)
	local secretMax = issecretvalue ~= nil and issecretvalue(max)
	ns.Print(("energy bar: shown=%s showsForReal=%s feral=%s cat=%s max used=%s split line at %s (%s) whole bar=%s value secret=%s, max secret=%s"):format(
		tostring(frame:IsShown()), tostring(ShowsForReal()), tostring(ns.IsFeral()), tostring(InCatForm()), tostring(knownMax),
		tostring(ns.db.energySplit), layoutSplit and "shown" or "hidden", tostring(ns.db.energyAboveWhole),
		tostring(secretCur), tostring(secretMax)))
end

function ns.InitEnergy()
	frame = CreateFrame("Frame", "MonroTrackerEnergy", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "energyX", "energyY")

	local back = frame:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.6)

	frame.unlockBg = frame:CreateTexture(nil, "BORDER")
	frame.unlockBg:SetAllPoints()
	frame.unlockBg:SetColorTexture(0.1, 0.8, 0.3, 0.35)

	local function FillBar()
		local b = CreateFrame("StatusBar", nil, frame)
		b:SetStatusBarTexture(BAR_TEXTURE)
		b:SetMinMaxValues(0, 1)
		b:SetValue(0)
		return b
	end
	below = FillBar()
	above = FillBar()
	-- "Recolor the whole bar": lies over the left bar in the past-the-line color. Its range is just below the line up to
	-- the line, so it is empty below the line and full from the line on, again without comparing the hidden number.
	gate = FillBar()
	gate:SetAllPoints(below)
	gate:SetFrameLevel(below:GetFrameLevel() + 1)
	gate:Hide()

	-- The split line and the number sit on their own frame above the fill so it never covers them.
	local top = CreateFrame("Frame", nil, frame)
	top:SetAllPoints()
	top:SetFrameLevel(gate:GetFrameLevel() + 1)
	line = top:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.9)
	line:SetWidth(2)
	line:Hide()

	text = top:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetFont(ns.DEFAULT_FONT, 14, "OUTLINE") -- a font must be set before SetText

	local events = CreateFrame("Frame")
	events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	events:SetScript("OnEvent", UpdateEnergy)
end
