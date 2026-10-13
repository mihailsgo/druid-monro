local ADDON_NAME, ns = ...

local panel, trackerPanel, category
local widgets = {} -- main panel widgets with a Refresh method
local trackerWidgets = {} -- tracker editor widgets with a Refresh method
local openCount = 0

local BUILTIN_FONTS = {
	{ name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
	{ name = "Skurri", path = "Fonts\\skurri.ttf" },
	{ name = "2002", path = "Fonts\\2002.TTF" },
	{ name = "2002 Bold", path = "Fonts\\2002B.TTF" },
}

-- Built-in fonts plus anything registered with LibSharedMedia (if some addon provides it).
local function GetFonts()
	local fonts, seen = {}, {}
	for _, f in ipairs(BUILTIN_FONTS) do
		fonts[#fonts + 1] = f
		seen[f.path:lower()] = true
	end
	local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
	if lsm then
		local extra = {}
		for name, path in pairs(lsm:HashTable("font")) do
			if not seen[path:lower()] then
				extra[#extra + 1] = { name = name, path = path }
			end
		end
		table.sort(extra, function(a, b)
			return a.name < b.name
		end)
		for _, f in ipairs(extra) do
			fonts[#fonts + 1] = f
		end
	end
	return fonts
end

-- Widget helpers -------------------------------------------------------------

local function Label(parent, text, x, y, template)
	local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function Checkbox(parent, label, x, y, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	cb.Text:SetText(label)
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		ns.Apply()
	end)
	cb.Refresh = function(self)
		self:SetChecked(get())
	end
	return cb
end

-- Plain slider built from textures so it does not depend on Blizzard's slider templates.
local function Slider(parent, label, x, y, minV, maxV, step, get, set)
	Label(parent, label, x, y)
	local s = CreateFrame("Slider", nil, parent)
	s:SetPoint("TOPLEFT", x, y - 24)
	s:SetSize(220, 16)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(0.3, 0.3, 0.3, 0.9)
	local value = s:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	value:SetPoint("LEFT", s, "RIGHT", 10, 0)
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v + 0.5)
		value:SetText(v)
		if v ~= get() then
			set(v)
			ns.Apply()
		end
	end)
	s.Refresh = function(self)
		self:SetValue(get())
		value:SetText(get())
	end
	return s
end

local function ColorSwatch(parent, x, y, getColor)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetPoint("TOPLEFT", x, y)
	btn:SetSize(28, 28)
	local border = btn:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(1, 1, 1, 1)
	local fill = btn:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 2, -2)
	fill:SetPoint("BOTTOMRIGHT", -2, 2)

	local function setColor(r, g, b)
		local c = getColor()
		c.r, c.g, c.b = r, g, b
		fill:SetColorTexture(r, g, b, 1)
		ns.Apply()
	end

	btn:SetScript("OnClick", function()
		local c = getColor()
		ColorPickerFrame:SetupColorPickerAndShow({
			r = c.r,
			g = c.g,
			b = c.b,
			hasOpacity = false,
			swatchFunc = function()
				setColor(ColorPickerFrame:GetColorRGB())
			end,
			cancelFunc = function(previous)
				setColor(previous.r, previous.g, previous.b)
			end,
		})
	end)
	btn.Refresh = function()
		local c = getColor()
		fill:SetColorTexture(c.r, c.g, c.b, 1)
	end
	return btn
end

local function Dropdown(parent, x, y, width, items, isSelected, onSelect)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetPoint("TOPLEFT", x, y)
	dd:SetWidth(width)
	dd:SetupMenu(function(_, root)
		root:SetScrollMode(260)
		for _, item in ipairs(items()) do
			root:CreateRadio(item.name, function()
				return isSelected(item)
			end, function()
				onSelect(item)
				ns.Apply()
			end)
		end
	end)
	dd.Refresh = function(self)
		self:GenerateMenu()
	end
	return dd
end

local function TextBox(parent, x, y, width, maxLetters, onCommit, onChange)
	local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	edit:SetPoint("TOPLEFT", x, y)
	edit:SetSize(width, 24)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(maxLetters)
	if onChange then
		edit:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				onChange(self:GetText())
			end
		end)
	end
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnEnterPressed", edit.ClearFocus)
	if onCommit then
		edit:SetScript("OnEditFocusLost", function(self)
			onCommit(self:GetText())
		end)
	end
	return edit
end

local function ActionButton(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 26)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function TrackConfigVisibility(p)
	p:SetScript("OnShow", function()
		openCount = openCount + 1
		ns.configOpen = true
		ns.RefreshConfig()
		ns.Apply()
	end)
	p:SetScript("OnHide", function()
		openCount = math.max(0, openCount - 1)
		ns.configOpen = openCount > 0
		ns.Apply()
	end)
end

local function UnlockButton(parent, x, y)
	local unlock = ActionButton(parent, "", 140, function()
		ns.SetUnlocked(not ns.unlocked)
	end)
	unlock:SetPoint("TOPLEFT", x, y)
	unlock.Refresh = function(self)
		self:SetText(ns.unlocked and "Lock" or "Unlock to move")
	end
	return unlock
