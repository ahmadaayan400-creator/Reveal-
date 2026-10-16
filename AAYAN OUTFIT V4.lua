--[[
	AAYAN OUTFIT REVEALER
	MADE BY AAYAN
	PREMIUM AVATAR INSPECTOR

	TYPE:      LocalScript (single file, no backend needed)
	PLACEMENT: StarterPlayer > StarterPlayerScripts > LocalScript  (paste this whole file)
	           It also runs from any client-side script context that can create GUIs.

	REQUIRED SERVICES (all built in, no configuration):
	Players, TweenService, UserInputService, RunService, MarketplaceService,
	GuiService, HttpService (JSON encoding only, HttpEnabled is NOT required).

	HOW DATA IS RETRIEVED (real APIs only):
	- Players:GetCharacterAppearanceInfoAsync(userId)  -> assets, body colors, scales, avatar type
	- Players:GetHumanoidDescriptionFromUserId(userId) + Players:CreateHumanoidModelFromDescription  -> 3D preview
	- MarketplaceService:GetProductInfo(assetId)       -> verified name / Robux price / on-sale state

	LIMITATIONS (honest list):
	1. LocalScripts cannot call roblox.com web endpoints through HttpService. Because of that,
	   BUNDLE information and equipped-emote lists are shown as "Unavailable". Getting them would
	   need an external HTTPS proxy that you host yourself, called from a server Script.
	2. Robux price comes only from MarketplaceService:GetProductInfo. Off-sale, limited, deleted or
	   user-moderated items show "Price unavailable" (never guessed). Prices are fetched when you
	   expand a card or press FETCH PRICES (rate-limit friendly, one request at a time).
	3. Catalog links are built from the real asset ID. Some assets (body parts, defaults, off-sale
	   items) may not have a public catalog page.
	4. Preview: the avatar is built from the player's HumanoidDescription (their saved appearance).
	   If that fails, the script clones their live character instead. A live clone can differ from
	   the saved avatar (game-specific costumes, tools, hidden accessories, non-archivable parts).
	   R6 and R15 are both supported through the rig type; layered clothing is shown on R15.
	5. Clipboard: setclipboard/toclipboard exist only in some environments. If missing, the text
	   is shown in a selectable box so you can copy it by hand.
	6. Export: a plain LocalScript cannot save files. If writefile exists in your environment the
	   JSON is saved to a file, otherwise the JSON is shown in the text box.
	7. OPEN CATALOG / OPEN PAGE use GuiService:OpenBrowserWindow when allowed; otherwise the link
	   is copied (or shown) instead.
]]

----------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	return
end

local GUI_NAME = "AayanOutfitRevealer"
local BRAND = "AAYAN OUTFIT REVEALER"

----------------------------------------------------------------------
-- PREVENT DUPLICATES / CLEANUP
----------------------------------------------------------------------
if _G.AayanRevealerCleanup then
	pcall(_G.AayanRevealerCleanup)
end

local connections = {}
local function track(conn)
	table.insert(connections, conn)
	return conn
end

local function getGlobal(name)
	local ok, v = pcall(function()
		return getfenv()[name]
	end)
	if ok then
		return v
	end
	return nil
end

local function resolveParent()
	local gh = getGlobal("gethui")
	if typeof(gh) == "function" then
		local ok, h = pcall(gh)
		if ok and typeof(h) == "Instance" then
			return h
		end
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local guiParent = resolveParent()
for _, parent in ipairs({ guiParent, LocalPlayer:FindFirstChild("PlayerGui") }) do
	if parent then
		local old = parent:FindFirstChild(GUI_NAME)
		if old then
			old:Destroy()
		end
	end
end

----------------------------------------------------------------------
-- THEME + UI HELPERS
----------------------------------------------------------------------
local C = {
	bg = Color3.fromRGB(10, 10, 14),
	bg2 = Color3.fromRGB(18, 18, 24),
	panel = Color3.fromRGB(24, 24, 33),
	panel2 = Color3.fromRGB(32, 32, 45),
	text = Color3.fromRGB(240, 240, 255),
	sub = Color3.fromRGB(150, 150, 178),
	purple = Color3.fromRGB(176, 72, 255),
	purpleDark = Color3.fromRGB(78, 34, 130),
	cyan = Color3.fromRGB(0, 229, 255),
	magenta = Color3.fromRGB(255, 60, 200),
	green = Color3.fromRGB(70, 235, 140),
	red = Color3.fromRGB(255, 80, 100),
	yellow = Color3.fromRGB(255, 205, 80),
}

local function new(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, ch in ipairs(children or {}) do
		ch.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(inst, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = inst })
end

local function stroke(inst, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or C.purple,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function label(parent, text, size, color, font, props)
	local l = new("TextLabel", {
		Parent = parent,
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size or 13,
		TextColor3 = color or C.text,
		Font = font or Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		BorderSizePixel = 0,
	})
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function esc(s)
	s = tostring(s)
	s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	return s
end

local function hex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- Neon gradient strokes (animated)
local mainGradients = {}
local toggleGradients = {}

local function neonStroke(inst, thickness, list)
	local s = stroke(inst, Color3.new(1, 1, 1), thickness or 2, 0)
	local g = new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.purple),
			ColorSequenceKeypoint.new(0.35, C.cyan),
			ColorSequenceKeypoint.new(0.7, C.magenta),
			ColorSequenceKeypoint.new(1, C.purple),
		}),
		Parent = s,
	})
	table.insert(list, g)
	return s
end

local function makeButton(parent, text, color, size)
	local b = new("TextButton", {
		Parent = parent,
		Text = text,
		Size = size or UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = color or C.panel2,
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	})
	corner(b, 8)
	local st = stroke(b, C.purple, 1, 0.55)
	local base = b.BackgroundColor3
	local hover = base:Lerp(C.purple, 0.28)
	local press = base:Lerp(Color3.new(0, 0, 0), 0.25)
	b.MouseEnter:Connect(function()
		tween(b, 0.15, { BackgroundColor3 = hover })
		tween(st, 0.15, { Transparency = 0, Color = C.cyan })
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.15, { BackgroundColor3 = base })
		tween(st, 0.15, { Transparency = 0.55, Color = C.purple })
	end)
	b.MouseButton1Down:Connect(function()
		tween(b, 0.08, { BackgroundColor3 = press })
	end)
	b.MouseButton1Up:Connect(function()
		tween(b, 0.12, { BackgroundColor3 = hover })
	end)
	return b
end

local function makeScroll(parent, props)
	local s = new("ScrollingFrame", {
		Parent = parent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.purple,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	})
	for k, v in pairs(props or {}) do
		s[k] = v
	end
	return s
end

local function makeLoadBar(parent, position, size)
	local trackFrame = new("Frame", {
		Parent = parent,
		Position = position,
		Size = size,
		BackgroundColor3 = C.panel2,
		BorderSizePixel = 0,
		Visible = false,
		ClipsDescendants = true,
	})
	corner(trackFrame, 2)
	local bar = new("Frame", {
		Parent = trackFrame,
		Size = UDim2.new(0.35, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	})
	corner(bar, 2)
	new("UIGradient", {
		Color = ColorSequence.new(C.purple, C.cyan),
		Parent = bar,
	})
	local tw
	local obj = {}
	function obj.start()
		trackFrame.Visible = true
		bar.Position = UDim2.new(-0.35, 0, 0, 0)
		if tw then
			tw:Cancel()
		end
		tw = TweenService:Create(
			bar,
			TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.new(1, 0, 0, 0) }
		)
		tw:Play()
	end
	function obj.stop()
		if tw then
			tw:Cancel()
			tw = nil
		end
		trackFrame.Visible = false
	end
	return obj
