local ADDON_NAME, ns = ...

local panel, category
local widgets = {} -- main panel widgets with a Refresh method
local trackerWidgets = {} -- tracker editor widgets with a Refresh method
local openCount = 0
local refreshReported = {} -- widget key -> true once its refresh error was printed

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

-- Panels and pages -----------------------------------------------------------

local NAV_WIDTH = 150
local DIM_ALPHA = 0.45

local navItems = {} -- sidebar entries, each with a Refresh method

local function RefreshNav()
	for _, item in ipairs(navItems) do
		item:Refresh()
	end
end

local function Border(f, r, g, b, a)
	local function edge(p1, p2, w, h)
		local t = f:CreateTexture(nil, "BORDER")
		t:SetColorTexture(r, g, b, a)
		t:SetPoint(p1)
		t:SetPoint(p2)
		if w then
			t:SetWidth(w)
		end
		if h then
			t:SetHeight(h)
		end
	end
	edge("TOPLEFT", "TOPRIGHT", nil, 1)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

-- A titled box that groups related controls; put them in `panel.content`.
-- With `get`/`set` the title becomes a checkbox (`panel.toggle`) that switches the whole feature on
-- or off and dims the controls while it is off.
local function Panel(parent, title, get, set)
	local p = CreateFrame("Frame", nil, parent)
	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.3)
	Border(p, 1, 1, 1, 0.12)

	local divider = p:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOPLEFT", 8, -38)
	divider:SetPoint("TOPRIGHT", -8, -38)
	divider:SetHeight(1)
	divider:SetColorTexture(1, 1, 1, 0.12)

	p.content = CreateFrame("Frame", nil, p)
	p.content:SetPoint("TOPLEFT", 12, -50)
	p.content:SetPoint("BOTTOMRIGHT", -12, 12)

	if get then
		local function dim(on)
			p.content:SetAlpha(on and 1 or DIM_ALPHA)
		end
		local toggle = Checkbox(p, title, 6, -4, get, function(v)
			set(v)
			dim(v)
			RefreshNav()
		end)
		toggle.Text:SetFontObject("GameFontNormalLarge")
		local refresh = toggle.Refresh
		toggle.Refresh = function(self)
			refresh(self)
			dim(get())
		end
		p.toggle = toggle
	else
		Label(p, title, 12, -12, "GameFontNormalLarge")
	end
	return p
end

local content -- right-hand area that holds the pages
local pages = {}
local currentPage = "general"

-- A page fills the content area; panels are placed below its title and description.
local function Page(key, title, description)
	local f = CreateFrame("Frame", nil, content)
	f:SetAllPoints()
	f:Hide()
	Label(f, title, 0, 0, "GameFontNormalHuge")
	local d = Label(f, description, 0, -32, "GameFontHighlight")
	d:SetPoint("TOPRIGHT", 0, -32)
	d:SetJustifyH("LEFT")
	pages[key] = f
	return f
end

local function SelectPage(key)
	currentPage = key
	for k, page in pairs(pages) do
		page:SetShown(k == key)
	end
	for _, item in ipairs(navItems) do
		item.selectedTex:SetShown(item.key == key)
	end
end

