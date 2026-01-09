-- LocalScript

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Default keybind
local currentBind = Enum.KeyCode.Q

-- Flag für UI Aktivität
local uiActive = true
local waitingForKey = false

-- === Funktion: alle Tools aus Charakter und Backpack ===
local function getAllTools()
    local tools = {}
    local backpack = Player:FindFirstChild("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") then
                table.insert(tools, tool)
            end
        end
    end
    local character = Player.Character
    if character then
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(tools, child)
            end
        end
    end
    return tools
end

-- === Funktion: alles benutzen ===
local function useEverythingAtOnce()
    local tools = getAllTools()
    for _, tool in ipairs(tools) do
        pcall(function()
            tool.Parent = Player.Character
            tool:Activate()
        end)
    end
end

-- === GUI erstellen ===
local screenGui = Instance.new("ScreenGui", PlayerGui)

-- Main Frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 320, 0, 140)
mainFrame.Position = UDim2.new(0, 100, 0, 100)
mainFrame.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = screenGui

-- Drag Bar
local dragBar = Instance.new("Frame")
dragBar.Size = UDim2.new(1, 0, 0, 25)
dragBar.Position = UDim2.new(0, 0, 0, 0)
dragBar.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
dragBar.BorderSizePixel = 0
dragBar.Parent = mainFrame

local dragLabel = Instance.new("TextLabel")
dragLabel.Size = UDim2.new(1, -55, 1, 0)
dragLabel.Text = "LBB Hub"
dragLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
dragLabel.BackgroundTransparency = 1
dragLabel.TextScaled = true
dragLabel.TextXAlignment = Enum.TextXAlignment.Left
dragLabel.Parent = dragBar

-- Funktion für Buttons mit Animation
local function createButton(parent, size, position, text, bgColor, callback)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = position
    btn.Text = text
    btn.BackgroundColor3 = bgColor
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextScaled = true
    btn.Parent = parent
    btn.MouseButton1Click:Connect(function()
        local originalSize = btn.Size
        local shrinkSize = UDim2.new(originalSize.X.Scale, originalSize.X.Offset - 5, originalSize.Y.Scale, originalSize.Y.Offset - 5)
        btn.Size = shrinkSize
        task.wait(0.05)
        btn.Size = originalSize
        if callback then callback() end
    end)
    return btn
end

-- Platzhalter für Minimize/Close Funktionen
local minimizeUI, closeUI

-- Buttons erstellen
local minimizeButton = createButton(dragBar, UDim2.new(0, 25, 0, 25), UDim2.new(1, -55, 0, 0), "_", Color3.fromRGB(120, 120, 120), function() minimizeUI() end)
local closeButton = createButton(dragBar, UDim2.new(0, 25, 0, 25), UDim2.new(1, -25, 0, 0), "X", Color3.fromRGB(120, 50, 80), function() closeUI() end)

-- Use Everything Button
local useButton = Instance.new("TextButton")
useButton.Size = UDim2.new(0.6, -10, 0, 50)
useButton.Position = UDim2.new(0, 10, 0, 30)
useButton.Text = "Use Everything"
useButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
useButton.TextColor3 = Color3.fromRGB(255, 255, 255)
useButton.TextScaled = true
useButton.Parent = mainFrame
useButton.MouseButton1Click:Connect(useEverythingAtOnce)

-- Keybind Section
local keybindButton = Instance.new("TextButton")
keybindButton.Size = UDim2.new(0.35, -10, 0, 50)
keybindButton.Position = UDim2.new(0.62, 0, 0, 30)
keybindButton.Text = "Set Keybind"
keybindButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
keybindButton.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindButton.TextScaled = true
keybindButton.Parent = mainFrame

local currentBindLabel = Instance.new("TextLabel")
currentBindLabel.Size = UDim2.new(1, 0, 0, 20)
currentBindLabel.Position = UDim2.new(0, 0, 1, 5)
currentBindLabel.BackgroundTransparency = 1
currentBindLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
currentBindLabel.TextScaled = true
currentBindLabel.Text = "Current Bind: " .. currentBind.Name
currentBindLabel.Parent = mainFrame

keybindButton.MouseButton1Click:Connect(function()
    keybindButton.Text = "Press any key..."
    waitingForKey = true
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not uiActive then return end
    if gameProcessed then return end
    if waitingForKey and input.UserInputType == Enum.UserInputType.Keyboard then
        currentBind = input.KeyCode
        currentBindLabel.Text = "Current Bind: " .. currentBind.Name
        keybindButton.Text = "Set Keybind"
        waitingForKey = false
        return
    end
    if input.KeyCode == currentBind then
        useEverythingAtOnce()
    end
end)