end

----------------------------------------------------------------------
-- ROOT GUI
----------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = GUI_NAME,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 1000,
})

local function clampToScreen(frame, fullyInside)
	local screen = gui.AbsoluteSize
	if screen.X <= 0 or screen.Y <= 0 then
		return
	end
	local size = frame.AbsoluteSize
	local topLeft = frame.AbsolutePosition
	local minX, maxX, minY, maxY
	if fullyInside then
		minX, maxX = 0, screen.X - size.X
		minY, maxY = 0, screen.Y - size.Y
	else
		local keep = 90
		minX, maxX = keep - size.X, screen.X - keep
		minY, maxY = 0, screen.Y - 50
	end
	maxX = math.max(maxX, minX)
	maxY = math.max(maxY, minY)
	local nx = math.clamp(topLeft.X, minX, maxX)
	local ny = math.clamp(topLeft.Y, minY, maxY)
	if nx ~= topLeft.X or ny ~= topLeft.Y then
		frame.Position = frame.Position + UDim2.fromOffset(nx - topLeft.X, ny - topLeft.Y)
	end
end

local function makeDraggable(handle, target, fullyInside, onRelease)
	local dragging, dragInput, startPos, startFramePos, moved = false, nil, nil, nil, false
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			startPos = input.Position
			startFramePos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if onRelease then
						onRelease(moved)
					end
				end
			end)
		end
	end)
	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput and startPos then
			local delta = input.Position - startPos
			if delta.Magnitude > 5 then
				moved = true
			end
			if moved then
				target.Position = UDim2.new(
					startFramePos.X.Scale,
					startFramePos.X.Offset + delta.X,
					startFramePos.Y.Scale,
					startFramePos.Y.Offset + delta.Y
				)
				clampToScreen(target, fullyInside)
			end
		end
	end))
end

----------------------------------------------------------------------
-- MAIN WINDOW
----------------------------------------------------------------------
local main = new("Frame", {
	Name = "Main",
	Parent = gui,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0.8, 0, 0.72, 0),
	BackgroundColor3 = C.bg,
	BorderSizePixel = 0,
	Visible = false,
	Active = true,
})
corner(main, 16)
new("UISizeConstraint", { MaxSize = Vector2.new(500, 400), MinSize = Vector2.new(250, 240), Parent = main })
local mainScale = new("UIScale", { Scale = 1, Parent = main })
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(20, 20, 28), Color3.fromRGB(8, 8, 11)),
	Rotation = 90,
	Parent = main,
})
neonStroke(main, 2.5, mainGradients)

-- Header
local header = new("Frame", {
	Name = "Header",
	Parent = main,
	Size = UDim2.new(1, 0, 0, 58),
	BackgroundTransparency = 1,
	Active = true,
})
label(header, BRAND, 18, C.text, Enum.Font.GothamBlack, {
	Position = UDim2.new(0, 16, 0, 7),
	Size = UDim2.new(1, -66, 0, 24),
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextWrapped = false,
})
label(header, "PREMIUM AVATAR INSPECTOR • MADE BY AAYAN", 10, C.cyan, Enum.Font.GothamBold, {
	Position = UDim2.new(0, 16, 0, 33),
	Size = UDim2.new(1, -66, 0, 16),
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextWrapped = false,
})
new("Frame", {
	Parent = header,
	Position = UDim2.new(0, 12, 1, -1),
	Size = UDim2.new(1, -24, 0, 1),
	BackgroundColor3 = C.purple,
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
})
local closeBtn = makeButton(header, "X", C.panel2, UDim2.fromOffset(34, 34))
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -12, 0, 10)
closeBtn.TextSize = 14

-- Tab bar
local tabBar = new("Frame", {
	Parent = main,
	Position = UDim2.new(0, 10, 0, 64),
	Size = UDim2.new(1, -20, 0, 32),
	BackgroundTransparency = 1,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = tabBar,
})

-- Pages
local pageHolder = new("Frame", {
	Parent = main,
	Position = UDim2.new(0, 10, 0, 102),
	Size = UDim2.new(1, -20, 1, -110), -- V4: footer removed, pages use the freed space
	BackgroundTransparency = 1,
	ClipsDescendants = true,
})

local pages = {}
local tabButtons = {}
local function setTab(name)
	for n, p in pairs(pages) do
		p.Visible = (n == name)
	end
	for n, b in pairs(tabButtons) do
		local active = (n == name)
		tween(b, 0.15, {
			BackgroundColor3 = active and C.purpleDark or C.panel,
			TextColor3 = active and C.text or C.sub,
		})
	end
end

for i, name in ipairs({ "PLAYERS", "PREVIEW", "RESULTS" }) do
	local b = makeButton(tabBar, name, C.panel, UDim2.new(1 / 3, -4, 1, 0))
	b.LayoutOrder = i
	b.TextColor3 = C.sub
	tabButtons[name] = b
	pages[name] = new("Frame", {
		Name = name,
		Parent = pageHolder,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
	})
	b.Activated:Connect(function()
		setTab(name)
	end)
end

-- V4: no footer. Notifications float over the bottom of the window as a small
-- pill and disappear on their own (tap the pill to dismiss it early).
local toastFrame = new("TextButton", {
	Name = "Toast",
	Parent = main,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.new(1, -28, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = C.bg2,
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 100,
})
corner(toastFrame, 10)
local toastStroke = stroke(toastFrame, C.cyan, 1, 1)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6),
	Parent = toastFrame,
})
local toast = label(toastFrame, "", 11, C.text, Enum.Font.GothamMedium, {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	TextTransparency = 1,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 101,
})

local toastToken = 0
local function notify(msg, kind)
	toastToken += 1
	local my = toastToken
	local col = C.cyan
	if kind == "success" then
		col = C.green
	elseif kind == "error" then
		col = C.red
	elseif kind == "warn" then
		col = C.yellow
	end
	toast.Text = msg
	toast.TextColor3 = col
	toastStroke.Color = col
	toastFrame.Visible = true
	toastFrame.BackgroundTransparency = 1
	toast.TextTransparency = 1
	toastStroke.Transparency = 1
	tween(toastFrame, 0.2, { BackgroundTransparency = 0.04 })
	tween(toast, 0.2, { TextTransparency = 0 })
	tween(toastStroke, 0.2, { Transparency = 0.25 })
	task.delay(3.5, function()
		if my == toastToken and toastFrame.Parent then
			tween(toastFrame, 0.3, { BackgroundTransparency = 1 })
			tween(toast, 0.3, { TextTransparency = 1 })
			tween(toastStroke, 0.3, { Transparency = 1 })
			task.delay(0.35, function()
				if my == toastToken and toastFrame.Parent then
					toastFrame.Visible = false
				end
			end)
		end
	end)
end
toastFrame.Activated:Connect(function()
	toastToken += 1
	toastFrame.Visible = false
end)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local selectedPlayer = nil
local results = nil
local busy = false
local entries = {}
local appearanceCache = {}
local productCache = {}

----------------------------------------------------------------------
-- CLIPBOARD / BROWSER / FILE HELPERS
----------------------------------------------------------------------
local showOutput -- forward declaration

local function copyText(text, what)
	local sc = getGlobal("setclipboard") or getGlobal("toclipboard")
	if typeof(sc) == "function" then
		local ok = pcall(sc, text)
		if ok then
			notify("Copied " .. what .. " to clipboard.", "success")
			return true
		end
	end
	showOutput(text, what)
	notify("Clipboard unavailable here. Text shown below, select and copy it manually.", "warn")
	return false
