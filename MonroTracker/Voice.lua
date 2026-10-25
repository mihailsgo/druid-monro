local ADDON_NAME, ns = ...

-- Spoken callouts through Blizzard's built-in text-to-speech, the same engine and voice handling MonroMDTTrack uses
-- for its boss callouts, so no sound files ship with the addon.

-- Trims "Microsoft David - English (United States)" down to "David" for the dropdown.
function ns.ShortVoiceName(name)
	if not name or name == "" then
		return "Automatic"
	end
	return (name:gsub("^Microsoft%s+", ""):gsub("%s*%-.*$", ""))
end

-- Windows lists its oldest, most robotic voices first; prefer the Windows 11 "Natural" ones, then non-Desktop ones.
local function RankVoice(name)
	name = name or ""
	local score = 0
	if name:find("Natural", 1, true) then
		score = score + 2
	end
	if not name:find("Desktop", 1, true) then
		score = score + 1
	end
	return score
end

function ns.GetVoices()
	local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
	return type(voices) == "table" and voices or {}
end

-- The voice picked here, else the one picked in MonroMDTTrack, else the best-ranked installed voice.
-- Picks are stored by name because voice IDs shift when a voice pack is added or removed.
local function ResolveVoiceID()
	local voices = ns.GetVoices()
	if not voices[1] then
		return nil
	end
	local chosen = ns.db.voiceName or (MonroMDTTrackDB and MonroMDTTrackDB.voiceName)
	local best, bestScore
	for _, voice in ipairs(voices) do
		if chosen and voice.name == chosen then
			return voice.voiceID
		end
		local score = RankVoice(voice.name)
		if not bestScore or score > bestScore then
			best, bestScore = voice, score
		end
	end
	return best.voiceID
end

-- Speaks `text`. Returns true, or false plus a reason (a failed call is otherwise indistinguishable from silence).
function ns.Speak(text)
	if not (C_VoiceChat and C_VoiceChat.SpeakText and C_VoiceChat.GetTtsVoices) then
		return false, "this client has no text-to-speech API"
	end
	local voiceID = ResolveVoiceID()
	if not voiceID then
		return false, "no text-to-speech voices are installed. On Windows add one under Settings > Time & Language > Speech, then /reload"
	end

	-- Follow the game's Text to Speech rate/volume, but never let a 0 volume there mute this addon.
	local rate = (C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()) or 0
	local volume = (C_TTSSettings and C_TTSSettings.GetSpeechVolume and C_TTSSettings.GetSpeechVolume()) or 100
	if volume <= 0 then
		volume = 100
	end

	-- Midnight dropped the destination argument in favour of a trailing queue flag.
	local ok, err
	local destinations = Enum and Enum.VoiceTtsDestination
	if destinations then
		local destination = destinations.QueuedLocalPlayback or destinations.LocalPlayback
		ok, err = pcall(C_VoiceChat.SpeakText, voiceID, text, destination, rate, volume)
	else
		ok, err = pcall(C_VoiceChat.SpeakText, voiceID, text, rate, volume, true)
	end
	if not ok then
		return false, "the text-to-speech engine rejected the request: " .. tostring(err)
	end
	return true
end
