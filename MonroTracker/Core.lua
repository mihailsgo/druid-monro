local ADDON_NAME, ns = ...
_G.MonroTracker = ns

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
	rageInCat = false, -- also show the rage bar in Cat Form
	rageX = 0,
	rageY = -100,

	cpEnabled = true, -- Feral druid only: combo point bar, one segment per point, shown in Cat Form
	cpWidth = 200,
	cpHeight = 16,
	cpGap = 3, -- pixels between segments
	cpColor = { r = 1, g = 0.75, b = 0.1 },
	cpFullHighlight = true, -- recolor every segment while at the maximum number of points
	cpFullColor = { r = 1, g = 0.25, b = 0.1 },
	cpAsNumber = false, -- show the count as a number instead of segments
	cpFontSize = 36, -- size of that number
	cpGlow = true, -- pulsing border while you have at least cpGlowAt combo points
	cpGlowAt = 5,
	cpCombatOnly = false,
	cpX = 0,
	cpY = -130,

	energyEnabled = true, -- Feral druid only: energy bar shown in Cat Form, with a split line at energySplit
	energyWidth = 200,
	energyHeight = 20,
	energyColor = { r = 1, g = 0.9, b = 0.2 },
	energySplit = 50, -- energy value where the split line sits; energy past it is drawn in energyAboveColor. 0 = no line
	energyAboveColor = { r = 0.15, g = 0.9, b = 0.2 },
	energyAboveWhole = false, -- once energy reaches the line, draw the whole fill in energyAboveColor, not only the part past it
	energyShowText = true,
	energyCombatOnly = false,
	energyX = 0,
	energyY = -155,

	rpEnabled = true, -- Death Knight only: runic power bar with a split line at rpPercent
	rpWidth = 200,
	rpHeight = 20,
	rpColor = { r = 0, g = 0.82, b = 1 },
	rpShowText = true,
	rpPercent = 75, -- split line position as a percentage of the bar, and the point from which the bar glows
	rpGlow = true, -- pulsing border while runic power is at or above the threshold
	rpCombatOnly = false,
	rpX = 0,
	rpY = -100,

	bsEnabled = true, -- Blood Death Knight only: Bone Shield icon with its stacks and time left, drawn by the engine so it works in combat
	bsSize = 64,
	bsSwipe = true, -- cooldown swipe over the icon
	bsShowStacks = true,
	bsStackFontSize = 28,
	bsShowTimer = true,
	bsTimerFontSize = 18,
	bsTimerDecimals = 5, -- show tenths of a second below this many seconds; 0 = whole seconds only
	bsLowSeconds = 5, -- low time: the timer turns red and "REFRESH" shows below this many seconds left; 0 = never
	bsLowStacks = 5, -- low stacks: "REFRESH" shows below this many stacks; 0 = never
	bsLowWarn = true, -- in combat, the "REFRESH" message while the time or the stacks are low (compared by the engine)
	bsLowPlace = "above", -- the message's place: above | below | left | right of the icon, or free = its own spot on the screen (bsLowX / bsLowY, set by dragging it)
	bsLowFont = ns.DEFAULT_FONT, -- the message's font file
	bsLowFontSize = 22,
	bsCombatOnly = false,
	bsWarnMissing = true, -- in combat with no Bone Shield: a red pulsing warning icon in the tracker's place
	bsVoice = true, -- says "Refresh Bone Shield" in combat when the buff drops, falls under 5 stacks (Ossuary) or is under bsLowSeconds
	bsRefreshSpells = {}, -- spellID -> true/false: casts seen to refresh Bone Shield or not, for the voice's own clock
	bsX = 0,
	bsY = -170,

	edEnabled = true, -- row of the external defensives other players put on you, drawn by the engine so it works in combat
	edSize = 48,
	edMax = 4, -- icons shown at once (1 to 8)
	edSwipe = true, -- cooldown swipe over the icons
	edShowTimer = true,
	edTimerFontSize = 16,
	edGlow = true, -- pulsing golden border on each icon
	edCombatOnly = false,
	edOthers = true, -- also show external defensives that are not in the list on the page (unless switched off there)
	edOff = {}, -- first spell ID of each listed defensive that is switched off, see ns.EXTDEF_CATALOG
	edX = -260,
	edY = 40,

	enrageEnabled = true, -- Druid only: panel listing the mobs that are enraged right now, i.e. where to cast Soothe
	enrageSay = true, -- say "Soothe" when a mob enrages
	enrageMarker = true, -- Soothe icon over the enraged mob's nameplate
	enrageMarkerSize = 40,
	enrageMarkerSide = "right", -- right | left | above | below the nameplate, clear of the raid markers
	enrageRecord = true, -- temporarily note what the client returns in combat into MonroTrackerDB.enrageLog (see /mtr enragelog)
	enrageMarkerFilter = "mine", -- mine: only enrages your class can remove | any: every dispellable buff (Magic too)
	enrageWidth = 230,
	enrageRows = 4, -- mobs listed at once
	enrageX = 260,
	enrageY = 40,

	dispelEnabled = true, -- Druid only: says "Dispel poison" / "Dispel curse" when someone in your group has one and your dispel is ready
	dispelPoison = true,
	dispelCurse = true,
	dispelSelf = true, -- also announce debuffs on yourself
	dispelCombatOnly = false,

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
	glowEnabled = true, -- master switch for the Glow page: abilities that glow on the action bars while they can be used
	glowSpells = {}, -- class token -> { { spellID, enabled }, ... }, see AbilityGlow.lua
	dkHeartStrikeDecay = true, -- Death Knight: glow Heart Strike on the action bars while the Death and Decay buff is on you
	heartEnabled = true, -- "Heart of the Wild ready"
	apexEnabled = true, -- "Apex" when Wild Guardian's Answered Calling procs
	weaponEnabled = true, -- Death Knight: "Weapon" when Dancing Rune Weapon comes up, cast by you or triggered by a talent
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
	print("|cff33ff99MonroTracker|r: " .. tostring(msg))
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		MonroTrackerDB = MonroTrackerDB or {}
		-- The Moonfire count feature was removed; its icon position and size now belong to the proc indicator.
		local old = MonroTrackerDB
		if old.moonCountX ~= nil then
			old.indX, old.indY, old.indicatorSize = old.moonCountX, old.moonCountY, old.moonCountSize
		end
		-- The Bone Shield voice reminder was replaced by the Bone Shield tracker.
		for _, k in ipairs({ "boneEnabled", "boneStacks", "boneSeconds", "boneLossSeconds", "boneLog", "bsShowMissing" }) do
			old[k] = nil
		end
		for _, k in ipairs({ "moonCountEnabled", "moonCountSize", "moonCountFontSize", "moonCountColor", "moonCountX", "moonCountY" }) do
			old[k] = nil
		end
		-- The Bone Shield "REFRESH" message used to scale with the icon; its size is now a setting, starting from what was shown.
		if old.bsLowFontSize == nil and type(old.bsSize) == "number" then
			old.bsLowFontSize = math.max(12, math.floor(old.bsSize * 0.34 + 0.5))
		end
		ApplyDefaults(MonroTrackerDB, ns.defaults)
		ns.db = MonroTrackerDB
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
	print("  /mtr - open the configuration panel")
	print("  /mtr unlock - show the text and Moonfire indicator and unlock them for dragging (run again to lock)")
	print("  /mtr minimap - show or hide the minimap button")
	print("  /mtr reset - reset all settings and positions to defaults")
	print("  /mtr glowdebug - show why the trinket and the Glow page's abilities are or are not glowing")
	print("  /mtr spy - print your casts and new buffs (to find proc spell IDs); run again to stop")
	print("  /mtr cddebug - show what the trinket / Heart of the Wild voice reminders see right now")
	print("  /mtr trackerdebug - show what the client reports for each ability tracker and what the addon makes of it")
	print("  /mtr enragedebug - show what the client lets the enrage panel read on each enemy nameplate")
	print("  /mtr dispeldebug - show what the client lets the dispel callout read on each group member")
	print("  /mtr bonedebug - show what the Bone Shield tracker reads, whether the engine display is built and the state of its warning and voice")
	print("  /mtr extdefdebug - show whether the external defensives display is built and what is switched on")
	print("  /mtr rpdebug - show what the client reports for the runic power bar and its glow")
	print("  /mtr cpdebug - show what the client reports for the combo point bar")
	print("  /mtr energydebug - show what the client reports for the energy bar and where its split line is")
	print("  /mtr enragelog [clear|on|off] - the enrage panel notes what the client returns in combat; saved on /reload")
