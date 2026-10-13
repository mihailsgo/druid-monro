local ADDON_NAME, ns = ...

-- Moonfire proc detection and glow. There is no icon of its own: the glow is drawn on the
-- Moonfire count icon (MoonfireCount.lua), which hosts it.

local MOONFIRE_SPELL = 8921
local MOONFIRE_SPELLS = { [8921] = true, [164812] = true }
local GALACTIC_GUARDIAN_AURA = 213708 -- Guardian: next Moonfire is free and empowered
local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"

ns.GLOW_OPTIONS = {
	{ key = "none", name = "None" },
	{ key = "pulse", name = "Pulse" },
	{ key = "pixel", name = "Pixel border" },
	{ key = "proc", name = "Blizzard proc" },
}

local PIXEL_DOTS = 16

local frame -- the icon frame the glow is drawn on
local pulseTex, pulseAnim
local procTex, procAnim
local dots = {}
local pixelPhase = 0
local procActive = false
local activeGlow

local function HasProcAtlas()
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(PROC_ATLAS) ~= nil
end

local function CheckProc()
	local active = false
	if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
		local ok, res = pcall(C_SpellActivationOverlay.IsSpellOverlayed, MOONFIRE_SPELL)
		active = ok and res and true or false
	end
	if not active and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, GALACTIC_GUARDIAN_AURA)
		active = ok and aura ~= nil
	end
	procActive = active
end

-- True while Moonfire is procced and the indicator is enabled (or the layout preview is on).
function ns.IsProcShown()
	if not ns.db.indicatorEnabled or not ns.IsDruid() then
		return false
	end
	return procActive or ns.IsPreview()
end

local function PixelOnUpdate(_, elapsed)
	pixelPhase = (pixelPhase + elapsed * 0.3) % 1
	local s = frame:GetWidth()
	local perimeter = s * 4
	for i, dot in ipairs(dots) do
		local d = (((i - 1) / PIXEL_DOTS) + pixelPhase) % 1 * perimeter
		local x, y
		if d < s then
			x, y = d, 0
		elseif d < s * 2 then
			x, y = s, -(d - s)
		elseif d < s * 3 then
			x, y = s - (d - s * 2), -s
		else
			x, y = 0, -(d - s * 3)
		end
		dot:SetPoint("CENTER", frame, "TOPLEFT", x, y)
	end
end

local function StopGlows()
	pulseAnim:Stop()
	pulseTex:Hide()
	procAnim:Stop()
	procTex:Hide()
	frame:SetScript("OnUpdate", nil)
	for _, dot in ipairs(dots) do
		dot:Hide()
	end
end

local function StartGlow(kind)
	if kind == "pulse" then
		pulseTex:Show()
		pulseAnim:Play()
	elseif kind == "proc" then
		procTex:Show()
		procAnim:Play()
	elseif kind == "pixel" then
		for _, dot in ipairs(dots) do
			dot:Show()
		end
		frame:SetScript("OnUpdate", PixelOnUpdate)
	end
end

-- Sizes and starts/stops the glow on the host icon. Called whenever the icon is refreshed.
function ns.ApplyIndicator()
	if not frame then
		return
	end
	local s = frame:GetWidth()
	pulseTex:SetSize(s * 1.8, s * 1.8)
	procTex:SetSize(s * 1.4, s * 1.4)
	local t = math.max(2, math.floor(s * 0.06))
	for _, dot in ipairs(dots) do
		dot:SetSize(t, t)
	end

	-- Only restart the glow when it actually changes; UNIT_AURA calls this often.
	local desired
	if frame:IsShown() and ns.IsProcShown() then
		desired = ns.db.glow
		if desired == "proc" and not HasProcAtlas() then
			desired = "pulse" -- atlas missing on this client build
		end
		if desired == "none" then
			desired = nil
		end
	end
	if desired ~= activeGlow then
		StopGlows()
		if desired then
			StartGlow(desired)
		end
		activeGlow = desired
	end
end

function ns.InitIndicator(host)
	frame = host

	-- Pulse: pulsing additive action-button border.
	pulseTex = frame:CreateTexture(nil, "OVERLAY")
	pulseTex:SetPoint("CENTER")
	pulseTex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	pulseTex:SetBlendMode("ADD")
	pulseAnim = pulseTex:CreateAnimationGroup()
	pulseAnim:SetLooping("BOUNCE")
	local fade = pulseAnim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.5)
	fade:SetSmoothing("IN_OUT")

	-- Blizzard-style spell-alert flipbook.
	procTex = frame:CreateTexture(nil, "OVERLAY")
	procTex:SetPoint("CENTER")
	if HasProcAtlas() then
		procTex:SetAtlas(PROC_ATLAS)
	end
	procAnim = procTex:CreateAnimationGroup()
	procAnim:SetLooping("REPEAT")
	local flip = procAnim:CreateAnimation("FlipBook")
	flip:SetFlipBookRows(6)
	flip:SetFlipBookColumns(5)
	flip:SetFlipBookFrames(30)
	flip:SetDuration(1)

	-- Pixel: dots marching around the border.
	for i = 1, PIXEL_DOTS do
		local dot = frame:CreateTexture(nil, "OVERLAY")
		dot:SetColorTexture(1, 0.85, 0.2, 1)
		dot:Hide()
		dots[i] = dot
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
	events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
	events:RegisterUnitEvent("UNIT_AURA", "player")
	events:SetScript("OnEvent", function(_, event, spellID)
		if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
			if MOONFIRE_SPELLS[spellID] then
				procActive = true
			end
		elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
			if MOONFIRE_SPELLS[spellID] then
				procActive = false
			end
		else
			CheckProc()
		end
		ns.ApplyMoonfireCount()
	end)

	CheckProc()
end