-- Drag main frame
local dragging, dragInput, mousePos, framePos = false
dragBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        mousePos = input.Position
        framePos = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
dragBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then dragInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - mousePos
        mainFrame.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X, framePos.Y.Scale, framePos.Y.Offset + delta.Y)
    end
end)

-- Minimized Circle
local circle = Instance.new("TextButton")
circle.Size = UDim2.new(0, 40, 0, 40)
circle.Position = mainFrame.Position
circle.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
circle.Text = "LBB"
circle.TextColor3 = Color3.fromRGB(255, 255, 255)
circle.TextScaled = true
circle.Visible = false
circle.Parent = screenGui

-- Drag circle
local circleDragging, circleDragInput, circleMousePos, circlePos = false
circle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        circleDragging = true
        circleMousePos = input.Position
        circlePos = circle.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then circleDragging = false end
        end)
    end
end)
circle.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then circleDragInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
    if circleDragging and input == circleDragInput then
        local delta = input.Position - circleMousePos
        circle.Position = UDim2.new(circlePos.X.Scale, circlePos.X.Offset + delta.X, circlePos.Y.Scale, circlePos.Y.Offset + delta.Y)
    end
end)

-- Minimize/Restore Functions
minimizeUI = function()
    mainFrame.Visible = false
    circle.Position = mainFrame.Position
    circle.Visible = true
    uiActive = false
end

circle.MouseButton1Click:Connect(function()
    circle.Visible = false
    mainFrame.Visible = true
    uiActive = true
    -- smooth opening animation
    local steps = 10
    local startSize = UDim2.new(0, 20, 0, 20)
    local goalSize = UDim2.new(0, 320, 0, 140)
    mainFrame.Size = startSize
    for i = 1, steps do
        local t = i / steps
        mainFrame.Size = UDim2.new(0, startSize.X.Offset + (goalSize.X.Offset - startSize.X.Offset) * t, 0, startSize.Y.Offset + (goalSize.Y.Offset - startSize.Y.Offset) * t)
        task.wait(0.02)
    end
    mainFrame.Size = goalSize
end)

closeUI = function()
    screenGui:Destroy()
    uiActive = false
end

-- Opening Animation
mainFrame.Visible = true
local steps = 15
local startSize = UDim2.new(0, 0, 0, 0)
local goalSize = UDim2.new(0, 320, 0, 140)
mainFrame.Size = startSize
for i = 1, steps do
    local t = i / steps
    mainFrame.Size = UDim2.new(0, startSize.X.Offset + (goalSize.X.Offset - startSize.X.Offset) * t, 0, startSize.Y.Offset + (goalSize.Y.Offset - startSize.Y.Offset) * t)
    task.wait(0.02)
end
mainFrame.Size = goalSize

-- === Speed Toggle ===
local defaultSpeed = 16
local speedOn = false

local speedFrame = Instance.new("Frame")
speedFrame.Size = UDim2.new(0, 150, 0, 50)
speedFrame.Position = UDim2.new(0, 10, 0, 90) -- unter Use Everything
speedFrame.BackgroundTransparency = 1
speedFrame.Parent = mainFrame

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0.6, 0, 1, 0)
speedLabel.Position = UDim2.new(0, 0, 0, 0)
speedLabel.Text = "Speed Toggle"
speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
speedLabel.BackgroundTransparency = 1
speedLabel.TextScaled = true
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = speedFrame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0.35, -5, 0, 30)
toggleButton.Position = UDim2.new(0.65, 0, 0.15, 0)
toggleButton.Text = ""
toggleButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
toggleButton.Parent = speedFrame

local toggleCircle = Instance.new("Frame")
toggleCircle.Size = UDim2.new(0, 20, 0, 20)
toggleCircle.Position = UDim2.new(0, 0, 0.15, 0)
toggleCircle.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
toggleCircle.BorderSizePixel = 0
toggleCircle.AnchorPoint = Vector2.new(0, 0)
toggleCircle.Parent = toggleButton

local function updateSpeedToggle()
    if speedOn then
        toggleCircle:TweenPosition(UDim2.new(1, -20, 0.15, 0), "Out", "Quad", 0.2, true)
        if Player.Character and Player.Character:FindFirstChild("Humanoid") then
            Player.Character.Humanoid.WalkSpeed = 27.7
        end
    else
        toggleCircle:TweenPosition(UDim2.new(0, 0, 0.15, 0), "Out", "Quad", 0.2, true)
        if Player.Character and Player.Character:FindFirstChild("Humanoid") then
            Player.Character.Humanoid.WalkSpeed = defaultSpeed
        end
    end
end

toggleButton.MouseButton1Click:Connect(function()
    speedOn = not speedOn
    updateSpeedToggle()
end)
