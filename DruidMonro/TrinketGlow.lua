local ADDON_NAME, ns = ...

-- Glows the selected trinket on action bars (placed directly or through a macro) while it can be used.
-- Supports the default bars, ButtonForge, and LibActionButton bars (Bartender4, ElvUI).

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
local buttonSource = {} -- button -> bar addon name, for /druidm glowdebug
local glows = {} -- button -> glow frame

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function HasProcAtlas()
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(PROC_ATLAS) ~= nil
end

-- itemID for a GetActionInfo-style ("item", id) / ("macro", index) pair, else nil.
local function ResolveAction(actionType, id)
	if IsSecret(actionType) or IsSecret(id) then
		return nil
	end
	if actionType == "item" then
		return tonumber(id) or (type(id) == "string" and tonumber(id:match("item:(%d+)"))) or nil
	elseif actionType == "macro" and GetMacroItem then
		local ok, _, link = pcall(GetMacroItem, id) -- also resolves "/use 13"
		if ok and link then
			return (C_Item.GetItemInfoInstant(link))
		end
	end
end

local function SlotItemID(slot)
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
				add(button, SlotItemID(slot), "Blizzard")
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
					add(button, SlotItemID(action), major)
				elseif kind == "item" then
					add(button, ResolveAction("item", action), major)
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
			add(button, ResolveAction(bf.GetButtonActionInfo(name)), "ButtonForge")
		end
	end
end

local function Rescan()
	wipe(buttonItem)
	wipe(buttonSource)
	local function add(button, itemID, source)
		buttonSource[button] = source
		buttonItem[button] = itemID
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
			ns.UpdateTrinketGlow()
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

function ns.UpdateTrinketGlow()
	local id = GlowingItem()
	for button in pairs(glows) do
		if not (id and buttonItem[button] == id) then
			SetGlow(button, false)
		end
	end
	if id then
		for button, itemID in pairs(buttonItem) do
			if itemID == id then
				SetGlow(button, true)
			end
		end
	end
end

-- /druidm glowdebug: why the trinket is or is not glowing, and which buttons hold it.
function ns.GlowDebug()
	Rescan()
	local id = ns.db.trinketItemID
	ns.Print("trinket glow debug")
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
	ns.UpdateTrinketGlow()
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
	C_Timer.NewTicker(0.25, ns.UpdateTrinketGlow)
	C_Timer.NewTicker(RESCAN_INTERVAL, QueueRescan)
	QueueRescan()
end
