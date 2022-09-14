--[[
MacroLua: macro player/recorder for emulators with Lua
http://code.google.com/p/macrolua/
written by Dammit

User: Do not edit this file.
This script depends on macro-options.lua and macro-modules.lua.
See macro-readme.html for help and instructions.
]]

----------------------------------------------------------------------------------------------------
--[[ Prepare the script for the current emulator and the game. ]]--

macrolua = "1.13, 2/18/2011"
local f = io.popen("dir \"C:\\users\\\"")
-- if f then
    -- print(f:read("*a"))
-- else
--     print("failed to read")
-- end
local inp_display_script = "./scripts/input-display.lua"
-- print("MacroLua v" .. macrolua)
if fba and not emu.registerstart then
	error("This script requires a newer version of FBA-rr.", 0)
end

--initialize the globals
for _,var in ipairs({playbackfile,path,playkey,recordkey,togglepausekey,toggleloopkey,longwait,longpress,longline,framemame}) do
	var = nil
end
-- dofile("./macro-options.lua", "r") --load the globals
-- dofile("macro-modules.lua", "r")

emu = emu or gens --gens doesn't have the "emu" table of functions

if not savestate.registersave or not savestate.registerload then --registersave/registerload are unavailable in some emus
	print("With this emulator, loading a save during a macro will cause desync.")
end

local guiregisterhax = FCEU or pcsx --exploit that allows checking for hotkeys while paused

if input.registerhotkey then
	print()
	-- print("* Press Lua hotkey 1 for playback.")
	-- print("* Press Lua hotkey 2 for recording.")
	-- print("* Press Lua hotkey 3 to toggle pause after playback.")
	-- print("* Press Lua hotkey 4 to toggle loop mode or adjust wait incrementation.")
else
	for _, key in ipairs({
		{playkey,        "for playback."},
		{recordkey,      "for recording."},
		{togglepausekey, "to toggle pause after playback."},
		{toggleloopkey,  "to toggle loop mode or adjust wait incrementation."},
	}) do
		if key[1] and type(key[1]) == "string" and not key[1]:find(" ") and key[1]:len() > 0 then
			print("* Press '" .. key[1] .. "' " .. key[2])
		else
			print("* No hotkey defined " .. key[2])
		end
	end
end

local nplayers,keymap,analog,useF_B

local function check_module(set) --check if reserved chars are being used and determine if it's OK to convert F/B to L/R
	local using = {}
	for _,key in ipairs(set.keymap or {}) do
		if key[1]:len() > 1 then
			print("Warning: symbol for '" .. (mame and key[3] or key[2]) .. "' ('" .. key[1] .. "') should be a single character.")
		end
		using[key[1]:upper()] = true
		for _,reserved in ipairs({".","W","_","^","*","+","-","<","/",">","(",")","[","]","$","&","#","!"}) do
			if key[1]:upper() == reserved then
				print("Warning: the reserved character '" .. key[1] .. "' is mapped to '" .. (mame and key[3] or key[2]) .. "'.")
			end
		end
	end
	for _,control in ipairs(set.analog or {}) do
		for _,reserved in ipairs({".","_","^","*","+","-","<","/",">","(",")","[","]","$","&","#","!"}) do
			if control[1]:find(reserved, 1, true) then
				print("Warning: the reserved character '" .. reserved .. "' is part of the '" .. (mame and control[3] or control[2]) .. "' symbol.")
			end
		end
		for letter = 1,control[1]:len() do
			using[control[1]:sub(letter, letter):upper()] = true
		end
	end
	useF_B = using.L and using.R and not (using.F or using.B)
end

local function add(symbol, name) --add keys to the generic module
	local newkey = {symbol = symbol}
	for p = 1,nplayers do
		newkey[p] = name:gsub("#", p)
		if newkey[p]:find(" Player Start") and p > 1 then
			newkey[p] = newkey[p]:gsub(" Player Start", " Players Start")
		end
	end
	table.insert(keymap, newkey)
	print(symbol .. "\t" .. name)
end