end

local function openUrl(url)
	local ok = pcall(function()
		GuiService:OpenBrowserWindow(url)
	end)
	if ok then
		notify("Opening browser window...", "info")
	else
		notify("Browser open blocked. Copying link instead.", "warn")
		copyText(url, "link")
	end
end

local function catalogLink(id)
	if id then
		return "https://www.roblox.com/catalog/" .. tostring(id)
	end
	return nil
end

----------------------------------------------------------------------
-- PLAYERS PAGE
----------------------------------------------------------------------
local playersPage = pages["PLAYERS"]

local searchBox = new("TextBox", {
	Parent = playersPage,
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundColor3 = C.panel,
	TextColor3 = C.text,
	PlaceholderText = "🔍 Search username, display name or UserId",
	PlaceholderColor3 = C.sub,
	Text = "",
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamMedium,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	BorderSizePixel = 0,
})
corner(searchBox, 10)
stroke(searchBox, C.cyan, 1, 0.5)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = searchBox })

local playerList = makeScroll(playersPage, {
	Position = UDim2.new(0, 0, 0, 44),
	Size = UDim2.new(1, 0, 1, -44),
})
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.Name, Parent = playerList })
new("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = playerList })

local emptyLabel = label(playersPage, "No players found.", 13, C.sub, Enum.Font.GothamMedium, {
	Position = UDim2.new(0, 0, 0, 60),
	Size = UDim2.new(1, 0, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
})

local function applyFilter()
	local q = string.lower(searchBox.Text)
	local visible, total = 0, 0
	for plr, e in pairs(entries) do
		total += 1
		local show = q == ""
			or string.find(string.lower(plr.DisplayName), q, 1, true) ~= nil
			or string.find(string.lower(plr.Name), q, 1, true) ~= nil
			or string.find(tostring(plr.UserId), q, 1, true) ~= nil
		e.frame.Visible = show
		if show then
			visible += 1
		end
	end
	emptyLabel.Visible = visible == 0
	if total == 0 then
		emptyLabel.Text = "No players in this server."
	else
		emptyLabel.Text = "No players match your search."
	end
end
searchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)

local selectPlayer -- forward declaration

local function addPlayer(plr)
	if entries[plr] then
		return
	end
	local frame = new("TextButton", {
		Name = string.lower(plr.DisplayName) .. "_" .. plr.UserId,
		Parent = playerList,
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = C.panel,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	})
	corner(frame, 10)
	local st = stroke(frame, C.purple, 1, 0.7)

	local thumb = new("ImageLabel", {
		Parent = frame,
		Position = UDim2.new(0, 8, 0.5, -22),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.panel2,
		BorderSizePixel = 0,
		Image = "",
	})
	corner(thumb, 22)
	stroke(thumb, C.cyan, 1, 0.5)

	local suffix = (plr == LocalPlayer) and "  (You)" or ""
	label(frame, plr.DisplayName .. suffix, 14, C.text, Enum.Font.GothamBold, {
		Position = UDim2.new(0, 60, 0, 6),
		Size = UDim2.new(1, -68, 0, 17),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	label(frame, "@" .. plr.Name, 11, C.cyan, Enum.Font.GothamMedium, {
		Position = UDim2.new(0, 60, 0, 23),
		Size = UDim2.new(1, -68, 0, 14),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	label(frame, "ID: " .. plr.UserId, 10, C.sub, Enum.Font.Gotham, {
		Position = UDim2.new(0, 60, 0, 38),
		Size = UDim2.new(1, -68, 0, 14),
		TextWrapped = false,
	})

	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, plr.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok and img and thumb.Parent then
			thumb.Image = img
		end
	end)

	frame.MouseEnter:Connect(function()
		if selectedPlayer ~= plr then
			tween(frame, 0.12, { BackgroundColor3 = C.panel2 })
		end
	end)
	frame.MouseLeave:Connect(function()
		if selectedPlayer ~= plr then
			tween(frame, 0.12, { BackgroundColor3 = C.panel })
		end
	end)
	frame.Activated:Connect(function()
		selectPlayer(plr)
	end)

	entries[plr] = { frame = frame, stroke = st }
	applyFilter()
end

local function removePlayer(plr)
	local e = entries[plr]
	if e then
		e.frame:Destroy()
		entries[plr] = nil
	end
	applyFilter()
end

local function refreshHighlights()
	for plr, e in pairs(entries) do
		local sel = (plr == selectedPlayer)
		tween(e.frame, 0.15, { BackgroundColor3 = sel and C.purpleDark or C.panel })
		tween(e.stroke, 0.15, {
			Color = sel and C.cyan or C.purple,
			Transparency = sel and 0 or 0.7,
			Thickness = sel and 2 or 1,
		})
	end
end

----------------------------------------------------------------------
-- PREVIEW PAGE
----------------------------------------------------------------------
local previewPage = pages["PREVIEW"]

local viewport = new("ViewportFrame", {
	Parent = previewPage,
	BackgroundColor3 = Color3.fromRGB(14, 14, 20),
	BorderSizePixel = 0,
	Ambient = Color3.fromRGB(175, 175, 195),
	LightColor = Color3.fromRGB(255, 255, 255),
	LightDirection = Vector3.new(-0.6, -1, -0.8),
	Size = UDim2.new(1, 0, 1, -104),
})
corner(viewport, 12)
stroke(viewport, C.cyan, 1, 0.45)

local previewStatus = label(viewport, "Select a player to preview their avatar.", 13, C.sub, Enum.Font.GothamMedium, {
	Size = UDim2.new(1, -20, 1, 0),
	Position = UDim2.new(0, 10, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 5,
})
local previewBar = makeLoadBar(viewport, UDim2.new(0.2, 0, 1, -10), UDim2.new(0.6, 0, 0, 3))

local controls = new("Frame", {
	Parent = previewPage,
	Position = UDim2.new(0, 0, 1, -100),
	Size = UDim2.new(1, 0, 0, 100),
	BackgroundTransparency = 1,
})
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = controls })

local selectedLabel = label(controls, "No player selected", 12, C.sub, Enum.Font.GothamBold, {
	Size = UDim2.new(1, 0, 0, 18),
	LayoutOrder = 1,
	TextWrapped = false,
	TextTruncate = Enum.TextTruncate.AtEnd,
})

local zoomRow = new("Frame", {
	Parent = controls,
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundTransparency = 1,
	LayoutOrder = 2,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = zoomRow,
})
local zoomOut = makeButton(zoomRow, "−", C.panel2, UDim2.new(1 / 3, -4, 1, 0))
local zoomIn = makeButton(zoomRow, "+", C.panel2, UDim2.new(1 / 3, -4, 1, 0))
local zoomReset = makeButton(zoomRow, "RESET", C.panel2, UDim2.new(1 / 3, -4, 1, 0))
zoomOut.TextSize, zoomIn.TextSize = 18, 18
zoomOut.LayoutOrder, zoomIn.LayoutOrder, zoomReset.LayoutOrder = 1, 2, 3

local getBtn = makeButton(controls, "[ GET AVATAR ]", C.purple, UDim2.new(1, 0, 0, 40))
getBtn.LayoutOrder = 3
getBtn.TextScaled = true
new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 8, Parent = getBtn })
getBtn.Font = Enum.Font.GothamBlack
getBtn.BackgroundColor3 = Color3.new(1, 1, 1)
new("UIGradient", { Color = ColorSequence.new(C.purple, C.cyan), Parent = getBtn })

-- FIX: AbsoluteSize includes the open/close UIScale animation, which used to flip the
-- layout mid-tween. We divide the scale out and only re-apply when the mode/size changes.
local lastPreviewMode, lastPreviewH = nil, nil
local function layoutPreview()
	local sc = math.max(mainScale.Scale, 0.01)
	local w = previewPage.AbsoluteSize.X / sc
	local h = previewPage.AbsoluteSize.Y / sc
	if w <= 0 or h <= 0 then
		return
	end
	local side = (w >= 380 and w >= h * 1.15)
	local hKey = math.floor(h / 4)
	if lastPreviewMode == side and lastPreviewH == hKey then
		return
	end
	lastPreviewMode, lastPreviewH = side, hKey
	if side then
		viewport.Size = UDim2.new(0.58, -4, 1, 0)
		controls.Position = UDim2.new(0.58, 4, 0, 0)
		controls.Size = UDim2.new(0.42, -4, 1, 0)
	else
		local vh = math.max(h - 108, 110)
		viewport.Size = UDim2.new(1, 0, 0, vh)
		controls.Position = UDim2.new(0, 0, 0, vh + 4)
		controls.Size = UDim2.new(1, 0, 0, 104)
	end
end
previewPage:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPreview)

