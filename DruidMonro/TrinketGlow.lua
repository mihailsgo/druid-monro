local ADDON_NAME, ns = ...

-- Glows the selected trinket, and the abilities on the Glow page (AbilityGlow.lua), on action bars (placed directly or
-- through a macro) while they can be used. Supports the default bars, ButtonForge, and LibActionButton bars (Bartender4, ElvUI).

local GCD_THRESHOLD = 1.5
local RESCAN_INTERVAL = 2 -- ButtonForge changes fire no event
local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local BAR_PREFIXES = {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarRightButton",
	"MultiBarLeftButton",
	"MultiBar5Button",
	"MultiBar6Button",
	"MultiBar7Button",
}
local LAB_VERSIONS = { "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }

local buttonItem = {} -- button -> itemID its action uses (rebuilt by Rescan)
local buttonSpell = {} -- button -> spellID its action casts
local buttonSpellName = {} -- button -> that spell's name
local buttonSource = {} -- button -> bar addon name, for /druidm glowdebug
local glows = {} -- button -> glow frame

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function HasProcAtlas()
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(PROC_ATLAS) ~= nil
end

-- itemID, spellID for a GetActionInfo-style ("item", id) / ("spell", id) / ("macro", index) pair; nil for what is not there.
local function ResolveAction(actionType, id)
	if IsSecret(actionType) or IsSecret(id) then
		return nil
	end
	if actionType == "item" then
		return tonumber(id) or (type(id) == "string" and tonumber(id:match("item:(%d+)"))) or nil
	elseif actionType == "spell" then
		return nil, tonumber(id)
	elseif actionType == "macro" then
		local item, spell
		if GetMacroItem then
			local ok, _, link = pcall(GetMacroItem, id) -- also resolves "/use 13"
			if ok and link then
				item = (C_Item.GetItemInfoInstant(link))
			end
		end
		if GetMacroSpell then
			local ok, spellID = pcall(GetMacroSpell, id) -- the spell a "/cast" macro currently casts
			if ok and spellID and not IsSecret(spellID) then
				spell = spellID
			end
		end
		return item, spell
	end
end

local function SlotAction(slot)
	if not slot or IsSecret(slot) then
		return nil
	end
	return ResolveAction(GetActionInfo(slot))
end

local function CollectBlizzard(add)
	for _, prefix in ipairs(BAR_PREFIXES) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then
				local slot = button.action
				if not slot and button.CalculateAction then
					slot = button:CalculateAction()
				end
				add(button, "Blizzard", SlotAction(slot))
			end
		end
	end
end

local function CollectLibActionButton(add)
	if not LibStub then
		return
	end
	for _, major in ipairs(LAB_VERSIONS) do
		local lab = LibStub(major, true)
		if lab and lab.buttonRegistry then
			for button in pairs(lab.buttonRegistry) do
				local kind, action = button._state_type, button._state_action
				if kind == "action" then
					add(button, major, SlotAction(action))
				elseif kind == "item" or kind == "spell" or kind == "macro" then
					add(button, major, ResolveAction(kind, action))
				end
			end
		end
	end
end

local function CollectButtonForge(add)
	local bf = ButtonForge_API1
	if not (bf and bf.GetButtonFrameNames and bf.GetButtonActionInfo) then
		return
	end
	for _, name in ipairs(bf.GetButtonFrameNames()) do
		local button = _G[name]
		if button then
			add(button, "ButtonForge", ResolveAction(bf.GetButtonActionInfo(name)))
		end
	end
end

local function Rescan()
	wipe(buttonItem)
	wipe(buttonSpell)
	wipe(buttonSpellName)
	wipe(buttonSource)
	local function add(button, source, itemID, spellID)
		buttonSource[button] = source
		buttonItem[button] = itemID
		buttonSpell[button] = spellID
		if spellID then
			local name = C_Spell.GetSpellName(spellID)
			buttonSpellName[button] = name and not IsSecret(name) and name or nil
		end
	end
	-- Each source on its own, so one bar addon misbehaving does not hide the others.
	for _, collect in ipairs({ CollectBlizzard, CollectLibActionButton, CollectButtonForge }) do
		local ok, err = pcall(collect, add)
		if not ok and ns.glowDebugErrors then
			ns.Print("glow scan error: " .. tostring(err))
		end
	end
end

-- Bars update their own actions in the same event, so rescan once they are done.
local rescanPending = false
local function QueueRescan()
	if not rescanPending then
		rescanPending = true
		C_Timer.After(0, function()
			rescanPending = false
			Rescan()
			ns.UpdateGlows()
		end)
	end
end

-- The trinket's itemID while it should glow, else nil (plus a reason, for /druidm glowdebug).
local function GlowingItem()
	local db = ns.db
	local id = db.trinketItemID
	if not db.trinketGlow then
		return nil, "glow is turned off"
	elseif not id then
		return nil, "no trinket selected"
	elseif not C_Item.IsEquippedItem(id) then
		return nil, "trinket not equipped"
	end
	if ns.IsPreview() then
		return id, "preview (settings open / unlocked)"
	end
	local start, duration, enabled = C_Item.GetItemCooldown(id)
	if IsSecret(start) or IsSecret(duration) or IsSecret(enabled) then
		-- Hidden cooldown: trust the voice reminder's estimate.
		if ns.TrinketCooling() == false then
			return id, "cooldown hidden, estimated ready"
		end
		return nil, "cooldown hidden, estimated on cooldown"
	end
	if enabled == false or enabled == 0 then
		return nil, "cooldown waiting to start"
	end
	if not start or start == 0 or not duration or duration <= GCD_THRESHOLD then
		return id, "ready"
	end
	return nil, ("on cooldown, %.0fs left"):format(start + duration - GetTime())
end

local function GetGlow(button)
	local g = glows[button]
	if g then
		return g
	end
	g = CreateFrame("Frame", nil, button)
	g:SetPoint("CENTER")
	g:SetFrameLevel(button:GetFrameLevel() + 10)
	g.tex = g:CreateTexture(nil, "OVERLAY")
	g.tex:SetAllPoints()
	g.anim = g.tex:CreateAnimationGroup()
	if HasProcAtlas() then
		-- Blizzard-style spell-alert flipbook, as on procced spells.
		g.tex:SetAtlas(PROC_ATLAS)
		g.scale = 1.4
		g.anim:SetLooping("REPEAT")
		local flip = g.anim:CreateAnimation("FlipBook")
		flip:SetFlipBookRows(6)
		flip:SetFlipBookColumns(5)
		flip:SetFlipBookFrames(30)
		flip:SetDuration(1)
	else
		g.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		g.tex:SetBlendMode("ADD")
		g.scale = 1.8
		g.anim:SetLooping("BOUNCE")
		local fade = g.anim:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.25)
		fade:SetDuration(0.5)
		fade:SetSmoothing("IN_OUT")
	end
	g:Hide()
	glows[button] = g
	return g