end

-- Main panel -----------------------------------------------------------------

local function BuildMainPanel()
	panel = CreateFrame("Frame")
	panel.name = "DruidMonro"

	Label(panel, "DruidMonro", 16, -16, "GameFontNormalHuge")

	-- Feature 1: not-in-bear-form text
	Label(panel, "Not in Bear Form text", 16, -56, "GameFontNormalLarge")

	Label(panel, "Text", 16, -88)
	widgets.edit = TextBox(panel, 24, -106, 300, 80, nil, function(text)
		ns.db.text = text
		ns.Apply()
	end)
	widgets.edit.Refresh = function(self)
		self:SetText(ns.db.text)
		self:SetCursorPosition(0)
	end

	Label(panel, "Font", 16, -144)
	widgets.font = Dropdown(panel, 16, -162, 220, GetFonts, function(item)
		return ns.db.fontPath == item.path
	end, function(item)
		ns.db.fontPath = item.path
	end)

	Label(panel, "Color", 270, -144)
	widgets.color = ColorSwatch(panel, 270, -164, function()
		return ns.db.color
	end)

	widgets.size = Slider(panel, "Font size", 16, -204, 12, 96, 1, function()
		return ns.db.fontSize
	end, function(v)
		ns.db.fontSize = v
	end)

	widgets.outline = Checkbox(panel, "Outline", 300, -224, function()
		return ns.db.outline
	end, function(v)
		ns.db.outline = v
	end)

	-- Feature 2: Moonfire proc indicator
	Label(panel, "Moonfire proc indicator", 16, -292, "GameFontNormalLarge")

	widgets.indEnabled = Checkbox(panel, "Show indicator when Moonfire procs", 16, -320, function()
		return ns.db.indicatorEnabled
	end, function(v)
		ns.db.indicatorEnabled = v
	end)

	Label(panel, "Glow effect", 16, -358)
	widgets.glow = Dropdown(panel, 16, -376, 220, function()
		return ns.GLOW_OPTIONS
	end, function(item)
		return ns.db.glow == item.key
	end, function(item)
		ns.db.glow = item.key
	end)

	widgets.indSize = Slider(panel, "Indicator size", 16, -418, 24, 200, 1, function()
		return ns.db.indicatorSize
	end, function(v)
		ns.db.indicatorSize = v
	end)

	-- Positioning
	Label(panel, "Position", 16, -486, "GameFontNormalLarge")
	Label(panel, "Unlock to show every element and drag it anywhere on screen.", 16, -512, "GameFontHighlight")

	widgets.unlock = UnlockButton(panel, 16, -536)
	local reset = ActionButton(panel, "Reset all", 140, function()
		ns.ResetAll()
	end)
	reset:SetPoint("LEFT", widgets.unlock, "RIGHT", 10, 0)

	TrackConfigVisibility(panel)
end

-- Ability trackers panel -----------------------------------------------------

local selected = 1
local listButtons = {}
local EMPTY = {
	enabled = true,
	text = "",
	fontPath = ns.DEFAULT_FONT,
	fontSize = 28,
	outline = true,
	color = { r = 1, g = 1, b = 1 },
}

local function T()
	return ns.db.trackers[selected] or EMPTY
end

local function SpellLabel(t)
	if t.spellID then
		local name = C_Spell.GetSpellName(t.spellID)
		return name or tostring(t.spellID)
	end
	return "no ability"
end