-- Sidebar entry; `isOn` (optional) drives the green/grey status dot for feature pages.
local function NavItem(parent, key, label, y, isOn)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(NAV_WIDTH, 28)
	b:SetPoint("TOPLEFT", 0, y)
	b.key = key
	b.selectedTex = b:CreateTexture(nil, "BACKGROUND")
	b.selectedTex:SetAllPoints()
	b.selectedTex:SetColorTexture(1, 0.82, 0, 0.2)
	b.selectedTex:Hide()
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.08)
	b.dot = b:CreateTexture(nil, "ARTWORK")
	b.dot:SetSize(8, 8)
	b.dot:SetPoint("LEFT", 8, 0)
	local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", 24, 0)
	text:SetText(label)
	b:SetScript("OnClick", function()
		SelectPage(key)
	end)
	b.Refresh = function(self)
		if isOn then
			local on = isOn()
			self.dot:SetColorTexture(on and 0.2 or 0.4, on and 0.9 or 0.4, on and 0.4 or 0.4, 1)
			self.dot:Show()
		else
			self.dot:Hide()
		end
	end
	navItems[#navItems + 1] = b
	return b
end

-- Pages ----------------------------------------------------------------------

local PAGE_TOP = -72

local function BuildGeneralPage()
	local description = "Settings that are not tied to a single feature."
	if not ns.IsDruid() then
		description = description .. " Druid-only features (Bear Form text, Moonfire indicator, Rage panel, combo point and energy bars, Enrage panel, Heart of the Wild "
			.. "and Apex reminders) are hidden on this character."
	end
	local page = Page("general", "General", description)

	local ui = Panel(page, "Interface")
	ui:SetPoint("TOPLEFT", 0, PAGE_TOP)
	ui:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	ui:SetHeight(100)
	widgets.minimap = Checkbox(ui.content, "Show minimap button", 0, 0, function()
		return not ns.db.minimap.hide
	end, function(v)
		ns.db.minimap.hide = not v
	end)

	local cmds = Panel(page, "Slash commands")
	cmds:SetPoint("TOPLEFT", ui, "BOTTOMLEFT", 0, -12)
	cmds:SetPoint("TOPRIGHT", ui, "BOTTOMRIGHT", 0, -12)
	cmds:SetHeight(150)
	local list = cmds.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	list:SetPoint("TOPLEFT")
	list:SetPoint("TOPRIGHT")
	list:SetJustifyH("LEFT")
	list:SetSpacing(4)
	list:SetText(
		"|cff33ff99/mtr|r  open these settings\n"
			.. "|cff33ff99/mtr unlock|r  show and drag every element (run again to lock)\n"
			.. "|cff33ff99/mtr minimap|r  show or hide the minimap button\n"
			.. "|cff33ff99/mtr reset|r  reset all settings and positions"
	)
end

local function BuildBearPage()
	local page = Page("bear", "Bear Form text", "Warns you while you are not in Bear Form. Feral druids are also fine in Cat Form.")
	local p = Panel(page, "Show the text", function()
		return ns.db.textEnabled
	end, function(v)
		ns.db.textEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(320)
	widgets.textEnabled = p.toggle
	local c = p.content

	Label(c, "Text", 0, 0)
	widgets.edit = TextBox(c, 8, -18, 300, 80, nil, function(text)
		ns.db.text = text
		ns.Apply()
	end)
	widgets.edit.Refresh = function(self)
		self:SetText(ns.db.text)
		self:SetCursorPosition(0)
	end

	Label(c, "Font", 0, -56)
	widgets.font = Dropdown(c, 0, -74, 220, GetFonts, function(item)
		return ns.db.fontPath == item.path
	end, function(item)
		ns.db.fontPath = item.path
	end)

	Label(c, "Color", 250, -56)
	widgets.color = ColorSwatch(c, 250, -76, function()
		return ns.db.color
	end)

	widgets.size = Slider(c, "Font size", 0, -116, 12, 96, 1, function()
		return ns.db.fontSize
	end, function(v)
		ns.db.fontSize = v
	end)

	widgets.outline = Checkbox(c, "Outline", 300, -136, function()
		return ns.db.outline
	end, function(v)
		ns.db.outline = v
	end)

	widgets.textCombatOnly = Checkbox(c, "Only show in combat", 0, -176, function()
		return ns.db.textCombatOnly
	end, function(v)
		ns.db.textCombatOnly = v
	end)

	widgets.textDungeonOnly = Checkbox(c, "Only show in dungeons", 0, -206, function()
		return ns.db.textDungeonOnly
	end, function(v)
		ns.db.textDungeonOnly = v
	end)
end

local function BuildIndicatorPage()
	local page = Page(
		"indicator",
		"Moonfire proc indicator",
		"Shows an icon with a glow when Moonfire procs."
	)
	local p = Panel(page, "Show the indicator", function()
		return ns.db.indicatorEnabled
	end, function(v)
		ns.db.indicatorEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(180)
	widgets.indEnabled = p.toggle
	local c = p.content

	Label(c, "Glow effect", 0, 0)
	widgets.glow = Dropdown(c, 0, -18, 220, function()
		return ns.GLOW_OPTIONS
	end, function(item)
		return ns.db.glow == item.key
	end, function(item)
		ns.db.glow = item.key
	end)

	widgets.indSize = Slider(c, "Indicator size", 0, -60, 24, 200, 1, function()
		return ns.db.indicatorSize
	end, function(v)
		ns.db.indicatorSize = v
	end)
end

-- Ability trackers page ------------------------------------------------------

local selected = 1
local listButtons = {}
local addButton, editorPanel, emptyHint
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
			b:SetText(("%d. %s"):format(i, SpellLabel(t)))
			b:Show()
			b.selectedTex:SetShown(i == selected)
		else
			b:Hide()
		end
	end
	addButton:SetEnabled(#trackers < ns.MAX_TRACKERS)
end

local function BuildTrackerPage()
	local page = Page(
		"trackers",
		"Ability trackers",
		"Show a text while an ability has no charge or is on cooldown, e.g. \"NO CHARGE\" or \"NO KICK\"."
	)

	-- Left: tracker list
	local list = Panel(page, "Trackers", function()
		return ns.db.trackersEnabled
	end, function(v)
		ns.db.trackersEnabled = v
	end)
	list:SetPoint("TOPLEFT", 0, PAGE_TOP)
	list:SetPoint("BOTTOMLEFT", 0, 0)
	list:SetWidth(190)
	widgets.trackersEnabled = list.toggle

	addButton = ActionButton(list.content, "Add tracker", 166, function()
		local i = ns.NewTracker()
		if i then
			selected = i
			ns.Apply()
			ns.RefreshConfig()
		end
	end)
	addButton:SetPoint("TOPLEFT", 0, 0)

	for i = 1, ns.MAX_TRACKERS do
		local b = CreateFrame("Button", nil, list.content, "UIPanelButtonTemplate")
		b:SetSize(166, 24)
		b:SetPoint("TOPLEFT", 0, -34 - (i - 1) * 26)
		local fs = b:GetFontString()
		fs:SetWordWrap(false)
		fs:SetJustifyH("LEFT")
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", 10, 0)
		fs:SetPoint("RIGHT", -10, 0)
		b.selectedTex = b:CreateTexture(nil, "OVERLAY")
		b.selectedTex:SetAllPoints()
		b.selectedTex:SetColorTexture(1, 0.82, 0, 0.25)
		b:SetScript("OnClick", function()
			selected = i
			ns.RefreshConfig()
		end)
		listButtons[i] = b
	end

	-- Right: editor for the selected tracker
	local ed = Panel(page, "Tracker settings", function()
		return T().enabled
	end, function(v)
		if T() ~= EMPTY then
			T().enabled = v
		end
	end)
	ed:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)
	ed:SetPoint("BOTTOMRIGHT", 0, 0)
	editorPanel = ed
	trackerWidgets.enabled = ed.toggle
	local c = ed.content

	emptyHint = Label(page, "Add a tracker to get started.", 0, 0, "GameFontHighlight")
	emptyHint:ClearAllPoints()
	emptyHint:SetPoint("CENTER", ed, "CENTER")

	Label(c, "Ability (name or spell ID)", 0, 0)
	local status = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	status:SetPoint("TOPLEFT", 0, -50)
	status:SetPoint("TOPRIGHT", 0, -50)
	status:SetJustifyH("LEFT")
	local function ShowStatus()
		local t = T()
		if t.spellID then
			local name, icon = C_Spell.GetSpellName(t.spellID), C_Spell.GetSpellTexture(t.spellID)
			status:SetText(("|cff33ff99Tracking:|r |T%s:16|t %s (%d)"):format(tostring(icon or 134400), name or "?", t.spellID))
		else
			status:SetText("|cffff5555No ability selected|r - type a spell you know and press Enter")
		end
	end
	local ability = TextBox(c, 8, -18, 250, 60, function(input)
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

	Label(c, "Text", 0, -92)
	trackerWidgets.text = TextBox(c, 8, -110, 250, 80, nil, function(value)
		if T() ~= EMPTY then
			T().text = value
			ns.Apply()
		end
	end)
	trackerWidgets.text.Refresh = function(self)
		self:SetText(T().text)
		self:SetCursorPosition(0)
	end

	Label(c, "Font", 0, -148)
	trackerWidgets.font = Dropdown(c, 0, -166, 160, GetFonts, function(item)
		return T().fontPath == item.path
	end, function(item)
		T().fontPath = item.path
	end)

	Label(c, "Color", 190, -148)
	trackerWidgets.color = ColorSwatch(c, 190, -168, function()
		return T().color
	end)

	trackerWidgets.size = Slider(c, "Font size", 0, -208, 12, 96, 1, function()
		return T().fontSize
	end, function(v)
		T().fontSize = v
	end)

	trackerWidgets.outline = Checkbox(c, "Outline", 0, -256, function()
		return T().outline
	end, function(v)
		T().outline = v
	end)

	local remove = ActionButton(c, "Remove this tracker", 160, function()
		if ns.db.trackers[selected] then
			table.remove(ns.db.trackers, selected)
			selected = math.max(1, math.min(selected, #ns.db.trackers))
			ns.Apply()
			ns.RefreshConfig()
		end
	end)
	remove:SetPoint("BOTTOMLEFT", 0, 0)
end

-- Ability glow page ----------------------------------------------------------

local GLOW_ROW_HEIGHT = 30
local glowRows = {}
local glowScrollChild, glowEmptyHint

local GLOW_STATUS = {
	ready = "|cff33ff99ready - glowing|r",
	cooldown = "|cff999999on cooldown|r",
	unknown = "|cffffaa00not known|r",
}

local function GlowRowStatus(row, entry)
	row.status:SetText(entry.enabled and GLOW_STATUS[ns.SpellState(entry.spellID)] or "|cff999999off|r")
end

local function GetGlowRow(i)
	local row = glowRows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, glowScrollChild)
	row:SetHeight(GLOW_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * GLOW_ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", 0, -(i - 1) * GLOW_ROW_HEIGHT)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(24, 24)
	row.icon:SetPoint("LEFT", 4, 0)
	row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.enabled:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.enabled:SetScript("OnClick", function(self)
		local entry = ns.GlowList()[row.index]
		if entry then
			entry.enabled = self:GetChecked() and true or false
			GlowRowStatus(row, entry)
			ns.Apply()
		end
	end)
	row.remove = ActionButton(row, "Remove", 70, function()
		local list = ns.GlowList()
		if list[row.index] then
			table.remove(list, row.index)
			ns.Apply()
			ns.RefreshConfig()
		end
	end)
	row.remove:SetPoint("RIGHT", -4, 0)
	row.status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.status:SetPoint("RIGHT", row.remove, "LEFT", -10, 0)
	row.status:SetJustifyH("RIGHT")
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.enabled, "RIGHT", 2, 0)
	row.name:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	glowRows[i] = row
	return row
end

local function RefreshGlowList()
	if not glowScrollChild then
		return
	end
	local list = ns.GlowList()
	for i, entry in ipairs(list) do
		local row = GetGlowRow(i)
		row.index = i
		row.icon:SetTexture(C_Spell.GetSpellTexture(entry.spellID) or 134400)
		row.name:SetText(C_Spell.GetSpellName(entry.spellID) or tostring(entry.spellID))
		row.enabled:SetChecked(entry.enabled)
		GlowRowStatus(row, entry)
		row:Show()
	end
	for i = #list + 1, #glowRows do
		glowRows[i]:Hide()
	end
	glowScrollChild:SetHeight(math.max(1, #list * GLOW_ROW_HEIGHT))
	glowEmptyHint:SetShown(#list == 0)
end

local function BuildGlowPage()
	local className = UnitClass("player")
	local page = Page(
		"glow",
		"Ability glow",
		("Add as many %s abilities as you like: their action-bar buttons glow while the ability can be used and stop when it "
			.. "is on cooldown or out of charges."):format(className)
	)
	local p = Panel(page, "Glow abilities", function()
		return ns.db.glowEnabled
	end, function(v)
		ns.db.glowEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("BOTTOMRIGHT", 0, 0)
	widgets.glowEnabled = p.toggle
	local c = p.content

	Label(c, "Add an ability (name or spell ID)", 0, 0)
	local status = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	status:SetPoint("TOPLEFT", 270, -22)
	status:SetPoint("TOPRIGHT", 0, -22)
	status:SetJustifyH("LEFT")
	local add
	add = TextBox(c, 8, -18, 250, 60, function(input)
		if strtrim(input) == "" then
			return
		end
		local id, problem = ns.AddGlowSpell(input)
		if not id then
			status:SetText("|cffff5555Spell not found|r - use the exact name of a spell you know, or its ID")
			return
		end
		add:SetText("")
		if problem == "duplicate" then
			status:SetText("|cffffaa00Already in the list|r")
		else
			status:SetText(("|cff33ff99Added|r |T%s:16|t %s"):format(tostring(C_Spell.GetSpellTexture(id) or 134400),
				C_Spell.GetSpellName(id) or id))
		end
		ns.Apply()
		ns.RefreshConfig()
	end)
	add:SetScript("OnEditFocusGained", function()
		status:SetText("")
	end)

	local listTop = -56
	if ns.IsDeathKnight() then
		widgets.dkHeartStrikeDecay = Checkbox(c, "Heart Strike: glow while Death and Decay is on you (hits up to 5 targets)", 0, -56,
			function()
				return ns.db.dkHeartStrikeDecay
			end, function(v)
				ns.db.dkHeartStrikeDecay = v
			end)
		listTop = -92
	end

	local scroll = CreateFrame("ScrollFrame", nil, c, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, listTop)
	scroll:SetPoint("BOTTOMRIGHT", -26, 0)
	glowScrollChild = CreateFrame("Frame", nil, scroll)
	glowScrollChild:SetSize(1, 1)
	scroll:SetScrollChild(glowScrollChild)
	scroll:SetScript("OnSizeChanged", function(_, width)
		glowScrollChild:SetWidth(width)
	end)

	glowEmptyHint = Label(c, "No abilities yet - type a spell above and press Enter.", 0, listTop - 14, "GameFontHighlight")

	-- The state of each ability changes as cooldowns end, so keep the status column current while the page is showing.
	local elapsed = 0
	page:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		local list = ns.GlowList()
		for i, entry in ipairs(list) do
			if glowRows[i] then
				GlowRowStatus(glowRows[i], entry)
			end
		end
	end)

	widgets.glowList = { Refresh = RefreshGlowList }
end

-- Rage panel page ------------------------------------------------------------

local function BuildRagePage()
	local page = Page("rage", "Rage panel", "A bar showing your current rage while you are in Bear Form (optionally in Cat Form too).")
	local p = Panel(page, "Show the rage panel", function()
		return ns.db.rageEnabled
	end, function(v)
		ns.db.rageEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(320)
	widgets.rageEnabled = p.toggle
	local c = p.content

	widgets.rageWidth = Slider(c, "Width", 0, 0, 50, 600, 1, function()
		return ns.db.rageWidth
	end, function(v)
		ns.db.rageWidth = v
	end)

	widgets.rageHeight = Slider(c, "Height", 0, -56, 8, 100, 1, function()
		return ns.db.rageHeight
	end, function(v)
		ns.db.rageHeight = v
	end)

	Label(c, "Color", 0, -112)
	widgets.rageColor = ColorSwatch(c, 0, -132, function()
		return ns.db.rageColor
	end)

	widgets.rageShowText = Checkbox(c, "Show rage number", 0, -170, function()
		return ns.db.rageShowText
	end, function(v)
		ns.db.rageShowText = v
	end)

	widgets.rageCombatOnly = Checkbox(c, "Only show in combat", 0, -200, function()
		return ns.db.rageCombatOnly
	end, function(v)
		ns.db.rageCombatOnly = v
	end)

	widgets.rageGlow = Checkbox(c, "Glow when rage is full", 0, -230, function()
		return ns.db.rageGlow
	end, function(v)
		ns.db.rageGlow = v
	end)

	widgets.rageInCat = Checkbox(c, "Show rage bar also in Cat Form", 0, -260, function()
		return ns.db.rageInCat
	end, function(v)
		ns.db.rageInCat = v
	end)
end

-- Combo points page (Feral druid) ----------------------------------------------

local function BuildComboPointsPage()
	local page = Page(
		"combo",
		"Combo point bar",
		"A bar with one segment per combo point, shown while a Feral druid is in Cat Form."
	)
	local p = Panel(page, "Show the combo point bar", function()
		return ns.db.cpEnabled
	end, function(v)
		ns.db.cpEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(390)
	widgets.cpEnabled = p.toggle
	local c = p.content

	widgets.cpWidth = Slider(c, "Width", 0, 0, 50, 600, 1, function()
		return ns.db.cpWidth
	end, function(v)
		ns.db.cpWidth = v
	end)

	widgets.cpHeight = Slider(c, "Height", 0, -56, 6, 100, 1, function()
		return ns.db.cpHeight
	end, function(v)
		ns.db.cpHeight = v
	end)

	widgets.cpGap = Slider(c, "Space between points", 0, -112, 0, 20, 1, function()
		return ns.db.cpGap
	end, function(v)
		ns.db.cpGap = v
	end)

	Label(c, "Color", 0, -168)
	widgets.cpColor = ColorSwatch(c, 0, -188, function()
		return ns.db.cpColor
	end)

	widgets.cpCombatOnly = Checkbox(c, "Only show in combat", 0, -226, function()
		return ns.db.cpCombatOnly
	end, function(v)
		ns.db.cpCombatOnly = v
	end)

	widgets.cpFullHighlight = Checkbox(c, "Recolor all points at the maximum", 0, -256, function()
		return ns.db.cpFullHighlight
	end, function(v)
		ns.db.cpFullHighlight = v
	end)

	Label(c, "Color at the maximum", 0, -296)
	widgets.cpFullColor = ColorSwatch(c, 0, -316, function()
		return ns.db.cpFullColor
	end)
end

-- Energy page (Feral druid) ----------------------------------------------------

local function BuildEnergyPage()
	local page = Page(
		"energy",
		"Energy bar",
		"A bar showing your energy while a Feral druid is in Cat Form. Energy past a split line you choose is drawn in its own color."
	)
	local p = Panel(page, "Show the energy bar", function()
		return ns.db.energyEnabled
	end, function(v)
		ns.db.energyEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(380)
	widgets.energyEnabled = p.toggle
	local c = p.content

	widgets.energyWidth = Slider(c, "Width", 0, 0, 50, 600, 1, function()
		return ns.db.energyWidth
	end, function(v)
		ns.db.energyWidth = v
	end)

	widgets.energyHeight = Slider(c, "Height", 0, -56, 8, 100, 1, function()
		return ns.db.energyHeight
	end, function(v)
		ns.db.energyHeight = v
	end)

	widgets.energySplit = Slider(c, "Split line at (energy, 0 = no line)", 0, -112, 0, 150, 1, function()
		return ns.db.energySplit
	end, function(v)
		ns.db.energySplit = v
	end)

	Label(c, "Color", 0, -168)
	widgets.energyColor = ColorSwatch(c, 0, -188, function()
		return ns.db.energyColor
	end)

	Label(c, "Color past the split line", 150, -168)
	widgets.energyAboveColor = ColorSwatch(c, 150, -188, function()
		return ns.db.energyAboveColor
	end)

	widgets.energyAboveWhole = Checkbox(c, "Recolor the whole bar once energy reaches the line", 0, -226, function()
		return ns.db.energyAboveWhole
	end, function(v)
		ns.db.energyAboveWhole = v
	end)

	widgets.energyShowText = Checkbox(c, "Show energy number", 0, -256, function()
		return ns.db.energyShowText
	end, function(v)
		ns.db.energyShowText = v
	end)

	widgets.energyCombatOnly = Checkbox(c, "Only show in combat", 0, -286, function()
		return ns.db.energyCombatOnly
	end, function(v)
		ns.db.energyCombatOnly = v
	end)
end

-- Runic power page (Death Knight) ----------------------------------------------

local function BuildRunicPowerPage()
	local page = Page(
		"runic",
		"Runic power bar",
		"A bar showing your runic power, with a split line at a percentage of the bar you choose. The bar glows once runic power reaches that line."
	)
	local p = Panel(page, "Show the runic power bar", function()
		return ns.db.rpEnabled
	end, function(v)
		ns.db.rpEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(380)
	widgets.rpEnabled = p.toggle
	local c = p.content

	widgets.rpWidth = Slider(c, "Width", 0, 0, 50, 600, 1, function()
		return ns.db.rpWidth
	end, function(v)
		ns.db.rpWidth = v
	end)

	widgets.rpHeight = Slider(c, "Height", 0, -56, 8, 100, 1, function()
		return ns.db.rpHeight
	end, function(v)
		ns.db.rpHeight = v
	end)

	widgets.rpPercent = Slider(c, "Split line and glow at (% of the bar)", 0, -112, 1, 100, 1, function()
		return ns.db.rpPercent
	end, function(v)
		ns.db.rpPercent = v
	end)

	Label(c, "Color", 0, -168)
	widgets.rpColor = ColorSwatch(c, 0, -188, function()
		return ns.db.rpColor
	end)

	widgets.rpShowText = Checkbox(c, "Show runic power number", 0, -226, function()
		return ns.db.rpShowText
	end, function(v)
		ns.db.rpShowText = v
	end)

	widgets.rpCombatOnly = Checkbox(c, "Only show in combat", 0, -256, function()
		return ns.db.rpCombatOnly
	end, function(v)
		ns.db.rpCombatOnly = v
	end)

	widgets.rpGlow = Checkbox(c, "Glow when at or above the split line", 0, -286, function()
		return ns.db.rpGlow
	end, function(v)
		ns.db.rpGlow = v
	end)
end

-- Bone Shield page (Death Knight) ----------------------------------------------

local function BuildBoneShieldPage()
	local page = Page(
		"bone",
		"Bone Shield",
		"An icon with your Bone Shield stacks and the time left. The game itself draws it, so it keeps working in combat when addons cannot see the buff."
	)
	local p = Panel(page, "Show the Bone Shield tracker", function()
		return ns.db.bsEnabled
	end, function(v)
		ns.db.bsEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(400)
	widgets.bsEnabled = p.toggle
	local c = p.content

	widgets.bsSize = Slider(c, "Icon size", 0, 0, 24, 200, 1, function()
		return ns.db.bsSize
	end, function(v)
		ns.db.bsSize = v
	end)

	widgets.bsStackFontSize = Slider(c, "Stack font size", 0, -56, 8, 96, 1, function()
		return ns.db.bsStackFontSize
	end, function(v)
		ns.db.bsStackFontSize = v
	end)

	widgets.bsTimerFontSize = Slider(c, "Time font size", 0, -112, 8, 96, 1, function()
		return ns.db.bsTimerFontSize
	end, function(v)
		ns.db.bsTimerFontSize = v
	end)

	widgets.bsTimerDecimals = Slider(c, "Tenths of a second below (0 = whole seconds)", 0, -168, 0, 10, 1, function()
		return ns.db.bsTimerDecimals
	end, function(v)
		ns.db.bsTimerDecimals = v
	end)

	widgets.bsLowSeconds = Slider(c, "Time turns red at or below (0 = never)", 0, -224, 0, 30, 1, function()
		return ns.db.bsLowSeconds
	end, function(v)
		ns.db.bsLowSeconds = v
	end)

	widgets.bsShowStacks = Checkbox(c, "Show stack count", 300, 0, function()
		return ns.db.bsShowStacks
	end, function(v)
		ns.db.bsShowStacks = v
	end)

	widgets.bsShowTimer = Checkbox(c, "Show time left", 300, -30, function()
		return ns.db.bsShowTimer
	end, function(v)
		ns.db.bsShowTimer = v
	end)

	widgets.bsSwipe = Checkbox(c, "Cooldown swipe on the icon", 300, -60, function()
		return ns.db.bsSwipe
	end, function(v)
		ns.db.bsSwipe = v
	end)

	widgets.bsCombatOnly = Checkbox(c, "Only show in combat", 300, -90, function()
		return ns.db.bsCombatOnly
	end, function(v)
		ns.db.bsCombatOnly = v
	end)

	local hint = Label(c, "Fonts and the checkboxes above are built into the display, so a change shows a moment after you stop. Use Unlock to move it.",
		0, -290, "GameFontHighlightSmall")
	hint:SetPoint("TOPRIGHT", 0, -290)
	hint:SetJustifyH("LEFT")
end

-- External defensives page ---------------------------------------------------

local EXTDEF_ROW_HEIGHT = 34
local EXTDEF_ROW_WIDTH = 200
local extDefRows = {}

local function ClassLabel(class)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
	return color and ("|c%s%s|r"):format(color.colorStr, name) or name
end

-- The settings area is narrow (about 430 wide), so this page is one column: the look on top, the choice of spells below.
local function BuildExtDefPage()
	local page = Page(
		"extdef",
		"External defensives",
		"Big defensives other players put on you, as icons with the time left. The game draws them, so it works in combat."
	)
	local p = Panel(page, "Show external defensives", function()
		return ns.db.edEnabled
	end, function(v)
		ns.db.edEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("BOTTOMRIGHT", 0, 0)
	widgets.edEnabled = p.toggle
	local c = p.content

	widgets.edSize = Slider(c, "Icon size", 0, 0, 24, 120, 1, function()
		return ns.db.edSize
	end, function(v)
		ns.db.edSize = v
	end)
	widgets.edMax = Slider(c, "Icons shown at once", 0, -52, 1, 8, 1, function()
		return ns.db.edMax
	end, function(v)
		ns.db.edMax = v
	end)
	widgets.edTimerFontSize = Slider(c, "Time font size", 0, -104, 8, 48, 1, function()
		return ns.db.edTimerFontSize
	end, function(v)
		ns.db.edTimerFontSize = v
	end)

	-- Beside the sliders, with short labels so they fit
	local CX = 276
	widgets.edShowTimer = Checkbox(c, "Show time", CX, 0, function()
		return ns.db.edShowTimer
	end, function(v)
		ns.db.edShowTimer = v
	end)
	widgets.edSwipe = Checkbox(c, "Swipe", CX, -30, function()
		return ns.db.edSwipe
	end, function(v)
		ns.db.edSwipe = v
	end)
	widgets.edGlow = Checkbox(c, "Glow on icons", CX, -90, function()
		return ns.db.edGlow
	end, function(v)
		ns.db.edGlow = v
	end)
	widgets.edCombatOnly = Checkbox(c, "Combat only", CX, -120, function()
		return ns.db.edCombatOnly
	end, function(v)
		ns.db.edCombatOnly = v
	end)
	local hint = Label(c, "Size, font, time, swipe and glow apply a moment after you stop. Use Unlock to move it.", 0, -150,
		"GameFontHighlightSmall")
	hint:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -150)
	hint:SetJustifyH("LEFT")

	-- Which defensives
	Label(c, "Show these defensives", 0, -178, "GameFontNormalLarge")
	local x = 0
	for _, preset in ipairs({ { "Select all", "all" }, { "Deselect all", "none" }, { "Healers only", "healers" } }) do
		local b = ActionButton(c, preset[1], 96, function()
			ns.ExtDefPreset(preset[2])
		end)
		b:SetPoint("TOPLEFT", x, -204)
		x = x + 100
	end
	widgets.edOthers = Checkbox(c, "Also show defensives not in this list", -4, -234, function()
		return ns.db.edOthers
	end, function(v)
		ns.db.edOthers = v
	end)

	-- Two columns of rows, in a scroll frame in case the list grows
	local scroll = CreateFrame("ScrollFrame", nil, c, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -266)
	scroll:SetPoint("BOTTOMRIGHT", -26, 0)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(EXTDEF_ROW_WIDTH * 2, 1)
	scroll:SetScrollChild(child)

	for i, e in ipairs(ns.EXTDEF_CATALOG) do
		local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
		local row = CreateFrame("Frame", nil, child)
		row:SetSize(EXTDEF_ROW_WIDTH, EXTDEF_ROW_HEIGHT)
		row:SetPoint("TOPLEFT", col * EXTDEF_ROW_WIDTH, -line * EXTDEF_ROW_HEIGHT)
		row.entry = e
		row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.check:SetSize(24, 24)
		row.check:SetPoint("LEFT", 0, 0)
		row.check:SetScript("OnClick", function(self)
			ns.db.edOff[e.ids[1]] = (not self:GetChecked()) or nil
			ns.Apply()
		end)
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(26, 26)
		icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
		icon:SetTexture(C_Spell.GetSpellTexture(e.ids[1]) or 134400)
		local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, 0)
		name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		name:SetText(C_Spell.GetSpellName(e.ids[1]) or e.name)
		local detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 5, 0)
		detail:SetText(ClassLabel(e.class) .. (e.healer and "  |cff33ff99healer|r" or ""))
		extDefRows[i] = row
	end
	child:SetHeight(math.ceil(#ns.EXTDEF_CATALOG / 2) * EXTDEF_ROW_HEIGHT)

	widgets.edList = {
		Refresh = function()
			for _, row in ipairs(extDefRows) do
				row.check:SetChecked(not ns.db.edOff[row.entry.ids[1]])
			end
		end,
	}
end

-- Absorb page ----------------------------------------------------------------

local function BuildAbsorbPage()
	local druid = ns.IsDruid()
	local page = Page(
		"absorb",
		"Absorb shield",
		druid and "Shows a Power Word: Shield icon with your total absorb (Frenzied Regeneration and any other absorbs) while you have one."
			or "Shows a Power Word: Shield icon with your total absorb while you have one."
	)
	local p = Panel(page, "Show the absorb icon", function()
		return ns.db.absorbEnabled
	end, function(v)
		ns.db.absorbEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(druid and 230 or 170)
	widgets.absorbEnabled = p.toggle
	local c = p.content

	widgets.absorbSize = Slider(c, "Icon size", 0, 0, 24, 200, 1, function()
		return ns.db.absorbSize
	end, function(v)
		ns.db.absorbSize = v
	end)

	widgets.absorbFontSize = Slider(c, "Font size", 0, -56, 8, 96, 1, function()
		return ns.db.absorbFontSize
	end, function(v)
		ns.db.absorbFontSize = v
	end)

	if druid then
		widgets.absorbFrenziedOnly = Checkbox(c, "Only while Frenzied Regeneration is active", 0, -112, function()
			return ns.db.absorbFrenziedOnly
		end, function(v)
			ns.db.absorbFrenziedOnly = v
		end)
	end
end

-- Voice reminders page -------------------------------------------------------

local function SpeakOrReport(text)
	local ok, err = ns.Speak(text)
	if not ok then
		ns.Print("voice failed: " .. err)
	end
end

local function VoiceItems()
	local items = { { name = "Automatic" } }
	for _, voice in ipairs(ns.GetVoices()) do
		items[#items + 1] = { name = ns.ShortVoiceName(voice.name), voiceName = voice.name }
	end
	return items
end

local function TrinketItems()
	local items = { { name = "None" } }
	local found = false
	for _, t in ipairs(ns.GetUseTrinkets()) do
		local where = t.where == "bags" and " |cff888888(bags)|r" or ""
		items[#items + 1] = { itemID = t.itemID, name = ("|T%s:16|t %s%s"):format(tostring(t.icon or 134400), t.name, where) }
		found = found or t.itemID == ns.db.trinketItemID
	end
	-- Keep the current pick listed (and the dropdown labelled) after it left the character.
	local id = ns.db.trinketItemID
	if id and not found then
		local name = C_Item.GetItemNameByID(id) or ("item " .. id)
		items[#items + 1] = { itemID = id, name = name .. " |cff888888(not on character)|r" }
	end
	return items
end

local function BuildRemindersPage()
	local page = Page(
		"reminders",
		"Voice reminders",
		ns.IsDruid() and "Text-to-speech callouts when a cooldown is ready again or a proc happens."
			or ns.IsDeathKnight() and "A callout when Dancing Rune Weapon comes up, and a text-to-speech callout and action-bar glow when your on-use trinket is ready again."
			or "Text-to-speech callout and action-bar glow when your on-use trinket is ready again."
	)

	local v = Panel(page, "Voice")
	v:SetPoint("TOPLEFT", 0, PAGE_TOP)
	v:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	v:SetHeight(110)
	widgets.voice = Dropdown(v.content, 0, 0, 220, VoiceItems, function(item)
		return item.voiceName == ns.db.voiceName
	end, function(item)
		ns.db.voiceName = item.voiceName
		SpeakOrReport("Trinket ready")
	end)
	local test = ActionButton(v.content, "Test", 80, function()
		SpeakOrReport("Trinket ready")
	end)
	test:SetPoint("TOPLEFT", 240, 0)
	local hint = Label(v.content, "Automatic uses the voice picked in MonroMDTTrack, otherwise the best installed one.", 0, -36,
		"GameFontHighlightSmall")
	hint:SetPoint("TOPRIGHT", 0, -36)
	hint:SetJustifyH("LEFT")

	local t = Panel(page, "Trinket")
	t:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -12)
	t:SetPoint("TOPRIGHT", v, "BOTTOMRIGHT", 0, -12)
	t:SetHeight(165)
	Label(t.content, "On-use trinket", 0, 0)
	widgets.trinket = Dropdown(t.content, 0, -18, 300, TrinketItems, function(item)
		return item.itemID == ns.db.trinketItemID
	end, function(item)
		ns.db.trinketItemID = item.itemID
		widgets.trinketStatus:Refresh()
	end)
	widgets.trinketEnabled = Checkbox(t.content, "Say \"Trinket ready\"", 0, -50, function()
		return ns.db.trinketEnabled
	end, function(value)
		ns.db.trinketEnabled = value
		RefreshNav()
	end)
	widgets.trinketGlow = Checkbox(t.content, "Glow on action bars while ready", 220, -50, function()
		return ns.db.trinketGlow
	end, function(value)
		ns.db.trinketGlow = value
		RefreshNav()
	end)
	widgets.trinketStatus = Label(t.content, "", 0, -86, "GameFontHighlight")
	widgets.trinketStatus.Refresh = function(self)
		local id = ns.db.trinketItemID
		if not id then
			self:SetText("|cffff5555No trinket selected|r - only trinkets with a Use: effect are listed")
		elseif C_Item.IsEquippedItem(id) then
			self:SetText("|cff33ff99Equipped|r - the glow is previewed on its action button while this panel is open")
		else
			self:SetText("|cffffaa00Not equipped|r - no reminder or glow until you equip it")
		end
	end

	if ns.IsDeathKnight() then
		local w = Panel(page, "Dancing Rune Weapon", function()
			return ns.db.weaponEnabled
		end, function(value)
			ns.db.weaponEnabled = value
		end)
		w:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
		w:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, -12)
		w:SetHeight(95)
		widgets.weaponEnabled = w.toggle
		local weaponTest = ActionButton(w, "Test", 60, function()
			PlaySoundFile(ns.WEAPON_SOUND, "Master")
		end)
		weaponTest:SetPoint("TOPRIGHT", -8, -8)
		local weaponText = Label(w.content, "Says \"Weapon\" when Dancing Rune Weapon comes up, whether you cast it or a talent triggers it.",
			0, 0, "GameFontHighlight")
		weaponText:SetPoint("TOPRIGHT")
		weaponText:SetJustifyH("LEFT")
	end

	if not ns.IsDruid() then
		return -- Heart of the Wild and Apex are Druid-only
	end

	-- Heart of the Wild and Apex share a row.
	local h = Panel(page, "Heart of the Wild ready", function()
		return ns.db.heartEnabled
	end, function(value)
		ns.db.heartEnabled = value
	end)
	h:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
	h:SetPoint("TOPRIGHT", t, "BOTTOM", -6, -12)
	h:SetHeight(95)
	widgets.heartEnabled = h.toggle
	widgets.heartStatus = Label(h.content, "", 0, 0, "GameFontHighlight")
	widgets.heartStatus:SetPoint("TOPRIGHT")
	widgets.heartStatus:SetJustifyH("LEFT")
	widgets.heartStatus.Refresh = function(self)
		if ns.KnownHeartOfTheWild() then
			self:SetText("|cff33ff99Talented|r - says \"Heart of the Wild ready\" when its cooldown ends")
		else
			self:SetText("|cffffaa00Not talented|r - no reminder until you take it")
		end
	end

	local a = Panel(page, "Apex proc", function()
		return ns.db.apexEnabled
	end, function(value)
		ns.db.apexEnabled = value
	end)
	a:SetPoint("TOPLEFT", t, "BOTTOM", 6, -12)
	a:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, -12)
	a:SetHeight(95)
	widgets.apexEnabled = a.toggle
	local apexTest = ActionButton(a, "Test", 60, function()
		PlaySoundFile(ns.APEX_SOUND, "Master")
	end)
	apexTest:SetPoint("TOPRIGHT", -8, -8)
	local apexText = Label(a.content, "Says \"Apex\" when Wild Guardian awakens a spirit (Answered Calling).", 0, 0,
		"GameFontHighlight")
	apexText:SetPoint("TOPRIGHT")
	apexText:SetJustifyH("LEFT")
end

-- Enrage panel page ----------------------------------------------------------

local function BuildEnragePage()
	local page = Page(
		"enrage",
		"Enrage panel",
		"Lists the enemies that are enraged right now, so you know which one to cast Soothe on. Needs enemy nameplates turned on."
	)
	local p = Panel(page, "Show the enrage panel", function()
		return ns.db.enrageEnabled
	end, function(v)
		ns.db.enrageEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(390)
	widgets.enrageEnabled = p.toggle
	local c = p.content

	widgets.enrageWidth = Slider(c, "Panel width", 0, 0, 160, 400, 1, function()
		return ns.db.enrageWidth
	end, function(v)
		ns.db.enrageWidth = v
	end)

	widgets.enrageRows = Slider(c, "Mobs listed", 0, -56, 1, 6, 1, function()
		return ns.db.enrageRows
	end, function(v)
		ns.db.enrageRows = v
	end)

	widgets.enrageMarkerSize = Slider(c, "Nameplate marker size", 0, -112, 24, 96, 1, function()
		return ns.db.enrageMarkerSize
	end, function(v)
		ns.db.enrageMarkerSize = v
	end)

	-- Beside the marker size, so a marker that collides with your raid markers is a one-click fix.
	Label(c, "Marker position", 300, -112)
	widgets.enrageMarkerSide = Dropdown(c, 300, -130, 190, function()
		return ns.MARKER_SIDES
	end, function(item)
		return ns.db.enrageMarkerSide == item.key
	end, function(item)
		ns.db.enrageMarkerSide = item.key
	end)

	-- What the marker shows: only buffs you can Soothe, or any dispellable buff (the fallback if "mine" shows nothing).
	Label(c, "Marker shows", 300, -56)
	widgets.enrageMarkerFilter = Dropdown(c, 300, -74, 190, function()
		return ns.MARKER_FILTERS
	end, function(item)
		return ns.db.enrageMarkerFilter == item.key
	end, function(item)
		ns.db.enrageMarkerFilter = item.key
	end)

	widgets.enrageSay = Checkbox(c, "Say \"Soothe\" when a mob enrages", 0, -170, function()
		return ns.db.enrageSay
	end, function(v)
		ns.db.enrageSay = v
	end)
	local test = ActionButton(c, "Test", 60, function()
		SpeakOrReport("Soothe")
	end)
	test:SetPoint("TOPLEFT", 300, -172)

	widgets.enrageMarker = Checkbox(c, "Mark the mob's nameplate", 0, -200, function()
		return ns.db.enrageMarker
	end, function(v)
		ns.db.enrageMarker = v
	end)

	widgets.enrageStatus = Label(c, "", 0, -244, "GameFontHighlight")
	widgets.enrageStatus:SetPoint("TOPRIGHT", 0, -244)
	widgets.enrageStatus:SetJustifyH("LEFT")
	widgets.enrageStatus.Refresh = function(self)
		if ns.KnowsSoothe and ns.KnowsSoothe() then
			self:SetText("|cff33ff99Soothe known|r - the panel appears while an enemy nameplate carries an enrage")
		else
			self:SetText("|cffffaa00Soothe not found in your spellbook|r - the panel stays hidden until you have it")
		end
	end

	local hint = Label(c, "The marker is drawn by the game itself, so it works in combat inside dungeons. The list and the voice "
		.. "need the addon to read the mob: they always work out of combat and in the open world, and in dungeon combat only "
		.. "when the marker's size can be read. /mtr enragedebug shows what each nameplate reports.", 0, -272,
		"GameFontHighlightSmall")
	hint:SetPoint("TOPRIGHT", 0, -272)
	hint:SetJustifyH("LEFT")
end

-- Dispel page ----------------------------------------------------------------

local function BuildDispelPage()
	local page = Page(
		"dispel",
		"Dispel",
		"Says what to dispel when someone in your group has it and your dispel is ready. Remove Corruption (Nature's Cure) removes poison and curse."
	)
	local p = Panel(page, "Dispel callouts", function()
		return ns.db.dispelEnabled
	end, function(v)
		ns.db.dispelEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(350)
	widgets.dispelEnabled = p.toggle
	local c = p.content

	widgets.dispelPoison = Checkbox(c, "Say \"Dispel poison\"", 0, 0, function()
		return ns.db.dispelPoison
	end, function(v)
		ns.db.dispelPoison = v
	end)
	local poisonTest = ActionButton(c, "Test", 60, function()
		SpeakOrReport("Dispel poison")
	end)
	poisonTest:SetPoint("TOPLEFT", 300, -2)

	widgets.dispelCurse = Checkbox(c, "Say \"Dispel curse\"", 0, -32, function()
		return ns.db.dispelCurse
	end, function(v)
		ns.db.dispelCurse = v
	end)
	local curseTest = ActionButton(c, "Test", 60, function()
		SpeakOrReport("Dispel curse")
	end)
	curseTest:SetPoint("TOPLEFT", 300, -34)

	widgets.dispelSelf = Checkbox(c, "Also announce debuffs on myself", 0, -72, function()
		return ns.db.dispelSelf
	end, function(v)
		ns.db.dispelSelf = v
	end)

	widgets.dispelCombatOnly = Checkbox(c, "Only in combat", 0, -102, function()
		return ns.db.dispelCombatOnly
	end, function(v)
		ns.db.dispelCombatOnly = v
	end)

	widgets.dispelStatus = Label(c, "", 0, -146, "GameFontHighlight")
	widgets.dispelStatus:SetPoint("TOPRIGHT", 0, -146)
	widgets.dispelStatus:SetJustifyH("LEFT")
	widgets.dispelStatus.Refresh = function(self)
		if ns.KnowsDispel and ns.KnowsDispel() then
			self:SetText("|cff33ff99Dispel known|r - announced when it is off cooldown and a group member in range carries a debuff you can remove")
		else
			self:SetText("|cffffaa00Remove Corruption not found in your spellbook|r - no callouts until you have it")
		end
	end

	local hint = Label(c, "The callout repeats every few seconds while the debuff stays and your dispel is ready, and stops "
		.. "while the dispel is on cooldown. Out of combat and in the open world the addon reads each member's debuffs. "
		.. "In dungeon combat the client hides them, so the addon asks the game to filter by dispel type instead; whether "
		.. "that stays readable there is what /mtr dispeldebug shows.", 0, -196, "GameFontHighlightSmall")
	hint:SetPoint("TOPRIGHT", 0, -196)
	hint:SetJustifyH("LEFT")
end

-- Main panel -----------------------------------------------------------------

local function BuildMainPanel()
	panel = CreateFrame("Frame")
	panel.name = "MonroTracker"

	-- Sidebar: feature navigation, with the always-needed positioning buttons at the bottom
	local nav = CreateFrame("Frame", nil, panel)
	nav:SetPoint("TOPLEFT", 16, -16)
	nav:SetPoint("BOTTOMLEFT", 16, 16)
	nav:SetWidth(NAV_WIDTH)
	Label(nav, "MonroTracker", 0, 0, "GameFontNormalHuge")

	-- Druid-only features get no sidebar entry (or page) on other classes.
	local druid = ns.IsDruid()
	local navY = -44
	local function Nav(key, label, isOn)
		NavItem(nav, key, label, navY, isOn)
		navY = navY - 30
	end

	Nav("general", "General")
	if druid then
		Nav("bear", "Bear Form text", function()
			return ns.db.textEnabled
		end)
		Nav("indicator", "Moonfire indicator", function()
			return ns.db.indicatorEnabled
		end)
	end
	Nav("trackers", "Ability trackers", function()
		return ns.db.trackersEnabled
	end)
	Nav("glow", "Ability glow", function()
		return ns.db.glowEnabled
	end)
	if druid then
		Nav("rage", "Rage panel", function()
			return ns.db.rageEnabled
		end)
		Nav("combo", "Combo point bar", function()
			return ns.db.cpEnabled
		end)
		Nav("energy", "Energy bar", function()
			return ns.db.energyEnabled
		end)
		Nav("enrage", "Enrage panel", function()
			return ns.db.enrageEnabled
		end)
		Nav("dispel", "Dispel", function()
			return ns.db.dispelEnabled
		end)
	end
	if ns.IsDeathKnight() then
		Nav("runic", "Runic power bar", function()
			return ns.db.rpEnabled
		end)
		Nav("bone", "Bone Shield", function()
			return ns.db.bsEnabled
		end)
	end
	Nav("extdef", "External defensives", function()
		return ns.db.edEnabled
	end)
	Nav("absorb", "Absorb shield", function()
		return ns.db.absorbEnabled
	end)
	Nav("reminders", "Voice reminders", function()
		local db = ns.db
		return db.trinketEnabled or db.trinketGlow or (druid and (db.heartEnabled or db.apexEnabled))
			or (ns.IsDeathKnight() and db.weaponEnabled)
	end)

	local reset = ActionButton(nav, "Reset all", NAV_WIDTH, function()
		ns.ResetAll()
	end)
	reset:SetPoint("BOTTOMLEFT", 0, 0)
	widgets.unlock = ActionButton(nav, "", NAV_WIDTH, function()
		ns.SetUnlocked(not ns.unlocked)
	end)
	widgets.unlock:SetPoint("BOTTOMLEFT", reset, "TOPLEFT", 0, 6)
	widgets.unlock.Refresh = function(self)
		self:SetText(ns.unlocked and "Lock" or "Unlock to move")
	end

	local sep = panel:CreateTexture(nil, "ARTWORK")
	sep:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
	sep:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", 8, 0)
	sep:SetWidth(1)
	sep:SetColorTexture(1, 1, 1, 0.12)

	content = CreateFrame("Frame", nil, panel)
	content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 24, 0)
	content:SetPoint("BOTTOMRIGHT", -16, 16)

	BuildGeneralPage()
	if druid then
		BuildBearPage()
		BuildIndicatorPage()
	end
	BuildTrackerPage()
	BuildGlowPage()
	if druid then
		BuildRagePage()
		BuildComboPointsPage()
		BuildEnergyPage()
	end
	if ns.IsDeathKnight() then
		BuildRunicPowerPage()
		BuildBoneShieldPage()
	end
	BuildExtDefPage()
	BuildAbsorbPage()
	BuildRemindersPage()
	if druid then
		BuildEnragePage()
		BuildDispelPage()
	end
	SelectPage(currentPage)

	TrackConfigVisibility(panel)
end

-- Public ---------------------------------------------------------------------

function ns.RefreshConfig()
	if not panel then
		return
	end
	selected = math.max(1, math.min(selected, math.max(1, #ns.db.trackers)))
	for key, w in pairs(widgets) do
		-- One widget failing must not leave the rest of the window unrefreshed (blank sliders, no status dots).
		local ok, err = pcall(w.Refresh, w)
		if not ok and not refreshReported[key] then
			refreshReported[key] = true
			ns.Print(("settings widget '%s' failed to refresh: %s"):format(tostring(key), tostring(err)))
		end
	end
	RefreshNav()
	UpdateListButtons()
	local hasTracker = ns.db.trackers[selected] ~= nil
	editorPanel:SetShown(hasTracker)
	emptyHint:SetShown(not hasTracker)
	if hasTracker then
		for _, w in pairs(trackerWidgets) do
			w:Refresh()
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
	category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)
end