end

function ns.ResetAll()
	wipe(ns.db)
	ApplyDefaults(ns.db, ns.defaults)
	ns.SetUnlocked(false)
	ns.Print("settings reset")
end

SLASH_MONROTRACKER1 = "/mtr"
SLASH_MONROTRACKER2 = "/monrotracker"
SLASH_MONROTRACKER3 = "/druidm" -- old names, still accepted
SLASH_MONROTRACKER4 = "/druidmonro"
SlashCmdList["MONROTRACKER"] = function(msg)
	if not ns.db then
		return
	end
	local cmd = strtrim(msg or ""):lower()
	if cmd == "" or cmd == "config" then
		ns.OpenConfig()
	elseif cmd == "unlock" or cmd == "lock" then
		ns.SetUnlocked(not ns.unlocked)
		ns.Print(ns.unlocked and "unlocked - drag the text, then run /mtr unlock again" or "locked")
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
	elseif cmd == "trackerdebug" then
		ns.TrackerDebug()
	elseif cmd == "enragedebug" then
		ns.EnrageDebug()
	elseif cmd == "dispeldebug" then
		ns.DispelDebug()
	elseif cmd == "bonedebug" then
		ns.BoneShieldDebug()
	elseif cmd == "extdefdebug" then
		ns.ExtDefDebug()
	elseif cmd == "rpdebug" then
		ns.RunicPowerDebug()
	elseif cmd == "cpdebug" then
		ns.ComboPointsDebug()
	elseif cmd == "energydebug" then
		ns.EnergyDebug()
	elseif cmd == "enragelog" or cmd:sub(1, 10) == "enragelog " then
		ns.EnrageLogCommand(strtrim(cmd:sub(11)))
	elseif cmd == "reset" then
		ns.ResetAll()
	else
		ns.PrintHelp()
	end
end
