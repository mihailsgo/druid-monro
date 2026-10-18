local ADDON_NAME, ns = ...

-- Glows the selected trinket on the default action bars (direct item or a macro that uses it) while it can be used.

local GCD_THRESHOLD = 1.5
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

local buttons = {} -- every default action button
local buttonItem = {} -- button -> itemID its action uses (rebuilt when bars change)
local glows = {} -- button -> glow frame

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function HasProcAtlas()
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(PROC_ATLAS) ~= nil
end

local function ActionItemID(slot)
	local actionType, id = GetActionInfo(slot)
	if IsSecret(actionType) or IsSecret(id) then
		return nil
	end
	if actionType == "item" then
		return id
	elseif actionType == "macro" then
		local _, link = GetMacroItem(id) -- also resolves "/use 13"
		if link then
			return (C_Item.GetItemInfoInstant(link))
		end
	end
end

local function Rescan()
	wipe(buttonItem)
	for _, button in ipairs(buttons) do
		local slot = button.action
		if slot and not IsSecret(slot) then
			local ok, id = pcall(ActionItemID, slot)
			buttonItem[button] = ok and id or nil
		end
	end
end

-- Bars update their own button.action in the same event, so rescan once they are done.
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

-- The trinket's itemID while it should glow, else nil.
local function GlowingItem()
	local db = ns.db
	local id = db.trinketItemID
	if not (db.trinketGlow and id and C_Item.IsEquippedItem(id)) then
		return nil
	end
	if ns.IsPreview() then
		return id
	end
	local start, duration, enabled = C_Item.GetItemCooldown(id)
	if IsSecret(start) or IsSecret(duration) or IsSecret(enabled) then
		-- Hidden cooldown: trust the voice reminder's estimate.
		return ns.TrinketCooling() == false and id or nil
	end
	if enabled == false or enabled == 0 then
		return nil
	end
	if not start or start == 0 or not duration or duration <= GCD_THRESHOLD then
		return id
	end
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
	for _, button in ipairs(buttons) do
		SetGlow(button, id ~= nil and buttonItem[button] == id)
	end
end

function ns.InitTrinketGlow()
	for _, prefix in ipairs(BAR_PREFIXES) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then
				buttons[#buttons + 1] = button
			end
		end
	end

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
	QueueRescan()
end
