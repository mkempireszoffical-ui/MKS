--!nocheck
-- MKS Hub for Practical Basketball (Real executor).
-- Source of truth: C:\Users\Lacedyaza\claude code\PracticalBasketball\MKS-Hub.luau
-- Copies: Real Scripts\MKS Hub.lua and Real workspace\MKS-Hub.lua (re-run after teleport).
-- Everything here uses the game's ordinary inputs (keypress/keyrelease of the player's own keys) or
-- client-only visuals. No teleports, no forced CFrame/velocity, no hidden-property or remote spoofing.
local genv = (getgenv and getgenv()) or _G
-- Free build only: the file is public, so it checks its own Work.ink key (link 5073123, or a dashboard key of account 756405) before doing anything.
-- shortcut: a client-side check in an unobfuscated public file can be edited out; it only stops casual ad skipping
do
	local key = tostring(genv.script_key or "")
	local ok, res = pcall(function() return game:GetService("HttpService"):JSONDecode(game:HttpGet("https://work.ink/_api/v2/token/isValid/" .. key)) end)
	if not (ok and type(res) == "table" and res.valid == true and type(res.info) == "table" and (tonumber(res.info.linkId) == 5073123 or tonumber(res.info.userId) == 756405)) then
		error("MKS Free: key expired or invalid. Get a new one from the key screen.", 0)
	end
end
for _, k in {"__mks_kill", "__pb_autotime_kill"} do
	if genv[k] then pcall(genv[k]) end
end
local LR = getfenv and getfenv(1).STATE -- Real live-reload state, nil when run from a file
local conns, cleanups = {}, {}
local function on(signal, fn)
	local c = LR and LR.connect(signal, fn) or signal:Connect(fn)
	table.insert(conns, c)
	return c
end
local function onCleanup(fn) table.insert(cleanups, fn) end

---------------------------------------------------------------- executor capabilities
-- Every executor-specific function is looked up once here, with its tested fallback; the rest of the file uses only
-- these locals, never the raw globals. genv.__mks_capOverride = {api = false} hides one API so its fallback can be
-- exercised on a full executor (that is test evidence for the fallback, not for another executor).
local CAP = {list = {}}
-- the hot ones are locals; the rest live on CAP (Luau allows 200 locals per chunk)
local keypress, keyrelease, isrbxactive, filtergc, gethui, readfile, writefile
do
	local ov = genv.__mks_capOverride or {}
	local sy = type(syn) == "table" and syn or {}
	local function find(name, ...)
		if ov[name] == false then return nil end
		for i = 1, select("#", ...) do
			local f = select(i, ...)
			if type(f) == "function" then return f end
		end
	end
	local function note(api, have, fallback, effect)
		table.insert(CAP.list, {api = api, status = if have then "ok" elseif fallback then "fallback" else "missing", effect = effect})
	end
	-- through this script's environment, which falls back to the executor's globals
	local env = getfenv and getfenv(1) or _G
	local function g(n) local ok, v = pcall(function() return env[n] end) if ok and v ~= nil then return v end return genv[n] end

	keypress, keyrelease = find("keypress", g("keypress")), find("keyrelease", g("keyrelease"))
	CAP.keys = keypress ~= nil and keyrelease ~= nil
	note("keypress/keyrelease", CAP.keys, false, "dribble moves use the game's dribble action; Perfect Timing, auto block jump and macros that hold keys are off")

	isrbxactive = find("isrbxactive", g("isrbxactive"), g("iswindowactive"))
	if not isrbxactive then
		-- shortcut: assumes the window is focused when MKS loads, upgrade if an executor exposes window focus
		local focused = true
		local UIS0 = game:GetService("UserInputService")
		table.insert(conns, UIS0.WindowFocused:Connect(function() focused = true end))
		table.insert(conns, UIS0.WindowFocusReleased:Connect(function() focused = false end))
		isrbxactive = function() return focused end
	end
	note("isrbxactive", find("isrbxactive", g("isrbxactive"), g("iswindowactive")) ~= nil, true, "window focus read from Roblox's WindowFocused events")

	filtergc = find("filtergc", g("filtergc"))
	-- no getgc fallback: walking the whole heap freezes the client (Real refuses it outright)
	note("filtergc", filtergc ~= nil, false,
		"game settings, key map, mascots and Practice Defender cannot be read")

	CAP.getcustomasset = find("getcustomasset", g("getcustomasset"), g("getsynasset"), sy.getcustomasset)
	note("getcustomasset", CAP.getcustomasset ~= nil, false, "text logo and no icons")

	CAP.queue_on_teleport = find("queue_on_teleport", g("queue_on_teleport"), g("queueonteleport"), sy.queue_on_teleport)
	CAP.clear_teleport_queue = find("clear_teleport_queue", g("clear_teleport_queue"), g("clearteleportqueue"))
	note("queue_on_teleport", CAP.queue_on_teleport ~= nil, false, "re-execute MKS after a server change")

	local gh = find("gethui", g("gethui"), g("get_hidden_gui"), sy.get_hidden_gui)
	gethui = gh or function()
		local ok = pcall(function()
			local t = Instance.new("Folder")
			t.Parent = game:GetService("CoreGui")
			t:Destroy()
		end)
		if ok then return game:GetService("CoreGui") end
		return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	end
	note("gethui", gh ~= nil, true, "menu parented to CoreGui, or PlayerGui when CoreGui is locked")

	CAP.setclipboard = find("setclipboard", g("setclipboard"), g("toclipboard"), sy.write_clipboard)
	note("setclipboard", CAP.setclipboard ~= nil, false, "Copy code button unavailable")

	CAP.identifyexecutor = find("identifyexecutor", g("identifyexecutor"), g("getexecutorname"))
		or function() return "unknown" end

	readfile, writefile = find("readfile", g("readfile")), find("writefile", g("writefile"))
	CAP.isfile, CAP.isfolder, CAP.makefolder = find("isfile", g("isfile")), find("isfolder", g("isfolder")), find("makefolder", g("makefolder"))
	CAP.persist = readfile ~= nil and writefile ~= nil
	if not CAP.persist then
		-- settings live in memory for this server only
		local mem = {}
		readfile = function(path) local v = mem[path] if v == nil then error("no file " .. path) end return v end
		writefile = function(path, v) mem[path] = v end
		CAP.isfile = function(path) return mem[path] ~= nil end
	end
	CAP.isfile = CAP.isfile or function(path) return (pcall(readfile, path)) end
	CAP.isfolder = CAP.isfolder or function() return true end
	CAP.makefolder = CAP.makefolder or function() end
	note("readfile/writefile", CAP.persist, true, "settings kept in memory until you leave this server")
	CAP.executor = select(2, pcall(CAP.identifyexecutor)) or "unknown"
end
-- registered first so a load that fails halfway can still be unloaded; the full version replaces it at the end
genv.__mks_kill = function()
	genv.__mks_kill = nil
	for _, c in conns do pcall(function() c:Disconnect() end) end
	for i = #cleanups, 1, -1 do pcall(cleanups[i]) end
end

-- CAP.queue_on_teleport runs this before the new place has loaded
if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
while not Players.LocalPlayer do task.wait() end
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local TS = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local lp = Players.LocalPlayer
local VERSION = "2.0.0"
-- build tier. tools/build_tiers.py writes MKS-Free.lua from this file: TIER = "free" and every --#premium ... --#end
-- block removed (so the Free build does not contain Premium code); --#free lines become code only in the Free build
local TIER = "free"
local PREMIUM = TIER == "premium"
local FREE_MOVE = {Crossover = true, Hesitation = true, BehindBack = true, StepBack = true, SwitchHand = true}

---------------------------------------------------------------- files / config
local DIR = "MKS"
pcall(function() if not CAP.isfolder(DIR) then CAP.makefolder(DIR) end end)
pcall(function() if not CAP.isfolder(DIR .. "/configs") then CAP.makefolder(DIR .. "/configs") end end)
local CFG_FILE, LOG_FILE, AUTOLOAD_FILE = DIR .. (if PREMIUM then "/config.json" else "/config-free.json"), DIR .. "/log.json", DIR .. "/autoload.txt"
local function readJson(file)
	local ok, v = pcall(function() return Http:JSONDecode(readfile(file)) end)
	return ok and type(v) == "table" and v or nil
end
local function writeJson(file, v) return pcall(writefile, file, Http:JSONEncode(v)) end

local CONTEST_SEED = {48.5, 55.1, 57.3, 35.5, 9, 1.5, 0.2} -- mean real contest % per stud of defender distance
local DEFAULTS = {
	v = 2,
	timing = {enabled = true, autoCal = true, ping = true, pingFactor = 1, extraLeadMs = 0, manualMode = false,
		profile = "Jumper", styleMs = {}, key = "F6"},
	profiles = {},
	anti = {enabled = true, maxPct = 20, pump = false, showPct = true, showRange = false, range = 27},
	shoot = {auto = false, autoKey = "", autoHold = false, autoCoolMs = 2500, selfLob = false, lobRange = 12},
	contestBins = {},
	meter = {recolor = false, fill = "White", fade = "Silver", green = "Green", back = "Black", scale = 1},
	block = {enabled = false, key = "F5", range = 14, commitMs = 170, delayMs = 40, rimDelayMs = 0, cooldownMs = 1200,
		teamCheck = true, jumpers = true, rim = true, shift = true, maxShift = 4, los = true, holdKey = "",
		-- per shot category (OT layout); jumper-type delays use MKS's measured 40 ms, rim-type 0 ms
		cats = {
			Jumpshots = {on = true, delayMs = 40, range = 14, sprint = true}, CloseShots = {on = true, delayMs = 0, range = 14, sprint = true},
			Fadeaways = {on = true, delayMs = 40, range = 14, sprint = true}, Floaters = {on = true, delayMs = 0, range = 14, sprint = true},
			FreeThrows = {on = true, delayMs = 40, range = 14, sprint = true}, Layups = {on = true, delayMs = 0, range = 14, sprint = true},
			MovingShots = {on = true, delayMs = 40, range = 14, sprint = true}, PostMovingShots = {on = true, delayMs = 40, range = 14, sprint = true},
			ClutchShots = {on = true, delayMs = 0, range = 14, sprint = true}, Dunks = {on = false, delayMs = 0, range = 14, sprint = true},
		}},
	rebound = {enabled = false, range = 10, rimRange = 10, delayMs = 0, minY = 3},
	guard = {enabled = false, key = "", dist = 5, holdG = true, sprint = false, ballOnly = true, teamCheck = true,
		reactionMs = 150, mistakes = 0, hold = false,
		range = 20, dribDist = 5, dynDist = false, dynK = 3, sticky = true, predictMs = 150, pauseEvery = 3, pauseMs = 200,
		sway = 0.4, bounds = true, boundsMargin = 2, screenAvoid = false, screenRadius = 8},
	runup = {enabled = false, key = "", hold = false, maxEngage = 45, stopDist = 3, predictMs = 300, smartSprint = true, delayMs = 0, jump = true},
	deny = {enabled = false, key = "F", hold = true, range = 7, dist = 2, cut = false, cutDist = 4, teamCheck = true},
	dribble = {binds = {}, combos = {}, comboKeys = {}, combo = "Main", interval = 0, direct = true,
		playKey = "", loopKey = "", stopKey = "", ankle = false, ankleRange = 5, ankleMove = "Crossover"},
	world = {fov = false, fovVal = 70, fullbright = false, noPost = false, spectate = false, target = "",
		mascot = "Wolf", customMascot = "", wearMascot = false, logo = false, logoId = "", weather = "None", weatherAmount = 40},
	misc = {antiAfk = true, debugConsole = false, fpsBoost = false, hideName = false},
	char = {speed = false, speedMult = 1.15, stamina = false},
	-- controller profile: buttons are KeyCode names, a chord is "ButtonR2+ButtonR3" (hold the first, press the second)
	pad = {menu = "ButtonSelect", binds = {}, playKey = "", stopKey = ""},
	ui = {hubKey = "RightShift", scale = 1, autoScale = true, dim = true, watermark = false, theme = "Graphite", autoHide = false,
		glow = true, shimmer = true, cardOpacity = 0, font = "Gotham", reloadTp = true, mobileToggle = false, autosave = true},
}
for i, m in CONTEST_SEED do DEFAULTS.contestBins[i] = {mean = m, n = 4} end

-- merge saved over defaults: known keys only, but open maps (empty default tables) keep every saved entry
local function merge(def, sav)
	if type(def) ~= "table" then
		if sav == nil or type(sav) ~= type(def) then return def end
		return sav
	end
	if next(def) == nil then return type(sav) == "table" and sav or {} end
	if #def > 0 then return type(sav) == "table" and #sav > 0 and sav or table.clone(def) end -- arrays
	local out = {}
	for k, v in def do out[k] = merge(v, type(sav) == "table" and sav[k] or nil) end
	return out
end

local cfg
do
	local saved = readJson(CFG_FILE)
	if not saved then
		-- first run of v2: migrate the old autotime config (backed up first, original left untouched)
		local old = readJson("pb_autotime_cfg.json")
		if old then
			writeJson(DIR .. "/backup_pb_autotime_cfg.json", old)
			saved = {timing = {enabled = old.enabled, autoCal = old.autoCal, pingFactor = old.pingFactor, extraLeadMs = old.extraLeadMs},
				anti = old.anti, contestBins = old.contestBins, ui = {hubKey = old.hubKey}}
			if old.block then saved.block = {enabled = old.block.enabled, range = old.block.range, delayMs = old.block.delayMs, rimDelayMs = old.block.rimDelayMs} end
			if old.types and old.types.Jumpshot1 and old.types.Jumpshot1.peakSeen then
				saved.profiles = {Jumper = {target = old.types.Jumpshot1.frac * old.types.Jumpshot1.peak}}
			end
		end
	end
	cfg = merge(DEFAULTS, saved or {})
end
-- combos are an open map (user-named); seed the starter one only when there are none
if next(cfg.dribble.combos) == nil then cfg.dribble.combos.Main = {"Crossover", "BehindBack", "StepBack"} end
if not cfg.dribble.combos[cfg.dribble.combo] then cfg.dribble.combo = next(cfg.dribble.combos) end
if not PREMIUM then
	-- Free tier: own config file; Premium systems stay off and only the starter moves and combos exist
	cfg.guard.enabled, cfg.runup.enabled, cfg.deny.enabled, cfg.rebound.enabled = false, false, false, false
	cfg.shoot.auto, cfg.shoot.selfLob, cfg.dribble.ankle = false, false, false
	cfg.misc.fpsBoost, cfg.misc.hideName, cfg.ui.autoHide = false, false, false
	cfg.world.fov, cfg.world.fullbright, cfg.world.noPost, cfg.world.spectate, cfg.world.weather = false, false, false, false, "None"
	cfg.dribble.combos = {Starter = {"Crossover", "BehindBack", "StepBack"}, Shake = {"Hesitation", "Crossover"}}
	if not cfg.dribble.combos[cfg.dribble.combo] then cfg.dribble.combo = "Starter" end
	for mv in cfg.dribble.binds do if not FREE_MOVE[mv] then cfg.dribble.binds[mv] = nil end end
	cfg.dribble.comboKeys = {}
	for mv in cfg.pad.binds do if not FREE_MOVE[mv] then cfg.pad.binds[mv] = nil end end
end
local log = readJson(LOG_FILE) or {}
local dirty, logDirty = false, false
local function markDirty() dirty = true end
local function saveNow()
	writeJson(CFG_FILE, cfg)
	if logDirty then writeJson(LOG_FILE, log) end
	dirty, logDirty = false, false