-- Camera + orbit
local camera = new("Camera", { FieldOfView = 40, Parent = viewport })
viewport.CurrentCamera = camera
local previewModel = nil
local loadPreview -- forward declaration (defined below)
local previewCenter = Vector3.new(0, 2.5, 0)
local defaultDist, dist = 10, 10
local yaw, pitch = 0, 0.12

local function updateCamera()
	local offset = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)) * dist
	camera.CFrame = CFrame.lookAt(previewCenter + offset, previewCenter)
end
updateCamera()

local function zoom(factor)
	dist = math.clamp(dist * factor, defaultDist * 0.35, defaultDist * 2.2)
	updateCamera()
end
zoomIn.Activated:Connect(function()
	zoom(0.85)
end)
zoomOut.Activated:Connect(function()
	zoom(1.18)
end)
zoomReset.Activated:Connect(function()
	-- If no model is showing (error or never loaded), RESET retries the preview.
	if not previewModel and selectedPlayer and selectedPlayer.Parent then
		loadPreview(selectedPlayer)
		return
	end
	yaw, pitch, dist = 0, 0.12, defaultDist
	updateCamera()
end)

local rotating, lastRotPos = false, nil
track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		rotating = false
	end
end))
viewport.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		rotating = true
		lastRotPos = input.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				rotating = false
			end
		end)
	end
end)
viewport.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		zoom(input.Position.Z > 0 and 0.9 or 1.1)
	end
end)
track(UserInputService.InputChanged:Connect(function(input)
	if rotating and lastRotPos and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - lastRotPos
		lastRotPos = input.Position
		yaw -= d.X * 0.012
		pitch = math.clamp(pitch + d.Y * 0.006, -0.6, 0.9)
		updateCamera()
	end
end))

local function setPreviewStatus(text, isError)
	previewStatus.Visible = text ~= nil
	if text then
		previewStatus.Text = text
		previewStatus.TextColor3 = isError and C.red or C.sub
	end
end

local function clearPreviewModel()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
end

local function fetchAppearance(userId, force)
	local cached = appearanceCache[userId]
	if cached and not force and os.clock() - cached.t < 60 then
		return cached.info
	end
	local lastErr = "unknown error"
	for attempt = 1, 3 do
		local ok, res = pcall(Players.GetCharacterAppearanceInfoAsync, Players, userId)
		if ok and type(res) == "table" then
			appearanceCache[userId] = { info = res, t = os.clock() }
			return res
		end
		lastErr = tostring(res)
		if attempt < 3 then
			task.wait(1.2 * attempt)
		end
	end
	return nil, lastErr
end

local function buildAvatarModel(plr)
	local rig = nil
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		rig = hum.RigType
	end
	if not rig then
		local info = fetchAppearance(plr.UserId)
		if info and info.playerAvatarType == "R6" then
			rig = Enum.HumanoidRigType.R6
		else
			rig = Enum.HumanoidRigType.R15
		end
	end

	local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, plr.UserId)
	if ok and desc then
		local ok2, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, rig)
		if ok2 and model then
			return model, nil
		end
	end

	-- Fallback: clone live character
	if char then
		local prev = char.Archivable
		char.Archivable = true
		local okC, clone = pcall(function()
			return char:Clone()
		end)
		char.Archivable = prev
		if okC and clone then
			return clone, nil
		end
	end
	return nil, "avatar could not be built (no description and no live character)"
end

local previewToken = 0
loadPreview = function(plr)
	previewToken += 1
	local my = previewToken
	clearPreviewModel()
	setPreviewStatus("Loading avatar...", false)
	previewBar.start()
	task.spawn(function()
		local model, err = buildAvatarModel(plr)
		if my ~= previewToken or not gui.Parent then
			if model then
				model:Destroy()
			end
			return
		end
		previewBar.stop()
		if not model then
			setPreviewStatus("Preview unavailable: " .. tostring(err), true)
			notify("Preview failed for " .. plr.Name .. ".", "error")
			return
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
			elseif d:IsA("Humanoid") then
				d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end
		model.Parent = viewport
		pcall(function()
			model:PivotTo(CFrame.new(0, 0, 0))
		end)
		local okB, cf, size = pcall(function()
			return model:GetBoundingBox()
		end)
		if okB and cf then
			previewCenter = cf.Position
			local radius = math.max(size.Magnitude / 2, 2)
			defaultDist = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
		else
			previewCenter = Vector3.new(0, 2.5, 0)
			defaultDist = 10
		end
		dist = defaultDist
		yaw, pitch = 0, 0.12
		updateCamera()
		previewModel = model
		setPreviewStatus(nil)
	end)
end

----------------------------------------------------------------------
-- RESULTS PAGE (layout)
----------------------------------------------------------------------
local resultsPage = pages["RESULTS"]

local actionBar = new("ScrollingFrame", {
	Parent = resultsPage,
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = C.purple,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = actionBar,
})
local function actionButton(text, order, w)
	local b = makeButton(actionBar, text, C.panel2, UDim2.new(0, w, 0, 32))
	b.LayoutOrder = order
	return b
end
local btnCopyIds = actionButton("[ COPY ALL IDS ]", 1, 128)
local btnCopyDetails = actionButton("[ COPY OUTFIT DETAILS ]", 2, 170)
local btnExport = actionButton("[ EXPORT AVATAR DATA ]", 3, 168)
local btnPrices = actionButton("[ FETCH PRICES ]", 4, 124)
local btnCatalog = actionButton("[ OPEN CATALOG ]", 5, 124)
local btnClear = actionButton("[ CLEAR RESULTS ]", 6, 128)

