local ADDON_NAME, ns = ...

local BEAR_FORM_ID = 5

ns.unlocked = false -- session only: frames are draggable and always shown
ns.configOpen = false -- set by the config panel while it is visible

local frame, text, bg

function ns.IsDruid()
	return select(2, UnitClass("player")) == "DRUID"
end

-- True while the user is positioning or styling: elements show regardless of game state.
function ns.IsPreview()
	return ns.unlocked or ns.configOpen
end

local function DefaultStore()
	return ns.db
end

-- Makes `f` draggable while ns.unlocked, saving its offset from the screen center
-- into store()[xKey] / store()[yKey]. `store` defaults to the saved-variables table.
function ns.MakeDraggable(f, xKey, yKey, store)
	store = store or DefaultStore
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if ns.unlocked then
			self:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local t = store()
		if not t then
			return
		end
		local cx, cy = self:GetCenter()
		local ux, uy = UIParent:GetCenter()
		t[xKey] = math.floor(cx - ux + 0.5)
		t[yKey] = math.floor(cy - uy + 0.5)
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", t[xKey], t[yKey])
	end)
end

function ns.PlaceFrame(f, xKey, yKey, t)
	t = t or ns.db
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", t[xKey], t[yKey])
end

local function InBearForm()
	return GetShapeshiftFormID() == BEAR_FORM_ID
end

local function ApplyText()
	if not frame then
		return
	end
	local db = ns.db
	local flags = db.outline and "OUTLINE" or ""
	if not text:SetFont(db.fontPath, db.fontSize, flags) then
		text:SetFont(ns.DEFAULT_FONT, db.fontSize, flags)
	end
	text:SetTextColor(db.color.r, db.color.g, db.color.b, 1)
	text:SetText(db.text)
	frame:SetSize(math.max(text:GetStringWidth() + 16, 60), math.max(text:GetStringHeight() + 12, 24))
	ns.PlaceFrame(frame, "x", "y")

	frame:EnableMouse(ns.unlocked)
	bg:SetShown(ns.unlocked)

	local show
	if ns.IsPreview() then
		show = true
	else
		show = ns.IsDruid() and not InBearForm() and strtrim(db.text) ~= ""
	end
	frame:SetShown(show)
end

function ns.Apply()
	ApplyText()
	if ns.ApplyIndicator then
		ns.ApplyIndicator()
	end
	if ns.ApplyTrackers then
		ns.ApplyTrackers()
	end
end

function ns.SetUnlocked(value)
	ns.unlocked = value and true or false
	ns.Apply()
	if ns.RefreshConfig then
		ns.RefreshConfig()
	end
end

function ns.InitDisplay()
	frame = CreateFrame("Frame", "DruidMonroText", UIParent)
	frame:SetFrameStrata("MEDIUM")
	ns.MakeDraggable(frame, "x", "y")

	bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.8, 0.3, 0.35)
	bg:Hide()

	text = frame:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetFont(ns.DEFAULT_FONT, 32, "OUTLINE") -- a font must be set before SetText

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:SetScript("OnEvent", ns.Apply)

	if ns.InitIndicator then
		ns.InitIndicator()
	end
	if ns.InitTrackers then
		ns.InitTrackers()
	end
	ns.Apply()
end