end

local function SetGlow(button, on)
	local g = glows[button]
	if on then
		g = GetGlow(button)
		if not g:IsShown() then
			local w, h = button:GetSize()
			g:SetSize(w * g.scale, h * g.scale)
			g:Show()
			g.anim:Play()
		end
	elseif g and g:IsShown() then
		g.anim:Stop()
		g:Hide()
	end
end

-- Does the button's action cast one of the abilities in `ids` / `names` (see ns.ReadyGlowSpells)?
local function HoldsSpell(button, ids, names)
	local spellID = buttonSpell[button]
	if not spellID then
		return false
	end
	if ids[spellID] then
		return true
	end
	local name = buttonSpellName[button]
	return name ~= nil and names[name] == true
end

function ns.UpdateGlows()
	local id = GlowingItem()
	local ids, names = ns.ReadyGlowSpells()
	for button in pairs(glows) do
		if not buttonSource[button] then
			SetGlow(button, false) -- no longer on any bar
		end
	end
	for button in pairs(buttonSource) do
		SetGlow(button, (id ~= nil and buttonItem[button] == id) or (ids ~= nil and HoldsSpell(button, ids, names)))
	end
end

-- /druidm glowdebug: why the trinket and the Glow page's abilities are or are not glowing, and which buttons hold them.
function ns.GlowDebug()
	Rescan()
	local id = ns.db.trinketItemID
	ns.Print("glow debug")
	print(("  trinket: %s (%s)"):format(id and (C_Item.GetItemNameByID(id) or "?") or "none", tostring(id)))
	local glowing, reason = GlowingItem()
	print(("  should glow: %s - %s"):format(glowing and "yes" or "no", reason))
	local counts, matches = {}, {}
	for button, source in pairs(buttonSource) do
		counts[source] = (counts[source] or 0) + 1
		if id and buttonItem[button] == id then
			matches[#matches + 1] = ("%s [%s]%s"):format(button:GetName() or "?", source, button:IsVisible() and "" or " (hidden)")
		end
	end
	local parts = {}
	for source, n in pairs(counts) do
		parts[#parts + 1] = ("%s %d"):format(source, n)
	end
	print("  buttons scanned: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
	print("  buttons with the trinket: " .. (#matches > 0 and table.concat(matches, ", ") or "none found"))

	if ns.IsDeathKnight() then
		local inDecay, source = ns.InDeathAndDecay()
		print(("  Heart Strike in Death and Decay: %s; in Death and Decay: %s (%s)"):format(ns.db.dkHeartStrikeDecay and "on" or "off",
			inDecay and "yes" or "no", source))
	end

	local list = ns.GlowList()
	print(("  ability glow: %s, %d abilities"):format(ns.db.glowEnabled and "on" or "off", #list))
	for i, entry in ipairs(list) do
		local sid = entry.spellID
		local held = {}
		local ids, names = { [sid] = true }, { [C_Spell.GetSpellName(sid) or "?"] = true }
		for button in pairs(buttonSource) do
			if HoldsSpell(button, ids, names) then
				held[#held + 1] = ("%s [%s]%s"):format(button:GetName() or "?", buttonSource[button], button:IsVisible() and "" or " (hidden)")
			end
		end
		print(("  %d. %s (%d): %s, state %s; buttons: %s"):format(i, C_Spell.GetSpellName(sid) or "?", sid,
			entry.enabled and "on" or "off", ns.SpellState(sid), #held > 0 and table.concat(held, ", ") or "none found"))
	end
	ns.UpdateGlows()
end

function ns.InitTrinketGlow()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	events:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
	events:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	events:RegisterEvent("UPDATE_MACROS")
	events:SetScript("OnEvent", QueueRescan)
	C_Timer.NewTicker(0.25, ns.UpdateGlows)
	C_Timer.NewTicker(RESCAN_INTERVAL, QueueRescan)
	QueueRescan()
end
