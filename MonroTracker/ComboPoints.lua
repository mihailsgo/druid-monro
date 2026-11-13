local ADDON_NAME, ns = ...

local COMBO_POINTS = Enum.PowerType.ComboPoints
local MAX_SEGMENTS = 7 -- more than any talent build gives; segments past the real maximum stay hidden
local DEFAULT_MAX = 5 -- used when the client hides the maximum
local PREVIEW_POINTS = 3 -- shown while positioning or styling outside Cat Form

local frame
local segments = {}
local shownCount = 0 -- segments currently laid out

local function InCatForm()
	return GetShapeshiftFormID() == 1
end

-- How many segments to draw. The maximum may be hidden by the client in combat; then fall back to the usual five.
local function SegmentCount(max)
	local ok, n = pcall(function()
		return math.floor(max + 0.5)
	end)
	if not ok or type(n) ~= "number" or n < 1 then
		n = DEFAULT_MAX
	end
	return math.min(n, MAX_SEGMENTS)
end

-- True when the bar would be shown with no preview involved, i.e. a Feral druid in Cat Form (and in combat if asked).
local function ShowsForReal()
	local db = ns.db
	if not db.cpEnabled or not ns.IsDruid() or not ns.IsFeral() or not InCatForm() then
		return false
	end
	return not db.cpCombatOnly or UnitAffectingCombat("player")
end

local function ShouldShow()
	if not ns.db.cpEnabled then
		return false
	end
	return ns.IsPreview() or ShowsForReal()
end

-- Splits the panel into `n` equal segments. Segment i fills once you have i points, so its bar covers the range
-- (i - 1, i); the highlight bar over it covers (n - 1, n) and so only fills at the maximum.
local function Layout(n)
	local db = ns.db
	local gap = db.cpGap
	local width = (db.cpWidth - gap * (n - 1)) / n
	for i, seg in ipairs(segments) do
		if i <= n then
			seg:ClearAllPoints()
			seg:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (width + gap), 0)
			seg:SetSize(width, db.cpHeight)
			seg.fill:SetMinMaxValues(i - 1, i)
			seg.full:SetMinMaxValues(n - 1, n)
			seg:Show()
		else
			seg:Hide()
		end
	end
	shownCount = n
end

-- Cheap pass for power events: only the segment values change (and the layout when the maximum changes).
local function UpdateCombo()
	if not frame or not frame:IsShown() then
		return
	end
	local n = SegmentCount(UnitPowerMax("player", COMBO_POINTS))
	if n ~= shownCount then
		Layout(n)
	end
	local cur = UnitPower("player", COMBO_POINTS)
	if ns.IsPreview() and not ShowsForReal() then
		cur = PREVIEW_POINTS
	end
	-- StatusBar setters accept values the client hides, so no arithmetic or comparison on them here.
	for i = 1, n do
		segments[i].fill:SetValue(cur)
		segments[i].full:SetValue(cur)
	end
end

-- Re-styles the panel (settings changed) and refreshes visibility.
function ns.ApplyComboPoints()
	if not frame then
		return
	end
	local db = ns.db
	frame:SetSize(db.cpWidth, db.cpHeight)
	ns.PlaceFrame(frame, "cpX", "cpY")
	for _, seg in ipairs(segments) do
		seg.fill:SetStatusBarColor(db.cpColor.r, db.cpColor.g, db.cpColor.b, 1)
		seg.full:SetStatusBarColor(db.cpFullColor.r, db.cpFullColor.g, db.cpFullColor.b, 1)
		seg.full:SetShown(db.cpFullHighlight)
	end

	frame:EnableMouse(ns.unlocked)
	frame.unlockBg:SetShown(ns.unlocked)
	frame:SetShown(ShouldShow())
	Layout(SegmentCount(UnitPowerMax("player", COMBO_POINTS)))
	UpdateCombo()
end

function ns.ComboPointsDebug()
	if not frame then
		ns.Print("combo point bar: only created on a Druid")
		return
	end
	local cur = UnitPower("player", COMBO_POINTS)
	local max = UnitPowerMax("player", COMBO_POINTS)
	local secretCur = issecretvalue ~= nil and issecretvalue(cur)
	local secretMax = issecretvalue ~= nil and issecretvalue(max)
	ns.Print(("combo point bar: shown=%s showsForReal=%s feral=%s cat=%s segments=%s value secret=%s, max secret=%s"):format(
		tostring(frame:IsShown()), tostring(ShowsForReal()), tostring(ns.IsFeral()), tostring(InCatForm()), tostring(shownCount),
		tostring(secretCur), tostring(secretMax)))
	for i = 1, shownCount do
		local lo, hi = segments[i].fill:GetMinMaxValues()
		print(("  segment %d: range %s-%s, shown=%s"):format(i, tostring(lo), tostring(hi), tostring(segments[i]:IsShown())))
	end
end

function ns.InitComboPoints()
	frame = CreateFrame("Frame", "MonroTrackerComboPoints", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "cpX", "cpY")

	frame.unlockBg = frame:CreateTexture(nil, "BORDER")
	frame.unlockBg:SetAllPoints()
	frame.unlockBg:SetColorTexture(0.1, 0.8, 0.3, 0.35)

	for i = 1, MAX_SEGMENTS do
		local seg = CreateFrame("Frame", nil, frame)
		seg:Hide()
		local back = seg:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.6)

		seg.fill = CreateFrame("StatusBar", nil, seg)
		seg.fill:SetPoint("TOPLEFT", 1, -1)
		seg.fill:SetPoint("BOTTOMRIGHT", -1, 1)
		seg.fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		seg.fill:SetMinMaxValues(i - 1, i)
		seg.fill:SetValue(0)

		-- Lights up over the fill only while the last segment is full, so no comparison against the hidden count is needed.
		seg.full = CreateFrame("StatusBar", nil, seg)
		seg.full:SetPoint("TOPLEFT", 1, -1)
		seg.full:SetPoint("BOTTOMRIGHT", -1, 1)
		seg.full:SetFrameLevel(seg.fill:GetFrameLevel() + 1)
		seg.full:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		seg.full:SetMinMaxValues(DEFAULT_MAX - 1, DEFAULT_MAX)
		seg.full:SetValue(0)

		segments[i] = seg
	end

	local events = CreateFrame("Frame")
	events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	events:SetScript("OnEvent", UpdateCombo)
end
