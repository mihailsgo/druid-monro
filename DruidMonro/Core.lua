local ADDON_NAME, ns = ...
_G.DruidMonro = ns

ns.DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

ns.defaults = {
	text = "NOT IN BEAR FORM",
	fontPath = ns.DEFAULT_FONT,
	fontSize = 32,
	outline = true,
	color = { r = 1, g = 0.1, b = 0.1 },
	x = 0, -- offsets from the screen center
	y = 150,

	indicatorEnabled = true,
	indicatorSize = 64,
	glow = "proc", -- none | pulse | pixel | proc
	indX = 0,
	indY = 60,

	trackers = {}, -- see ns.NewTracker in Tracker.lua
}

local function ApplyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = {}
				ApplyDefaults(dst[k], v)
			else
				dst[k] = v
			end
		end
	end
end

function ns.Print(msg)
	print("|cff33ff99DruidMonro|r: " .. tostring(msg))
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		DruidMonroDB = DruidMonroDB or {}
		ApplyDefaults(DruidMonroDB, ns.defaults)
		ns.db = DruidMonroDB
		if ns.InitDisplay then
			ns.InitDisplay()
		end
		if ns.InitConfig then
			ns.InitConfig()
		end
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

function ns.PrintHelp()
	ns.Print("commands")
	print("  /druidm - open the configuration panel")
	print("  /druidm unlock - show the text and Moonfire indicator and unlock them for dragging (run again to lock)")
	print("  /druidm reset - reset all settings and positions to defaults")
end

function ns.ResetAll()
	wipe(ns.db)
	ApplyDefaults(ns.db, ns.defaults)
	ns.SetUnlocked(false)
	ns.Print("settings reset")
end

SLASH_DRUIDMONRO1 = "/druidm"
SLASH_DRUIDMONRO2 = "/druidmonro"
SlashCmdList["DRUIDMONRO"] = function(msg)
	if not ns.db then
		return
	end
	local cmd = strtrim(msg or ""):lower()
	if cmd == "" or cmd == "config" then
		ns.OpenConfig()
	elseif cmd == "unlock" or cmd == "lock" then
		ns.SetUnlocked(not ns.unlocked)
		ns.Print(ns.unlocked and "unlocked - drag the text, then run /druidm unlock again" or "locked")
	elseif cmd == "reset" then
		ns.ResetAll()
	else
		ns.PrintHelp()
	end
end