local statusLabel = label(resultsPage, "Select a player and press GET AVATAR.", 11, C.sub, Enum.Font.GothamMedium, {
	Position = UDim2.new(0, 0, 0, 42),
	Size = UDim2.new(1, 0, 0, 18),
	TextWrapped = false,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
local resultsBar = makeLoadBar(resultsPage, UDim2.new(0, 0, 0, 60), UDim2.new(1, 0, 0, 3))

local resultsScroll = makeScroll(resultsPage, {
	Position = UDim2.new(0, 0, 0, 66),
	Size = UDim2.new(1, 0, 1, -66),
})
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = resultsScroll })
new("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), Parent = resultsScroll })

-- Output panel (manual copy fallback)
local outputPanel = new("Frame", {
	Parent = resultsPage,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 130),
	BackgroundColor3 = C.bg2,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 10,
})
corner(outputPanel, 10)
stroke(outputPanel, C.cyan, 1, 0.3)
local outputTitle = label(outputPanel, "OUTPUT", 11, C.cyan, Enum.Font.GothamBold, {
	Position = UDim2.new(0, 10, 0, 6),
	Size = UDim2.new(1, -80, 0, 16),
	TextWrapped = false,
	ZIndex = 11,
})
local outputHide = makeButton(outputPanel, "HIDE", C.panel2, UDim2.fromOffset(52, 22))
outputHide.AnchorPoint = Vector2.new(1, 0)
outputHide.Position = UDim2.new(1, -8, 0, 4)
outputHide.TextSize = 10
outputHide.ZIndex = 11
local outputScroll = makeScroll(outputPanel, {
	Position = UDim2.new(0, 8, 0, 28),
	Size = UDim2.new(1, -16, 1, -34),
	ZIndex = 11,
})
local outputBox = new("TextBox", {
	Parent = outputScroll,
	Size = UDim2.new(1, -6, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	TextColor3 = C.text,
	Font = Enum.Font.Code,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	MultiLine = true,
	ClearTextOnFocus = false,
	TextEditable = true,
	Text = "",
	ZIndex = 12,
})

local function layoutResults()
	if outputPanel.Visible then
		resultsScroll.Size = UDim2.new(1, 0, 1, -66 - 136)
	else
		resultsScroll.Size = UDim2.new(1, 0, 1, -66)
	end
end

showOutput = function(text, title)
	outputBox.Text = text
	outputTitle.Text = "OUTPUT • " .. string.upper(tostring(title or "TEXT")) .. " (select and copy)"
	outputPanel.Visible = true
	layoutResults()
	setTab("RESULTS")
end
outputHide.Activated:Connect(function()
	outputPanel.Visible = false
	layoutResults()
end)

local function setStatus(text, color)
	statusLabel.Text = text
	statusLabel.TextColor3 = color or C.sub
end

----------------------------------------------------------------------
-- PRODUCT INFO (verified prices) - serialized + cached
----------------------------------------------------------------------
local productLock = false
local lastProductCall = 0

local function getProductInfo(id)
	local c = productCache[id]
	if c then
		return true, c
	end
	while productLock do
		task.wait(0.05)
		if not gui.Parent then
			return false, "gui closed"
		end
	end
	c = productCache[id]
	if c then
		return true, c
	end
	productLock = true
	local gap = 0.18 - (os.clock() - lastProductCall)
	if gap > 0 then
		task.wait(gap)
	end
	local ok, data = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.Asset)
	lastProductCall = os.clock()
	productLock = false
	if ok and type(data) == "table" then
		productCache[id] = data
		return true, data
	end
	return false, tostring(data)
end

local function priceTextFrom(d)
	if d.IsLimited or d.IsLimitedUnique then
		return "Limited item • resale price unavailable"
	end
	if d.IsForSale then
		if type(d.PriceInRobux) == "number" then
			if d.PriceInRobux == 0 then
				return "Free (R$ 0)"
			end
			return "R$ " .. tostring(d.PriceInRobux)
		end
		return "Price unavailable"
	end
	return "Not on sale • price unavailable"
end

-- Fills item.priceText / item.creator, updates labels if they still exist
local function loadItemProduct(item, priceLabel, nameLabel, creatorLabel)
	if item.priceText then
		return
	end
	if not item.id then
		item.priceText = "Price unavailable"
		return
	end
	if priceLabel and priceLabel.Parent then
		priceLabel.Text = "Price: <font color=\"" .. hex(C.yellow) .. "\">checking...</font>"
	end
	local ok, data = getProductInfo(item.id)
	if ok then
		item.priceText = priceTextFrom(data)
		if (item.name == nil or item.name == "Unavailable") and data.Name then
			item.name = tostring(data.Name)
		end
		if data.Creator and data.Creator.Name then
			item.creator = tostring(data.Creator.Name)
		end
	else
		item.priceText = nil
		item.priceError = data
	end
	if priceLabel and priceLabel.Parent then
		if ok then
			priceLabel.Text = "Price: <font color=\"" .. hex(C.green) .. "\">" .. esc(item.priceText) .. "</font>"
		else
			priceLabel.Text = "Price: <font color=\"" .. hex(C.red) .. "\">Price unavailable (lookup failed or rate limited, expand again to retry)</font>"
		end
	end
	if nameLabel and nameLabel.Parent and item.name then
		nameLabel.Text = item.name
	end
	if creatorLabel and creatorLabel.Parent and item.creator then
		creatorLabel.Text = "Creator: " .. item.creator
	end
end

----------------------------------------------------------------------
-- AVATAR DATA PROCESSING
----------------------------------------------------------------------
local function norm(s)
	return (string.lower(tostring(s or "")):gsub("[^%w]", ""))
end

local CLOTHING_LABELS = {
	shirt = "Classic Shirt",
	pants = "Classic Pants",
	tshirt = "T-Shirt Graphic",
	shirtaccessory = "Layered Shirt",
	pantsaccessory = "Layered Pants",
	jacketaccessory = "Layered Jacket",
	sweateraccessory = "Layered Sweater",
	shortsaccessory = "Layered Shorts",
	leftshoeaccessory = "Layered Left Shoe",
	rightshoeaccessory = "Layered Right Shoe",
	dressskirtaccessory = "Layered Dress/Skirt",
}
local CLOTHING_REPORT = { shirt = "CLASSIC SHIRT ID", pants = "CLASSIC PANTS ID", tshirt = "T-SHIRT ID" }

local ACCESSORY_LABELS = {
	hat = "Hat",
	hairaccessory = "Hair",
	faceaccessory = "Face Accessory",
	neckaccessory = "Neck",
	shoulderaccessory = "Shoulder",
	frontaccessory = "Front",
	backaccessory = "Back",
	waistaccessory = "Waist",
	eyebrowaccessory = "Eyebrow",
	eyelashaccessory = "Eyelash",
}
local ACCESSORY_ORDER = { "Hat", "Hair", "Face Accessory", "Eyebrow", "Eyelash", "Neck", "Shoulder", "Front", "Back", "Waist" }

local BODY_LABELS = {
	head = "Head",
	torso = "Torso",
	leftarm = "Left Arm",
	rightarm = "Right Arm",
	leftleg = "Left Leg",
	rightleg = "Right Leg",
	face = "Face",
	dynamichead = "Dynamic Head",
}

local function buildResults(plr, info)
	local r = {
		userId = plr.UserId,
		username = plr.Name,
		displayName = plr.DisplayName,
		avatarType = info.playerAvatarType,
		info = info,
		clothing = {},
		accessories = {},
		bodyParts = {},
		animations = {},
		other = {},
	}
	for _, a in ipairs(info.assets or {}) do
		local typeName = (a.assetType and a.assetType.name) or "Unknown"
		local n = norm(typeName)
		local item = {
			name = (a.name ~= nil and tostring(a.name) ~= "") and tostring(a.name) or "Unavailable",
			id = tonumber(a.id),
			category = typeName,
			key = n,
		}
		if CLOTHING_LABELS[n] then
			item.label = CLOTHING_LABELS[n]
			table.insert(r.clothing, item)
		elseif ACCESSORY_LABELS[n] then
			item.label = ACCESSORY_LABELS[n]
			table.insert(r.accessories, item)
		elseif string.sub(n, -9) == "accessory" then
			item.label = typeName
			table.insert(r.accessories, item)
		elseif string.find(n, "animation", 1, true) then
			item.label = typeName
			table.insert(r.animations, item)
		elseif BODY_LABELS[n] then
			item.label = BODY_LABELS[n]
			table.insert(r.bodyParts, item)
		else
			item.label = typeName
			table.insert(r.other, item)
		end
	end
	table.sort(r.accessories, function(a, b)
		local ia, ib = table.find(ACCESSORY_ORDER, a.label) or 99, table.find(ACCESSORY_ORDER, b.label) or 99
		if ia ~= ib then
			return ia < ib
		end
		return (a.id or 0) < (b.id or 0)
	end)
	return r
