local ADDON_NAME, ns = ...

local ICON = "Interface\\Icons\\Ability_Racial_BearForm"

local button

local function UpdatePosition()
	local angle = math.rad(ns.db.minimap.angle)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragUpdate()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local px, py = GetCursorPosition()
	ns.db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
	UpdatePosition()
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("DruidMonro")
	GameTooltip:AddLine("|cffffffffLeft-click|r open settings", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffRight-click|r " .. (ns.unlocked and "lock" or "unlock") .. " elements", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function ns.ApplyMinimap()
	if not button then
		return
	end
	button:SetShown(not ns.db.minimap.hide)
	UpdatePosition()
end

function ns.InitMinimap()
	button = CreateFrame("Button", "DruidMonroMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			ns.SetUnlocked(not ns.unlocked)
			if GameTooltip:IsOwned(self) then
				ShowTooltip(self)
			end
		else
			ns.OpenConfig()
		end
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		icon:SetVertexColor(0.7, 0.7, 0.7)
		self:SetScript("OnUpdate", DragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		icon:SetVertexColor(1, 1, 1)
	end)

	ns.ApplyMinimap()
end