end
local function pushLog(e)
	table.insert(log, e)
	if #log > 600 then table.remove(log, 1) end
	logDirty = true
	markDirty()
end
-- in-hub diagnostics: routine events and real errors land here (shown on Info > Diagnostics), never in the
-- Developer Console unless the user turns "Echo to Developer Console" on. Bounded to 80 entries.
local diag = {}
local function report(level, msg)
	table.insert(diag, {t = os.date("%H:%M:%S"), level = level, msg = tostring(msg)})
	if #diag > 80 then table.remove(diag, 1) end
	if cfg.misc.debugConsole then (if level == "error" then warn else print)("[MKS] " .. tostring(msg)) end
end
local function getp(path)
	local t = cfg
	for k in path:gmatch("[^%.]+") do
		if type(t) ~= "table" then return nil end
		t = t[k]
	end
	return t
end
local function setp(path, v)
	local keys = {}
	for k in path:gmatch("[^%.]+") do table.insert(keys, k) end
	local t = cfg
	for i = 1, #keys - 1 do t = t[keys[i]] end
	t[keys[#keys]] = v
	markDirty()
end

---------------------------------------------------------------- keys
local VK = {Space = 0x20, LeftShift = 0xA0, RightShift = 0xA1, LeftControl = 0xA2, Tab = 0x09, Return = 0x0D,
	Zero = 0x30, One = 0x31, Two = 0x32, Three = 0x33, Four = 0x34, Five = 0x35, Six = 0x36, Seven = 0x37, Eight = 0x38, Nine = 0x39}
for i = 0, 25 do VK[string.char(65 + i)] = 65 + i end
for i = 1, 12 do VK["F" .. i] = 0x6F + i end
-- Windows virtual-key codes for the rest of the keyboard (only needed for keys MKS itself has to press)
for i, n in {"KeypadZero", "KeypadOne", "KeypadTwo", "KeypadThree", "KeypadFour", "KeypadFive", "KeypadSix", "KeypadSeven",
	"KeypadEight", "KeypadNine"} do VK[n] = 0x5F + i end
for n, v in {KeypadMultiply = 0x6A, KeypadPlus = 0x6B, KeypadMinus = 0x6D, KeypadPeriod = 0x6E, KeypadDivide = 0x6F,
	RightControl = 0xA3, LeftAlt = 0xA4, RightAlt = 0xA5, CapsLock = 0x14, Left = 0x25, Up = 0x26, Right = 0x27, Down = 0x28,
	Insert = 0x2D, Home = 0x24, End = 0x23, PageUp = 0x21, PageDown = 0x22, Backquote = 0xC0, Minus = 0xBD, Equals = 0xBB,
	LeftBracket = 0xDB, RightBracket = 0xDD, BackSlash = 0xDC, Semicolon = 0xBA, Quote = 0xDE, Comma = 0xBC, Period = 0xBE} do VK[n] = v end
-- keys a bind may never use, with the reason shown to the player
local RESERVED = {Escape = "Roblox menu (and cancels capture)", Backspace = "unbinds in the capture prompt",
	Delete = "unbinds in the capture prompt", Slash = "opens Roblox chat", F9 = "Roblox Developer Console", F11 = "Roblox fullscreen",
	Print = "screenshot", LeftSuper = "Windows key", RightSuper = "Windows key", Menu = "Windows context menu", Unknown = "unrecognised key"}
local keyCode
do
local kcCache = {}
function keyCode(name)
	if kcCache[name] == nil then
		local ok, k = pcall(function() return Enum.KeyCode[name] end)
		kcCache[name] = ok and k or false
	end
	return kcCache[name] or nil
end
end
local held, synthAt = {}, {} -- synthetic keys we hold, and when we last sent each (so our own events are ignored)
local function kdown(name)
	local vk = VK[name]
	if not vk or held[name] then return end
	-- synthetic keys go to whatever window is in front: never type into another app
	if not CAP.keys or not isrbxactive() then return end
	held[name] = true
	synthAt[name] = os.clock()
	keypress(vk)
end
local function kup(name)
	local vk = VK[name]
	if not vk or not held[name] then return end
	held[name] = nil
	synthAt[name] = os.clock()
	if keyrelease then keyrelease(vk) end
end
local function ktap(name, ms)
	kdown(name)
	task.wait((ms or 30) / 1000)
	kup(name)
end
local function releaseAll() for name in held do kup(name) end end
local function isSynthetic(name) return synthAt[name] ~= nil and os.clock() - synthAt[name] < 0.12 end
local function physicallyDown(name)
	local kc = keyCode(name)
	return kc ~= nil and not held[name] and not isSynthetic(name) and UIS:IsKeyDown(kc)
end
onCleanup(releaseAll)

---------------------------------------------------------------- game helpers
local function rig()
	local f = workspace:FindFirstChild("Characters")
	return f and f:FindFirstChild(lp.Name)
end
local function hrpOf(m) return m and m:FindFirstChild("HumanoidRootPart") end
local function hasBall(m)
	local h = hrpOf(m)
	local w = h and h:FindFirstChild("Basketball")
	return w ~= nil and w:IsA("Motor6D") and w.Part1 ~= nil
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function meterOf(r)
	local m = r and r:GetAttribute("meterOffset")
	if typeof(m) ~= "Vector2" then return nil end
	return math.max(math.abs(m.X), math.abs(m.Y))
end
local function shotAnim(r)
	local a = r:GetAttribute("BaseAnimation")
	return typeof(a) == "string" and a ~= "" and (a:gsub("Base$", "")) or nil
end
local FAMILIES = {"Jumper", "Layup", "Dunk", "ReverseL", "ReverseR"}
local function family(anim, action)
	anim = anim or ""
	if anim:find("Reverse") then return if anim:find("L$") then "ReverseL" else "ReverseR" end
	if action == "Dunking" or anim:find("Dunk") then return "Dunk" end
	if anim:find("Layup") or anim:find("Close") or anim:find("Floater") then return "Layup" end
	return "Jumper"
end
-- OT's block categories, read from the game's own shot animation names (BaseAnimation)
local SHOT_CATS = {"Jumpshots", "CloseShots", "Fadeaways", "Floaters", "FreeThrows", "Layups", "MovingShots", "PostMovingShots", "ClutchShots", "Dunks"}
local function shotCategory(anim, action)
	anim = anim or ""
	if action == "Dunking" or anim:find("Dunk") then return "Dunks" end
	if anim:find("FreeThrow") then return "FreeThrows" end
	if anim:find("Clutch") then return "ClutchShots" end
	if anim:find("^Post") or anim:find("PostFade") then return "PostMovingShots" end
	if anim:find("MovingShot") then return "MovingShots" end
	if anim:find("Floater") then return "Floaters" end
	if anim:find("Fade") then return "Fadeaways" end
	if anim:find("CloseShot") then return "CloseShots" end
	if anim:find("Layup") then return "Layups" end
	return "Jumpshots"
end
do -- self-check against real animation names on this build
	for a, want in {Jumpshot1R = "Jumpshots", FadeAwayL = "Fadeaways", CloseFadeR = "Fadeaways", UnderRimCloseShotL = "CloseShots",
		FloaterR = "Floaters", FreeThrow = "FreeThrows", InsideHandLayupR = "Layups", ReverseLayupL = "Layups", MovingShotLeftR = "MovingShots",
		PostFadeRightL = "PostMovingShots", StepPostFadeR = "PostMovingShots", PostHookLeftL = "PostMovingShots", ReverseClutchLayupR = "ClutchShots",
		ClutchShotR = "ClutchShots", TwoHandedOffTwoStandingDunkLR = "Dunks"} do
		assert(shotCategory(a, "Shooting") == want, "shotCategory " .. a)
	end
end
local hoops = {}
local function refreshHoops()
	hoops = {}
	local f = workspace:FindFirstChild("Hoops")
	if f then
		for _, h in f:GetChildren() do
			local g = h:FindFirstChild("Goal")
			if g and g:IsA("BasePart") then table.insert(hoops, g) end
		end
	end
end
refreshHoops()
local function nearestHoop(pos)
	local best, bd
	for _, g in hoops do
		if g.Parent then
			local d = (flat(g.Position) - flat(pos)).Magnitude
			if not bd or d < bd then best, bd = g, d end
		end
	end
	return best, bd
end
local function isOpponent(me, c)
	if c == me then return false end
	-- a Private Gym NPC defends only in Defender mode (Tab Menu > AI Players); AI in a real game has InGame set
	if not Players:FindFirstChild(c.Name) and not c:GetAttribute("InGame") then return c:GetAttribute("GymMode") == "Defender" end
	local myTeam = me:GetAttribute("Team")
	return myTeam == 0 or myTeam == nil or c:GetAttribute("Team") ~= myTeam
end
local function gameMeter()
	local P = genv.__mks_player
	local ok, t = pcall(function() return P.ProfileData.SavedSettings.Meter.Type end)
	return ok and t or "?"
end
task.spawn(function() -- the game's Player controller (settings/profile); found natively, no heap walk
	local ok, t = pcall(filtergc, "table", {Keys = {"ProfileData", "OnSettingUpdate"}}, true)
	if ok and t then genv.__mks_player = t end
end)
local gameBinds = {}
local gamePad = {} -- button -> the game's actions on it (one button carries several, by game state)
task.spawn(function()
	local ok, B = pcall(filtergc, "table", {Keys = {"GetMap"}}, true)
	local P = genv.__mks_player
	for _ = 1, 20 do
		if P then break end
		task.wait(0.25)
		P = genv.__mks_player
	end
	if ok and B and P then
		local ok2, map = pcall(function() return B:GetMap("Keyboard", P.ProfileData.SavedSettings.Inputs) end)
		if ok2 and type(map) == "table" then
			for action, key in map do if key ~= "None" then gameBinds[key] = action end end
		end
		local ok3, pmap = pcall(function() return B:GetMap("Gamepad", P.ProfileData.SavedSettings.Inputs) end)
		if ok3 and type(pmap) == "table" then
			for action, btn in pmap do
				if btn ~= "None" then gamePad[btn] = gamePad[btn] or {}; table.insert(gamePad[btn], action) end
			end
		end
	end
end)

---------------------------------------------------------------- ping
local pingMs = 60
local function readPing()
	local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
	return ok and v or pingMs
end
local function leadMs(p)
	local net = if cfg.timing.ping then pingMs / 2 * cfg.timing.pingFactor else 0
	return net + cfg.timing.extraLeadMs + (p and p.offsetMs or 0) + (cfg.timing.styleMs[gameMeter()] or 0)
end

---------------------------------------------------------------- contest prediction (distance bins + in-line defender boost, 2026-11-15)
local function predictContest(d)
	local bins = cfg.contestBins
	if d >= #bins then return bins[#bins].mean end
	local i = math.floor(d) + 1
	local a, b = bins[i].mean, (bins[i + 1] or bins[i]).mean
	return a + (b - a) * (d - math.floor(d))
end
local function nearestOpponent(r)
	local h = hrpOf(r)
	if not h then return nil end
	local best
	for _, c in workspace.Characters:GetChildren() do
		local oh = c ~= r and c.Name ~= "InvisCharacter" and hrpOf(c)
		if oh and isOpponent(r, c) then
			local d = (flat(oh.Position) - flat(h.Position)).Magnitude
			if d < 20 and (not best or d < best.d) then best = {model = c, name = c.Name, d = d, air = c:GetAttribute("InAir") == true, pos = oh.Position} end
		end
	end
	if best then
		best.pct = predictContest(best.d)
		-- the game scores the defender's contest (jump/reach timing), which needs him between you and the rim.
		-- fitted to 5 measured in-line shots, defender jumping (2.3 st 100%, 2.9 100%, 3.1 90%, 3.5 95%, 4.6 89%)
		-- shortcut: nothing measured past 4.6 st, so it fades to the distance curve by 6.5 st; refit with farther samples
		local hoop = nearestHoop(h.Position)
		if hoop then
			local dot = (flat(best.pos) - flat(h.Position)).Unit:Dot((flat(hoop.Position) - flat(h.Position)).Unit)
			best.inLine = dot > 0.4 and best.d <= 6.5
			if best.inLine then
				local base = 100 - 4.5 * math.max(best.d - 2.3, 0)
				best.pct = math.max(best.pct, base * math.clamp((6.5 - best.d) / 1.9, 0, 1))
			end
		end
	end
	return best
end

---------------------------------------------------------------- timing engine
local GRADE_IDX = {["very early"] = 1, early = 2, ["slightly early"] = 3, good = 4, perfect = 5, ["slightly late"] = 6, late = 7, ["very late"] = 8}
local GRADE_NAME = {"Very Early", "Early", "Slightly Early", "Good", "Perfect", "Slightly Late", "Late", "Very Late"}
local STEP = {0.06, 0.04, 0.025, 0.012, 0, 0.025, 0.04, 0.06}
local STEP_MS = {35, 20, 12, 6, 0, 12, 20, 35}
local function parseGrade(text)
	local t = text:lower():gsub("%s*release%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
	local i = GRADE_IDX[t]
	return i, i and GRADE_NAME[i]
end
assert(parseGrade("GOOD RELEASE") == 4 and parseGrade("Slightly Late") == 6 and parseGrade("Perfect Release") == 5, "grade parser")
local PROFILE_DEFAULT = {target = 0.90, offsetMs = 0, n = 0, perfect = 0, meterlessN = 0, locked = false}
local function prof(fam)
	local p = cfg.profiles[fam]
	if type(p) ~= "table" then
		p = {}
		cfg.profiles[fam] = p
	end
	for k, v in PROFILE_DEFAULT do if p[k] == nil then p[k] = v end end
	p.samples = p.samples or {}
	return p
end
-- where the server's meter will be when a release sent now arrives
local function arrival(mLast, rate, sinceLast, leadS) return mLast + rate * (sinceLast + leadS) end
do -- self-check with measured 2026-11-15 jumpers: fill 2.35/s, Perfects arrive 0.86-0.93
	local a = arrival(0.82, 2.35, 0, 0.03)
	assert(math.abs(a - 0.89) < 0.01, "arrival model")
end
local function suggestTarget(p)
	local perfect, early, late = {}, -math.huge, math.huge
	for i = #p.samples, math.max(1, #p.samples - 25), -1 do
		local s = p.samples[i]
		if s.mArr then
			if s.g == 5 then table.insert(perfect, s.mArr)
			elseif s.g and s.g < 4 then early = math.max(early, s.mArr)
			elseif s.g and s.g > 5 then late = math.min(late, s.mArr) end
		end
	end
	if #perfect > 0 then
		table.sort(perfect)
		return perfect[math.ceil(#perfect / 2)], #perfect
	elseif early > -math.huge and late < math.huge and early < late then
		return (early + late) / 2, 0
	end
	return nil, 0
end
local function confidence(p)
	local n, g = 0, 0
	for i = #p.samples, math.max(1, #p.samples - 9), -1 do
		n += 1
		if p.samples[i].g == 5 then g += 1 end
	end
	return n, g
end

local shot, pending = nil, nil
local lastShot = {text = "no shots yet", grade = nil}
local nearestNow
local SHOT_KEYS = {E = true, Space = true}

local function record(s, gi, gname, contestText)
	local fam = s.fam or "Jumper"
	local p = prof(fam)
	local hold = s.tRel and s.started and math.round((s.tRel - s.started) * 1000) or nil
	local contestPct = tonumber((contestText or ""):match("(%d+)%%")) or 0
	local smp = {at = os.time(), g = gi, mArr = s.mArrive and math.round(s.mArrive * 1000) / 1000, hold = hold,
		manual = s.manualRel or nil, ping = math.round(pingMs), ml = s.meterless or nil}
	table.insert(p.samples, smp)
	if #p.samples > 40 then table.remove(p.samples, 1) end
	p.n += 1
	if gi == 5 then p.perfect += 1 end
	pushLog({at = os.time(), fam = fam, anim = s.anim, key = s.key, grade = gname, reason = s.reason, manual = s.manualRel or nil,
		ping = math.round(pingMs), leadMs = s.lead and math.round(s.lead * 1000), rate = s.rate and math.round(s.rate * 100) / 100,
		mRel = s.mNow, mArr = smp.mArr, target = p.target, hold = hold, meterless = s.meterless or nil, style = gameMeter(),
		contest = contestPct, contestPred = s.def and math.round(s.def.pct), defD = s.def and math.round(s.def.d * 10) / 10,
		peak = s.maxDist, trace = if gi ~= 5 or s.manualRel then s.trace else nil})
	-- contest curve learns from real grades
	if s.def and cfg.timing.autoCal and not s.def.inLine then -- in-line contests use the boost, not the distance bins
		local bin = cfg.contestBins[math.clamp(math.floor(s.def.d) + 1, 1, #cfg.contestBins)]
		bin.mean = (bin.mean * bin.n + contestPct) / (bin.n + 1)
		bin.n = math.min(bin.n + 1, 40)
	end
	-- heavy contest narrows the green window (Perfect almost never shows at 85%+), so those grades say nothing about the open-shot target
	local learn = cfg.timing.autoCal and not p.locked and not s.aborted and contestPct < 80
	if s.meterless and hold then
		p.meterlessN += 1
		if learn then
			if not p.holdMs then
				-- seed only from measured holds: need 3 meterless observations first
				if p.meterlessN >= 3 then
					local hs = {}
					for _, x in p.samples do if x.ml and x.hold then table.insert(hs, x.hold) end end
					table.sort(hs)
					p.holdMs = hs[math.ceil(#hs / 2)]
				end
			elseif gi == 5 then
				p.holdMs = math.round(p.holdMs * 0.8 + hold * 0.2)
			else
				local late = if gi == 4 then hold > p.holdMs else gi > 5
				p.holdMs = math.clamp(p.holdMs + (if late then -STEP_MS[gi] else STEP_MS[gi]), 40, 900)
			end
		end
	elseif learn and not s.manualRel and s.mArrive then
		if gi == 5 then
			p.target = p.target * 0.85 + math.clamp(s.mArrive, p.target - 0.03, p.target + 0.03) * 0.15
		else
			-- "Good" has no side: judge it against where Perfects actually land, not the target (judging vs the target ratcheted it 0.915 -> 0.953)
			local ref = suggestTarget(p) or p.target
			local late = if gi == 4 then s.mArrive > ref else gi > 5
			p.target += if late then -STEP[gi] else STEP[gi]
		end
		p.target = math.clamp(p.target, 0.6, 1.0)
	end
	lastShot = {grade = gname, text = ("%s · %s%s · %s"):format(fam, gname, s.manualRel and " (you released)" or "",
		if s.meterless then ("held %sms"):format(hold or "?") else ("landed %.3f vs %.3f"):format(s.mArrive or -1, p.target))}
	report("shot", ("%s %s%s · arrive %.3f target %.3f · hold %s · ping %d · %s"):format(fam, gname, s.manualRel and " (manual)" or "",
		s.mArrive or -1, p.target, tostring(hold), math.round(pingMs), s.reason or "-"))
	markDirty()
end

local function releaseShot(reason, now)
	local s = shot
	s.released, s.reason, s.tRel = true, reason, now
	pending, shot = s, nil -- cleared first so our own key-up is not read as the player letting go
	kup(s.key)
	-- the player is still physically holding: Roblox would see no second release, which is fine for the game
end

local function startShot(key)
	local r = rig()
	if not r or not hasBall(r) then return end
	if shot then return end
	local now = os.clock()
	shot = {tDown = now, key = key, sst0 = r:GetAttribute("ShotStartTime"), stale = meterOf(r), trace = {}, samples = 0}
	-- we own the key from here: mark it held so releaseShot can send the matching key-up
	held[key] = true
	if key == "E" and cfg.anti.enabled and cfg.anti.pump and nearestNow and nearestNow.pct > cfg.anti.maxPct then
		-- too contested: let go inside the game's 150 ms tap window, which the game reads as a pump fake (measured 2026-11-15)
		local n = nearestNow
		shot = nil
		task.delay(0.07, function() kup("E") end)
		pushLog({at = os.time(), pump = true, contestPred = math.round(n.pct), defD = math.round(n.d * 10) / 10, defName = n.name})
		lastShot.text = ("pump fake: ~%d%% contest from %s"):format(n.pct, n.name)
	end
end

local function stepShot(r, now, dt)
	if not shot then return end
	local s = shot
	local act = r:GetAttribute("Action")
	local m = meterOf(r)
	if not s.started then
		local sst = r:GetAttribute("ShotStartTime")
		if (act == "Shooting" or act == "Dunking") and sst ~= s.sst0 then
			s.started = now
			s.anim = shotAnim(r)
			s.fam = family(s.anim, act)
		elseif now - s.tDown > 2.5 then
			if s.auto then kup(s.key) end -- our own held E must be let go
			held[s.key] = nil
			shot = nil -- never became a shot (gather, pass, pump fake)
		end
		return
	end
	-- re-detect the type through animation transitions (gathers turn into layups, etc.)
	local a = shotAnim(r)
	if a and a ~= s.anim then
		s.anim = a
		s.fam = family(a, act)
	end
	s.def = nearestNow or s.def
	if act ~= "Shooting" and act ~= "Dunking" then
		s.aborted = true -- shot cancelled before release: keep the log, teach nothing
		releaseShot("aborted", now)
		return
	end
	local p = prof(s.fam)
	local auto = cfg.timing.enabled and not cfg.timing.manualMode
	if m and #s.trace < 160 then
		local last = s.trace[#s.trace]
		local v = math.floor(m * 1000) / 1000
		if not last or last[2] ~= v then table.insert(s.trace, {math.floor((now - s.tDown) * 1000), v}) end
	end
	if now - s.started > 1.6 then -- hard cap: a failed detector never holds the shot forever
		if auto then releaseShot("cap", now) end
		return
	end
	if not s.live then
		-- the meter keeps the last shot's value until the new fill resets it near 0
		if m and m < 0.12 and (s.stale == nil or math.abs(m - s.stale) > 0.0005) then
			s.live, s.meterless = true, nil
			s.tFirst, s.dFirst, s.last, s.tLast, s.samples, s.maxDist = now, m, m, now, 0, m
		elseif now - s.started > 0.35 then
			s.meterless = true
		end
		if s.meterless and auto and p.holdMs and p.meterlessN >= 3 and (now - s.started) * 1000 + dt * 500 >= p.holdMs then
			releaseShot("hold", now)
		end
		return
	end
	if m ~= s.last then
		s.last, s.tLast, s.samples = m, now, s.samples + 1
		s.maxDist = math.max(s.maxDist, m)
	end
	local elapsed = s.tLast - s.tFirst
	if s.samples < 2 or elapsed < 0.03 then return end
	local rate = (s.last - s.dFirst) / elapsed
	local leadS = leadMs(p) / 1000
	s.mNow, s.rate, s.lead = m, rate, leadS
	s.mArrive = arrival(s.last, rate, now - s.tLast, leadS)
	if not auto then return end
	if s.mArrive + rate * dt * 0.5 >= p.target then
		releaseShot("timed", now)
	elseif m < s.maxDist - 0.02 then
		releaseShot("peak", now) -- meter already turning down: later only gets worse
	end
end

local lastFbActive = false
local function stepPending(r, now)
	local fb = hrpOf(r) and hrpOf(r):FindFirstChild("ShotFeedback")
	local active = fb ~= nil and fb:GetAttribute("Active") == true
	if pending then
		local m = meterOf(r)
		if m and pending.live then pending.maxDist = math.max(pending.maxDist or 0, m) end
		if active and not lastFbActive then
			-- the labels can still show the previous shot when Active flips (measured 2026-11-15); read them once settled
			local s = pending
			pending = nil
			task.delay(0.12, function()
				local rt = fb:FindFirstChild("ReleaseTiming")
				local gi, gname = parseGrade(rt and rt.Text or "")
				local ct = fb:FindFirstChild("Contest")
				if gi then record(s, gi, gname, ct and ct.Text) end
			end)
		elseif now - pending.tRel > 4 then
			pending = nil
		end
	end
	lastFbActive = active
end

---------------------------------------------------------------- movement steering (ordinary WASD only)
local MOVE_KEYS = {"W", "A", "S", "D"}
local steering = false
local function userMoving()
	for _, k in MOVE_KEYS do if physicallyDown(k) then return true end end
	return false
end
local function steer(dir)
	-- dir: horizontal world direction or nil to stop. Never fights the player's own movement keys.
	if not dir or dir.Magnitude < 0.05 or userMoving() then
		if steering then for _, k in MOVE_KEYS do kup(k) end end
		steering = false
		return
	end
	steering = true
	local cam = workspace.CurrentCamera.CFrame
	local f = flat(cam.LookVector).Unit
	local rt = flat(cam.RightVector).Unit
	dir = dir.Unit
	local z, x = dir:Dot(f), dir:Dot(rt)
	local want = {W = z > 0.38, S = z < -0.38, D = x > 0.38, A = x < -0.38}
	for k, v in want do if v then kdown(k) else kup(k) end end
end

---------------------------------------------------------------- auto block (cancellable state machine)
local blk = {cand = nil, cool = 0, lastSST = {}, stats = {jumps = 0, cancels = 0}}
local function blockLog(e)
	e.at = os.time()
	e.block = true
	pushLog(e)
end
local function losClear(from, to, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true -- nets, glass trims and invisible triggers do not block a block
	local res = workspace:Raycast(from, to - from, params)
	return res == nil
end
local function stepBlock(r, now)
	local c = cfg.block
	local me = hrpOf(r)
	-- hold key (OT "Block Key (Hold)"): empty = always armed; a shot already being tracked finishes either way
	local armed = c.enabled and (c.holdKey == "" or physicallyDown(c.holdKey))
	if not me or (not armed and not blk.cand) or not c.enabled then
		if blk.cand then
			blk.cand = nil
			steer(nil)
		end
		return
	end
	-- the player's own shooting/holding always wins
	local busy = shot ~= nil or pending ~= nil or hasBall(r) or physicallyDown("E") or physicallyDown("Space")
	for _, o in workspace.Characters:GetChildren() do
		if o ~= r and o.Name ~= "InvisCharacter" then
			local act, sst = o:GetAttribute("Action"), o:GetAttribute("ShotStartTime")
			local prev = blk.lastSST[o]
			blk.lastSST[o] = sst
			local oh = hrpOf(o)
			if oh and act == "Shooting" and prev ~= nil and sst ~= prev and not blk.cand and now >= blk.cool and not busy
				and (not c.teamCheck or isOpponent(r, o)) then
				local d = (flat(oh.Position) - flat(me.Position)).Magnitude
				local anim = shotAnim(o) or ""
				local rim = family(anim, act) ~= "Jumper"
				local catName = shotCategory(anim, act)
				local cat = c.cats[catName]
				if cat and cat.on and d <= cat.range then
					blk.cand = {o = o, t0 = now, d0 = d, anim = anim, rim = rim, cat = cat, catName = catName, start = me.Position, hoop = nearestHoop(oh.Position)}
				end
			end
		end
	end
	local cd = blk.cand
	if not cd then return end
	local o, oh = cd.o, hrpOf(cd.o)
	local function finish(result, extra)
		steer(nil)
		kup("LeftShift")
		blk.cand = nil
		blk.cool = now + c.cooldownMs / 1000
		if result ~= "jump" then blk.stats.cancels += 1 end
		local e = {result = result, shooter = o.Name, anim = cd.anim, cat = cd.catName, rim = cd.rim, d0 = math.round(cd.d0 * 10) / 10,
			ms = math.round((now - cd.t0) * 1000), shift = math.round((flat(me.Position) - flat(cd.start)).Magnitude * 10) / 10}
		if extra then for k, v in extra do e[k] = v end end
		blockLog(e)
		lastShot.text = ("block: %s on %s (%s)"):format(result, o.Name, cd.catName)
	end
	if not o.Parent or not oh then return finish("lost") end
	if busy and not cd.jumped then return finish("cancel-own-input") end
	local act = o:GetAttribute("Action")
	local ballGone = not hasBall(o)
	if act ~= "Shooting" and ballGone and not cd.released then cd.released = now end
	local d = (flat(oh.Position) - flat(me.Position)).Magnitude
	if not cd.jumped then
		if act ~= "Shooting" and not ballGone then return finish("cancel-abort") end -- pump fake / shot cancelled
		if d > c.range * 1.3 then return finish("cancel-range") end
		if c.los and not losClear(me.Position + Vector3.new(0, 2, 0), oh.Position + Vector3.new(0, 2, 0), {r, o}) then
			return finish("cancel-los")
		end
	end
	local committed = cd.committed or (now - cd.t0) * 1000 >= c.commitMs or o:GetAttribute("InAir") == true or ballGone
	if committed and not cd.committed then cd.committed = now end
	if not committed then return end
	-- intercept: the ball leaves the shooter toward the rim; meet it a few studs in front of the shooter
	local hoopPos = cd.hoop and cd.hoop.Position or (oh.Position + oh.CFrame.LookVector * 15)
	local lane = flat(hoopPos - oh.Position)
	lane = if lane.Magnitude > 0.1 then lane.Unit else flat(oh.CFrame.LookVector).Unit
	local reach = if cd.rim then 2.2 else 3.2
	local intercept = flat(oh.Position) + lane * math.min(reach, math.max(d - 0.5, 1))
	cd.intercept = cd.intercept or intercept
	if not cd.jumped then
		local toI = intercept - flat(me.Position)
		local shifted = (flat(me.Position) - flat(cd.start)).Magnitude
		if c.shift and toI.Magnitude > 1 and shifted < c.maxShift then steer(toI) else steer(nil) end
		if cd.cat.sprint and c.shift and toI.Magnitude > 2 and shifted < c.maxShift then kdown("LeftShift") else kup("LeftShift") end
		local wait = cd.cat.delayMs - pingMs / 2
		if (now - cd.committed) * 1000 >= math.max(0, wait) or cd.released then
			cd.jumped = now
			steer(nil)
			kup("LeftShift")
			task.spawn(ktap, "Space", 40)
			blk.stats.jumps += 1
		end
		return
	end
	-- after the jump: watch where the ball actually crossed, for the predicted-vs-observed log
	local ball = o:FindFirstChild("HumanoidRootPart") and o.HumanoidRootPart:FindFirstChild("Basketball")
	local bpart = ball and ball.Part1
	if not cd.observed and cd.released then
		for _, b in (workspace:FindFirstChild("Basketballs") or workspace):GetChildren() do
			if b:IsA("BasePart") and b.AssemblyLinearVelocity.Magnitude > 8 then
				local bp = flat(b.Position)
				if (bp - flat(oh.Position)).Magnitude >= reach then cd.observed = bp end
			end
		end
	end
	if now - cd.jumped > 1.2 or cd.observed then
		local err = cd.observed and math.round((cd.observed - cd.intercept).Magnitude * 10) / 10
		finish("jump", {predictErr = err, released = cd.released ~= nil, ballPart = bpart and bpart.Name})
	end
end

---------------------------------------------------------------- dribble moves and combos
-- key strings from the game's Dribbling.Input table, per ball hand (verified: Z with right hand = Crossover)
local MOVES = {
	{"Crossover", {R = "Z", L = "C"}}, {"Hesitation", {R = "C", L = "Z"}}, {"DoubleCrossover", {R = "CC", L = "ZZ"}},
	{"Tween", {R = "ZZ", L = "CC"}}, {"BehindBack", {R = "CX", L = "ZX"}}, {"DoubleBehindBack", {R = "XZ", L = "XZ"}},
	{"Spin", {R = "CXZ", L = "ZXC"}}, {"HalfSpin", {R = "V", L = "V"}}, {"StepBack", {R = "X", L = "X"}},
	{"SnatchBack", {R = "XX", L = "XX"}}, {"BreakdownLeft", {R = "VZ", L = "VZ"}}, {"BreakdownRight", {R = "VC", L = "VC"}},
	{"Combo", {R = "VV", L = "VV"}}, {"SwitchHand", {R = "H", L = "H"}},
	-- gathers: sprinting (Shift) on a live dribble, an E tap/double tap; the server picks the gather from the
	-- real movement and names it in the GatherType attribute (live-mapped 2026-11-15, right hand)
	{"HopStep", {gather = "E", expect = "Hopstep"}}, {"EuroStep", {gather = "EE", expect = "Eurostep"}},
	{"HopStepBack", {gather = "E", dir = "S", expect = "Backstep"}},
	-- side gathers come from a real turn (A -> BTBWrap, D -> Sidestep): 24-37 degree twitch before the gather, so off
	{"SideStepLeft", {gather = "E", dir = "A", expect = "BTBWrap", disabled = "needs a visible 24-37 degree turn before the gather (game picks it from real movement)"}},
	{"SideStepRight", {gather = "E", dir = "D", expect = "Sidestep", disabled = "needs a visible 34 degree turn before the gather (game picks it from real movement)"}},
	{"SpinGather", {gather = "EE", disabled = "no tested input produces SpinGather on this build (direction + double E gives a shot fake)"}},
}
local MOVE_BY = {}
local MOVE_NAMES = {}
for _, mv in MOVES do
	MOVE_BY[mv[1]] = mv[2]
	table.insert(MOVE_NAMES, mv[1])
end
local macro = {running = false, loop = false, token = 0, status = "idle"}
local function canDribble(r) return r and hasBall(r) and r:GetAttribute("CanMove") ~= false and shot == nil end
-- The game buffers dribble keys: every press waits the player's own DribbleDelay setting, then sends the
-- whole buffer as one move string. A key that lands while an earlier buffer is still open joins it and
-- turns into a different move, so a move may only start after the previous buffer has been flushed.
local lastKeyAt = 0
local function dribbleDelay()
	local ok, v = pcall(function() return genv.__mks_player.ProfileData.SavedSettings.Gameplay.Keyboard.DribbleDelay end)
	return if ok and type(v) == "number" then v else 0.15
end
-- ready = holding the ball, free to move, no action or move debounce running, no open key buffer
local function moveReady(r)
	if not canDribble(r) then return false end
	local a = r:GetAttribute("Action")
	if a ~= "" and a ~= nil then return false end
	if r:GetAttribute("Debounce") == true then return false end
	return os.clock() - lastKeyAt > dribbleDelay() + 0.04
end
local function waitReady(r, timeout, token)
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		if token and macro.token ~= token then return false end
		if moveReady(r) then return true end
		task.wait()
	end
	return false
end
-- sends one move and waits for the game to confirm it; returns ok, ms to confirmation or a reason
-- The server queues one direct move sent while the previous one plays and starts it the moment that
-- move's Debounce clears (measured 2026-11-15: sent at 158 ms -> ran at 393 ms; at 300 ms -> chained at 376 ms).
-- So a direct move only waits for the previous send to be confirmed (Hand has flipped by then), not for the
-- whole ~880 ms Action/CanMove lock.
local pendingMove = false
local function chainReady(r)
	if not (r and hasBall(r)) or shot ~= nil then return false end
	local a = r:GetAttribute("Action")
	return (a == "" or a == nil or a == "Dribbling") and not pendingMove
end
local lastPad = false -- last input came from a controller
-- the game's own dribble action (remote) instead of pressing its keys: always on a controller or without keypress
local function useDirect() return cfg.dribble.direct or lastPad or not CAP.keys end
local function doMove(name, noChain)
	local r = rig()
	local spec = MOVE_BY[name]
	if not spec then return false, "unknown move" end
	if spec.disabled then return false, "disabled: " .. spec.disabled end
	if not PREMIUM and not FREE_MOVE[name] then return false, "Premium move" end
	if spec.gather then
		if r:GetAttribute("TripleThreat") then return false, "gathers need a live dribble" end
		if not (r:GetAttribute("Sprinting") or UIS:IsKeyDown(Enum.KeyCode.LeftShift)) then return false, "hold Shift (sprint) to gather" end
	end
	local chain = useDirect() and not spec.gather and not noChain
	local function ready() return if chain then chainReady(r) else moveReady(r) end
	local tw = os.clock()
	while not ready() and os.clock() - tw < 1.5 do task.wait() end
	if not ready() then return false, "not ready" end
	-- the game maps keys to jabs in triple threat (Config.Game.Dribbling.Input.TripleThreat); dribble moves need a live dribble
	if not spec.gather and r:GetAttribute("TripleThreat") then return false, "in triple threat: move to start dribbling first" end
	if spec.gather and (spec.expect == "Hopstep" or spec.expect == "Eurostep") then
		-- the game picks the gather from the angle between movement and facing: ~24-37 degrees gives BTBWrap / Sidestep,
		-- and coming out of a Spin the body is still turning. Send only once movement lines up with facing.
		local function offAngle()
			local ok, mv = pcall(function() return genv.__mks_player.Character.Movement.MoveDirection end)
			if not ok or typeof(mv) ~= "Vector3" or mv.Magnitude < 0.1 then return nil end
			local look = r.HumanoidRootPart.CFrame.LookVector
			local a, b = Vector3.new(mv.X, 0, mv.Z).Unit, Vector3.new(look.X, 0, look.Z).Unit
			return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
		end
		local tw = os.clock()
		local ang = offAngle()
		while ang and ang > 15 and os.clock() - tw < 0.4 do task.wait() ang = offAngle() end
		if ang and ang > 15 then return false, ("still turning (%d degrees off): the game would play a side gather, not %s"):format(ang, spec.expect) end
		macro.lastGather = {angle = ang, waited = math.floor((os.clock() - tw) * 1000)}
	end
	local confirmed, t0 = false, os.clock()
	local conns = {}
	local function watch(attr, pred)
		table.insert(conns, r:GetAttributeChangedSignal(attr):Connect(function() if pred(r:GetAttribute(attr)) then confirmed = true end end))
	end
	if spec.gather then
		-- Action=Gathering alone also fires for pump fakes; only the expected GatherType counts
		local got
		table.insert(conns, r:GetAttributeChangedSignal("Action"):Connect(function()
			if r:GetAttribute("Action") == "Gathering" then
				-- Action lands a frame before GatherType in the same update; read the name after it settles
				task.delay(0.03, function()
					got = r:GetAttribute("GatherType")
					confirmed = got == spec.expect
				end)
			end
		end))
		if spec.dir then
			-- the direction key stays down until the game has taken the gather (released early = Hopstep)
			kdown(spec.dir); ktap("E", 60)
			local tw = os.clock()
			while got == nil and os.clock() - tw < 0.6 do task.wait() end
			kup(spec.dir)
		elseif useDirect() then
			-- the call the game's tap buffer makes after ShootDelay, sent at once: no wait, no keys, no movement
			pcall(function()
				game:GetService("ReplicatedStorage").Aero.AeroRemoteServices.InputService.Shoot:FireServer({Shoot = false, Input = spec.gather, Sprint = true})
			end)
			macro.sends = macro.sends or {}
			table.insert(macro.sends, {t = os.clock(), move = name, seq = spec.gather, hand = r:GetAttribute("Hand"), gather = true, action = r:GetAttribute("Action"), deb = r:GetAttribute("Debounce"),
				sprinting = r:GetAttribute("Sprinting"), sv = (r:GetAttribute("ServerVelocity") or Vector3.zero).Magnitude, ws = r:GetAttribute("WalkSpeed"),
				angle = macro.lastGather and macro.lastGather.angle, waited = macro.lastGather and macro.lastGather.waited})
		elseif spec.gather == "EE" then
			ktap("E", 40); task.wait(0.04); ktap("E", 40)
		else
			ktap("E", 60)
		end
		local tw = os.clock()
		while got == nil and os.clock() - tw < 0.6 do task.wait() end
		if got ~= nil and not confirmed then
			for _, c in conns do c:Disconnect() end
			return false, ("game played %s, not %s"):format(tostring(got), spec.expect)
		end
	else
		-- a repeated move keeps the same package name, so Debounce rising also counts as confirmation
		watch("LastDribblePackage", function() return true end)
		watch("Debounce", function(v) return v == true end)
		-- a queued repeat (Crossover x2) can arrive with no attribute change; its animation still starts
		local animator = r:FindFirstChildWhichIsA("Animator", true)
		if animator then
			table.insert(conns, animator.AnimationPlayed:Connect(function()
				if r:GetAttribute("Action") == "Dribbling" then confirmed = true end
			end))
		end
		local seq = spec[r:GetAttribute("Hand") or "R"] or spec.R
		local sent = false
		pendingMove = chain
		if useDirect() then
			-- the same call the game's keyboard handler makes once its DribbleDelay buffer closes (user-approved 2026-11-15)
			sent = pcall(function()
				local P = genv.__mks_player
				local sprint = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or r:GetAttribute("Sprinting") == true
				-- without the game's controller table (no filtergc): the humanoid's move direction, else facing.
				-- shortcut: this fallback is not yet verified against the game's own direction; test on a filtergc-less executor
				local dir = P and P.Character.Movement.lastMoveDirection
				if not dir then
					local hum = r:FindFirstChildWhichIsA("Humanoid")
					dir = if hum and hum.MoveDirection.Magnitude > 0.1 then hum.MoveDirection else r.HumanoidRootPart.CFrame.LookVector
				end
				game:GetService("ReplicatedStorage").Aero.AeroRemoteServices.InputService.Dribble:FireServer(seq, sprint, dir)
			end)
			macro.sends = macro.sends or {}
			table.insert(macro.sends, {t = os.clock(), move = name, seq = seq, hand = r:GetAttribute("Hand"), chain = chain, retry = noChain == true, action = r:GetAttribute("Action"), deb = r:GetAttribute("Debounce")})
			if #macro.sends > 60 then table.remove(macro.sends, 1) end
		end
		if not sent then
			for ch in seq:gmatch(".") do -- every key inside one buffer window
				ktap(ch, 22)
				task.wait(0.008)
			end
			lastKeyAt = os.clock()
		end
	end
	-- a queued move only starts when the previous move's Debounce clears, up to ~0.5 s later
	local limit = if chain then 0.8 else dribbleDelay() + 0.6
	while not confirmed and os.clock() - t0 < limit do task.wait() end
	pendingMove = false
	for _, c in conns do c:Disconnect() end
	if not confirmed then
		-- some repeats (StepBack x2) are dropped when queued; send once more after the game frees up
		if chain then return doMove(name, true) end
		return false, "no response from the game"
	end
	return true, math.floor((os.clock() - t0) * 1000)
end
local function stopMacro(why)
	macro.token += 1
	macro.running = false
	macro.status = "stopped" .. (why and (" (" .. why .. ")") or "")
	if why then report("macro", "combo " .. macro.status) end
	for _, k in {"Z", "X", "C", "V", "H", "E", "A", "D", "S"} do kup(k) end
end
local function playCombo(loop)
	stopMacro()
	local list = cfg.dribble.combos[cfg.dribble.combo]
	if not list or #list == 0 then macro.status = "combo is empty" return end
	macro.token += 1
	local token = macro.token
	macro.running, macro.loop = true, loop
	task.spawn(function()
		local lastStart = 0
		repeat
			for i, name in list do
				if macro.token ~= token then return end
				local r = rig()
				if not hasBall(r) then stopMacro("lost the ball") return end
				-- next move goes the moment the game is ready; interval is only a minimum gap between move starts
				if not useDirect() and not waitReady(r, 1.5, token) then
					if macro.token == token then stopMacro(("%s: game not ready after 1.5 s"):format(name)) end
					return
				end
				local gap = cfg.dribble.interval - (os.clock() - lastStart)
				if gap > 0 then task.wait(gap) end
				if macro.token ~= token then return end
				macro.status = ("%s %d/%d"):format(name, i, #list)
				lastStart = os.clock()
				local ok, info = doMove(name)
				pushLog({at = os.time(), combo = true, move = name, ok = ok, info = info})
				if not ok then
					if macro.token == token then stopMacro(("%s failed: %s"):format(name, tostring(info))) end
					return
				end
			end
		until not macro.loop or macro.token ~= token
		if macro.token == token then
			macro.running = false
			macro.status = "done"; report("macro", ("combo %s done"):format(cfg.dribble.combo))
		end
	end)
end
---------------------------------------------------------------- world
local origLight, disabledFx = nil, {}
local function applyLighting()
	local w = cfg.world
	if w.fullbright then
		origLight = origLight or {Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
			GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient}
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows = 2, 14, 1e6, false
		Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178), Color3.fromRGB(178, 178, 178)
	elseif origLight then
		for k, v in origLight do Lighting[k] = v end
		origLight = nil
	end
	if w.noPost then
		for _, fx in Lighting:GetChildren() do
			if fx:IsA("PostEffect") and fx.Enabled then
				fx.Enabled = false
				table.insert(disabledFx, fx)
			end
		end
	else
		for _, fx in disabledFx do if fx.Parent then fx.Enabled = true end end
		disabledFx = {}
	end
end
onCleanup(function()
	cfg.world.fullbright, cfg.world.noPost = false, false
	applyLighting()
end)
local function myAppearance(r)
	local ok, list = pcall(filtergc, "table", {Keys = {"MascotPieces", "model"}}, false)
	if not ok or type(list) ~= "table" then return nil end
	for _, t in list do if rawget(t, "model") == r then return t end end
	return nil
end
local mascotMsg = ""
local function mascotNames()
	local out = {}
	local f = game:GetService("ReplicatedStorage"):FindFirstChild("Accessories")
	f = f and f:FindFirstChild("Mascots")
	if f then for _, m in f:GetChildren() do table.insert(out, m.Name) end end
	table.sort(out)
	return out
end
local function wearMascot(on)
	local r = rig()
	local app = r and myAppearance(r)
	if not app then mascotMsg = "appearance controller not found" return end
	if not on then
		-- own thread: the game's mascot code leaves the calling thread without Instance access afterwards
		task.spawn(pcall, app.ClearMascot, app)
		mascotMsg = "mascot removed (respawn restores your normal accessories)"
		return
	end
	local name = cfg.world.mascot
	if cfg.world.customMascot ~= "" then
		local id = cfg.world.customMascot:match("%d+")
		local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
		local model = ok and type(objs) == "table" and objs[1]
		if not model or not model:FindFirstChild("HumanoidRootPart") then
			mascotMsg = "custom ID " .. tostring(id) .. " could not be loaded as a mascot rig (Real's GetObjects only loads local assets)"
			return
		end
		local f = game:GetService("ReplicatedStorage").Accessories.Mascots
		local old = f:FindFirstChild("MKS_Custom")
		if old then old:Destroy() end
		model.Name = "MKS_Custom"
		model.Parent = f
		name = "MKS_Custom"
	end
	task.spawn(function()
		local ok, err = pcall(app.ApplyMascot, app, name)
		mascotMsg = if ok then ("wearing %s (client-side, only you see it)"):format(name) else ("failed: " .. tostring(err))
	end)
end
local weatherPart
local function applyWeather()
	if weatherPart then weatherPart:Destroy(); weatherPart = nil end
	local kind = cfg.world.weather
	if kind == "None" then return end
	weatherPart = Instance.new("Part")
	weatherPart.Name = "MKS_Weather"
	weatherPart.Anchored, weatherPart.CanCollide, weatherPart.CanQuery, weatherPart.CanTouch = true, false, false, false
	weatherPart.Transparency, weatherPart.Size = 1, Vector3.new(80, 1, 80)
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = cfg.world.weatherAmount * (if kind == "Rain" then 6 else 2)
	pe.Lifetime = NumberRange.new(2.5, 3.5)
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.Speed = if kind == "Rain" then NumberRange.new(45, 55) else NumberRange.new(6, 10)
	pe.Size = if kind == "Rain" then NumberSequence.new(0.08) else NumberSequence.new(0.25)
	pe.Transparency = NumberSequence.new(0.35)
	pe.SpreadAngle = Vector2.new(8, 8)
	pe.Color = ColorSequence.new(Color3.fromRGB(235, 235, 245))
	pe.LightEmission = 0.3
	pe.Parent = weatherPart
	weatherPart.Parent = workspace.CurrentCamera
end
onCleanup(function() if weatherPart then weatherPart:Destroy() end end)
local COLORS = {White = Color3.fromRGB(255, 255, 255), Silver = Color3.fromRGB(190, 190, 200), Graphite = Color3.fromRGB(70, 70, 80),
	Black = Color3.fromRGB(12, 12, 14), Green = Color3.fromRGB(80, 255, 130), Red = Color3.fromRGB(255, 70, 70),
	Blue = Color3.fromRGB(80, 160, 255), Gold = Color3.fromRGB(255, 205, 80), Purple = Color3.fromRGB(175, 110, 255), Cyan = Color3.fromRGB(80, 235, 255)}
local COLOR_NAMES = {"White", "Silver", "Graphite", "Black", "Green", "Red", "Blue", "Gold", "Purple", "Cyan"}
local meterOrig = {}
local function applyMeter(r)
	if not r then return end
	for _, b in r:GetDescendants() do
		if b:IsA("BillboardGui") and b.Name:find("Meter$") then
			meterOrig[b] = meterOrig[b] or {size = b.Size}
			b.Size = UDim2.new(meterOrig[b].size.X.Scale * cfg.meter.scale, 0, meterOrig[b].size.Y.Scale * cfg.meter.scale, 0)
			local function setc(n, c)
				local x = b:FindFirstChild(n)
				if x and x:IsA("ImageLabel") then
					meterOrig[x] = meterOrig[x] or x.ImageColor3
					x.ImageColor3 = if cfg.meter.recolor then c else meterOrig[x]
				end
			end
			setc("Meter_Fill", COLORS[cfg.meter.fill])
			setc("Meter_Green", COLORS[cfg.meter.green])
			setc("Meter_Base", COLORS[cfg.meter.back])
			local fg = b:FindFirstChild("FillGradient", true)
			if fg then
				meterOrig[fg] = meterOrig[fg] or fg.Color
				fg.Color = if cfg.meter.recolor then ColorSequence.new(COLORS[cfg.meter.fill], COLORS[cfg.meter.fade]) else meterOrig[fg]
			end
		end
	end
end
onCleanup(function()
	for inst, o in meterOrig do
		pcall(function()
			if typeof(o) == "table" then inst.Size = o.size elseif typeof(o) == "Color3" then inst.ImageColor3 = o else inst.Color = o end
		end)
	end
end)
local function setGameMeter(t)
	local P = genv.__mks_player
	if not P then return false end
	return pcall(function()
		P.ProfileData.SavedSettings.Meter.Type = t
		P:OnSettingUpdate()
	end)
end

---------------------------------------------------------------- overhead (contest % / range)
local hud = Instance.new("ScreenGui")
hud.Name = "MKS_HUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = 70
hud.Parent = (gethui and gethui()) or game:GetService("CoreGui")
onCleanup(function() hud:Destroy() end)
local overhead = Instance.new("BillboardGui")
overhead.Size = UDim2.fromOffset(150, 52)
overhead.StudsOffset = Vector3.new(0, 2.8, 0)
overhead.AlwaysOnTop = true
overhead.Parent = hud
local pctLabel = Instance.new("TextLabel")
pctLabel.Size = UDim2.fromScale(1, 0.62)
pctLabel.BackgroundTransparency = 1
pctLabel.Font = Enum.Font.GothamBold
pctLabel.TextScaled = true
pctLabel.TextStrokeTransparency = 0.35
pctLabel.Parent = overhead
local subLabel = pctLabel:Clone()
subLabel.Position = UDim2.fromScale(0, 0.62)
subLabel.Size = UDim2.fromScale(1, 0.38)
subLabel.Font = Enum.Font.GothamMedium
subLabel.TextColor3 = Color3.new(1, 1, 1)
subLabel.Parent = overhead
local watermark = Instance.new("TextLabel")
watermark.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
watermark.BackgroundTransparency = 0.25
watermark.Position = UDim2.fromOffset(12, 64)
watermark.Size = UDim2.fromOffset(330, 26)
watermark.Font = Enum.Font.GothamMedium
watermark.TextSize = 13
watermark.TextColor3 = Color3.fromRGB(230, 230, 236)
watermark.Parent = hud
do
	local wc = Instance.new("UICorner")
	wc.CornerRadius = UDim.new(0, 8)
	wc.Parent = watermark
end

---------------------------------------------------------------- main loop
local fps, fpsAcc, fpsN = 60, 0, 0
local spectateBound = false
local function applySpectate()
	local cam = workspace.CurrentCamera
	if cfg.world.spectate and cfg.world.target ~= "" then
		if not spectateBound then
			spectateBound = true
			RS:BindToRenderStep("MKS_Spectate", Enum.RenderPriority.Camera.Value + 10, function()
				local t = workspace.Characters:FindFirstChild(cfg.world.target)
				local th = hrpOf(t)
				if th then
					local back = flat(th.CFrame.LookVector)
					back = if back.Magnitude > 0.1 then back.Unit else Vector3.new(0, 0, 1)
					cam.CFrame = CFrame.lookAt(th.Position - back * 12 + Vector3.new(0, 6, 0), th.Position + Vector3.new(0, 1.5, 0))
				end
			end)
		end
	elseif spectateBound then
		spectateBound = false
		RS:UnbindFromRenderStep("MKS_Spectate")
	end
end
onCleanup(function() if spectateBound then RS:UnbindFromRenderStep("MKS_Spectate") end end)

local lastRig, saveAt, meterAt, nameAt = nil, 0, 0, 0
on(RS.RenderStepped, function(dt)
	local now = os.clock()
	pingMs = pingMs * 0.9 + readPing() * 0.1
	fpsAcc += dt
	fpsN += 1
	if fpsAcc >= 0.5 then fps, fpsAcc, fpsN = fpsN / fpsAcc, 0, 0 end
	local r = rig()
	if r ~= lastRig then -- respawn or first frame: nothing synthetic may stay held
		if lastRig then
			stopMacro("respawn")
			releaseAll()
			shot, pending, blk.cand = nil, nil, nil
		end
		lastRig = r
		meterOrig = {}
	end
	if not r then return end
	if not isrbxactive() and next(held) then releaseAll() end -- tabbed out: let go of everything we hold
	nearestNow = nearestOpponent(r)
	if macro.running and not hasBall(r) then stopMacro("lost the ball") end
	stepShot(r, now, dt)
	stepPending(r, now)
	stepBlock(r, now)
	if cfg.world.fov then workspace.CurrentCamera.FieldOfView = cfg.world.fovVal end
	if weatherPart then weatherPart.CFrame = CFrame.new(workspace.CurrentCamera.CFrame.Position + Vector3.new(0, 25, 0)) end
	-- overhead
	local head = r:FindFirstChild("Head")
	overhead.Adornee = head
	overhead.Enabled = head ~= nil and (cfg.anti.showPct or cfg.anti.showRange)
	if head then
		local pct = nearestNow and nearestNow.pct or 0
		pctLabel.Visible = cfg.anti.showPct
		pctLabel.Text = ("%d%%"):format(pct)
		pctLabel.TextColor3 = if pct > cfg.anti.maxPct then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(110, 255, 150)
		local parts = {}
		if cfg.anti.showPct then table.insert(parts, if nearestNow then ("%.1f st%s"):format(nearestNow.d, nearestNow.air and " · jumping" or "") else "open") end
		if cfg.anti.showRange then
			local _, hd = nearestHoop(hrpOf(r).Position)
			table.insert(parts, if hd and hd <= cfg.anti.range then ("IN RANGE %.0f"):format(hd) else ("OUT %.0f"):format(hd or 0))
		end
		subLabel.Text = table.concat(parts, "  ·  ")
	end
	watermark.Visible = cfg.ui.watermark
	if cfg.ui.watermark then
		watermark.Text = ("MKS  ·  %d fps  ·  %d ms  ·  %s"):format(fps, pingMs, lastShot.grade or "--")
	end
	if now >= meterAt then
		meterAt = now + 1
		applyMeter(r)
	end
	if dirty and cfg.ui.autosave and now >= saveAt then
		saveAt = now + 1.5
		saveNow()
	end
end)

-- anti AFK: Roblox kicks after 20 idle minutes; a virtual right-click resets the idle timer without moving
on(lp.Idled, function()
	if not cfg.misc.antiAfk then return end
	pcall(function()
		local VU = game:GetService("VirtualUser")
		VU:CaptureController()
		VU:ClickButton2(Vector2.new())
	end)
end)

---------------------------------------------------------------- UI
local THEMES = {
	Graphite = {bg = Color3.fromRGB(6, 6, 9), panel = Color3.fromRGB(14, 14, 18), card = Color3.fromRGB(22, 22, 28),
		element = Color3.fromRGB(34, 34, 42), hover = Color3.fromRGB(48, 48, 58), outline = Color3.fromRGB(70, 70, 82),
		accent = Color3.fromRGB(235, 235, 242), text = Color3.fromRGB(244, 244, 248), dim = Color3.fromRGB(150, 150, 162)},
	Silver = {bg = Color3.fromRGB(10, 10, 12), panel = Color3.fromRGB(24, 24, 28), card = Color3.fromRGB(34, 34, 40),
		element = Color3.fromRGB(52, 52, 60), hover = Color3.fromRGB(70, 70, 80), outline = Color3.fromRGB(120, 120, 132),
		accent = Color3.fromRGB(255, 255, 255), text = Color3.fromRGB(250, 250, 252), dim = Color3.fromRGB(176, 176, 186)},
	Midnight = {bg = Color3.fromRGB(3, 3, 5), panel = Color3.fromRGB(8, 8, 12), card = Color3.fromRGB(14, 14, 20),
		element = Color3.fromRGB(24, 24, 32), hover = Color3.fromRGB(36, 36, 46), outline = Color3.fromRGB(52, 52, 64),
		accent = Color3.fromRGB(205, 205, 220), text = Color3.fromRGB(232, 232, 240), dim = Color3.fromRGB(128, 128, 142)},
}
local FONTS = {Gotham = {Enum.Font.Gotham, Enum.Font.GothamMedium, Enum.Font.GothamBold},
	["Builder Sans"] = {Enum.Font.BuilderSans, Enum.Font.BuilderSansMedium, Enum.Font.BuilderSansBold},
	Montserrat = {Enum.Font.Montserrat, Enum.Font.Montserrat, Enum.Font.MontserratBold},
	Ubuntu = {Enum.Font.Ubuntu, Enum.Font.Ubuntu, Enum.Font.Ubuntu}}
local function asset(path)
	local ok, id = pcall(CAP.getcustomasset, path)
	return ok and id or nil
end
local LOGO = asset(DIR .. "/MKS-logo-transparent.png") or asset("MKS-logo-transparent.png") or asset("MKS-logo.png")
local ICONS = {}
for _, n in {"shooting", "dribbling", "defense", "player", "world", "info", "settings",
	"chevron-down", "chevron-up", "chevron-left", "close"} do
	ICONS[n] = asset(DIR .. "/icons/" .. n .. ".png")
end

local CATEGORIES = {
	{"Shooting", "shooting", {"Perfect Timing"}},
	{"Dribbling", "dribbling", {"Moves", "Combos"}},
	{"Defense", "defense", {"Block"}},
	{"World", "world", {"Mascots"}},
	{"Info", "info", {"Info"}},
	{"Settings", "settings", {"Menu"}},
}
local capturing -- {path=, done=fn}
local refreshers = {} -- live text updaters for the open page
local ui = {}

local function keyConflict(name, path)
	-- hold keys (block/guard/run up/deny) are meant to ride on the game's own G/F defense keys, like OT's defaults
	local HOLD = {["block.holdKey"] = true, ["guard.key"] = true, ["runup.key"] = true, ["deny.key"] = true}
	if gameBinds[name] and not HOLD[path] then return "game: " .. gameBinds[name] end
	if name == cfg.ui.hubKey and path ~= "ui.hubKey" then return "menu key" end
	local function chk(p, v) if v == name and p ~= path then return p end end
	for _, p in {"timing.key", "block.key", "guard.key", "dribble.playKey", "dribble.loopKey", "dribble.stopKey", "shoot.autoKey",
		"block.holdKey", "runup.key", "deny.key"} do
		-- hold keys may share one key with each other (G for block, guard and run up, as in OT)
		local hit = not (HOLD[p] and HOLD[path]) and chk(p, getp(p))
		if hit then return "MKS " .. hit end
	end
	for cn, k in cfg.dribble.comboKeys do
		if k == name and "dribble.comboKeys." .. cn ~= path then return "MKS combo " .. cn end
	end
	for mv, k in cfg.dribble.binds do
		if k == name and "dribble.binds." .. mv ~= path then return "MKS move " .. mv end
	end
	return nil
end

-- controller: game actions that are safe to share a button with while dribbling (anything else would fire a
-- second, unwanted action - a pass, shot, fake or dribble - alongside the bound move)
local PAD = {safe = {Sprint = true, QuickChat = true, QuickChatDrop = true, EmoteWheel = true, TabMenu = true, Vehicles = true, Camera = true},
	reserved = {ButtonStart = "Roblox menu", ButtonA = "selects menu items", ButtonB = "back / cancel in the menu"},
	paths = {"pad.menu", "pad.playKey", "pad.stopKey"},
	mods = {"ButtonR2", "ButtonL2", "ButtonR1", "ButtonL1"}}
local function padConflict(chord, path)
	for part in chord:gmatch("[^+]+") do
		if PAD.reserved[part] then return part .. " is reserved: " .. PAD.reserved[part] end
		for _, act in gamePad[part] or {} do
			if not PAD.safe[act] then return ("%s is the game's %s: it would fire too"):format(part, act) end
		end
	end
	for _, p in PAD.paths do if p ~= path and getp(p) == chord then return "used by MKS " .. p end end
	for mv, k in cfg.pad.binds do if k == chord and "pad.binds." .. mv ~= path then return "used by MKS move " .. mv end end
	return nil
end

local buildHub -- forward
local function destroyHub()
	if ui.root then ui.root:Destroy() end
	ui = {}
	refreshers = {}
end
onCleanup(destroyHub)

buildHub = function(openNow)
	destroyHub()
	local T = THEMES[cfg.ui.theme] or THEMES.Graphite
	local F = FONTS[cfg.ui.font] or FONTS.Gotham
	local root = Instance.new("ScreenGui")
	root.Name = "MKS_Hub"
	root.ResetOnSpawn = false
	root.IgnoreGuiInset = true
	root.DisplayOrder = 90
	root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	root.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	ui.root = root
	local function make(class, props, parent)
		local o = Instance.new(class)
		for k, v in props do o[k] = v end
		o.Parent = parent
		return o
	end
	local function corner(o, px) make("UICorner", {CornerRadius = UDim.new(0, px)}, o) end
	local function stroke(o, color, th, tr) return make("UIStroke", {Color = color, Thickness = th or 1, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, o) end
	local function text(parent, str, size, weight, color, props)
		local l = make("TextLabel", {Text = str, TextSize = size, Font = F[weight or 1], TextColor3 = color or T.text, BackgroundTransparency = 1,
			TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y}, parent)
		if props then for k, v in props do l[k] = v end end
		return l
	end
	local function tween(o, t, props, style)
		local tw = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
		tw:Play()
		return tw
	end

	-- dim + stage
	local dim = make("Frame", {BackgroundColor3 = T.bg, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false}, root)
	ui.dim = dim
	local stars = make("Frame", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)}, dim)
	local rng = Random.new(614)
	for i = 1, 70 do
		local sz = if i % 9 == 0 then 3 else (if i % 3 == 0 then 2 else 1)
		local st = make("Frame", {BorderSizePixel = 0, BackgroundColor3 = T.accent, BackgroundTransparency = rng:NextNumber(0.35, 0.85),
			Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()), Size = UDim2.fromOffset(sz, sz)}, stars)
		if i % 10 == 0 then -- a few twinkle; one tween each, no per-frame work
			TS:Create(st, TweenInfo.new(rng:NextNumber(1.6, 3), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.95}):Play()
		end
	end

	-- galaxy: logo + Saturn ring + category satellites, moved as one composition
	local galaxy = make("Frame", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 640)}, dim)
	local gScale = make("UIScale", {Scale = 1}, galaxy)
	ui.galaxy, ui.gScale = galaxy, gScale
	local ring = make("CanvasGroup", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 600), Rotation = -14, GroupTransparency = 0.2}, galaxy)
	for i = 0, 89 do
		local a = i / 90 * math.pi * 2
		local x, y = math.cos(a) * 272, math.sin(a) * 82
		local back = math.sin(a) < 0
		make("Frame", {BorderSizePixel = 0, BackgroundColor3 = T.accent, BackgroundTransparency = if back then 0.78 else 0.45,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, y), Size = UDim2.fromOffset(if i % 6 == 0 then 4 else 2, if i % 6 == 0 then 4 else 2)}, ring)
	end
	TS:Create(ring, TweenInfo.new(9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Rotation = -6}):Play()
	local glow = make("Frame", {BackgroundColor3 = T.accent, BackgroundTransparency = 0.93, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(250, 250)}, galaxy)
	corner(glow, 125)
	if cfg.ui.glow then
		TS:Create(glow, TweenInfo.new(2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.975, Size = UDim2.fromOffset(280, 280)}):Play()
	end
	local logoBtn = make("ImageButton", {Image = LOGO or "", ScaleType = Enum.ScaleType.Fit, BackgroundTransparency = 1, AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 210)}, galaxy)
	if not LOGO then text(logoBtn, "MKS", 64, 3, T.text, {TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None}) end
	text(galaxy, "MKS HUB  ·  PRACTICAL BASKETBALL", 13, 2, T.dim, {TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 112), Size = UDim2.fromOffset(360, 0)})

	local sats = {}
	ui.sats = sats
	local R = 268
	for i, cat in CATEGORIES do
		local name = cat[1]
		local ang = -math.pi / 2 + (i - 1) / #CATEGORIES * math.pi * 2
		local px, py = math.cos(ang) * R, math.sin(ang) * R * 0.86
		local b = make("TextButton", {Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = T.card, BackgroundTransparency = 0.08,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, px, 0.5, py), Size = UDim2.fromOffset(150, 48)}, galaxy)
		corner(b, 24)
		local st = stroke(b, T.outline, 1.2, 0.2)
		make("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 178))}, b)
		local icon = make("ImageLabel", {Image = ICONS[cat[2]] or "", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 13),
			Size = UDim2.fromOffset(22, 22), ImageColor3 = T.text}, b)
		local lab = text(b, name:upper(), 14, 3, T.text, {Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -54, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Center})
		local sc = make("UIScale", {Scale = 0}, b)
		sats[name] = {button = b, stroke = st, icon = icon, label = lab, scale = sc}
		b.MouseEnter:Connect(function() tween(sc, 0.18, {Scale = 1.06}); tween(b, 0.18, {BackgroundColor3 = T.hover}) end)
		b.MouseLeave:Connect(function()
			tween(sc, 0.18, {Scale = 1})
			tween(b, 0.18, {BackgroundColor3 = if ui.active == name then T.element else T.card})
		end)
		b.MouseButton1Down:Connect(function() tween(sc, 0.08, {Scale = 0.95}) end)
		b.MouseButton1Up:Connect(function() tween(sc, 0.12, {Scale = 1.06}) end)
		b.Activated:Connect(function() ui.open(name) end)
		TS:Create(b, TweenInfo.new(2.6 + i * 0.21, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{Position = UDim2.new(0.5, px, 0.5, py - 6)}):Play()
	end

	-- content panel (slides in from the right)
	local panel = make("Frame", {BackgroundColor3 = T.panel, BackgroundTransparency = cfg.ui.cardOpacity * 0.5, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(1.05, 0.5), Size = UDim2.fromOffset(1000, 780), Visible = false}, dim)
	corner(panel, 20)
	-- graphite at the top fading to near-black; static, no per-frame cost
	make("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(105, 105, 112))}, panel)
	local pStroke = stroke(panel, T.outline, 1, 0.25)
	local pScale = make("UIScale", {Scale = 1}, panel)
	ui.panel, ui.pScale = panel, pScale
	if cfg.ui.shimmer then
		local g = make("UIGradient", {Rotation = 20, Color = ColorSequence.new({ColorSequenceKeypoint.new(0, T.outline),
			ColorSequenceKeypoint.new(0.5, T.accent), ColorSequenceKeypoint.new(1, T.outline)}), Offset = Vector2.new(-1, 0)}, pStroke)
		TS:Create(g, TweenInfo.new(4.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Offset = Vector2.new(1, 0)}):Play()
	end
	local header = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, -48, 0, 92), Position = UDim2.fromOffset(24, 18)}, panel)
	local back = make("TextButton", {Text = "", Font = F[3], TextSize = 28, TextColor3 = T.text, BackgroundColor3 = T.element, AutoButtonColor = false,
		Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(0, 4)}, header)
	corner(back, 20)
	stroke(back, T.outline, 1, 0.3)
	make("ImageLabel", {Image = ICONS["chevron-left"] or "", ImageColor3 = T.text, BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18)}, back)
	local title = text(header, "", 30, 3, T.text, {Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -56, 0, 36), AutomaticSize = Enum.AutomaticSize.None})
	local sub = text(header, "", 13, 2, T.dim, {Position = UDim2.fromOffset(56, 38), Size = UDim2.new(1, -56, 0, 18), AutomaticSize = Enum.AutomaticSize.None})
	local tabs = make("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(56, 62), Size = UDim2.new(1, -56, 0, 30)}, header)
	make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8)}, tabs)
	local scroll = make("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = T.outline,
		Position = UDim2.fromOffset(20, 122), Size = UDim2.new(1, -40, 1, -138), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y}, panel)
	local cols = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y}, scroll)
	-- two columns side by side; layout() switches to one stacked column on narrow panels
	local colLayout = make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder}, cols)
	local colFrames = {}
	for i = 1, 2 do
		local c = make("Frame", {BackgroundTransparency = 1, LayoutOrder = i,
			Size = UDim2.new(0.5, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y}, cols)
		make("UIListLayout", {Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder}, c)
		make("UIPadding", {PaddingBottom = UDim.new(0, 16)}, c)
		colFrames[i] = c
	end
	local popup = make("Frame", {BackgroundColor3 = T.card, Visible = false, ZIndex = 50, Size = UDim2.fromOffset(200, 10), AutomaticSize = Enum.AutomaticSize.Y}, root)
	corner(popup, 10)
	stroke(popup, T.outline, 1, 0.1)
	make("UIListLayout", {Padding = UDim.new(0, 2)}, popup)
	make("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, popup)

	-- layout: readable at 1080p and on small windows (scale never below 0.8)
	local function layout()
		local vp = workspace.CurrentCamera.ViewportSize
		local s = cfg.ui.scale
		if cfg.ui.autoScale then s *= math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.8, 1.3) end
		ui.s = s
		pScale.Scale, gScale.Scale = s, s * (if ui.active then 0.78 else 1)
		local pw = math.min(1040, vp.X / s * 0.6)
		local ph = math.min(820, vp.Y / s * 0.88)
		panel.Size = UDim2.fromOffset(pw, ph)
		local narrow = pw < 760
		colLayout.FillDirection = if narrow then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
		colLayout.Padding = UDim.new(0, if narrow then 0 else 16)
		for _, cf in colFrames do cf.Size = if narrow then UDim2.new(1, 0, 0, 0) else UDim2.new(0.5, -8, 0, 0) end
		ui.openX = 1 - (pw * s + 24) / vp.X
		ui.galaxyX = math.max(0.2, (ui.openX * vp.X / 2) / vp.X)
	end
	layout()
	on(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function() if ui.root == root then layout() end end)

	---------------------------------------------------------------- controls
	local cardN = 0
	local function card(titleText, desc, col)
		cardN += 1
		local holder = make("CanvasGroup", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			GroupTransparency = 1, LayoutOrder = cardN}, colFrames[col or (if cardN % 2 == 1 then 1 else 2)])
		local c = make("Frame", {BackgroundColor3 = T.card, BackgroundTransparency = cfg.ui.cardOpacity, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y}, holder)
		corner(c, 14)
		stroke(c, T.outline, 1, 0.55)
		make("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, c)
		make("UIPadding", {PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16)}, c)
		text(c, titleText, 17, 3, T.text, {LayoutOrder = 0})
		if desc then text(c, desc, 13, 1, T.dim, {LayoutOrder = 1}) end
		local n = cardN
		task.delay(0.04 * n, function() if holder.Parent then tween(holder, 0.32, {GroupTransparency = 0}) end end)
		c:SetAttribute("order", 2)
		return c
	end
	-- title and hint are stacked siblings in a text column that leaves rightW px for the control,
	-- so wrapped text grows the row (and the card/canvas) instead of drawing over the next row
	local function row(c, label, hint, rightW)
		local o = c:GetAttribute("order")
		c:SetAttribute("order", o + 1)
		local r = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = o}, c)
		local col = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, -((rightW or 140) + 12), 0, 0), AutomaticSize = Enum.AutomaticSize.Y}, r)
		make("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, col)
		make("UIPadding", {PaddingTop = UDim.new(0, 6)}, col)
		local l = text(col, label, 14, 2, T.text, {LayoutOrder = 1})
		if hint then text(col, hint, 12, 1, T.dim, {LayoutOrder = 2}) end
		return r, l, col
	end
	local function pill(parent, w)
		local b = make("TextButton", {AutoButtonColor = false, BackgroundColor3 = T.element, Font = F[2], TextSize = 13, TextColor3 = T.text,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(w or 130, 30), Text = ""}, parent)
		corner(b, 8)
		stroke(b, T.outline, 1, 0.5)
		b.MouseEnter:Connect(function() tween(b, 0.12, {BackgroundColor3 = T.hover}) end)
		b.MouseLeave:Connect(function() tween(b, 0.12, {BackgroundColor3 = T.element}) end)
		return b
	end
	local function toggle(c, label, path, hint, after)
		local r = row(c, label, hint, 46)
		local track = make("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = T.element, AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 3), Size = UDim2.fromOffset(46, 24)}, r)
		corner(track, 12)
		stroke(track, T.outline, 1, 0.4)
		local knob = make("Frame", {BackgroundColor3 = T.dim, Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3)}, track)
		corner(knob, 9)
		local function paint(animate)
			local v = getp(path) == true
			local props1 = {Position = UDim2.fromOffset(if v then 25 else 3, 3), BackgroundColor3 = if v then T.bg else T.dim}
			local props2 = {BackgroundColor3 = if v then T.accent else T.element}
			if animate then tween(knob, 0.16, props1); tween(track, 0.16, props2)
			else for k, v2 in props1 do knob[k] = v2 end; for k, v2 in props2 do track[k] = v2 end end
		end
		paint(false)
		track.Activated:Connect(function()
			setp(path, not getp(path))
			paint(true)
			if after then after(getp(path)) end
		end)
		return track
	end
	local function slider(c, label, path, min, max, step, fmt, after)
		local r = row(c, label, nil, 110)
		r.Size = UDim2.new(1, 0, 0, 46)
		local val = text(r, "", 13, 2, T.dim, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(110, 18),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right})
		local bar = make("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = T.element, Position = UDim2.new(0, 0, 0, 30),
			Size = UDim2.new(1, 0, 0, 6)}, r)
		corner(bar, 3)
		local fill = make("Frame", {BackgroundColor3 = T.accent, Size = UDim2.fromScale(0, 1), BorderSizePixel = 0}, bar)
		corner(fill, 3)
		local knob = make("Frame", {BackgroundColor3 = T.text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(14, 14)}, bar)
		corner(knob, 7)
		local function paint()
			local v = getp(path) or min
			local a = math.clamp((v - min) / (max - min), 0, 1)
			fill.Size = UDim2.fromScale(a, 1)
			knob.Position = UDim2.fromScale(a, 0.5)
			val.Text = (fmt or "%s"):format(v)
		end
		paint()
		local dragging = false
		local function set(x)
			local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			local v = math.clamp(math.round((min + a * (max - min)) / step) * step, min, max)
			v = math.round(v * 1000) / 1000
			if v ~= getp(path) then
				setp(path, v)
				paint()
				if after then after(v) end
			end
		end
		bar.MouseButton1Down:Connect(function(x) dragging = true; set(x) end)
		-- controller: keep focus on the bar for left/right, which then step the value
		bar.NextSelectionLeft, bar.NextSelectionRight = bar, bar
		on(UIS.InputBegan, function(i)
			if GuiService.SelectedObject ~= bar or (i.KeyCode ~= Enum.KeyCode.DPadLeft and i.KeyCode ~= Enum.KeyCode.DPadRight) then return end
			local v = math.clamp((getp(path) or min) + (if i.KeyCode == Enum.KeyCode.DPadRight then step else -step), min, max)
			setp(path, math.round(v * 1000) / 1000)
			paint()
			if after then after(getp(path)) end
		end)
		on(UIS.InputChanged, function(i)
			if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then set(i.Position.X) end
		end)
		on(UIS.InputEnded, function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
	end
	local function closePopup() popup.Visible = false; for _, ch in popup:GetChildren() do if ch:IsA("TextButton") then ch:Destroy() end end end
	ui.closePopup = closePopup
	local function dropdown(c, label, path, options, after)
		local r = row(c, label, nil, 170)
		local b = pill(r, 170)
		local isColor = options == COLOR_NAMES
		local valueX = if isColor then 34 else 12
		local valueLabel = make("TextLabel", {Text = "", Font = F[2], TextSize = 13, TextColor3 = T.text,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundTransparency = 1, Position = UDim2.fromOffset(valueX, 0),
			Size = UDim2.new(1, -(valueX + 30), 1, 0)}, b)
		make("ImageLabel", {Image = ICONS["chevron-down"] or "", ImageColor3 = T.dim,
			BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -17, 0.5, 0), Size = UDim2.fromOffset(13, 13)}, b)
		local swatch
		if isColor then
			swatch = make("Frame", {BorderSizePixel = 0, Position = UDim2.fromOffset(11, 8), Size = UDim2.fromOffset(14, 14)}, b)
			corner(swatch, 4)
			stroke(swatch, T.outline, 1, 0.2)
		end
		local function paint()
			local value = getp(path)
			valueLabel.Text = tostring(value)
			if swatch then swatch.BackgroundColor3 = COLORS[value] or T.dim end
		end
		paint()
		b.Activated:Connect(function()
			if popup.Visible then
				closePopup()
				return
			end
			local opts = if type(options) == "function" then options() else options
			for i, o in opts do
				local ob = make("TextButton", {Text = "", Font = F[2], TextSize = 13, TextColor3 = T.text, AutoButtonColor = false,
					BackgroundColor3 = if o == getp(path) then T.hover else T.card,
					Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, ZIndex = 51}, popup)
				corner(ob, 6)
				make("TextLabel", {Text = tostring(o), Font = F[2], TextSize = 13, TextColor3 = T.text,
					TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
					BackgroundTransparency = 1, Position = UDim2.fromOffset(valueX, 0),
					Size = UDim2.new(1, -(valueX + 8), 1, 0), ZIndex = 52}, ob)
				if isColor then
					local chip = make("Frame", {BorderSizePixel = 0, BackgroundColor3 = COLORS[o] or T.dim,
						Position = UDim2.fromOffset(11, 6), Size = UDim2.fromOffset(14, 14), ZIndex = 52}, ob)
					corner(chip, 4)
					stroke(chip, T.outline, 1, 0.2)
				end
				ob.Activated:Connect(function()
					setp(path, o)
					paint()
					closePopup()
					if after then after(o) end
				end)
			end
			local s = ui.s or 1
			popup.Size = UDim2.fromOffset(170 * s, 0)
			popup.Position = UDim2.fromOffset(b.AbsolutePosition.X, b.AbsolutePosition.Y + b.AbsoluteSize.Y + 4)
			popup.Visible = true
			if lastPad then ui.padFocus(popup) end
		end)
	end
	local function keybind(c, label, path, hint)
		local r, _, col = row(c, label, hint, 120)
		local b = pill(r, 120)
		-- capture prompt / conflict message goes under the label, never beside the pill
		local warn = text(col, "", 11, 1, Color3.fromRGB(255, 120, 120), {LayoutOrder = 3, Visible = false})
		local function say(msg) warn.Text = msg or ""; warn.Visible = warn.Text ~= "" end
		local function paint() local v = getp(path); b.Text = if v == nil or v == "" then "unbound" else v end
		paint()
		local pad = path:find("^pad%.") ~= nil
		b.Activated:Connect(function()
			b.Text = if pad then "press a button…" else "press a key…"
			say(if pad then "Hold R2 / L2 / R1 / L1 then press a button for a chord · B cancel · Y unbind" else "Esc cancel · Backspace unbind")
			capturing = {path = path, pad = pad, at = os.clock(), done = function(msg) paint(); say(msg) end}
		end)
	end
	local function button(c, label, fn, hint)
		local r = row(c, label, hint, 130)
		local b = pill(r, 130)
		b.Text = "RUN"
		b.Activated:Connect(function()
			local ok, res = pcall(fn)
			b.Text = if ok then (res or "DONE") else "ERROR"
			if not ok then report("error", ("%s: %s"):format(label, tostring(res))) end
			task.delay(1.2, function() if b.Parent then b.Text = "RUN" end end)
		end)
		return b
	end
	local function buttons(c, list)
		local o = c:GetAttribute("order")
		c:SetAttribute("order", o + 1)
		local r = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = o}, c)
		make("UIGridLayout", {CellSize = UDim2.new(1 / math.min(#list, 3), -6, 0, 30), CellPadding = UDim2.fromOffset(6, 6)}, r)
		for _, it in list do
			local b = make("TextButton", {AutoButtonColor = false, BackgroundColor3 = T.element, Font = F[2], TextSize = 13, TextColor3 = T.text, Text = it[1]}, r)
			corner(b, 8)
			stroke(b, T.outline, 1, 0.5)
			b.MouseEnter:Connect(function() tween(b, 0.12, {BackgroundColor3 = T.hover}) end)
			b.MouseLeave:Connect(function() tween(b, 0.12, {BackgroundColor3 = T.element}) end)
			b.Activated:Connect(function()
				local ok, err = pcall(it[2])
				if not ok then report("error", ("%s: %s"):format(it[1], tostring(err))) end
			end)
		end
	end
	local function textbox(c, label, path, placeholder, after)
		local r = row(c, label, nil, 170)
		local b = make("TextBox", {BackgroundColor3 = T.element, Font = F[1], TextSize = 13, TextColor3 = T.text, PlaceholderText = placeholder or "",
			PlaceholderColor3 = T.dim, ClearTextOnFocus = false, Text = tostring(getp(path) or ""), AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(170, 30), TextTruncate = Enum.TextTruncate.AtEnd}, r)
		corner(b, 8)
		stroke(b, T.outline, 1, 0.5)
		b.FocusLost:Connect(function()
			setp(path, b.Text)
			if after then after(b.Text) end
		end)
		return b
	end
	local function live(c, fn, size)
		local o = c:GetAttribute("order")
		c:SetAttribute("order", o + 1)
		local l = text(c, "", size or 13, 1, T.dim, {LayoutOrder = o, RichText = true})
		local function upd() local ok, s = pcall(fn); l.Text = if ok then s else ("error: " .. tostring(s)) end
		upd()
		table.insert(refreshers, upd)
		return l
	end
	local function unsupported(c, label, reason)
		local r = row(c, label, reason, 100)
		local b = text(r, "UNSUPPORTED", 11, 3, T.dim, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 6), Size = UDim2.fromOffset(110, 16),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right})
		return b
	end
	local MOVEMENT_RULE = "Changes movement or server-owned stats; excluded by the no-forced-movement / anti-cheat rule."

	---------------------------------------------------------------- pages
	local PAGES = {}
	PAGES["Perfect Timing"] = function()
		local c = card("Perfect Timing", "Holds your E or Space and lets go so the release reaches the server inside the green window. You can always release yourself.")
		toggle(c, "Auto Timing", "timing.enabled", "Lets go for you")
		keybind(c, "Toggle key", "timing.key")
		live(c, function() return "<b>Last shot:</b> " .. lastShot.text end)
		c = card("Premium", "Ping compensation, per-meter offsets, calibration, meter styles and Auto Shoot are in MKS Premium.")
	end
	PAGES["Moves"] = function()
		local c = card("Move Keybinds", "Any key the game does not already use. Click, press a key; Backspace unbinds. Moves run only while you hold the ball.")
		toggle(c, "Instant moves", "dribble.direct", "Sends the move straight to the game instead of waiting out its key buffer (about 110 ms faster). Off = real key presses.")
		for _, name in MOVE_NAMES do if not PREMIUM and not FREE_MOVE[name] then continue end if MOVE_BY[name].disabled then unsupported(c, name, MOVE_BY[name].disabled) else keybind(c, name, "dribble.binds." .. name, if MOVE_BY[name].gather then "gather: hold Shift while driving" else nil) end end
		c = card("Controller binds", "Pick a button or a chord (hold R2/L2/R1/L1, press another). Controller moves always use the game's dribble action.")
		for _, name in MOVE_NAMES do if not PREMIUM and not FREE_MOVE[name] then continue end if not MOVE_BY[name].disabled then keybind(c, name, "pad.binds." .. name, if MOVE_BY[name].gather then "gather: hold R2 (sprint) while driving" else nil) end end
		c = card("Premium", "All 13 moves, gathers, Auto Ankle Breaker and the combo editor are in MKS Premium.")
		c = card("Test a move", "Runs the selected move once (needs the ball).")
		dropdown(c, "Move", "dribble._test", MOVE_NAMES)
		button(c, "Run move", function() task.spawn(doMove, cfg.dribble._test or "Crossover") end)
		c = card("Not available", nil)
		unsupported(c, "Halo Dribble", "Not one of this game's moves (Dribbling.Input has no Halo).")
		unsupported(c, "Dribble / Gather Glide", MOVEMENT_RULE)
	end
	PAGES["Combos"] = function()
		local c = card("Combo", "Pick, build and run a sequence. Stops on respawn, losing the ball, unload or Stop.")
		dropdown(c, "Combo", "dribble.combo", function() local o = {} for k in cfg.dribble.combos do table.insert(o, k) end table.sort(o) return o end,
			function() ui.render() end)
		buttons(c, {{"Play", function() playCombo(false) end}, {"Loop", function() playCombo(true) end}, {"Stop", function() stopMacro("manual") end}})
		live(c, function() return "Status: <b>" .. macro.status .. "</b>" end)
	end
	PAGES["Block"] = function()
		local c = card("Auto Block", "Reads the shot first: a new ShotStartTime only arms it; it jumps after the shooter commits (held shot, airborne or ball released) and cancels on pump fake, abort, pass, range or line of sight.")
		toggle(c, "Auto Block", "block.enabled")
		keybind(c, "Toggle key", "block.key")
		toggle(c, "Team check", "block.teamCheck")
		live(c, function()
			return ("Jumps <b>%d</b> · cancels <b>%d</b> · %s"):format(blk.stats.jumps, blk.stats.cancels,
				if blk.cand then ("tracking %s (%s)"):format(blk.cand.o.Name, blk.cand.catName) else "idle")
		end)
		c = card("Premium", "Per-shot-type blocking, lane shift, Auto Rebound, Auto Guard, Run Up and Off-ball Deny are in MKS Premium.")
	end
	PAGES["Mascots"] = function()
		local c = card("Custom Mascots", "Uses the game's own mascot renderer on your character. Client-side: only you see it.")
		dropdown(c, "Mascot", "world.mascot", mascotNames)
		textbox(c, "Custom mascot ID", "world.customMascot", "asset id (optional)")
		toggle(c, "Wear Mascot", "world.wearMascot", nil, function(v) wearMascot(v) end)
		button(c, "Re-apply", function() wearMascot(cfg.world.wearMascot) end)
		live(c, function() return mascotMsg end)
		c = card("Not available", nil)
		unsupported(c, "Unlock All", "Cosmetic ownership is server data; a client-only unlock would be fake.")
	end
	PAGES["Info"] = function()
		local c = card("Game", nil)
		live(c, function()
			return ("Place <b>%d</b> (v%d)<br/>Server age <b>%dm</b> · players <b>%d</b><br/>You: <b>%s</b> (@%s)<br/>FPS <b>%d</b> · ping <b>%d ms</b>"):format(
				game.PlaceId, game.PlaceVersion, workspace.DistributedGameTime // 60, #Players:GetPlayers(),
				if cfg.misc.hideName then "Player" else lp.DisplayName, if cfg.misc.hideName then "hidden" else lp.Name, fps, pingMs)
		end)
		c = card("Compatibility", nil)
		live(c, function()
			local lines = {("Executor <b>%s</b> · MKS %s %s · game data <b>%s</b>"):format(tostring(CAP.executor), VERSION,
				if PREMIUM then "Premium" else "Free", if genv.__mks_player then "read" else "not read")}
			for _, e in CAP.list do
				local col = if e.status == "ok" then "#9be89b" elseif e.status == "fallback" then "#ffd27a" else "#ff8080"
				table.insert(lines, ('<font color="%s">%s</font> %s%s'):format(col, e.status, e.api, if e.status == "ok" then "" else (" · " .. e.effect)))
			end
			return table.concat(lines, "<br/>")
		end)
		c = card("Keys", nil)
		live(c, function()
			return ("Menu <b>%s</b> · timing <b>%s</b> · block <b>%s</b> · Esc returns to the galaxy"):format(cfg.ui.hubKey, cfg.timing.key, cfg.block.key)
		end)
		c = card("Diagnostics", "MKS keeps its own log here instead of the Developer Console. Errors are listed first.")
		live(c, function()
			return ("Last shot: <b>%s</b><br/>Combo: <b>%s</b>"):format(lastShot.text, macro.status)
		end)
		live(c, function()
			local errs, rest = {}, {}
			for i = #diag, 1, -1 do
				local e = diag[i]
				local line = ("%s  %s"):format(e.t, (e.msg:gsub("<", "‹")))
				if e.level == "error" then if #errs < 5 then table.insert(errs, '<font color="#ff8080">' .. line .. "</font>") end
				elseif #rest < 8 then table.insert(rest, line) end
			end
			if #errs + #rest == 0 then return "Nothing logged yet." end
			return table.concat(errs, "<br/>") .. ((#errs > 0 and #rest > 0) and "<br/>" or "") .. table.concat(rest, "<br/>")
		end, 12)
		toggle(c, "Echo to Developer Console", "misc.debugConsole", "Off for normal play. On prints MKS events with an [MKS] tag for testing.")
		buttons(c, {{"Clear log", function() table.clear(diag) end}})
		c = card("Bug reports & suggestions", "Tell Claude or Codex in chat; the shared vault 04 Log tracks MKS status.")
	end
	PAGES["Menu"] = function()
		local c = card("Menu", nil)
		keybind(c, "Menu key", "ui.hubKey")
		keybind(c, "Menu button (controller)", "pad.menu", "Select by default. B goes back; A picks; d-pad moves.")
		toggle(c, "Dim background", "ui.dim", nil, function() ui.applyDim() end)
		toggle(c, "Watermark", "ui.watermark", "fps · ping · last grade")
		toggle(c, "Auto scale to screen", "ui.autoScale", nil, function() layout() end)
		slider(c, "UI scale", "ui.scale", 0.8, 1.4, 0.05, "×%.2f", function() layout() end)
		dropdown(c, "Font", "ui.font", {"Gotham", "Builder Sans", "Montserrat", "Ubuntu"}, function() buildHub(true) end)
		toggle(c, "Mobile toggle button", "ui.mobileToggle", "Off by default: no permanent launcher", function() buildHub(true) end)
		c = card("Teleport", nil)
		toggle(c, "Reload after teleport", "ui.reloadTp", nil, function() genv.__mks_queue() end)
		button(c, "Unload MKS", function() task.defer(genv.__mks_kill) return "BYE" end)
		c = card("Not available", nil)
		unsupported(c, "Custom cursor / wallpaper / icon", "Needs image uploads; uploading assets requires your approval.")
		unsupported(c, "Draggable cards / sidebar", "MKS uses the galaxy layout instead of Zero Hub's sidebar.")
	end

	---------------------------------------------------------------- navigation
	local tabButtons = {}
	-- controller navigation: put selection on the first visible button under `root`
	ui.padFocus = function(rootObj)
		task.defer(function()
			for _, d in rootObj:GetDescendants() do
				if d:IsA("GuiButton") and d.Visible and d.Selectable then GuiService.SelectedObject = d return end
			end
		end)
	end
	ui.render = function()
		closePopup()
		refreshers = {}
		for _, col in colFrames do for _, ch in col:GetChildren() do if ch:IsA("GuiObject") then ch:Destroy() end end end
		cardN = 0
		scroll.CanvasPosition = Vector2.zero
		local pageFn = PAGES[ui.page]
		if pageFn then
			local ok, err = pcall(pageFn)
			if not ok then report("error", ("page %s: %s"):format(ui.page, tostring(err))) end
		end
		for n, b in tabButtons do
			b.BackgroundColor3 = if n == ui.page then T.accent else T.element
			b.TextColor3 = if n == ui.page then T.bg else T.text
		end
		if lastPad then ui.padFocus(scroll) end
	end
	local function setTabs(cat)
		for _, b in tabButtons do b:Destroy() end
		tabButtons = {}
		for i, n in cat[3] do
			local b = make("TextButton", {Text = n, Font = F[2], TextSize = 13, AutoButtonColor = false, BackgroundColor3 = T.element, TextColor3 = T.text,
				Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i}, tabs)
			make("UIPadding", {PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14)}, b)
			corner(b, 15)
			b.Activated:Connect(function() ui.page = n; ui.render() end)
			tabButtons[n] = b
		end
	end
	ui.open = function(name)
		local cat
		for _, c in CATEGORIES do if c[1] == name then cat = c end end
		if not cat then return end
		local first = ui.active == nil
		ui.active = name
		ui.page = cat[3][1]
		for n, s in sats do
			local on = n == name
			s.stroke.Color = if on then T.accent else T.outline
			s.stroke.Thickness = if on then 2 else 1.2
			s.stroke.Transparency = if on then 0 else 0.2
			s.button.BackgroundColor3 = if on then T.element else T.card
			s.icon.ImageColor3 = if on then T.accent else T.dim
			s.label.TextColor3 = if on then T.text else T.dim
		end
		title.Text = name:upper()
		sub.Text = "MKS  /  " .. name:upper()
		setTabs(cat)
		layout()
		-- galaxy glides left as one piece; the panel comes in from the right
		tween(galaxy, 0.55, {Position = UDim2.fromScale(ui.galaxyX, 0.5)})
		tween(gScale, 0.55, {Scale = ui.s * 0.78})
		panel.Visible = true
		if first then
			panel.Position = UDim2.fromScale(1.05, 0.5)
			tween(panel, 0.5, {Position = UDim2.fromScale(ui.openX, 0.5)})
		end
		ui.render()
	end
	ui.home = function()
		ui.active = nil
		closePopup()
		for _, s in sats do
			s.stroke.Color, s.stroke.Thickness, s.stroke.Transparency = T.outline, 1.2, 0.2
			s.button.BackgroundColor3, s.icon.ImageColor3, s.label.TextColor3 = T.card, T.text, T.text
		end
		tween(galaxy, 0.5, {Position = UDim2.fromScale(0.5, 0.5)})
		tween(gScale, 0.5, {Scale = ui.s})
		local tw = tween(panel, 0.4, {Position = UDim2.fromScale(1.05, 0.5)})
		tw.Completed:Once(function() if not ui.active and panel.Parent then panel.Visible = false end end)
	end
	back.Activated:Connect(ui.home)
	logoBtn.Activated:Connect(function() if ui.active then ui.home() end end)
	ui.applyDim = function() if ui.shown then tween(dim, 0.3, {BackgroundTransparency = if cfg.ui.dim then 0.35 else 1}) end end
	ui.show = function(v)
		ui.shown = v
		closePopup()
		if v then
			dim.Visible = true
			ui.active = nil
			panel.Visible = false
			galaxy.Position = UDim2.fromScale(0.5, 0.5)
			layout()
			gScale.Scale = ui.s * 0.85
			tween(gScale, 0.6, {Scale = ui.s})
			ui.applyDim()
			for i, cat in CATEGORIES do
				local s = sats[cat[1]]
				s.scale.Scale = 0
				task.delay(0.08 + i * 0.05, function() if s.scale.Parent then tween(s.scale, 0.42, {Scale = 1}, Enum.EasingStyle.Back) end end)
				s.stroke.Color, s.stroke.Thickness, s.stroke.Transparency = T.outline, 1.2, 0.2
				s.button.BackgroundColor3, s.icon.ImageColor3, s.label.TextColor3 = T.card, T.text, T.text
			end
		else
			tween(dim, 0.25, {BackgroundTransparency = 1})
			local tw = tween(gScale, 0.25, {Scale = ui.s * 0.9})
			for _, s in sats do tween(s.scale, 0.2, {Scale = 0}) end
			tween(panel, 0.25, {Position = UDim2.fromScale(1.05, 0.5)})
			tw.Completed:Once(function() if not ui.shown and dim.Parent then dim.Visible = false end end)
		end
	end
	if cfg.ui.mobileToggle then
		local mb = make("TextButton", {Text = "MKS", Font = F[3], TextSize = 13, TextColor3 = T.text, BackgroundColor3 = T.card,
			Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(52, 52)}, root)
		corner(mb, 26)
		stroke(mb, T.outline, 1, 0.2)
		mb.Activated:Connect(function() ui.show(not ui.shown) end)
	end
	-- after the satellites' intro tween: a button still scaled to zero is not given selection
	ui.focusHome = function() local s1 = sats[CATEGORIES[1][1]] if s1 then task.delay(0.55, function() if ui.shown and s1.button.Parent then GuiService.SelectedObject = s1.button end end) end end
	if openNow then
		ui.show(true)
	end
	return root
end

---------------------------------------------------------------- input
local function runBound(name)
	if name == cfg.timing.key then cfg.timing.enabled = not cfg.timing.enabled; markDirty() return true end
	if name == cfg.block.key then cfg.block.enabled = not cfg.block.enabled; markDirty() return true end
	if cfg.dribble.playKey ~= "" and name == cfg.dribble.playKey then playCombo(false) return true end
	if cfg.dribble.loopKey ~= "" and name == cfg.dribble.loopKey then playCombo(true) return true end
	if cfg.dribble.stopKey ~= "" and name == cfg.dribble.stopKey then stopMacro("manual") return true end
	for _, sys in {"guard", "runup", "deny"} do
		local c = cfg[sys]
		if c.key ~= "" and name == c.key and not c.hold then c.enabled = not c.enabled; markDirty() return true end
	end
	if cfg.shoot.autoKey ~= "" and name == cfg.shoot.autoKey then
		if not cfg.shoot.autoHold then cfg.shoot.auto = not cfg.shoot.auto; markDirty() end
		return true
	end
	for cn, k in cfg.dribble.comboKeys do
		if k == name and cfg.dribble.combos[cn] then cfg.dribble.combo = cn; playCombo(false) return true end
	end
	for mv, k in cfg.dribble.binds do
		if k == name then task.spawn(doMove, mv) return true end
	end
	return false
end
-- controller --------------------------------------------------------------------------------------------
PAD.cap = nil -- modifier pressed during capture, waiting for a second button or its own release
local function padDown(i)
	local name = i.KeyCode.Name
	if not name:find("^Button") and not name:find("^DPad") then return end
	if capturing and capturing.pad then
		local cap = capturing
		if os.clock() - cap.at < 0.25 then return end -- the A press that opened the prompt
		if name == "ButtonB" then capturing, PAD.cap = nil, nil; cap.done("cancelled") return end
		if name == "ButtonY" and not PAD.cap then capturing = nil; setp(cap.path, ""); cap.done("unbound") return end
		if table.find(PAD.mods, name) and not PAD.cap then PAD.cap = name return end
		local chord = if PAD.cap and PAD.cap ~= name then PAD.cap .. "+" .. name else name
		capturing, PAD.cap = nil, nil
		local clash = padConflict(chord, cap.path)
		if clash then cap.done(clash) return end
		setp(cap.path, chord)
		cap.done()
		return
	end
	if UIS:GetFocusedTextBox() then return end
	-- the pressed button with any modifier already held; an exact chord bind wins over the bare button
	local chord
	for _, m in PAD.mods do
		if m ~= name and UIS:IsGamepadButtonDown(i.UserInputType, Enum.KeyCode[m]) then chord = m .. "+" .. name break end
	end
	local function match(k) return k ~= "" and (k == chord or k == name) end
	local P = cfg.pad
	if match(P.menu) then
		if not ui.root then buildHub(false) end
		ui.show(not ui.shown)
		if ui.shown then ui.focusHome() else GuiService.SelectedObject = nil end
		return
	end
	if ui.shown and name == "ButtonB" then
		if ui.active then ui.home(); ui.focusHome() else ui.show(false); GuiService.SelectedObject = nil end
		return
	end
	if ui.shown and GuiService.SelectedObject then return end -- navigating the menu
	if match(P.playKey) then playCombo(false) return end
	if match(P.stopKey) then stopMacro("manual") return end
	local exact
	for mv, k in P.binds do if k ~= "" and k == chord then exact = mv end end
	if not exact then for mv, k in P.binds do if k == name then exact = mv end end end
	if exact then task.spawn(doMove, exact) end
end
local function padUp(i)
	local name = i.KeyCode.Name
	if capturing and capturing.pad and PAD.cap == name then
		-- a modifier pressed and released alone binds on its own
		local cap = capturing
		capturing, PAD.cap = nil, nil
		local clash = padConflict(name, cap.path)
		if clash then cap.done(clash) return end
		setp(cap.path, name)
		cap.done()
	end
end
local function isPad(t) return t == Enum.UserInputType.Gamepad1 or t == Enum.UserInputType.Gamepad2 end

on(UIS.InputBegan, function(i, gp)
	if isPad(i.UserInputType) then lastPad = true padDown(i) return end
	if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
	lastPad = false
	local name = i.KeyCode.Name
	if isSynthetic(name) then return end
	if capturing then
		local cap = capturing
		capturing = nil
		if name == "Escape" then cap.done("cancelled") return end
		if name == "Backspace" or name == "Delete" then setp(cap.path, ""); cap.done("unbound") return end
		if cap.pad then capturing = cap; cap.done("press a controller button (Esc cancels)") return end
		if RESERVED[name] then cap.done(name .. " is reserved: " .. RESERVED[name]) return end
		local clash = keyConflict(name, cap.path)
		if clash then cap.done(name .. " is used by " .. clash) return end
		setp(cap.path, name)
		cap.done()
		return
	end
	if UIS:GetFocusedTextBox() then return end
	if name == cfg.ui.hubKey then
		if not ui.root then buildHub(false) end
		ui.show(not ui.shown)
		return
	end
	if name == "Escape" and ui.shown and ui.active then ui.home() return end
	if gp then return end
	if SHOT_KEYS[name] then
		startShot(name)
		return
	end
	if macro.running and (name == "W" or name == "A" or name == "S" or name == "D") then
		-- the player taking over movement does not stop a combo; only Stop, respawn or losing the ball do
	end
	runBound(name)
end)
on(UIS.InputEnded, function(i)
	if isPad(i.UserInputType) then padUp(i) return end
	if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local name = i.KeyCode.Name
	if isSynthetic(name) then return end
	if shot and shot.key == name then
		held[name] = nil
		if not shot.started then
			shot = nil -- quick tap: gather / pump fake, not a shot
		elseif not shot.released then
			shot.manualRel, shot.released, shot.tRel = true, true, os.clock()
			pending, shot = shot, nil
		end
	end
end)

---------------------------------------------------------------- teleport / unload
genv.__mks_queue = function()
	pcall(CAP.clear_teleport_queue)
	-- started by the Luarmor loader: the loader queues itself (and its saved key) for the next server
	if cfg.ui.reloadTp and not genv.__mks_via_loader then
		pcall(CAP.queue_on_teleport, 'local ok, src = pcall(readfile, "MKS-Hub.lua") if ok then loadstring(src)() end')
	end
end
genv.__mks_queue()
on(lp.OnTeleport, function(state)
	if state == Enum.TeleportState.Started then
		stopMacro("teleport")
		releaseAll()
		saveNow()
	end
end)
genv.__mks_kill = function()
	genv.__mks_kill = nil
	stopMacro("unload")
	releaseAll()
	pcall(saveNow)
	for _, c in conns do pcall(function() c:Disconnect() end) end
	for i = #cleanups, 1, -1 do pcall(cleanups[i]) end
end
if LR then LR.onCleanup(function() if genv.__mks_kill then genv.__mks_kill() end end) end
genv.__mks_apply_world = function() applyLighting(); applyWeather(); applySpectate() end
-- test/inspection handle (used by the in-game test runs; harmless otherwise)
genv.__mks_debug = function()
	return {ui = ui, cfg = cfg, prof = prof, shot = shot, pending = pending, blk = blk, macro = macro, lastShot = lastShot,
		doMove = doMove, playCombo = playCombo, stopMacro = stopMacro, wearMascot = wearMascot, held = held, ping = pingMs, fps = fps,
		log = log, diag = diag, report = report, nearest = nearestNow, steer = steer, keyConflict = keyConflict, save = saveNow,
		runBound = runBound, shotCategory = shotCategory, tier = TIER, cap = CAP, padDown = padDown, padUp = padUp,
		padConflict = padConflict, keyCode = keyCode, useDirect = useDirect, setPad = function(v) lastPad = v end,
		near = function() return nearestNow end, -- live; `nearest` above is a snapshot from when the handle was made
		capture = function(path, cb, pad) capturing = {path = path, pad = pad, at = 0, done = cb or function() end} end}
end
applyLighting()
applyWeather()
applySpectate()
if cfg.world.wearMascot then task.delay(2, wearMascot, true) end

-- transparent logo-only splash, then the galaxy opens centered
local splash = Instance.new("ScreenGui")
splash.Name = "MKS_Splash"
splash.IgnoreGuiInset = true
splash.DisplayOrder = 95
splash.Parent = (gethui and gethui()) or game:GetService("CoreGui")
onCleanup(function() splash:Destroy() end)
local sl = Instance.new("ImageLabel")
sl.BackgroundTransparency = 1
sl.Image = LOGO or ""
sl.ScaleType = Enum.ScaleType.Fit
sl.ImageTransparency = 1
sl.AnchorPoint = Vector2.new(0.5, 0.5)
sl.Position = UDim2.fromScale(0.5, 0.5)
sl.Size = UDim2.fromOffset(200, 140)
sl.Parent = splash
TS:Create(sl, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency = 0, Size = UDim2.fromOffset(340, 238)}):Play()
task.delay(0.9, function()
	if not splash.Parent then return end
	local tw = TS:Create(sl, TweenInfo.new(0.3), {ImageTransparency = 1})
	tw:Play()
	tw.Completed:Once(function() splash:Destroy() end)
	if genv.__mks_kill then buildHub(not cfg.ui.autoHide) end
end)

-- live page text refresh, twice a second (no per-frame UI work)
task.spawn(function()
	while genv.__mks_kill do
		task.wait(0.5)
		if ui.shown then for _, f in refreshers do f() end end
	end
end)
return ("MKS %s loaded · %d profiles · %d log entries"):format(VERSION, (function() local n = 0 for _ in cfg.profiles do n += 1 end return n end)(), #log)
