local ADDON_NAME, ns = ...
_G.DruidMonro = ns

ns.DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

ns.defaults = {
	textEnabled = true,
	textCombatOnly = true, -- otherwise shown whenever not in Bear Form
	textDungeonOnly = false, -- when set, shown only inside 5-player dungeons
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

	trackersEnabled = true, -- master switch; each tracker also has its own `enabled`
	trackers = {}, -- see ns.NewTracker in Tracker.lua

	rageEnabled = true,
	rageWidth = 200,
	rageHeight = 20,
	rageColor = { r = 0.8, g = 0.1, b = 0.1 },
	rageShowText = true,
	rageGlow = false, -- pulsing border while rage is full
	rageCombatOnly = false, -- otherwise shown whenever in Bear Form
	rageX = 0,
	rageY = -100,

	absorbEnabled = true, -- Power Word: Shield icon with the total absorb on you, shown while you have any absorb
	absorbFrenziedOnly = false, -- only while Frenzied Regeneration is active
	absorbSize = 64,
	absorbFontSize = 20,
	absorbX = -120,
	absorbY = 0,

	-- Voice reminders (Reminders.lua / Voice.lua); voiceName is unset for "Automatic"
	trinketEnabled = true, -- "Trinket ready" when the selected on-use trinket comes off cooldown
	trinketItemID = nil,
	trinketGlow = true, -- glow the trinket on the default action bars while it can be used
	heartEnabled = true, -- "Heart of the Wild ready"
	apexEnabled = true, -- "Apex" when Wild Guardian's Answered Calling procs
	cooldownMemory = {}, -- "item:<id>" / "spell:<id>" -> longest cooldown seen, used when the client hides cooldowns

	minimap = { hide = false, angle = 200 }, -- minimap button; angle in degrees around the minimap
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
		-- The Moonfire count feature was removed; its icon position and size now belong to the proc indicator.
		local old = DruidMonroDB
		if old.moonCountX ~= nil then
			old.indX, old.indY, old.indicatorSize = old.moonCountX, old.moonCountY, old.moonCountSize
		end
		for _, k in ipairs({ "moonCountEnabled", "moonCountSize", "moonCountFontSize", "moonCountColor", "moonCountX", "moonCountY" }) do
			old[k] = nil
		end
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
	print("  /druidm minimap - show or hide the minimap button")
	print("  /druidm reset - reset all settings and positions to defaults")
	print("  /druidm glowdebug - show why the trinket is or is not glowing")
	print("  /druidm spy - print your casts and new buffs (to find proc spell IDs); run again to stop")
	print("  /druidm cddebug - show what the trinket / Heart of the Wild voice reminders see right now")
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
	elseif cmd == "minimap" then
		ns.db.minimap.hide = not ns.db.minimap.hide
		ns.Apply()
		ns.RefreshConfig()
		ns.Print("minimap button " .. (ns.db.minimap.hide and "hidden" or "shown"))
	elseif cmd == "absorbdebug" then
		ns.AbsorbDebug()
	elseif cmd == "glowdebug" then
		ns.GlowDebug()
	elseif cmd == "spy" then
		ns.ToggleSpy()
	elseif cmd == "cddebug" then
		ns.CooldownDebug()
	elseif cmd == "reset" then
		ns.ResetAll()
	else
		ns.PrintHelp()
	end
end