end

local function allItems(r)
	local list = {}
	for _, group in ipairs({ r.clothing, r.accessories, r.bodyParts, r.animations, r.other }) do
		for _, it in ipairs(group) do
			table.insert(list, it)
		end
	end
	return list
end

local function bodyColorList(info)
	local out = {}
	local bc = info.bodyColors
	if type(bc) ~= "table" then
		return out
	end
	local order = {
		{ "Head", "headColorId" },
		{ "Torso", "torsoColorId" },
		{ "Left Arm", "leftArmColorId" },
		{ "Right Arm", "rightArmColorId" },
		{ "Left Leg", "leftLegColorId" },
		{ "Right Leg", "rightLegColorId" },
	}
	for _, p in ipairs(order) do
		local id = bc[p[2]]
		if id ~= nil then
			local ok, brick = pcall(BrickColor.new, id)
			if ok and brick then
				table.insert(out, { label = p[1], name = brick.Name, id = id, color = brick.Color })
			else
				table.insert(out, { label = p[1], name = "Unknown", id = id })
			end
		end
	end
	return out
end

local function scaleList(info)
	local out = {}
	local s = info.scales
	if type(s) ~= "table" then
		return out
	end
	for _, p in ipairs({
		{ "Height", "height" },
		{ "Width", "width" },
		{ "Head", "head" },
		{ "Depth", "depth" },
		{ "Proportion", "proportion" },
		{ "Body type", "bodyType" },
	}) do
		if s[p[2]] ~= nil then
			table.insert(out, { label = p[1], value = tostring(s[p[2]]) })
		end
	end
	return out
end

----------------------------------------------------------------------
-- RESULT CARDS
----------------------------------------------------------------------
local orderCounter = 0
local function nextOrder()
	orderCounter += 1
	return orderCounter
end

local function clearResultsUI()
	for _, c in ipairs(resultsScroll:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	orderCounter = 0
end

local function addSectionHeader(text, color)
	local f = new("Frame", {
		Parent = resultsScroll,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
	})
	corner(f, 8)
	new("Frame", {
		Parent = f,
		Size = UDim2.new(0, 4, 1, -10),
		Position = UDim2.new(0, 6, 0, 5),
		BackgroundColor3 = color or C.purple,
		BorderSizePixel = 0,
	})
	label(f, text, 12, C.text, Enum.Font.GothamBlack, {
		Position = UDim2.new(0, 18, 0, 0),
		Size = UDim2.new(1, -24, 1, 0),
		TextWrapped = false,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
end

local function addNote(text, color)
	label(resultsScroll, text, 11, color or C.sub, Enum.Font.Gotham, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
	})
end

local function addInfoRow(labelText, richValue)
	local f = new("Frame", {
		Parent = resultsScroll,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel2,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
	})
	corner(f, 8)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = f,
	})
	label(f, "<font color=\"" .. hex(C.cyan) .. "\"><b>" .. esc(labelText) .. "</b></font>  " .. richValue, 12, C.text, Enum.Font.Gotham, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		RichText = true,
	})
end

