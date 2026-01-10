-- LocalScript

--// SERVICES
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

--// CONFIG
local ADMIN_SPEED = 27.7
local currentBind = Enum.KeyCode.Q
local waitingForKey = false
local speedEnabled = false

--// TRACK HUMANOID
local currentHumanoid

local function hookHumanoid(humanoid)
	currentHumanoid = humanoid
end

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	hookHumanoid(humanoid)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

--// TOOLS
local function getAllTools()
	local tools = {}
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") then
				table.insert(tools, t)
			end
		end
	end
	if player.Character then
		for _, t in ipairs(player.Character:GetChildren()) do
			if t:IsA("Tool") then
				table.insert(tools, t)
			end
		end
	end
	return tools
end

local function useEverything()
	for _, t in ipairs(getAllTools()) do
		pcall(function()
			t.Parent = player.Character
			t:Activate()
		end)
	end
end

--// GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AdminPanel"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(340, 220) -- made taller for new section
mainFrame.Position = UDim2.fromOffset(100, 100)
mainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

-- Title bar & drag
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundTransparency = 1
titleBar.Parent = mainFrame

local dragging = false
local dragStart
local startPos
titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPos = mainFrame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)
titleBar.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStart
		mainFrame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -70, 1, 0)
titleLabel.Position = UDim2.fromOffset(10, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "LBB Hub"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.SourceSansSemibold
titleLabel.TextSize = 20
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local function topButton(text, pos)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(30, 30)
	b.Position = pos
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 18
	b.Parent = titleBar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local minimizeButton = topButton("-", UDim2.new(1, -60, 0, 0))
local closeButton = topButton("X", UDim2.new(1, -30, 0, 0))

-- Use Everything
local useButton = Instance.new("TextButton")
useButton.Size = UDim2.fromOffset(300, 40)
useButton.Position = UDim2.fromOffset(10, 40)
useButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
useButton.Text = "Use Everything"
useButton.TextColor3 = Color3.new(1, 1, 1)
useButton.Font = Enum.Font.SourceSans
useButton.TextSize = 18
useButton.Parent = mainFrame
Instance.new("UICorner", useButton).CornerRadius = UDim.new(0, 6)
useButton.MouseButton1Click:Connect(useEverything)

-- Keybind
local keybindButton = Instance.new("TextButton")
keybindButton.Size = UDim2.fromOffset(150, 30)
keybindButton.Position = UDim2.fromOffset(10, 90)
keybindButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
keybindButton.Text = "Set Keybind"
keybindButton.TextColor3 = Color3.new(1, 1, 1)
keybindButton.Font = Enum.Font.SourceSans
keybindButton.TextSize = 16
keybindButton.Parent = mainFrame
Instance.new("UICorner", keybindButton)

local currentBindLabel = Instance.new("TextLabel")
currentBindLabel.Size = UDim2.fromOffset(150, 20)
currentBindLabel.Position = UDim2.fromOffset(10, 130)
currentBindLabel.BackgroundTransparency = 1
currentBindLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
currentBindLabel.Font = Enum.Font.SourceSans
currentBindLabel.TextSize = 14
currentBindLabel.Text = "Current Bind: " .. currentBind.Name
currentBindLabel.Parent = mainFrame

keybindButton.MouseButton1Click:Connect(function()
	waitingForKey = true
	keybindButton.Text = "Press key..."
end)

-- Input connection
local inputConn
inputConn = UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if waitingForKey and input.UserInputType == Enum.UserInputType.Keyboard then
		currentBind = input.KeyCode
		currentBindLabel.Text = "Current Bind: " .. currentBind.Name
		keybindButton.Text = "Set Keybind"
		waitingForKey = false
		return
	end
	if input.KeyCode == currentBind then
		useEverything()
	end
end)

-- Speed toggle
local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.fromOffset(50, 24)
toggleButton.Position = UDim2.fromOffset(220, 95)
toggleButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
toggleButton.Text = ""
toggleButton.Parent = mainFrame
Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 6)

local toggleCircle = Instance.new("Frame")
toggleCircle.Size = UDim2.fromOffset(20, 20)
toggleCircle.Position = UDim2.fromOffset(2, 2)
toggleCircle.BackgroundColor3 = Color3.fromRGB(176, 176, 176)
toggleCircle.Parent = toggleButton
Instance.new("UICorner", toggleCircle).CornerRadius = UDim.new(1, 0)

toggleButton.MouseButton1Click:Connect(function()
	speedEnabled = not speedEnabled
	if speedEnabled then
		toggleCircle:TweenPosition(UDim2.fromOffset(28, 2), "Out", "Quad", 0.2, true)
	else
		toggleCircle:TweenPosition(UDim2.fromOffset(2, 2), "Out", "Quad", 0.2, true)
	end
end)

-- Apply speed every frame
RunService.Heartbeat:Connect(function()
	if speedEnabled and currentHumanoid then
		currentHumanoid.WalkSpeed = ADMIN_SPEED
	end
end)

-- Minimize / restore
local circle = Instance.new("TextButton")
circle.Size = UDim2.fromOffset(40, 40)
circle.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
circle.Text = "LBB"
circle.TextColor3 = Color3.new(1, 1, 1)
circle.Font = Enum.Font.SourceSans
circle.TextSize = 16
circle.Visible = false
circle.Parent = screenGui
Instance.new("UICorner", circle).CornerRadius = UDim.new(0, 8)

