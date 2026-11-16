--!nocheck
-- MKS Hub public loader (STAGED for owner review, not live).
-- Holds no secrets: script IDs and the get-key link are public by design. Never put the Luarmor API key here.
-- Players:  script_key = "KEY"; loadstring(game:HttpGet(LOADER_URL))()   -- or run without a key and use the key screen.
-- Tiers: Luarmor holds ONLY Premium keys (its server rejects anything else). Free keys come from Work.ink (8 h, 2 ad steps).
local PREMIUM_ID = "b4ad1a00cffa1ed610e4b26178189f17"  -- Luarmor script "MKS Premium"
local GET_KEY_URL = "https://work.ink/3aM5/mks-free-8h-key" -- step 1 -> step 2 -> work.ink/token shows the key
local WORKINK_LINK_ID = 5073123 -- the step-2 link; keys minted by it count
local WORKINK_USER_ID = 756405  -- owner's work.ink account; keys made by hand in the dashboard (linkId null) count too
local FREE_URL = "https://raw.githubusercontent.com/mkempireszoffical-ui/MKS/main/MKS-Free.lua"   -- Luarmor FFA needs a paid plan; Free is hosted raw here
local LOADER_URL = "https://raw.githubusercontent.com/mkempireszoffical-ui/MKS/main/MKS-Loader.lua" -- this file's own raw URL; used to re-load after teleport
local ASSET_URL = "https://raw.githubusercontent.com/mkempireszoffical-ui/MKS/main"  -- folder holding mks-planet.png and MKS-logo-transparent.png
local DIR, KEY_FILE = "MKS", "MKS/key.txt"

local genv = getgenv()
if genv.__mks_key_kill then pcall(genv.__mks_key_kill) end
if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
while not Players.LocalPlayer do task.wait() end
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local cam = workspace.CurrentCamera

local api = loadstring(game:HttpGet("https://sdkapi-public.luarmor.net/library.lua"))()

---------------------------------------------------------------- key logic
-- Tier comes from the key servers' answers, never from anything the player can edit.
-- Work.ink keys are UUIDs (36 chars with dashes); Luarmor keys are 32 letters. Shape picks which server to ask.
local FREE, PREMIUM = "free", "premium"
local function isWorkinkKey(key) return #key == 36 and key:match("^[%x%-]+$") ~= nil end
local function checkFree(key)
	local body = game:HttpGet("https://work.ink/_api/v2/token/isValid/" .. key)
	local r = game:GetService("HttpService"):JSONDecode(body)
	-- isValid always answers 200; only the body decides. linkId stops keys minted by other people's work.ink links.
	local info = r.info or {}
	if r.valid == true and (tonumber(info.linkId) == WORKINK_LINK_ID or tonumber(info.userId) == WORKINK_USER_ID) then return FREE end
	return nil, "Free key expired or not valid. Press GET KEY for a new 8-hour key."
end
local MESSAGES = {
	KEY_EXPIRED = "Premium key expired. Contact the owner to renew it.",
	KEY_HWID_LOCKED = "Premium key is locked to another device. Contact the owner for a reset.",
	KEY_INCORRECT = "That key doesn't exist. Check for typos.",
	KEY_INVALID = "That doesn't look like a key.",
	KEY_BANNED = "This key is banned.",
}
local function checkPremium(key)
	api.script_id = PREMIUM_ID
	local r = api.check_key(key)
	if r.code == "KEY_VALID" then return PREMIUM end
	return nil, MESSAGES[r.code] or ("Key check failed: " .. tostring(r.code))
end
local function check(key)
	key = tostring(key or ""):gsub("%s", "")
	if #key == 0 then return nil, "Paste your key first." end
	local ok, tier, msg = pcall(isWorkinkKey(key) and checkFree or checkPremium, key)
	if not ok then return nil, "Couldn't reach the key server. Try again." end
	if not tier then return nil, msg end
	return tier, key