local function UpdateListButtons()
	local trackers = ns.db.trackers
	for i = 1, ns.MAX_TRACKERS do
		local b = listButtons[i]
		local t = trackers[i]
		if t then
			b:SetText(("%d. %s (%s)"):format(i, t.text ~= "" and t.text or "-", SpellLabel(t)))
			b:Show()
			b.selectedTex:SetShown(i == selected)
		else
			b:Hide()
		end
	end
	trackerWidgets.add:SetEnabled(#trackers < ns.MAX_TRACKERS)
end

local function BuildTrackerPanel()
	trackerPanel = CreateFrame("Frame")
	trackerPanel.name = "Ability trackers"
	local p = trackerPanel

	Label(p, "Ability trackers", 16, -16, "GameFontNormalHuge")
	Label(p, "Show a text while an ability has no charge or is on cooldown, e.g. \"NO CHARGE\" or \"NO KICK\".", 16, -48, "GameFontHighlight")

	-- Left column: tracker list
	trackerWidgets.add = ActionButton(p, "Add tracker", 200, function()
		local i = ns.NewTracker()
		if i then
			selected = i
			ns.Apply()
			ns.RefreshConfig()
		end
	end)
	trackerWidgets.add:SetPoint("TOPLEFT", 16, -80)

	for i = 1, ns.MAX_TRACKERS do
		local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		b:SetSize(200, 24)
		b:SetPoint("TOPLEFT", 16, -112 - (i - 1) * 26)
		b.selectedTex = b:CreateTexture(nil, "OVERLAY")
		b.selectedTex:SetAllPoints()
		b.selectedTex:SetColorTexture(1, 0.82, 0, 0.25)
		b:SetScript("OnClick", function()
			selected = i
			ns.RefreshConfig()
		end)
		listButtons[i] = b
	end

	-- Right column: editor for the selected tracker
	local ed = CreateFrame("Frame", nil, p)
	ed:SetPoint("TOPLEFT", 240, -80)
	ed:SetPoint("BOTTOMRIGHT")
	trackerWidgets.editor = ed
	ed.Refresh = function(self)
		self:SetShown(ns.db.trackers[selected] ~= nil)
	end

	Label(ed, "Ability (name or spell ID)", 0, 0)
	local status = ed:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	status:SetPoint("TOPLEFT", 0, -56)
	local function ShowStatus()
		local t = T()
		if t.spellID then
			local name, icon = C_Spell.GetSpellName(t.spellID), C_Spell.GetSpellTexture(t.spellID)
			status:SetText(("|cff33ff99Tracking:|r |T%s:16|t %s (%d)"):format(tostring(icon or 134400), name or "?", t.spellID))
		else
			status:SetText("|cffff5555No ability selected|r - type a spell you know and press Enter")
		end
	end
	local ability = TextBox(ed, 8, -18, 280, 60, function(input)
		local t = T()
		if t == EMPTY then
			return
		end
		local id = ns.ResolveSpell(input)
		if id then
			t.spellID = id
		elseif strtrim(input) ~= "" then
			status:SetText("|cffff5555Spell not found|r - use the exact name of a spell you know, or its ID")
			return
		else
			t.spellID = nil
		end
		ShowStatus()
		ns.Apply()
		UpdateListButtons()
	end)
	ability.Refresh = function(self)
		local t = T()
		self:SetText(t.spellID and C_Spell.GetSpellName(t.spellID) or "")
		self:SetCursorPosition(0)
		ShowStatus()
	end
	trackerWidgets.ability = ability

	Label(ed, "Text", 0, -88)
	local text = TextBox(ed, 8, -106, 280, 80, nil, function(value)
		if T() ~= EMPTY then
			T().text = value
			ns.Apply()
			UpdateListButtons()
		end
	end)
	text.Refresh = function(self)
		self:SetText(T().text)
		self:SetCursorPosition(0)
	end
	trackerWidgets.text = text

	Label(ed, "Font", 0, -144)
	trackerWidgets.font = Dropdown(ed, 0, -162, 220, GetFonts, function(item)
		return T().fontPath == item.path
	end, function(item)
		T().fontPath = item.path
	end)

	Label(ed, "Color", 250, -144)
	trackerWidgets.color = ColorSwatch(ed, 250, -164, function()
		return T().color
	end)

	trackerWidgets.size = Slider(ed, "Font size", 0, -204, 12, 96, 1, function()
		return T().fontSize
	end, function(v)
		T().fontSize = v
	end)

	trackerWidgets.outline = Checkbox(ed, "Outline", 280, -224, function()
		return T().outline
	end, function(v)
		T().outline = v
	end)

	trackerWidgets.enabled = Checkbox(ed, "Enabled", 0, -262, function()
		return T().enabled
	end, function(v)
		T().enabled = v
	end)

	local remove = ActionButton(ed, "Remove this tracker", 160, function()
		if ns.db.trackers[selected] then
			table.remove(ns.db.trackers, selected)
			selected = math.max(1, math.min(selected, #ns.db.trackers))
			ns.Apply()
			ns.RefreshConfig()
		end
	end)
	remove:SetPoint("TOPLEFT", 0, -300)

	Label(ed, "Position", 0, -350, "GameFontNormalLarge")
	Label(ed, "Unlock to show every element and drag it anywhere on screen.", 0, -376, "GameFontHighlight")
	trackerWidgets.unlock = UnlockButton(ed, 0, -400)

	TrackConfigVisibility(p)
end

-- Public ---------------------------------------------------------------------

function ns.RefreshConfig()
	if not panel then
		return
	end
	selected = math.max(1, math.min(selected, math.max(1, #ns.db.trackers)))
	for _, w in pairs(widgets) do
		w:Refresh()
	end
	UpdateListButtons()
	trackerWidgets.editor:Refresh()
	if ns.db.trackers[selected] then
		for key, w in pairs(trackerWidgets) do
			if key ~= "add" and key ~= "editor" then
				w:Refresh()
			end
		end
	end
end

function ns.OpenConfig()
	if Settings and Settings.OpenToCategory and category then
		Settings.OpenToCategory(category:GetID())
	end
end

function ns.InitConfig()
	BuildMainPanel()
	BuildTrackerPanel()
	category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)
	Settings.RegisterCanvasLayoutSubcategory(category, trackerPanel, trackerPanel.name)
end