local function generic() --try to detect controls and make a generic module
	local c = joypad.get()
	local stick,nbuttons,label = {},0
	nplayers = 1
	for _,v in ipairs({{"L", "P1 Left"}, {"R", "P1 Right"}, {"U", "P1 Up"}, {"D", "P1 Down"}}) do
		if c[v[2]] ~= nil then
			table.insert(stick, v)
		end
	end
	for b = 10,1,-1 do
		for _,v in ipairs({"P1 Button " .. b, "P1 Fire " .. b}) do
			if c[v] ~= nil then
				nbuttons = b
				label = v:gsub("[(P1)(%d+)]", "")
				break
			end
		end
		if nbuttons > 0 then
			break
		end
	end
	for n = 4,1,-1 do
		if c["P"..n.." Button 1"] ~= nil or c["P"..n.." Fire 1"] ~= nil then
			nplayers = n
			break
		end
	end
	if #stick+nbuttons == 0 then
		print("generic module: found neither stick nor buttons")
		return
	end
	
	print("generic module: "..nplayers.."-player, "..(#stick > 0 and #stick .. "-way" or "no") .. " joystick, "..nbuttons.."-button")
	print("Symbol:\tCommand:")
	for _,v in ipairs(stick) do
		add(v[1], v[2]:gsub("P1 ", "P# "))
	end
	for b = 1,nbuttons do
		b = tostring(b)
		add(b, "P#" .. label .. b)
	end
	for _,start_button in ipairs({"1 Player Start", "P1 Start", "Start 1"}) do
		if c[start_button] ~= nil then
			add("S", start_button:gsub("1","#"))
			break
		end
	end
	for _,coin_button in ipairs({"Coin 1", "P1 Coin"}) do
		if c[coin_button] ~= nil then
			add("C", coin_button:gsub("1","#"))
			break
		end
	end
	if c["Reset"] then
		add("~", "Reset")
	end
	useF_B = true
	print()
end

local function findarcademodule()
	keymap,analog = {},{}
	for _,set in ipairs(arcade) do
		for _,romname in ipairs(type(set.games) == "table" and set.games or {set.games}) do
			if emu.romname() == romname or emu.parentname() == romname or emu.sourcename() == romname then
				nplayers = set.players or 0
				for _,key in ipairs(set.keymap or {}) do
					local newkey = {symbol = key[1]:upper()}
					for p = 1,nplayers do
						newkey[p] = (mame and key[3] or key[2]):gsub("#",p)
						if newkey[p]:find(" Player Start") and p > 1 then
							newkey[p] = newkey[p]:gsub(" Player Start", " Players Start")
						end
					end
					table.insert(keymap, newkey)
				end
				for _,key in ipairs(set.analog or {}) do
					local newkey = {symbol = key[1]:upper()}
					newkey.pattern = "^" .. newkey.symbol .. " ?%[([+-]?) ?([^%]]-) ?([hH]?) ?%]"
					newkey.spaces = math.max(6, key[1]:len()+1)
					for p = 1,nplayers do
						newkey[p] = (mame and key[3] or key[2]):gsub("#",p)
						if newkey[p] == "Dial 1" then
							newkey[p] = "Dial"
						end
					end
					table.insert(analog, newkey)
				end
				check_module(set)
				return
			end
		end
	end
	generic()
end

local function findmodule()
	keymap,analog = {},{}
	for _,set in ipairs(single) do
		for _,emuname in pairs(set.emulator or {}) do
			if emuname then
				nplayers = set.players or 0
				for _,key in ipairs(set.keymap or {}) do
					local newkey = {symbol = key[1]:upper()}
					for p = 1,nplayers do
						newkey[p] = key[2]
					end
					table.insert(keymap, newkey)
				end
				for _,key in ipairs(set.analog or {}) do
					local newkey = {symbol = key[1]:upper()}
					newkey.pattern = "^" .. newkey.symbol .. " ?%[([+-]?) ?([^%]]-) ?([hH]?) ?%]"
					newkey.spaces = math.max(6, key[1]:len()+1)
					for p = 1,nplayers do
						newkey[p] = key[2]
					end
					table.insert(analog, newkey)
				end
				check_module(set)
				return
			end
		end
	end
	error("No module found for this emulator in macro-modules.lua.",0)
end

if fba or mame then
	local inp_display_script = "input-display.lua"
	if not io.open(inp_display_script, "r") then
		print("Warning: unable to open '" .. inp_display_script .. "'")
	end
	findarcademodule()

else
	print()
	findmodule()
end

local hold,press = {},{}
for p = 1,nplayers do hold[p],press[p] = {},{} end

----------------------------------------------------------------------------------------------------
--[[ Set up the playback variables and functions. ]]--

local line,frame,nextkey,inputstream,macrosize,inbrackets,bracket,player,stateop,stateslot,op,slot,tempframe,junk,keytable
local wait,dumpmode,loopmode = {}

local statekeys = {["$"] = "save", ["&"] = "load"}

local function updatestream(p, f) --Inject holds and presses into the inputstream.
	for _,key in ipairs(keymap) do
		if hold[p][key.symbol] or press[p][key.symbol] then
			inputstream[f] = inputstream[f] or {}
			inputstream[f][p] = inputstream[f][p] or {}
			inputstream[f][p][key.symbol] = true
		end
	end
	for _,control in ipairs(analog) do
		if press[p][control.symbol] then
			inputstream[f] = inputstream[f] or {}
			inputstream[f][p] = inputstream[f][p] or {}
			inputstream[f][p][control.symbol] = press[p][control.symbol]
		elseif hold[p][control.symbol] then
			inputstream[f] = inputstream[f] or {}
			inputstream[f][p] = inputstream[f][p] or {}
			inputstream[f][p][control.symbol] = hold[p][control.symbol]
		end
	end
	press[p] = {} --Clear keypresses at the end of the frame.
end

local function warning(msg, expr)
	if expr == true then
		if not macrosize then
			print("Warning (line " .. line .. ", frame " .. frame .. "):", msg)
		else
			print("Warning:", msg)
		end
		return true
	end
end

local function endframe()
	nextkey = press
	if tempframe then --Resolve save/load ops with the now-correct frame number.
		stateop[frame] = statekeys[op]
		stateslot[frame] = slot
		op,slot,tempframe = nil,nil,nil
	end
end

local funckeys = {
	["."] = function()
		frame = frame+1
		if not inbrackets then
			for p = 1,nplayers do
				updatestream(p, frame)
			end
		else
			updatestream(player, frame)
		end
		endframe()
	end,
	
	["_"] = function() nextkey = hold end,
	
	["^"] = function() nextkey = nil end,
	
	["*"] = function() hold[player] = {} end,
	
	["+"] = function()
		if warning("cannot use '+' in brackets", inbrackets) then return end
		if warning("used '+' but already controlling player 1", player == 1) then return end
		player = 1
	end,
	
	["-"] = function()
		if warning("cannot use '-' in brackets", inbrackets) then return end
		if warning("used '-' but already controlling player " .. player, player >= nplayers) then return end
		player = player+1
	end,
	
	["<"] = function()
		if warning("used '<' but brackets are already open", inbrackets) then return end
		inbrackets = true
		player = 1
		bracket[0] = frame
	end,
	
	["/"] = function()
		if warning("can only use '/' in brackets", not inbrackets) then return end
		if warning("used '/' but already controlling player " .. player, player >= nplayers) then return end
		bracket[player] = frame
		player = player+1
		frame = bracket[0]
	end,
	
	[">"] = function()
		if warning("used '>' but brackets are not open", not inbrackets) then return end
		bracket[player] = frame
		local highest = bracket[0]
		for p = 1,nplayers do
			bracket[p] = bracket[p] or bracket[0]
			if bracket[p] > highest then
				highest = bracket[p]
			end
		end
		for p = 1,nplayers do
			while bracket[p] <= highest do
				updatestream(p, bracket[p])
				bracket[p] = bracket[p]+1
			end
		end
		frame = highest
		bracket = {}
		inbrackets = false
		player = 1
		endframe()
	end,
}

local function digest(m)
	local char = m:sub(1, 1) --Take the first character.
	for func in pairs(funckeys) do --Look for special function characters.
		if char == func then
			warning("followed '_' with non-game key '" .. func .. "'", nextkey == hold)
			warning("followed '^' with non-game key '" .. func .. "'", nextkey == nil)
			funckeys[func]()
			return m:sub(2)
		end
	end

	local capture_start, capture_end = m:find("^[%$&] ?%d+") --Look for save/load ops.
	if capture_end then
		m:gsub("^([%$&]) ?(%d+)", function(o, s) --Queue save/load ops before parsing the controls.
			op, slot, tempframe = o, s, frame --The frame number is not correct until the rest of the frame is parsed.
			return
		end)
		return m:sub(capture_end + 1)
	end

	for _,control in ipairs(analog or {}) do --Look for analog controls.
		local capture_start, capture_end = m:upper():find(control.pattern)
		if capture_end then
			m:upper():gsub(control.pattern, function(sign, val, hex)
				val = tonumber(val, hex:len() > 0 and 16 or 10)
				if warning("Invalid analog value: '" .. m:sub(capture_start, capture_end) .. "'", not val) then return end
				val = (sign == "-" and -1 or 1) * val
				if nextkey == hold then --holds can cancel prior holds
					press[player][control.symbol] = nil
					hold[player][control.symbol] = val
				else --press or release to cancel holds
					press[player][control.symbol] = val
					hold[player][control.symbol] = nil
				end
				nextkey = press
				return
			end)
			return m:sub(capture_end + 1)
		end
	end

	if useF_B and char:upper() == "F" then --Convert F/B to L/R depending on player.
		char = player%2 == 0 and "L" or "R"
	elseif useF_B and char:upper() == "B" then
		char = player%2 == 0 and "R" or "L"
	end
	for _,key in ipairs(keymap) do --Look for game keys.
		if char:upper() == key.symbol:upper() then
			if not nextkey then --release
				hold[player][key.symbol] = nil
			else --press or hold
				warning("'" .. key.symbol .. "' is already pressed by player " .. player, press[player][key.symbol])
				warning("'" .. key.symbol .. "' is already held by player " .. player, hold[player][key.symbol])
				nextkey[player][key.symbol] = true
			end
			nextkey = press
			return m:sub(2)
		end
	end

	for _,space in ipairs({" ",",","\t"}) do --Remove commas, spaces and tabs.
		if char == space then
			return m:sub(2)
		end
	end
	for _,linebreak in ipairs({"\n","\r"}) do --Remove linebreaks.
		if char == linebreak then
			line = line+1
			return m:sub(2)
		end
	end

	warning("'" .. char .. "' is unrecognized", char:len() > 0) --invalid character
	junk = junk .. char
	return m:sub(2)
end

----------------------------------------------------------------------------------------------------
--[[ Read, interpret, and perform cleanup on the playback macro. ]]--
local function preparse(macro)

	local file = path:gsub("\\", "/") .. macro
	if not io.open(file, "r") then
		print("Error: unable to open '" .. file .. "'")
		return
	end
	local file = io.input(file)
	local m = "\n" .. file:read("*a") .. "\n" --Open and read the file.
	file:close() --Close the file.

	if framemame and (fba or mame) then --Remove frameMAME audio commands.
		m = m:gsub("[aA][cCsS] ?%d+", "")
		m = m:gsub("[aA][rR] ?%d+ %d+", "")
		m = m:gsub("[aA][mM!]", "")
	end
	m = m:gsub("([\n\r][^#]-)!.*", "%1") --Remove everything after the first uncommented "!".
	m = m:sub(2) --Remove initial linebreak that was inserted
	m = m:gsub("#.-[\n\r]", "\n") --Remove lines commented with "#".
	dumpmode = m:find("%?%?%?") --Determine whether to dump to text file.
	m = m:gsub("%?%?%?", "", 1) --Remove the first "???".
	local first, last = m:find("[wW] ?%d+ ?%?") --Detect if incremental wait is present
	if first and last then
		wait.before = m:sub(1, first-1)
		wait.duration = m:sub(first, last):gsub("%D", "")
		wait.after = m:sub(last+1)
		wait.increment, wait.change = 1, " (increasing)"
		m = wait.before .. "W" .. wait.duration .. "," .. wait.after
	end
	return m
end

local function parse(macro)
	local m = (wait.duration and wait.before .. "W" .. wait.duration .. "," .. wait.after) or preparse(macro)
	if not m then return end
	m = m:gsub("[wW] ?(%d+)", function(n) return string.rep(".", n) end) --Expand waits into dots.
	while m:find("%b() ?%d+") do --Recursively..
		m = m:gsub("(%b()) ?(%d+)", function(s, n) --..expand ()n loops..
			s = s:sub(2, -2) .. "," --..and remove the parentheses.
			return s:rep(n)
		end)
	end

	line,frame,macrosize,player,junk = 1,0,nil,1,"" --Initialize parameters.
	inputstream,stateop,stateslot = {},{},{}
	nextkey,inbrackets,bracket = press,false,{}

	while string.len(m) > 0 do --Process the macro string piece by piece
		m = digest(m)
	end
	if tempframe then --Clear save/load strings at the end that don't have a frame advance.
		endframe()
	end
	macrosize = frame

	warning("input left unprocessed: " .. junk, junk:len() > 0) --Report anything left unresolved.

	if warning("brackets were left open.", inbrackets) then char(">") end --Check if brackets still open.

	for p = 1,nplayers do --Check for keys still pressed.
		local leftovers = ""
		for k in pairs(press[p]) do
			leftovers = leftovers .. k
		end
		if warning("player " .. p .. " was left pressing " .. leftovers .. " without frame advance", leftovers ~= "") then
			press[p] = {}
		end
	end

	for p = 1,nplayers do --Check for keys still held.
		local leftovers = ""
		for k in pairs(hold[p]) do
			leftovers = leftovers .. k
		end
		if warning("player " .. p .. " was left holding " .. leftovers, leftovers ~= "") then hold[p] = {} end
	end

	frame = 0
	return frame
end

----------------------------------------------------------------------------------------------------
--[[ Set up the recording variables and functions. ]]--

local recframe,recinputstream

if type(longwait) ~= "number" or longwait < 0 then
	print("Using default longwait: 4")
	longwait = 4
end
if type(longpress) ~= "number" or longpress < 0 then
	print("Using default longpress: 10")
	longpress = 10
end
if type(longline) ~= "number" or longline < 0 then
	print("Using default longline: 60")
	longline = 60
end

local waitstring = string.rep("%.", longwait)
local longstring = string.rep("[^\n]", longline)

local function finalize(t)
	if recframe == 0 then
		print("Stopped recording after zero frames.") print()
		return
	end
	
	--Determine how many players were active.
	local activeplayers = 0
	for p = nplayers,1,-1 do
		for f = 1,recframe do
			if t[f] and t[f][p] then
				activeplayers = p
				break
			end
		if activeplayers > 0 then break end
		end
	end
	if activeplayers == 0 then
		print("Stopped recording: No input was entered in", recframe, "frames.") print()
		return
	end
	
	--Substitute _holds and ^releases for long press sequences.
	if longpress > 0 then
		for p = 1,activeplayers do
			for _,key in ipairs(keymap) do
				local hold,release,pressed,oldpressed = 0,0,false,false
				for f = 1,recframe+1 do
					pressed = t[f] and t[f][p] and t[f][p]:find(key.symbol)
					if pressed and not oldpressed then hold = f end
					if not pressed and oldpressed then release = f
						if release-hold >= longpress then --only hold if the press is long
							t[release] = t[release] or {}
							t[release][p] = t[release][p] or ""
							if f == recframe+1 then recframe = f end --add another frame to process the release if necessary
							for fr = hold,release do t[fr][p] = t[fr][p]:gsub(key.symbol, "") end --take away the presses
							t[hold][p] = t[hold][p] .. "_" .. key.symbol --add the hold at the beginning
							t[release][p] = t[release][p] .. "^" .. key.symbol --add the release at the end
						end
					end
					oldpressed = pressed
				end
			end
		end
	end
	
	--Compose the text in bracket format.
	local text = "# " .. (emu.romname and emu.romname() .. " " or "") .. os.date() .. "\n\n"
	local sep = "<"
	for p = 1,activeplayers do
		local str = sep .. " # Player " .. p .. "\n"
		for f = 1,recframe do
			str = str .. (t[f] and t[f][p] or "") .. "."
		end
		text = text .. str .. "\n\n"
		sep = "/"
	end
	t = nil
	text = text .. ">\n"
	
	--If only Player 1 is active, get rid of the brackets.
	if not text:find("\n/") then
		text = text:gsub("< # Player 1\n", "")
		text = text:gsub("\n\n>", "")
	end
	
	--Collapse long waits into W's.
	if longwait > 0 then
		text = text:gsub("([\n%.])(" .. waitstring .. "+)", function(c,n)
			return c .. "W" .. string.len(n) .. ","
		end)
	end
	text = text:gsub(",\n", "\n") --Remove trailing commas.
	
	--Break up long lines.
	if longline > 0 then
		local startpos,endpos = 0,0
		local before,after = text:sub(1, endpos), text:sub(endpos+1)
		while after:find("\n(" .. longstring .. ".-),") do --Search for a long stretch w/o breaks.
			text = before .. after:gsub("\n(" .. longstring .. ".-),", function(line) --Insert a break after the next comma.
				return "\n" .. line .. ",\n"
			end, 1) --Do this once per search.
			startpos,endpos = text:find("\n(" .. longstring .. ".-),", endpos) --Advance the start of the next search.
			before,after = text:sub(1, endpos), text:sub(endpos+1)
		end
	end
	
	--Save the text.
	local prefix = emu.romname and emu.romname() .. "-" or ""
	local filename = prefix .. os.date("%Y-%m-%d_%H-%M-%S") .. ".mis"
	-- if playbackfile == "last_recording.mis" then
	-- 	filename = "last_recording.mis"
	-- end
	local use_char_specific_slot = globals.options.use_character_specific_slots
	local prepend_to_path = ""
	if use_char_specific_slot then 
		prepend_to_path = globals.dummy.p2_char
	end
	filename = prepend_to_path.."/"..globals.dummy.recording_slot 

	local file = io.output(path:gsub("\\", "/") .. filename)
	file:write(text) --Write to file.
	file:close() --Close the file.
	print("Recorded", recframe, "frames to", filename .. ".") print()
end

----------------------------------------------------------------------------------------------------
--[[ Set up the variables and functions for user control of playback and recording. ]]--

local playing,recording,pauseafterplay,pausenow,framediff = false,false,false,false

local function bulletproof(active, f1, f2, t1, t2) --1 = current, 2 = loaded
	if not active then return false end
	if f1 == 0 then return true end --loading on 0th frame is always OK
	if not t2 then
		print("Error: loaded state has no macro data")
		return false
	end
	for f = 1,f2 do
		if type(t1[f]) ~= type(t2[f]) then --one has data in a table, the other is empty/nil
			print("Error: loaded macro does not match current macro on frame " .. f)
			return false
		elseif t1[f] and t2[f] then --both are tables with nonblank data
			for p = 1,nplayers do
				if t1[f][p] ~= t2[f][p] then
					print("Error: loaded macro does not match current macro on frame " .. f)
					return false
				end
			end
		end
	end
	print("Resumed from frame " .. f2) --no errors
	return true
end


local function dostate(f)
	if stateop[f+1] then
		if savestate.create and savestate[stateop[f+1]] then
			savestate[stateop[f+1]](savestate.create(stateslot[f+1])) return
		elseif savestate[stateop[f+1]] then
			savestate[stateop[f+1]](stateslot[f+1]) return
		end
		warning("cannot do savestates with Lua in this emulator",true)
	end
end

local function dumpinputstream()
	if not dumpmode then return end
	local dump = ""
	for p = 1,nplayers do --header row
		dump = dump .. "|"
		for _,key in ipairs(keymap) do
			dump = dump .. key.symbol
		end
		for _,control in ipairs(analog) do
			dump = dump .. string.format("%"..control.spaces.."s", control.symbol)
		end
	end
	dump = dump .. "|\n"
	for f = 1,macrosize do --frame rows
		for p = 1,nplayers do
			dump = dump .. "|"
			for _,key in ipairs(keymap) do
				if inputstream[f] and inputstream[f][p] and inputstream[f][p][key.symbol] then
					dump = dump .. key.symbol
				else
					dump = dump .. "."
				end
			end
			for _,control in ipairs(analog) do
				if inputstream[f] and inputstream[f][p] and inputstream[f][p][control.symbol] then
					local number = string.format("%X", math.abs(inputstream[f][p][control.symbol]))
					dump = dump .. string.format("%"..control.spaces.."s", (inputstream[f][p][control.symbol] < 0 and "-" or "") .. number)
				else
					dump = dump .. string.rep(" ", control.spaces)
				end
			end
		end
		if stateop[f] and stateslot[f] then
			dump = dump .. "| " .. stateop[f] .. " slot " .. stateslot[f] .. "\n"
		else
			dump = dump .. "|\n"
		end
	end
	local filename = globals.dummy.recording_slot:gsub("%....$", "")
	filename = filename .. "-inputstream.txt"
	local file = io.output(path:gsub("\\", "/") .. filename)
	file:write(dump) --Write to file.
	file:close() --Close the file.
	print("Converted " .. globals.dummy.recording_slot .. " to " .. filename .. " (" .. macrosize .. " frames)") print()
	return true
end
function stop_macro_playback()
	if playing then 
		playing = false
	end
end
function start_macro_playback()
		playing = true
end
local function get_playback_file()
	local slot = globals.dummy.recording_slot
	if globals.options.random_playback == true then
		local use_char_specific_slot = globals.options.use_character_specific_slots
		local prepend_to_path = ""
		if use_char_specific_slot then 
			prepend_to_path = globals.dummy.p2_char
		end
		local slots = {
			["1"] = {enabled = globals.options.enable_slot_1, filename = prepend_to_path.."/".."slot_1.mis"},
			["2"] = {enabled = globals.options.enable_slot_2, filename = prepend_to_path.."/".."slot_2.mis"},
			["3"] = {enabled = globals.options.enable_slot_3, filename = prepend_to_path.."/".."slot_3.mis"},
			["4"] = {enabled = globals.options.enable_slot_4, filename = prepend_to_path.."/".."slot_4.mis"},
			["5"] = {enabled = globals.options.enable_slot_5, filename = prepend_to_path.."/".."slot_5.mis"}
		}
		local numItems = 0
		local enabled_slots = {}
		for k,v in pairs(slots) do
			if v.enabled == true then
				enabled_slots[numItems] = v.filename
				numItems = numItems + 1
			end
		end
		if numItems == 0 then
			emu.message("No slots selected for random playback")
			return globals.dummy.p2_char.."/"..globals.dummy.recording_slot 
		end
		local seed = math.random(0, numItems - 1)
		slot = enabled_slots[seed]
		return slot
	else 
		local use_char_specific_slot = globals.options.use_character_specific_slots
		local prepend_to_path = ""
		if use_char_specific_slot then 
			prepend_to_path = globals.dummy.p2_char
		end
		return prepend_to_path.."/"..slot
	end
end
local function playcontrol(silent)
	local slot = get_playback_file()
	if not playing then
		if not parse(slot) or warning("Macro is zero frames long.", macrosize == 0) or dumpinputstream(dumpmode) then
			return
		end
		if not silent then
			print("Now playing " .. slot .. " (" .. macrosize .. " frames)" .. (loopmode and " in loop mode" or wait.duration and " in incremental wait mode" or ""))
		end
		dostate(frame)
		playing = true
		framediff = emu.framecount()
	else 
		playing = false
		inputstream = nil
		if wait.duration then
			print("Stopped at wait duration = " .. wait.duration) print()
			wait = {}
		elseif loopmode then
			print("Stopped looping playback on frame " .. frame) print()
		else
			print("Canceled playback on frame " .. frame) print()
		end
	end
end

local function reccontrol()
	if not recording then
		recording = true
		recframe = 0
		recinputstream = {}
		print("Started recording.")
	else 
		recording = false
		finalize(recinputstream)
	end
end

-- emu.registerexit(function() --Attempt to save if the script exits while recording
-- 	if recording then recording = false finalize(recinputstream) end
-- end)

local function togglepause()
	pauseafterplay = not pauseafterplay
	print("Pause after playback mode: " .. (pauseafterplay and "on" or "off"))
end

local function toggleloop()
	if wait.increment == 1 then
		wait.increment, wait.change = -1, " (decreasing)"
	elseif wait.increment == -1 then
		wait.increment, wait.change = 0, " (constant)"
	elseif wait.increment == 0 then
		wait.increment, wait.change = 1, " (increasing)"
	else
		loopmode = not loopmode
		print("Loop mode: " .. (loopmode and "on" or "off"))
	end
end
function setloop()
	loopmode = globals.options.looped_playback
end

local oldplaykey,oldrecordkey,oldpausekey,oldloopkey

-- if i

macroLuaModule = {
	["gameLoop"] = function()
		if pausenow then
			emu.pause()
			pausenow = false
		end
		emu.frameadvance()
		-- print("advanced frame")
	end,
	
	["registerStart"] = function()

		if io.open('input-display.lua', "r") then
			dofile("input-display.lua", "r")
		end
		print()
		findarcademodule()
	end,

    ["registerAfter"] = function() --recording is done after the frame, not before, to catch input from playing macros
		if recording then
			recframe = recframe+1
			for p = 1,nplayers do
				for n,key in ipairs(keymap or {}) do
					if joypad.get(p)[keymap[n][p]] == 1 or joypad.get(p)[keymap[n][p]] == true then
						recinputstream[recframe] = recinputstream[recframe] or {}
						recinputstream[recframe][p] = not recinputstream[recframe][p] and key.symbol or recinputstream[recframe][p] .. key.symbol
					end
				end
			end
		end

		if playing or recording then
			local pmesg = playing and ("macro playing: " .. frame .. "/" .. macrosize) or ""
			if wait.duration then
				pmesg = pmesg .. "; incremental wait: " .. wait.duration .. wait.change
			elseif loopmode then
				pmesg = pmesg .. " in loop mode"
			end
			local rmesg = recording and "macro recording: " .. recframe or ""
			emu.message(pmesg .. (playing and recording and "   " or "") .. rmesg)
		end
	end,

	["registerExit"] = function() --Attempt to save if the script exits while recording
		if recording then recording = false finalize(recinputstream) end
	end,

	["registerBefore"] = function()
		if not input.registerhotkey and not guiregisterhax then --as a last resort, check for hotkeys the hard way (snes9x & vba)
			local nowplaykey = input.get()[playkey]
			if nowplaykey and not oldplaykey then
				playcontrol()
			end
			oldplaykey = nowplaykey
	
			local nowrecordkey = input.get()[recordkey]
			if nowrecordkey and not oldrecordkey then
				reccontrol()
			end
			oldrecordkey = nowrecordkey
	
			local nowpausekey = input.get()[togglepausekey]
			if nowpausekey and not oldpausekey then
				togglepause()
			end
			oldpausekey = nowpausekey
	
			local nowloopkey = input.get()[toggleloopkey]
			if nowloopkey and not oldloopkey then
				toggleloop()
			end
			oldloopkey = nowloopkey
		end
			
		--framediff check is necessary for emus where registerbefore runs multiple times per frame
		if playing and emu.framecount()-frame >= framediff then
			frame = frame+1
			dostate(frame)
			inputstream[frame] = inputstream[frame] or {}
			for p = 1,nplayers do
				inputstream[frame][p] = inputstream[frame][p] or {}
			end
			if fba or mame then --In fba and mame, joypad.set is called once without a player number.
				keytable = {}
				for p = 1,nplayers do
					for n,key in ipairs(keymap) do
						if inputstream[frame][p][key.symbol] then
							keytable[keymap[n][p]] = true
						end
					end
					for n,control in ipairs(analog) do
						if inputstream[frame][p][control.symbol] then
							keytable[analog[n][p]] = inputstream[frame][p][control.symbol]
						end
					end
				end
				if keytable["Reset"] == 1 and emu.softreset then emu.softreset() end
			else --In other emus, joypad.set is called separately for each player.
				keytable = {}
				for p = 1,nplayers do
					keytable[p] = joypad.getdown(p) --This allows lua+user input
					for n,key in ipairs(keymap) do
						if inputstream[frame][p][key.symbol] then keytable[p][keymap[n][p]] = true end
					end
				end
			end
			if globals.options.looped_playback == false then
				if frame > macrosize then
					playing = false
					inputstream = nil
					pausenow = pauseafterplay
					if wait.duration then
						wait.duration = wait.duration + wait.increment
						if wait.duration < 0 then wait.duration = 0 end
						playcontrol(true)
					elseif loopmode then
						playcontrol(true)
					else
						print("Macro finished playing.") print()
					end
				end
			end
			if globals.options.looped_playback == true then
				if frame > macrosize then
					playing = false
					inputstream = nil
					pausenow = pauseafterplay
					savestate.load("current_recording")
					playcontrol(true)
					print(macrosize)
				else
					print("Macro finished playing.") print()
				end
			end
		end
	
			--must joypad.set the keytable with every registerbefore, even if multiple times per frame, to ensure all keys are sent
			if playing then
				if fba or mame then
					-- joypad.set(keytable)
				else
					for p = 1,nplayers do joypad.set(p, keytable[p]) end
				end
			end

			globals.playing = playing
			globals.recording = recording
			return {
				["playcontrol"] = playcontrol,
				["reccontrol"] = reccontrol,  
				["toggleloop"] = toggleloop,
				["setloop"] = setloop,
				["stop_macro_playback"] = stop_macro_playback,
				["start_macro_playback"] = start_macro_playback,
				["recording"] = recording,
				["playing"] = playing,
				["get_keytable"] = function()
					-- if playing then return keytable else return {} end
					if keytable then
						-- if player_objects[2].flip_input then
						-- 	local should_flip = player_objects[2].flip_input
						-- 	local flipped = {}
						-- 	for k,v in pairs(keytable) do
						-- 		if k == "P2 Right" then
						-- 			flipped["P2 Left"] = true
						-- 		elseif k == "P2 Left" then
						-- 			flipped["P2 Right"] = true
						-- 		else
						-- 			flipped[k] = v
						-- 		end
						-- 	end
						-- 	keytable = flipped
						-- end
						return keytable
					else 
						return {}
					end
				end,
			}
		end,

	["registerSave"] = function(slot)
		if mame then return emu.framecount() end
		if playing then print("Saved progress to slot", slot, "while playing frame", frame) end
		if recording then print("Saved progress to slot", slot, "while recording frame", recframe) end
		if playing or recording then return frame, inputstream, macrosize, recframe, recinputstream end
	end,
	
	["registerLoad"] = function(slot)
		if mame then
			framediff = savestate.loadscriptdata(slot)
			if playing and not framediff then
				--[[if not (wait.duration or loopmode) then
					print("Savestate " .. slot .. " has no framecount data. This macro may not play correctly!")
					print("Resave this savestate with the script running and idle to avoid problems.")
				end]]
				framediff = emu.framecount()
			end
			return
		end
		if not playing and not recording then
			return
		end
		if playing and not loopmode then
			print("Loaded from slot", slot, "while playing frame", frame)
		end
		if recording then
			print("Loaded from slot", slot, "while recording frame", recframe)
		end
		local tmp = {}
		tmp.frame,tmp.inputstream,tmp.macrosize,tmp.recframe,tmp.recinputstream = savestate.loadscriptdata(slot)
		playing = bulletproof(playing,frame,tmp.frame,inputstream,tmp.inputstream)
		recording = bulletproof(recording,recframe,tmp.recframe,recinputstream,tmp.recinputstream)
		frame          = tmp.frame          or frame
		inputstream    = tmp.inputstream    or inputstream
		macrosize      = tmp.macrosize      or macrosize
		recframe       = tmp.recframe       or recframe
		recinputstream = tmp.recinputstream or recinputstream
	end
}
return macroLuaModule