end
local function launch(tier, key)
	pcall(writefile, KEY_FILE, key)
	genv.script_key = key
	if LOADER_URL ~= "" then pcall(queue_on_teleport, ("loadstring(game:HttpGet(%q))()"):format(LOADER_URL)) end
	genv.__mks_via_loader = true -- hub builds skip their own teleport re-queue when this is set; the loader owns it
	if tier == PREMIUM then
		api.script_id = PREMIUM_ID
		api.load_script()
	else
		assert(FREE_URL ~= "", "MKS Free isn't hosted yet (FREE_URL is empty).")
		loadstring(game:HttpGet(FREE_URL))()
	end
end

---------------------------------------------------------------- assets
pcall(function() if not isfolder(DIR) then makefolder(DIR) end end)
local function asset(file)
	local path = DIR .. "/" .. file
	if ASSET_URL ~= "" and not (isfile and isfile(path)) then
		pcall(function() writefile(path, game:HttpGet(ASSET_URL .. "/" .. file)) end)
	end
	local ok, id = pcall(getcustomasset, path)
	return ok and id or nil
end
local PLANET = asset("mks-planet.png") or asset("planet.png")
local LOGO = asset("MKS-logo-transparent.png")

---------------------------------------------------------------- theme (MKS Graphite, same values as the hub)
local T = {bg = Color3.fromRGB(6, 6, 9), panel = Color3.fromRGB(14, 14, 18), card = Color3.fromRGB(22, 22, 28),
	element = Color3.fromRGB(34, 34, 42), hover = Color3.fromRGB(48, 48, 58), outline = Color3.fromRGB(70, 70, 82),
	accent = Color3.fromRGB(235, 235, 242), text = Color3.fromRGB(244, 244, 248), dim = Color3.fromRGB(150, 150, 162),
	bad = Color3.fromRGB(255, 120, 120), good = Color3.fromRGB(110, 255, 150)}
local F = {Enum.Font.Gotham, Enum.Font.GothamMedium, Enum.Font.GothamBold}

local alive, conns = true, {}
local root
genv.__mks_key_kill = function()
	alive = false
	genv.__mks_key_kill = nil
	for _, c in conns do pcall(function() c:Disconnect() end) end
	if root then root:Destroy() end
end

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
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, size + 4)}, parent)
	if props then for k, v in props do l[k] = v end end
	return l
end
local function tween(o, t, props, style, dir, delay)
	local tw = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end
local function loop(o, t, props)
	TS:Create(o, TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), props):Play()
end

---------------------------------------------------------------- build (parented last)
root = make("ScreenGui", {Name = "MKS_Key", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 95,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, nil)
local dim = make("Frame", {BackgroundColor3 = T.bg, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)}, root)
-- no UIGradient on dim: its Transparency overrides the fade and the game shows straight through

-- starfield: three depth layers drift at different speeds (one looping tween per layer, no per-frame work)
local stars = {}
local rng = Random.new(614)
for layer = 1, 3 do
	local f = make("Frame", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)}, dim)
	for i = 1, 40 do
		local sz = layer == 3 and (i % 5 == 0 and 3 or 2) or 1
		local st = make("Frame", {BorderSizePixel = 0, BackgroundColor3 = T.accent, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()), Size = UDim2.fromOffset(sz, sz)}, f)
		if sz > 1 then corner(st, 2) end
		table.insert(stars, {o = st, target = rng:NextNumber(0.25, 0.8) + (3 - layer) * 0.06, twinkle = i % 8 == 0})
	end
	loop(f, 14 + layer * 6, {Position = UDim2.fromOffset(-10 * layer, 4 * layer)})
end

-- planet stage: glow, dotted orbit (same ring as the hub galaxy), planet
local stage = make("Frame", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(900, 900)}, dim)
local sScale = make("UIScale", {Scale = 1}, stage)
local glow = make("Frame", {BackgroundColor3 = T.accent, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -150), Size = UDim2.fromOffset(300, 300)}, stage)
corner(glow, 150)
local orbit = make("CanvasGroup", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -150),
	Size = UDim2.fromOffset(640, 640), Rotation = -14, GroupTransparency = 1}, stage)