minimizeButton.MouseButton1Click:Connect(function()
	mainFrame.Visible = false
	circle.Position = mainFrame.Position
	circle.Visible = true
end)

circle.MouseButton1Click:Connect(function()
	circle.Visible = false
	mainFrame.Visible = true
end)

-- COMPLETE KILL SWITCH
closeButton.MouseButton1Click:Connect(function()
	screenGui:Destroy()
	speedEnabled = false
	currentHumanoid = nil
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
	script.Disabled = true
end)

--[[ =====================================================
  CUSTOM SPEED SECTION — INDEPENDENT
=====================================================]]--

local customSpeedEnabled = false
local customSpeedValue = 27.7

-- Custom toggle
local customToggleButton = Instance.new("TextButton")
customToggleButton.Size = UDim2.fromOffset(50, 24)
customToggleButton.Position = UDim2.fromOffset(220, 125)
customToggleButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
customToggleButton.Text = ""
customToggleButton.Parent = mainFrame
Instance.new("UICorner", customToggleButton).CornerRadius = UDim.new(0, 6)

local customToggleCircle = Instance.new("Frame")
customToggleCircle.Size = UDim2.fromOffset(20, 20)
customToggleCircle.Position = UDim2.fromOffset(2, 2)
customToggleCircle.BackgroundColor3 = Color3.fromRGB(176, 176, 176)
customToggleCircle.Parent = customToggleButton
Instance.new("UICorner", customToggleCircle).CornerRadius = UDim.new(1, 0)

customToggleButton.MouseButton1Click:Connect(function()
	customSpeedEnabled = not customSpeedEnabled
	if customSpeedEnabled then
		customToggleCircle:TweenPosition(UDim2.fromOffset(28, 2), "Out", "Quad", 0.2, true)
	else
		customToggleCircle:TweenPosition(UDim2.fromOffset(2, 2), "Out", "Quad", 0.2, true)
	end
end)

-- Label for slider value
local customSpeedLabel = Instance.new("TextLabel")
customSpeedLabel.Size = UDim2.fromOffset(80, 20)
customSpeedLabel.Position = UDim2.fromOffset(10, 160)
customSpeedLabel.BackgroundTransparency = 1
customSpeedLabel.TextColor3 = Color3.fromRGB(200,200,200)
customSpeedLabel.Font = Enum.Font.SourceSans
customSpeedLabel.TextSize = 14
customSpeedLabel.Text = "Speed: " .. customSpeedValue
customSpeedLabel.Parent = mainFrame

-- Slider background
local sliderBg = Instance.new("Frame")
sliderBg.Size = UDim2.fromOffset(200, 10)
sliderBg.Position = UDim2.fromOffset(90, 165)
sliderBg.BackgroundColor3 = Color3.fromRGB(50,50,50)
sliderBg.Parent = mainFrame
Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(0,5)

-- Slider handle
local sliderHandle = Instance.new("Frame")
sliderHandle.Size = UDim2.fromOffset(14,14)
sliderHandle.Position = UDim2.fromOffset((customSpeedValue/1000)*200 - 7, -2)
sliderHandle.BackgroundColor3 = Color3.fromRGB(176,176,176)
sliderHandle.Parent = sliderBg
Instance.new("UICorner", sliderHandle).CornerRadius = UDim.new(1,0)

-- Drag logic for slider
local draggingSlider = false
sliderHandle.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		draggingSlider = true
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				draggingSlider = false
			end
		end)
	end
end)

sliderHandle.InputChanged:Connect(function(input)
	if draggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
		local pos = math.clamp(input.Position.X - sliderBg.AbsolutePosition.X,0,200)
		sliderHandle.Position = UDim2.fromOffset(pos-7,-2)
		customSpeedValue = math.floor((pos/200)*1000)
		customSpeedLabel.Text = "Speed: " .. customSpeedValue
	end
end)

-- Editable textbox
local customSpeedBox = Instance.new("TextBox")
customSpeedBox.Size = UDim2.fromOffset(50, 20)
customSpeedBox.Position = UDim2.fromOffset(300,160)
customSpeedBox.BackgroundColor3 = Color3.fromRGB(50,50,50)
customSpeedBox.TextColor3 = Color3.new(1,1,1)
customSpeedBox.Font = Enum.Font.SourceSans
customSpeedBox.TextSize = 14
customSpeedBox.Text = tostring(customSpeedValue)
customSpeedBox.ClearTextOnFocus = false
customSpeedBox.Parent = mainFrame
Instance.new("UICorner", customSpeedBox).CornerRadius = UDim.new(0,4)

customSpeedBox.FocusLost:Connect(function(enterPressed)
	local num = tonumber(customSpeedBox.Text)
	if num then
		customSpeedValue = math.clamp(num,1,1000)
		sliderHandle.Position = UDim2.fromOffset((customSpeedValue/1000)*200 - 7,-2)
		customSpeedLabel.Text = "Speed: "..customSpeedValue
	else
		customSpeedBox.Text = tostring(customSpeedValue)
	end
end)

-- Apply custom speed (using the same humanoid you already track)
RunService.Heartbeat:Connect(function()
	if customSpeedEnabled and currentHumanoid then
		currentHumanoid.WalkSpeed = customSpeedValue
	end
end)
