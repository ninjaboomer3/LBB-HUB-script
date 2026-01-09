-- LocalScript

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Default keybind
local currentBind = Enum.KeyCode.Q
local waitingForKey = false

-- === Helper: Get Humanoid (updated on respawn) ===
local currentHumanoid = nil
local function updateHumanoid()
    local char = Player.Character
    if char then
        currentHumanoid = char:FindFirstChildWhichIsA("Humanoid")
    end
end
Player.CharacterAdded:Connect(function()
    task.wait(0.1)
    updateHumanoid()
end)
updateHumanoid()

-- === Tools Functions ===
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

local function useEverythingAtOnce()
    for _, tool in ipairs(getAllTools()) do
        pcall(function()
            tool.Parent = Player.Character
            tool:Activate()
        end)
    end
end

-- === GUI Setup ===
local screenGui = Instance.new("ScreenGui")
screenGui.Parent = PlayerGui
screenGui.IgnoreGuiInset = true

-- Main Frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(300, 160)
mainFrame.Position = UDim2.fromOffset(100, 100)
mainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
mainFrame.BorderSizePixel = 0
mainFrame.AnchorPoint = Vector2.new(0, 0)
mainFrame.Parent = screenGui

-- Rounded Corners
local uiCorner = Instance.new("UICorner", mainFrame)
uiCorner.CornerRadius = UDim.new(0, 8)

-- Title Bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundTransparency = 1
titleBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -70, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "LBB Hub"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.SourceSansSemibold
titleLabel.TextSize = 20
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- Minimize & Close
local function makeTopButton(text, position)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(30, 30)
    btn.Position = position
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.SourceSansBold
    btn.TextSize = 18
    btn.Parent = titleBar
    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, 6)
    return btn
end

local minimizeButton = makeTopButton("-", UDim2.new(1, -60, 0, 0))
local closeButton    = makeTopButton("X", UDim2.new(1, -30, 0, 0))

-- Use Everything Button
local useButton = Instance.new("TextButton")
useButton.Size = UDim2.fromScale(1, 0) - UDim2.fromOffset(20, 60)
useButton.Position = UDim2.fromOffset(10, 40)
useButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
useButton.TextColor3 = Color3.fromRGB(255, 255, 255)
useButton.Font = Enum.Font.SourceSans
useButton.TextSize = 18
useButton.Text = "Use Everything"
useButton.Parent = mainFrame
local useCorner = Instance.new("UICorner", useButton)
useCorner.CornerRadius = UDim.new(0, 6)

useButton.MouseButton1Click:Connect(useEverythingAtOnce)

-- Keybind Button
local keybindButton = Instance.new("TextButton")
keybindButton.Size = UDim2.fromScale(1, 0) - UDim2.fromOffset(180, 110)
keybindButton.Position = UDim2.fromOffset(10, 100)
keybindButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
keybindButton.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindButton.Font = Enum.Font.SourceSans
keybindButton.TextSize = 16
keybindButton.Text = "Set Keybind"
keybindButton.Parent = mainFrame
Instance.new("UICorner", keybindButton)

local currentBindLabel = Instance.new("TextLabel")
currentBindLabel.Size = UDim2.new(1, 0, 0, 20)
currentBindLabel.Position = UDim2.new(0, 0, 0, 140)
currentBindLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
currentBindLabel.BackgroundTransparency = 1
currentBindLabel.Font = Enum.Font.SourceSans
currentBindLabel.TextSize = 14
currentBindLabel.Text = "Current Bind: " .. currentBind.Name
currentBindLabel.Parent = mainFrame

keybindButton.MouseButton1Click:Connect(function()
    keybindButton.Text = "Press any key..."
    waitingForKey = true
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
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

-- Minimize & Close Logic
local circle = Instance.new("TextButton")
circle.Size = UDim2.fromOffset(40, 40)
circle.Position = mainFrame.Position
circle.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
circle.Text = "LBB"
circle.TextColor3 = Color3.fromRGB(255, 255, 255)
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

closeButton.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

-- === Speed Toggle ===
local toggleFrame = Instance.new("Frame")
toggleFrame.Size = UDim2.fromOffset(100, 28)
toggleFrame.Position = UDim2.fromOffset(180, 100)
toggleFrame.BackgroundTransparency = 1
toggleFrame.Parent = mainFrame

local toggleBg = Instance.new("Frame")
toggleBg.Size = UDim2.fromScale(1, 1)
toggleBg.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
toggleBg.Parent = toggleFrame
Instance.new("UICorner", toggleBg).CornerRadius = UDim.new(0, 6)

local toggleCircle = Instance.new("Frame")
toggleCircle.Size = UDim2.fromOffset(24, 24)
toggleCircle.Position = UDim2.fromOffset(2, 2)
toggleCircle.BackgroundColor3 = Color3.fromRGB(176, 176, 176)
toggleCircle.Parent = toggleBg
Instance.new("UICorner", toggleCircle).CornerRadius = UDim.new(1, 0)

local speedOn = false

local function updateSpeedToggle()
    if speedOn then
        toggleCircle:TweenPosition(UDim2.fromScale(0.75, 0), "Out", "Quad", 0.2, true)
        if currentHumanoid then
            currentHumanoid.WalkSpeed = 28
        end
    else
        toggleCircle:TweenPosition(UDim2.fromOffset(2, 2), "Out", "Quad", 0.2, true)
        if currentHumanoid then
            currentHumanoid.WalkSpeed = 16
        end
    end
end

toggleBg.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        speedOn = not speedOn
        updateSpeedToggle()
    end
end)

-- Make sure speed still applies after respawn
Player.CharacterAdded:Connect(function()
    task.wait(0.1)
    updateSpeedToggle()
end)
