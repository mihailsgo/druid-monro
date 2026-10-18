local ADDON_NAME, ns = ...

local panel, category
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
	local page = Page("general", "General", "Settings that are not tied to a single feature.")

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
		"|cff33ff99/druidm|r  open these settings\n"
			.. "|cff33ff99/druidm unlock|r  show and drag every element (run again to lock)\n"
			.. "|cff33ff99/druidm minimap|r  show or hide the minimap button\n"
			.. "|cff33ff99/druidm reset|r  reset all settings and positions"
	)
end

local function BuildBearPage()
	local page = Page("bear", "Bear Form text", "Warns you while you are not in Bear Form.")
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

-- Rage panel page ------------------------------------------------------------

local function BuildRagePage()
	local page = Page("rage", "Rage panel", "A bar showing your current rage while you are in Bear Form.")
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
end

-- Absorb page ----------------------------------------------------------------

local function BuildAbsorbPage()
	local page = Page(
		"absorb",
		"Absorb shield",
		"Shows a Power Word: Shield icon with your total absorb (Frenzied Regeneration and any other absorbs) while you have one."
	)
	local p = Panel(page, "Show the absorb icon", function()
		return ns.db.absorbEnabled
	end, function(v)
		ns.db.absorbEnabled = v
	end)
	p:SetPoint("TOPLEFT", 0, PAGE_TOP)
	p:SetPoint("TOPRIGHT", 0, PAGE_TOP)
	p:SetHeight(230)
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

	widgets.absorbFrenziedOnly = Checkbox(c, "Only while Frenzied Regeneration is active", 0, -112, function()
		return ns.db.absorbFrenziedOnly
	end, function(v)
		ns.db.absorbFrenziedOnly = v
	end)
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
		"Text-to-speech callouts when a cooldown is ready again or a proc happens."
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

-- Main panel -----------------------------------------------------------------

local function BuildMainPanel()
	panel = CreateFrame("Frame")
	panel.name = "DruidMonro"

	-- Sidebar: feature navigation, with the always-needed positioning buttons at the bottom
	local nav = CreateFrame("Frame", nil, panel)
	nav:SetPoint("TOPLEFT", 16, -16)
	nav:SetPoint("BOTTOMLEFT", 16, 16)
	nav:SetWidth(NAV_WIDTH)
	Label(nav, "DruidMonro", 0, 0, "GameFontNormalHuge")

	NavItem(nav, "general", "General", -44)
	NavItem(nav, "bear", "Bear Form text", -74, function()
		return ns.db.textEnabled
	end)
	NavItem(nav, "indicator", "Moonfire indicator", -104, function()
		return ns.db.indicatorEnabled
	end)
	NavItem(nav, "trackers", "Ability trackers", -134, function()
		return ns.db.trackersEnabled
	end)
	NavItem(nav, "rage", "Rage panel", -164, function()
		return ns.db.rageEnabled
	end)
	NavItem(nav, "absorb", "Absorb shield", -194, function()
		return ns.db.absorbEnabled
	end)
	NavItem(nav, "reminders", "Voice reminders", -224, function()
		local db = ns.db
		return db.trinketEnabled or db.trinketGlow or db.heartEnabled or db.apexEnabled
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
	BuildBearPage()
	BuildIndicatorPage()
	BuildTrackerPage()
	BuildRagePage()
	BuildAbsorbPage()
	BuildRemindersPage()
	SelectPage(currentPage)

	TrackConfigVisibility(panel)
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