for i = 0, 89 do
	local a = i / 90 * math.pi * 2
	local back = math.sin(a) < 0
	make("Frame", {BorderSizePixel = 0, BackgroundColor3 = T.accent, BackgroundTransparency = back and 0.78 or 0.45, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.cos(a) * 300, 0.5, math.sin(a) * 90), Size = UDim2.fromOffset(i % 6 == 0 and 4 or 2, i % 6 == 0 and 4 or 2)}, orbit)
end
-- a small moon rides the orbit; one Heartbeat hook moving one frame
local moon = make("Frame", {BackgroundColor3 = T.accent, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(9, 9)}, orbit)
corner(moon, 5)
local planet = make("ImageLabel", {Image = PLANET or "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ScaleType = Enum.ScaleType.Fit,
	Position = UDim2.new(1.4, 0, -0.35, 0), Size = UDim2.fromOffset(380, 380), Rotation = 38, ImageTransparency = PLANET and 0 or 1}, stage)
local pScale = make("UIScale", {Scale = 0.25}, planet)
if not PLANET then -- no image on disk and no ASSET_URL: a plain disc keeps the composition
	planet.BackgroundTransparency, planet.BackgroundColor3 = 0, T.element
	corner(planet, 190)
end

-- key card
local card = make("CanvasGroup", {BackgroundColor3 = T.panel, BackgroundTransparency = 0.06, AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1.25, 0), Size = UDim2.fromOffset(480, 268), GroupTransparency = 1}, stage)
corner(card, 20)
make("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(105, 105, 112))}, card)
local cStroke = stroke(card, T.outline, 1, 0.25)
local shimmer = make("UIGradient", {Rotation = 20, Offset = Vector2.new(-1, 0), Color = ColorSequence.new({ColorSequenceKeypoint.new(0, T.outline),
	ColorSequenceKeypoint.new(0.5, T.accent), ColorSequenceKeypoint.new(1, T.outline)})}, cStroke)
loop(shimmer, 4.5, {Offset = Vector2.new(1, 0)})
local cScale = make("UIScale", {Scale = 0.85}, card)
local CARD_Y = 70 -- card top, in stage pixels below centre

if LOGO then
	make("ImageLabel", {Image = LOGO, BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(180, 50)}, card)
else
	text(card, "MKS HUB", 26, 3, T.text, {Position = UDim2.fromOffset(0, 20)})
end
text(card, "ENTER YOUR KEY TO LAUNCH", 14, 2, T.dim, {Position = UDim2.fromOffset(0, 68)})
local closeBtn = make("TextButton", {Text = "×", Font = F[3], TextSize = 20, TextColor3 = T.dim, BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(28, 28)}, card)

local field = make("Frame", {BackgroundColor3 = T.element, Position = UDim2.fromOffset(24, 98), Size = UDim2.new(1, -48, 0, 44)}, card)
corner(field, 12)
local fStroke = stroke(field, T.outline, 1, 0.3)
local box = make("TextBox", {BackgroundTransparency = 1, Text = "", PlaceholderText = "Paste your key here", PlaceholderColor3 = T.dim,
	TextColor3 = T.text, Font = F[2], TextSize = 16, ClearTextOnFocus = false, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, field)

local function pill(label, x, primary)
	local b = make("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = primary and T.accent or T.card, AnchorPoint = Vector2.new(x, 0),
		Position = UDim2.new(x, x == 0 and 24 or -24, 0, 156), Size = UDim2.new(0.5, -30, 0, 46)}, card)
	corner(b, 22)
	stroke(b, primary and T.accent or T.outline, 1.2, primary and 0.6 or 0.2)
	make("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 178))}, b)
	local lab = text(b, label, 16, 3, primary and T.bg or T.text, {Size = UDim2.fromScale(1, 1)})
	local sc = make("UIScale", {Scale = 1}, b)
	b.MouseEnter:Connect(function() tween(sc, 0.18, {Scale = 1.05}); if not primary then tween(b, 0.18, {BackgroundColor3 = T.hover}) end end)
	b.MouseLeave:Connect(function() tween(sc, 0.18, {Scale = 1}); if not primary then tween(b, 0.18, {BackgroundColor3 = T.card}) end end)
	b.MouseButton1Down:Connect(function() tween(sc, 0.08, {Scale = 0.95}) end)
	b.MouseButton1Up:Connect(function() tween(sc, 0.12, {Scale = 1.05}) end)
	return b, lab
end
local getBtn = pill("GET KEY", 0, false)
local goBtn, goLab = pill("LAUNCH", 1, true)
local status = text(card, "Free keys last 8 hours. Premium keys unlock everything.", 13, 1, T.dim,
	{Position = UDim2.fromOffset(24, 214), Size = UDim2.new(1, -48, 0, 40)})

-- fit any screen: same idea as the hub's galaxy scale
local function fit()
	local vp = cam.ViewportSize
	sScale.Scale = math.clamp(math.min(vp.Y / 980, vp.X / 760), 0.55, 1.15)
end
fit()
table.insert(conns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit))
root.Parent = (gethui and gethui()) or game:GetService("CoreGui")

---------------------------------------------------------------- motion
local t0 = os.clock()
table.insert(conns, RS.Heartbeat:Connect(function()
	local a = (os.clock() - t0) * 0.6
	moon.Position = UDim2.new(0.5, math.cos(a) * 300, 0.5, math.sin(a) * 90)
	moon.BackgroundTransparency = math.sin(a) < 0 and 0.75 or 0.1 -- dims behind the planet
end))

local function setStatus(msg, color)
	status.Text, status.TextColor3 = msg, color or T.dim
end

local function intro()
	tween(dim, 0.6, {BackgroundTransparency = 0.12}, Enum.EasingStyle.Quad)
	for i, s in stars do
		tween(s.o, 0.8, {BackgroundTransparency = s.target}, Enum.EasingStyle.Quad, nil, (i % 30) * 0.02)
		if s.twinkle then task.delay(1, function() if alive then loop(s.o, rng:NextNumber(1.6, 3), {BackgroundTransparency = 0.95}) end end) end
	end
	-- the planet flies in from the top right, spinning down to rest
	tween(planet, 1.3, {Position = UDim2.new(0.5, 0, 0.5, -150), Rotation = -8}, Enum.EasingStyle.Quint, nil, 0.15)
	tween(pScale, 1.3, {Scale = 1}, Enum.EasingStyle.Back, nil, 0.15)
	task.delay(1.4, function()
		if not alive then return end
		loop(planet, 3.2, {Position = UDim2.new(0.5, 0, 0.5, -160)})
		loop(planet, 9, {Rotation = -2})
	end)
	tween(orbit, 1, {GroupTransparency = 0.2}, Enum.EasingStyle.Quad, nil, 0.9)
	loop(orbit, 9, {Rotation = -6})
	tween(glow, 1, {BackgroundTransparency = 0.93}, Enum.EasingStyle.Quad, nil, 0.9)
	task.delay(1.9, function() if alive then loop(glow, 2.8, {BackgroundTransparency = 0.975, Size = UDim2.fromOffset(340, 340)}) end end)
	-- the card swoops up underneath
	tween(card, 0.9, {Position = UDim2.new(0.5, 0, 0.5, CARD_Y), GroupTransparency = 0}, Enum.EasingStyle.Quint, nil, 0.75)
	tween(cScale, 0.9, {Scale = 1}, Enum.EasingStyle.Back, nil, 0.75)
end

-- shooting stars, every few seconds while the screen is up
task.spawn(function()
	task.wait(1.5)
	while alive do
		local y = rng:NextNumber(0.05, 0.45)
		local s = make("Frame", {BorderSizePixel = 0, BackgroundColor3 = T.accent, AnchorPoint = Vector2.new(1, 0.5), Rotation = 155,
			Position = UDim2.fromScale(rng:NextNumber(0.55, 1.05), y), Size = UDim2.fromOffset(0, 2)}, dim)
		make("UIGradient", {Transparency = NumberSequence.new(1, 0)}, s)
		tween(s, 0.25, {Size = UDim2.fromOffset(rng:NextInteger(90, 160), 2)}, Enum.EasingStyle.Quad)
		tween(s, 0.9, {Position = UDim2.fromScale(s.Position.X.Scale - 0.45, y + 0.22), BackgroundTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(1, function() s:Destroy() end)
		task.wait(rng:NextNumber(2.5, 5))
	end
end)

local function shake()
	local base = UDim2.new(0.5, 0, 0.5, CARD_Y)
	task.spawn(function()
		for _, dx in {-14, 12, -9, 6, -3, 0} do
			tween(card, 0.05, {Position = base + UDim2.fromOffset(dx, 0)}, Enum.EasingStyle.Sine)
			task.wait(0.05)
		end
	end)
	tween(fStroke, 0.15, {Color = T.bad, Transparency = 0})
	task.delay(1.2, function() if alive then tween(fStroke, 0.4, {Color = T.outline, Transparency = 0.3}) end end)
end

-- warp out: stars stretch into streaks from the centre, the planet rushes past, then the hub loads
local function warp(done)
	tween(cScale, 0.35, {Scale = 0.9}, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	tween(card, 0.35, {GroupTransparency = 1}, Enum.EasingStyle.Quad)
	tween(orbit, 0.4, {GroupTransparency = 1}, Enum.EasingStyle.Quad)
	tween(glow, 0.4, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad)
	tween(pScale, 0.9, {Scale = 5}, Enum.EasingStyle.Quart, Enum.EasingDirection.In, 0.15)
	tween(planet, 0.9, {ImageTransparency = 1, Rotation = 20}, Enum.EasingStyle.Quart, Enum.EasingDirection.In, 0.15)
	for _, s in stars do
		local p = s.o.AbsolutePosition - dim.AbsolutePosition - dim.AbsoluteSize / 2
		local ang = math.atan2(p.Y, p.X)
		s.o.Rotation = math.deg(ang)
		tween(s.o, 0.8, {Size = UDim2.fromOffset(rng:NextInteger(40, 120), 2), BackgroundTransparency = 1,
			Position = s.o.Position + UDim2.fromOffset(math.cos(ang) * 260, math.sin(ang) * 260)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.1)
	end
	task.delay(0.85, function()
		tween(dim, 0.35, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad)
		task.wait(0.4)
		if genv.__mks_key_kill then genv.__mks_key_kill() end
		done()
	end)
end

---------------------------------------------------------------- flow
local busy = false
local function attempt(key, fromSave)
	if busy then return end
	busy = true
	setStatus(fromSave and "Checking your saved key..." or "Checking key...", T.dim)
	goLab.Text = "..."
	task.spawn(function()
		local id, res = check(key)
		if not alive then return end
		goLab.Text = "LAUNCH"
		if id then
			setStatus(id == PREMIUM_ID and "Premium key accepted. Launching MKS Premium..." or "Key accepted. Launching MKS...", T.good)
			task.wait(0.5)
			warp(function() launch(id, res) end)
			return
		end
		busy = false
		setStatus(fromSave and ("Saved key: " .. res) or res, T.bad)
		if not fromSave then shake() end
	end)
end

getBtn.MouseButton1Click:Connect(function()
	pcall(setclipboard, GET_KEY_URL)
	setStatus("Link copied. Paste it in your browser, finish the 2 steps, then paste your key here.", T.text)
end)
goBtn.MouseButton1Click:Connect(function() attempt(box.Text) end)
box.FocusLost:Connect(function(enter) if enter then attempt(box.Text) end end)
box.Focused:Connect(function() tween(fStroke, 0.2, {Color = T.accent, Transparency = 0}) end)
box.FocusLost:Connect(function() tween(fStroke, 0.3, {Color = T.outline, Transparency = 0.3}) end)
closeBtn.MouseButton1Click:Connect(function()
	alive = false
	tween(card, 0.3, {GroupTransparency = 1, Position = UDim2.new(0.5, 0, 1.25, 0)}, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	tween(dim, 0.45, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad)
	tween(planet, 0.45, {ImageTransparency = 1}, Enum.EasingStyle.Quad)
	task.delay(0.5, function() if genv.__mks_key_kill then genv.__mks_key_kill() end end)
end)

intro()
local saved = (genv.script_key and tostring(genv.script_key)) or (isfile and isfile(KEY_FILE) and readfile(KEY_FILE))
if saved and #saved > 0 then
	task.delay(1.6, function() if alive then attempt(saved, true) end end)
end