local function createCard(item)
	local card = new("Frame", {
		Parent = resultsScroll,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel2,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
	})
	corner(card, 10)
	stroke(card, C.purple, 1, 0.65)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })

	local head = new("TextButton", {
		Parent = card,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 1,
	})
	local nameLabel = label(head, item.name, 13, C.text, Enum.Font.GothamBold, {
		Position = UDim2.new(0, 10, 0, 5),
		Size = UDim2.new(1, -40, 0, 18),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	label(
		head,
		(item.label or item.category) .. "  •  ID: " .. (item.id and tostring(item.id) or "Unavailable"),
		11,
		C.cyan,
		Enum.Font.GothamMedium,
		{
			Position = UDim2.new(0, 10, 0, 24),
			Size = UDim2.new(1, -40, 0, 16),
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}
	)
	local chevron = label(head, "▼", 12, C.purple, Enum.Font.GothamBold, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local body = new("Frame", {
		Parent = card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 2,
	})
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		Parent = body,
	})
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })

	local link = catalogLink(item.id)
	local function line(text, order, rich)
		return label(body, text, 11, C.text, Enum.Font.Gotham, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			RichText = rich or false,
		})
	end
	line("Category: " .. tostring(item.category), 1)
	line("Asset ID: " .. (item.id and tostring(item.id) or "Unavailable"), 2)
	local priceLabel = line("Price: <font color=\"" .. hex(C.sub) .. "\">expand to check</font>", 3, true)
	local creatorLabel = line("Creator: Unavailable", 4)
	line("Link: " .. (link or "Unavailable"), 5)

	local row = new("Frame", {
		Parent = body,
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		LayoutOrder = 6,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local bId = makeButton(row, "COPY ID", C.panel, UDim2.new(1 / 3, -4, 1, 0))
	local bLink = makeButton(row, "COPY LINK", C.panel, UDim2.new(1 / 3, -4, 1, 0))
	local bOpen = makeButton(row, "OPEN PAGE", C.panel, UDim2.new(1 / 3, -4, 1, 0))
	bId.LayoutOrder, bLink.LayoutOrder, bOpen.LayoutOrder = 1, 2, 3
	bId.TextSize, bLink.TextSize, bOpen.TextSize = 11, 11, 11

	bId.Activated:Connect(function()
		if item.id then
			copyText(tostring(item.id), "asset ID")
		else
			notify("Asset ID unavailable.", "warn")
		end
	end)
	bLink.Activated:Connect(function()
		if link then
			copyText(link, "catalog link")
		else
			notify("Catalog link unavailable.", "warn")
		end
	end)
	bOpen.Activated:Connect(function()
		if link then
			openUrl(link)
		else
			notify("Catalog link unavailable.", "warn")
		end
	end)

	local expanded = false
	head.Activated:Connect(function()
		expanded = not expanded
		body.Visible = expanded
		chevron.Text = expanded and "▲" or "▼"
		if expanded then
			task.spawn(loadItemProduct, item, priceLabel, nameLabel, creatorLabel)
		end
	end)

	-- Show already known data if prices were fetched earlier
	if item.priceText then
		priceLabel.Text = "Price: <font color=\"" .. hex(C.green) .. "\">" .. esc(item.priceText) .. "</font>"
	end
	if item.creator then
		creatorLabel.Text = "Creator: " .. item.creator
	end
end

local function addCards(list, emptyText)
	if #list == 0 then
		addNote(emptyText, C.sub)
		return
	end
	for _, it in ipairs(list) do
		createCard(it)
	end
end

local function renderResults(r)
	clearResultsUI()

	addSectionHeader("A  •  CLOTHING (" .. #r.clothing .. ")", C.purple)
	addCards(r.clothing, "No clothing found (default or missing). Unavailable.")

	addSectionHeader("B  •  ACCESSORIES (" .. #r.accessories .. ")", C.cyan)
	addCards(r.accessories, "No accessories found. Unavailable.")

	addSectionHeader("C  •  AVATAR DETAILS", C.magenta)
	addInfoRow("User ID:", esc(r.userId))
	addInfoRow("Username:", esc(r.username))
	addInfoRow("Display name:", esc(r.displayName))
	addInfoRow("Avatar type:", esc(r.avatarType or "Unavailable"))
	if r.info.defaultShirtApplied ~= nil or r.info.defaultPantsApplied ~= nil then
		addInfoRow(
			"Defaults applied:",
			"shirt = " .. esc(tostring(r.info.defaultShirtApplied)) .. ", pants = " .. esc(tostring(r.info.defaultPantsApplied))
		)
	end

	local colors = bodyColorList(r.info)
	if #colors == 0 then
		addInfoRow("Body colors:", "Unavailable")
	else
		local parts = {}
		for _, c in ipairs(colors) do
			local swatch = c.color and ("<font color=\"" .. hex(c.color) .. "\">■</font> ") or ""
			table.insert(parts, swatch .. esc(c.label) .. ": " .. esc(c.name) .. " (" .. esc(c.id) .. ")")
		end
		addInfoRow("Body colors:", table.concat(parts, "\n"))
	end

	local scales = scaleList(r.info)
	if #scales == 0 then
		addInfoRow("Body scale:", "Unavailable")
	else
		local parts = {}
		for _, s in ipairs(scales) do
			table.insert(parts, esc(s.label) .. ": " .. esc(s.value))
		end
		addInfoRow("Body scale:", table.concat(parts, "\n"))
	end

	addInfoRow("Bundles:", "Unavailable (needs Roblox web API access that LocalScripts do not have)")

	addSectionHeader("BODY PARTS & FACE (" .. #r.bodyParts .. ")", C.sub)
	addCards(r.bodyParts, "No body-part or face asset IDs returned. Unavailable.")

	addSectionHeader("EQUIPPED ANIMATIONS (" .. #r.animations .. ")", C.sub)
	addCards(r.animations, "No custom animation IDs returned. Unavailable.")

	if #r.other > 0 then
		addSectionHeader("OTHER ASSETS (" .. #r.other .. ")", C.sub)
		addCards(r.other, "")
	end
end

----------------------------------------------------------------------
-- REPORT BUILDERS
----------------------------------------------------------------------
local function buildIdsReport(r)
	local L = {}
	table.insert(L, "PLAYER: " .. r.username)
	table.insert(L, "USER ID: " .. r.userId)
	table.insert(L, "")
	for _, it in ipairs(r.clothing) do
		local lbl = CLOTHING_REPORT[it.key] or string.upper(it.label) .. " ID"
		table.insert(L, lbl .. ": " .. (it.id and tostring(it.id) or "Unavailable"))
	end
	if #r.accessories > 0 then
		table.insert(L, "")
		table.insert(L, "ACCESSORIES:")
		for _, it in ipairs(r.accessories) do
			table.insert(L, it.label .. ": " .. (it.id and tostring(it.id) or "Unavailable"))
		end
	end
	if #r.bodyParts > 0 then
		table.insert(L, "")
		table.insert(L, "BODY PARTS:")
		for _, it in ipairs(r.bodyParts) do
			table.insert(L, it.label .. ": " .. (it.id and tostring(it.id) or "Unavailable"))
		end
	end
	if #r.animations > 0 then
		table.insert(L, "")
		table.insert(L, "ANIMATIONS:")
		for _, it in ipairs(r.animations) do
			table.insert(L, it.label .. ": " .. (it.id and tostring(it.id) or "Unavailable"))
		end
	end
	return table.concat(L, "\n")
end

local function itemLine(it)
	local price = it.priceText or "Not checked (expand card or press FETCH PRICES)"
	return string.format(
		"- %s | %s | ID: %s | Price: %s | Link: %s",
		it.name,
		it.label or it.category,
		it.id and tostring(it.id) or "Unavailable",
		price,
		catalogLink(it.id) or "Unavailable"
	)
end

local function buildDetailsReport(r)
	local L = {}
	table.insert(L, BRAND .. " • MADE BY AAYAN")
	table.insert(L, "")
	table.insert(L, "PLAYER: " .. r.username .. " (display: " .. r.displayName .. ")")
	table.insert(L, "USER ID: " .. r.userId)
	table.insert(L, "AVATAR TYPE: " .. tostring(r.avatarType or "Unavailable"))
	table.insert(L, "")
	local function section(title, list)
		table.insert(L, title .. ":")
		if #list == 0 then
			table.insert(L, "- Unavailable")
		else
			for _, it in ipairs(list) do
				table.insert(L, itemLine(it))
			end
		end
		table.insert(L, "")
	end
	section("CLOTHING", r.clothing)
	section("ACCESSORIES", r.accessories)
	table.insert(L, "BODY COLORS:")
	local colors = bodyColorList(r.info)
	if #colors == 0 then
		table.insert(L, "- Unavailable")
	end
	for _, c in ipairs(colors) do
		table.insert(L, string.format("- %s: %s (%s)", c.label, c.name, tostring(c.id)))
	end
	table.insert(L, "")
	table.insert(L, "BODY SCALE:")
	local scales = scaleList(r.info)
	if #scales == 0 then
		table.insert(L, "- Unavailable")
	end
	for _, s in ipairs(scales) do
		table.insert(L, string.format("- %s: %s", s.label, s.value))
	end
	table.insert(L, "")
	section("BODY PARTS / FACE", r.bodyParts)
	section("ANIMATIONS", r.animations)
	if #r.other > 0 then
		section("OTHER ASSETS", r.other)
	end
	table.insert(L, "BUNDLES: Unavailable")
	return table.concat(L, "\n")
end

local function toExportItem(it)
	return {
		name = it.name,
		assetId = it.id,
		category = it.category,
		catalogLink = catalogLink(it.id),
		price = it.priceText,
		creator = it.creator,
	}
end

local function buildExportJson(r)
	local function list(group)
		local out = {}
		for _, it in ipairs(group) do
			table.insert(out, toExportItem(it))
		end
		return out
	end
	local colors = {}
	for _, c in ipairs(bodyColorList(r.info)) do
		table.insert(colors, { part = c.label, brickColorName = c.name, brickColorId = c.id })
	end
	local scales = {}
	for _, s in ipairs(scaleList(r.info)) do
		scales[s.label] = s.value
	end
	local data = {
		tool = BRAND,
		madeBy = "AAYAN",
		exportedAtUtc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		player = {
			userId = r.userId,
			username = r.username,
			displayName = r.displayName,
			avatarType = r.avatarType,
		},
		clothing = list(r.clothing),
		accessories = list(r.accessories),
		bodyParts = list(r.bodyParts),
		animations = list(r.animations),
		other = list(r.other),
		bodyColors = colors,
		bodyScale = scales,
		bundles = "Unavailable",
		note = "price is null unless it was verified through MarketplaceService:GetProductInfo",
	}
	local ok, json = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if ok then
		return json
	end
	return nil
end

----------------------------------------------------------------------
-- GET AVATAR
----------------------------------------------------------------------
local function setBusy(on)
	busy = on
	getBtn.Text = on and "[ LOADING... ]" or "[ GET AVATAR ]"
	if on then
		resultsBar.start()
	else
		resultsBar.stop()
	end
end

local function getAvatar()
	if busy then
		notify("Already loading, please wait.", "warn")
		return
	end
	local plr = selectedPlayer
	if not plr or not plr.Parent then
		notify("Select a player first.", "error")
		setTab("PLAYERS")
		return
	end
	setBusy(true)
	setTab("RESULTS")
	setStatus("Loading avatar data for @" .. plr.Name .. "...", C.yellow)
	task.spawn(function()
		local info, err = fetchAppearance(plr.UserId, true)
		if not gui.Parent then
			return
		end
		setBusy(false)
		if not info then
			setStatus("Failed to load avatar data.", C.red)
			notify("Avatar request failed (network or rate limit): " .. tostring(err), "error")
			return
		end
		results = buildResults(plr, info)
		renderResults(results)
		local total = #allItems(results)
		setStatus(string.format("@%s • UserId %d • %d assets found", results.username, results.userId, total), C.green)
		notify("Avatar data loaded (" .. total .. " assets).", "success")
	end)
end
getBtn.Activated:Connect(getAvatar)

----------------------------------------------------------------------
-- ACTION BUTTONS
----------------------------------------------------------------------
local function requireResults()
	if not results then
		notify("No results yet. Press GET AVATAR first.", "warn")
		return false
	end
	return true
end

btnCopyIds.Activated:Connect(function()
	if requireResults() then
		copyText(buildIdsReport(results), "all IDs")
	end
end)

btnCopyDetails.Activated:Connect(function()
	if requireResults() then
		copyText(buildDetailsReport(results), "outfit details")
	end
end)

btnExport.Activated:Connect(function()
	if not requireResults() then
		return
	end
	local json = buildExportJson(results)
	if not json then
		notify("Export failed while encoding JSON.", "error")
		return
	end
	local wf = getGlobal("writefile")
	if typeof(wf) == "function" then
		local fname = string.format("AayanOutfitRevealer_%s_%d.json", results.username, results.userId)
		local ok = pcall(wf, fname, json)
		if ok then
			notify("Saved file: " .. fname, "success")
			showOutput(json, "export json")
			return
		end
	end
	showOutput(json, "export json")
	notify("Cannot write files here. JSON shown below, select and copy it.", "warn")
end)

local pricesRunning = false
btnPrices.Activated:Connect(function()
	if not requireResults() then
		return
	end
	if pricesRunning then
		notify("Price lookup already running.", "warn")
		return
	end
	pricesRunning = true
	local items = allItems(results)
	task.spawn(function()
		resultsBar.start()
		local done, failed = 0, 0
		for i, it in ipairs(items) do
			if not gui.Parent then
				return
			end
			setStatus(string.format("Fetching prices... %d / %d", i, #items), C.yellow)
			loadItemProduct(it, nil, nil, nil)
			if it.priceText then
				done += 1
			else
				failed += 1
			end
		end
		resultsBar.stop()
		pricesRunning = false
		setStatus(string.format("Prices checked: %d ok, %d failed", done, failed), failed == 0 and C.green or C.yellow)
		if results then
			renderResults(results)
		end
		notify("Price lookup finished.", failed == 0 and "success" or "warn")
	end)
end)

btnCatalog.Activated:Connect(function()
	openUrl("https://www.roblox.com/catalog")
end)

btnClear.Activated:Connect(function()
	results = nil
	clearResultsUI()
	outputPanel.Visible = false
	outputBox.Text = ""
	layoutResults()
	setStatus("Results cleared. Select a player and press GET AVATAR.", C.sub)
	notify("Results cleared.", "success")
end)

----------------------------------------------------------------------
-- SELECTION
----------------------------------------------------------------------
selectPlayer = function(plr)
	if not plr or not plr.Parent then
		notify("That player is no longer in the server.", "error")
		return
	end
	selectedPlayer = plr
	selectedLabel.Text = "Selected: " .. plr.DisplayName .. " (@" .. plr.Name .. ")"
	selectedLabel.TextColor3 = C.cyan
	refreshHighlights()
	loadPreview(plr)
	setTab("PREVIEW")
end

----------------------------------------------------------------------
-- TOGGLE BUTTON
----------------------------------------------------------------------
local toggle = new("TextButton", {
	Name = "Toggle",
	Parent = gui,
	Size = UDim2.fromOffset(44, 44),
	Position = UDim2.new(1, -66, 0.35, 0),
	BackgroundColor3 = C.bg,
	Text = "A",
	TextColor3 = C.text,
	Font = Enum.Font.GothamBlack,
	TextSize = 20,
	AutoButtonColor = false,
	BorderSizePixel = 0,
	ZIndex = 50,
})
corner(toggle, 22)
neonStroke(toggle, 3, toggleGradients)
local toggleScale = new("UIScale", { Scale = 1, Parent = toggle })
label(toggle, "AOR", 8, C.cyan, Enum.Font.GothamBold, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -5),
	Size = UDim2.new(1, 0, 0, 10),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = false,
	ZIndex = 51,
})
toggle.TextYAlignment = Enum.TextYAlignment.Center

local isOpen = false
local function setOpen(open)
	if open == isOpen then
		return
	end
	isOpen = open
	if open then
		main.Visible = true
		mainScale.Scale = 0.85
		tween(mainScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		task.delay(0.28, function()
			if isOpen then
				clampToScreen(main, false)
			end
		end)
	else
		tween(mainScale, 0.18, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			if not isOpen and main.Parent then
				main.Visible = false
			end
		end)
	end
end

makeDraggable(toggle, toggle, true, function(moved)
	if not moved then
		tween(toggleScale, 0.08, { Scale = 0.9 })
		task.delay(0.08, function()
			if toggleScale.Parent then
				tween(toggleScale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
		setOpen(not isOpen)
	end
end)
makeDraggable(header, main, false, nil)
closeBtn.Activated:Connect(function()
	setOpen(false)
end)

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	clampToScreen(toggle, true)
	if isOpen then
		clampToScreen(main, false)
	end
end)

----------------------------------------------------------------------
-- RGB BORDER ANIMATION (single Heartbeat connection, tied to GUI life)
----------------------------------------------------------------------
local t0 = 0
track(RunService.Heartbeat:Connect(function(dt)
	t0 += dt
	local seq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.purple),
		ColorSequenceKeypoint.new(0.35, C.cyan),
		ColorSequenceKeypoint.new(0.7, Color3.fromHSV((t0 * 0.25) % 1, 1, 1)),
		ColorSequenceKeypoint.new(1, C.purple),
	})
	local rot = (t0 * 90) % 360
	for _, g in ipairs(toggleGradients) do
		g.Rotation = rot
		g.Color = seq
	end
	if isOpen then
		for _, g in ipairs(mainGradients) do
			g.Rotation = rot
			g.Color = seq
		end
	end
end))

----------------------------------------------------------------------
-- PLAYER EVENTS
----------------------------------------------------------------------
for _, plr in ipairs(Players:GetPlayers()) do
	addPlayer(plr)
end
track(Players.PlayerAdded:Connect(addPlayer))
track(Players.PlayerRemoving:Connect(function(plr)
	removePlayer(plr)
	appearanceCache[plr.UserId] = nil
	if selectedPlayer == plr then
		selectedPlayer = nil
		previewToken += 1
		clearPreviewModel()
		previewBar.stop()
		setPreviewStatus("Selected player left the server.", true)
		selectedLabel.Text = "No player selected"
		selectedLabel.TextColor3 = C.sub
		notify(plr.Name .. " left the server. Pick another player.", "warn")
	end
end))

----------------------------------------------------------------------
-- FINISH: parent, cleanup hook, open
----------------------------------------------------------------------
_G.AayanRevealerCleanup = function()
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(connections)
	previewToken += 1
	if gui then
		gui:Destroy()
	end
	_G.AayanRevealerCleanup = nil
end

gui.Parent = guiParent
setTab("PLAYERS")
layoutPreview()
layoutResults()
applyFilter()
task.defer(function()
	clampToScreen(toggle, true)
	setOpen(true)
	notify("Welcome to AAYAN OUTFIT REVEALER • MADE BY AAYAN", "info")
end)
