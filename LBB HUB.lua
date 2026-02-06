-- LocalScript (full updated version - custom speed slider removed, only textbox remains)
-- All previous features preserved: instant off toggles, separate TP window, resize handle, fling, etc.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- State
local state = {
    currentBind = Enum.KeyCode.Q,
    waitingForKey = false,
    speedEnabled = false,
    customSpeedEnabled = false,
    customSpeedValue = 27.7,
    customJumpEnabled = false,
    customJumpValue = 50,
    flyEnabled = false,
    noclipEnabled = false,
    customFlySpeed = 65,
    flingEnabled = false,
}

local SPEED_27_7 = 27.7
local DEFAULT_WALKSPEED = 16
local DEFAULT_JUMPPOWER = 50

-- Character refs
local currentHumanoid = nil
local currentRootPart = nil
local character = nil

local function hookHumanoid(char)
    character = char
    currentHumanoid = nil
    currentRootPart = nil
    if not char then return end

    currentHumanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    currentRootPart = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)

    if currentHumanoid then
        if state.speedEnabled then currentHumanoid.WalkSpeed = SPEED_27_7 end
        if state.customSpeedEnabled then currentHumanoid.WalkSpeed = state.customSpeedValue end
        if state.customJumpEnabled then currentHumanoid.JumpPower = state.customJumpValue end
    end

    if state.noclipEnabled then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end

    char.DescendantAdded:Connect(function(desc)
        if desc:IsA("BasePart") and state.noclipEnabled then
            desc.CanCollide = false
        end
    end)
end

if player.Character then hookHumanoid(player.Character) end
player.CharacterAdded:Connect(hookHumanoid)

-- Tools helper
local function getAllTools()
    local tools = {}
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, t in ipairs(backpack:GetChildren()) do
            if t:IsA("Tool") then table.insert(tools, t) end
        end
    end
    if player.Character then
        for _, t in ipairs(player.Character:GetChildren()) do
            if t:IsA("Tool") then table.insert(tools, t) end
        end
    end
    return tools
end

local function useEverything()
    for _, t in ipairs(getAllTools()) do
        pcall(function()
            t.Parent = player.Character
            if t.Activate then t:Activate() end
        end)
    end
end

-- TP helpers
local function getRoot(char)
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function isValidTarget(p)
    if p == player then return false end
    local char = p.Character
    if not char then return false end
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    return hum and hum.Health > 0
end

local function tpTo(target)
    local myRoot = getRoot(player.Character)
    local tRoot = getRoot(target.Character)
    if myRoot and tRoot then
        myRoot.CFrame = tRoot.CFrame * CFrame.new(0, 5, 0)
    end
end

-- Fling
local flingConnection = nil

local function startFling()
    if flingConnection then return end
    local function flingLoop()
        if not currentRootPart or not currentRootPart.Parent then return end
        local savedCF = currentRootPart.CFrame
        local savedLin = currentRootPart.AssemblyLinearVelocity
        local savedAng = currentRootPart.AssemblyAngularVelocity

        local randX = (math.random() - 0.5) * 240000
        local randY = 144000 + math.random() * 72000
        local randZ = (math.random() - 0.5) * 240000
        currentRootPart.AssemblyLinearVelocity = Vector3.new(randX, randY, randZ)

        currentRootPart.AssemblyAngularVelocity = Vector3.new(math.random(-3000,3000), math.random(-6000,6000), math.random(-3000,3000))

        RunService.RenderStepped:Wait()

        currentRootPart.CFrame = savedCF * CFrame.Angles(0, math.rad(30000), 0)
        currentRootPart.AssemblyLinearVelocity = savedLin
        currentRootPart.AssemblyAngularVelocity = savedAng

        currentRootPart.AssemblyLinearVelocity += Vector3.new(0, 0.15, 0)
    end
    flingConnection = RunService.Heartbeat:Connect(flingLoop)
end

local function stopFling()
    if flingConnection then
        flingConnection:Disconnect()
        flingConnection = nil
    end
    if currentRootPart then
        currentRootPart.AssemblyLinearVelocity = Vector3.zero
        currentRootPart.AssemblyAngularVelocity = Vector3.zero
    end
end

player.CharacterRemoving:Connect(stopFling)
player.CharacterAdded:Connect(function()
    task.wait(1.2)
    if state.flingEnabled then startFling() end
end)

-- GUI
local sg = Instance.new("ScreenGui")
sg.Name = "LBBHub"
sg.ResetOnSpawn = false
sg.Parent = PlayerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 380, 0, 480)
mainFrame.Position = UDim2.new(0.5, -190, 0.5, -240)
mainFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = sg
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(40, 40, 48)
stroke.Thickness = 1.2
stroke.Parent = mainFrame

-- Resize handle (bottom-right)
local savedSize = {width = 380, height = 480}

local resizeHandle = Instance.new("TextButton")
resizeHandle.Size = UDim2.new(0, 24, 0, 24)
resizeHandle.Position = UDim2.new(1, -24, 1, -24)
resizeHandle.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
resizeHandle.Text = "↘"
resizeHandle.TextColor3 = Color3.fromRGB(180, 180, 200)
resizeHandle.Font = Enum.Font.SourceSansBold
resizeHandle.TextSize = 16
resizeHandle.BorderSizePixel = 0
resizeHandle.ZIndex = 15
resizeHandle.Parent = mainFrame

local rhCorner = Instance.new("UICorner")
rhCorner.CornerRadius = UDim.new(0, 6)
rhCorner.Parent = resizeHandle

local resizing = false
local resizeStartMouse, resizeStartSize

resizeHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        resizing = true
        resizeStartMouse = input.Position
        resizeStartSize = mainFrame.AbsoluteSize
        resizeHandle.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
    end
end)

resizeHandle.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        resizing = false
        resizeHandle.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
        savedSize.width = mainFrame.AbsoluteSize.X
        savedSize.height = mainFrame.AbsoluteSize.Y
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - resizeStartMouse
        local newWidth  = math.max(320, resizeStartSize.X + delta.X)
        local newHeight = math.max(400, resizeStartSize.Y + delta.Y)

        mainFrame.Size = UDim2.new(0, newWidth, 0, newHeight)

        local ratioMain = 300 / 480
        local ratioNot  = 800 / 480
        scrollMain.CanvasSize = UDim2.new(0, 0, 0, newHeight * ratioMain)
        scrollNot.CanvasSize  = UDim2.new(0, 0, 0, newHeight * ratioNot)
    end
end)

resizeHandle.MouseEnter:Connect(function()
    if not resizing then resizeHandle.BackgroundColor3 = Color3.fromRGB(70, 70, 90) end
end)

resizeHandle.MouseLeave:Connect(function()
    if not resizing then resizeHandle.BackgroundColor3 = Color3.fromRGB(50, 50, 60) end
end)

task.delay(0.1, function()
    if savedSize.width and savedSize.height then
        mainFrame.Size = UDim2.new(0, savedSize.width, 0, savedSize.height)
        scrollMain.CanvasSize = UDim2.new(0, 0, 0, savedSize.height * (300/480))
        scrollNot.CanvasSize  = UDim2.new(0, 0, 0, savedSize.height * (800/480))
    end
end)

-- Titlebar, minimize, bubble, drag, tabs, scroll frames (unchanged)
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1,0,0,36)
titleBar.BackgroundTransparency = 1
titleBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1,-70,1,0)
titleLabel.Position = UDim2.fromOffset(12,0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "LBB Hub"
titleLabel.TextColor3 = Color3.fromRGB(225,225,235)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 15
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0,32,0,32)
closeBtn.Position = UDim2.new(1,-38,0,2)
closeBtn.BackgroundColor3 = Color3.fromRGB(185,45,45)
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,8)
closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

local bubble = Instance.new("TextButton")
bubble.Size = UDim2.fromOffset(48,48)
bubble.Position = mainFrame.Position
bubble.BackgroundColor3 = Color3.fromRGB(24,24,32)
bubble.Text = "LBB"
bubble.TextColor3 = Color3.fromRGB(225,225,235)
bubble.Font = Enum.Font.GothamBold
bubble.TextSize = 14
bubble.Visible = false
bubble.Parent = sg
Instance.new("UICorner", bubble).CornerRadius = UDim.new(1,0)

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.fromOffset(30,30)
minimizeButton.Position = UDim2.new(1,-74,0,3)
minimizeButton.BackgroundColor3 = Color3.fromRGB(40,40,40)
minimizeButton.Text = "-"
minimizeButton.TextColor3 = Color3.new(1,1,1)
minimizeButton.Font = Enum.Font.SourceSansBold
minimizeButton.TextSize = 20
minimizeButton.Parent = titleBar
Instance.new("UICorner", minimizeButton).CornerRadius = UDim.new(0,6)

minimizeButton.MouseButton1Click:Connect(function()
    bubble.Position = mainFrame.Position
    mainFrame.Visible = false
    bubble.Visible = true
end)

bubble.MouseButton1Click:Connect(function()
    mainFrame.Position = bubble.Position
    bubble.Visible = false
    mainFrame.Visible = true
end)

-- Dragging main frame
do
    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    titleBar.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- Dragging bubble
do
    local dragging, dragStart, startPos
    bubble.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = bubble.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    bubble.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            bubble.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- Tabs & scroll
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1,0,0,34)
tabBar.Position = UDim2.new(0,0,0,36)
tabBar.BackgroundColor3 = Color3.fromRGB(18,18,22)
tabBar.BorderSizePixel = 0
tabBar.Parent = mainFrame

local tabMain = Instance.new("TextButton")
tabMain.Size = UDim2.new(0.5,0,1,0)
tabMain.BackgroundTransparency = 1
tabMain.Text = "Main"
tabMain.TextColor3 = Color3.fromRGB(110,170,255)
tabMain.Font = Enum.Font.GothamSemibold
tabMain.TextSize = 13
tabMain.Parent = tabBar

local tabNotSAB = Instance.new("TextButton")
tabNotSAB.Size = UDim2.new(0.5,0,1,0)
tabNotSAB.Position = UDim2.new(0.5,0,0,0)
tabNotSAB.BackgroundTransparency = 1
tabNotSAB.Text = "NOT FOR SAB!"
tabNotSAB.TextColor3 = Color3.fromRGB(170,170,180)
tabNotSAB.Font = Enum.Font.GothamSemibold
tabNotSAB.TextSize = 13
tabNotSAB.Parent = tabBar

local scrollMain = Instance.new("ScrollingFrame")
scrollMain.Size = UDim2.new(1,-16,1,-84)
scrollMain.Position = UDim2.new(0,8,0,78)
scrollMain.BackgroundTransparency = 1
scrollMain.ScrollBarThickness = 4
scrollMain.CanvasSize = UDim2.new(0,0,0,300)
scrollMain.Parent = mainFrame

local layoutMain = Instance.new("UIListLayout")
layoutMain.Padding = UDim.new(0,8)
layoutMain.SortOrder = Enum.SortOrder.LayoutOrder
layoutMain.Parent = scrollMain

local scrollNot = Instance.new("ScrollingFrame")
scrollNot.Size = UDim2.new(1,-16,1,-84)
scrollNot.Position = UDim2.new(0,8,0,78)
scrollNot.BackgroundTransparency = 1
scrollNot.ScrollBarThickness = 4
scrollNot.CanvasSize = UDim2.new(0,0,0,800)
scrollNot.Visible = false
scrollNot.Parent = mainFrame

local layoutNot = Instance.new("UIListLayout")
layoutNot.Padding = UDim.new(0,8)
layoutNot.SortOrder = Enum.SortOrder.LayoutOrder
layoutNot.Parent = scrollNot

local function switch(toMain)
    scrollMain.Visible = toMain
    scrollNot.Visible = not toMain
    tabMain.TextColor3 = toMain and Color3.fromRGB(110,170,255) or Color3.fromRGB(170,170,180)
    tabNotSAB.TextColor3 = toMain and Color3.fromRGB(170,170,180) or Color3.fromRGB(110,170,255)
end

tabMain.MouseButton1Click:Connect(function() switch(true) end)
tabNotSAB.MouseButton1Click:Connect(function() switch(false) end)

-- Toggle & action helpers
local toggleUpdateFns = {}
local function createToggle(parent, labelText, stateKey, onToggleImmediate)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,46)
    btn.BackgroundColor3 = Color3.fromRGB(24,24,32)
    btn.TextColor3 = Color3.fromRGB(215,215,225)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 14
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = parent
    local pad = Instance.new("UIPadding", btn)
    pad.PaddingLeft = UDim.new(0,16)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,9)

    local function update()
        btn.Text = labelText .. " " .. (state[stateKey] and "[ON]" or "[OFF]")
        btn.BackgroundColor3 = state[stateKey] and Color3.fromRGB(28,44,70) or Color3.fromRGB(24,24,32)
    end
    update()
    btn.MouseButton1Click:Connect(function()
        local wasOn = state[stateKey]
        state[stateKey] = not state[stateKey]
        if stateKey == "speedEnabled" and state[stateKey] then state.customSpeedEnabled = false end
        if stateKey == "customSpeedEnabled" and state[stateKey] then state.speedEnabled = false end

        if onToggleImmediate then onToggleImmediate(state[stateKey]) end

        if not state[stateKey] and wasOn then
            if (stateKey == "speedEnabled" or stateKey == "customSpeedEnabled") and currentHumanoid then
                currentHumanoid.WalkSpeed = DEFAULT_WALKSPEED
            end
            if stateKey == "customJumpEnabled" and currentHumanoid then
                currentHumanoid.JumpPower = DEFAULT_JUMPPOWER
            end
            if stateKey == "noclipEnabled" and character then
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = true end
                end
            end
            if stateKey == "flingEnabled" then
                stopFling()
            end
        end

        for _, fn in ipairs(toggleUpdateFns) do fn() end
    end)
    table.insert(toggleUpdateFns, update)
    return btn, update
end

local function createAction(parent, text, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,46)
    btn.BackgroundColor3 = Color3.fromRGB(24,24,32)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(215,215,225)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 14
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = parent
    local pad = Instance.new("UIPadding", btn)
    pad.PaddingLeft = UDim.new(0,16)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,9)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- MAIN TAB
createAction(scrollMain, "Use Everything", useEverything)

local keyBtn = Instance.new("TextButton")
keyBtn.Size = UDim2.new(1,0,0,46)
keyBtn.BackgroundColor3 = Color3.fromRGB(24,24,32)
keyBtn.Text = "Set Keybind (Current: " .. state.currentBind.Name .. ")"
keyBtn.TextColor3 = Color3.fromRGB(215,215,225)
keyBtn.Font = Enum.Font.GothamSemibold
keyBtn.TextSize = 14
keyBtn.TextXAlignment = Enum.TextXAlignment.Left
keyBtn.Parent = scrollMain
Instance.new("UICorner", keyBtn).CornerRadius = UDim.new(0,9)
local keyPad = Instance.new("UIPadding", keyBtn)
keyPad.PaddingLeft = UDim.new(0,16)

keyBtn.MouseButton1Click:Connect(function()
    state.waitingForKey = true
    keyBtn.Text = "Press key..."
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if state.waitingForKey and input.UserInputType == Enum.UserInputType.Keyboard then
        state.currentBind = input.KeyCode
        keyBtn.Text = "Set Keybind (Current: " .. state.currentBind.Name .. ")"
        state.waitingForKey = false
        return
    end
    if input.KeyCode == state.currentBind then
        useEverything()
    end
end)

createToggle(scrollMain, "Speed 27.7 (stealing)", "speedEnabled", function(enabled)
    if enabled and currentHumanoid then currentHumanoid.WalkSpeed = SPEED_27_7 end
end)

-- NOT FOR SAB tab
createToggle(scrollNot, "Custom Speed", "customSpeedEnabled", function(enabled)
    if enabled and currentHumanoid then currentHumanoid.WalkSpeed = state.customSpeedValue end
end)

createToggle(scrollNot, "Custom Jump", "customJumpEnabled", function(enabled)
    if enabled and currentHumanoid then currentHumanoid.JumpPower = state.customJumpValue end
end)

createToggle(scrollNot, "Fly", "flyEnabled", function() end)

createToggle(scrollNot, "Noclip", "noclipEnabled", function(enabled)
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = not enabled end
        end
    end
end)

createToggle(scrollNot, "Fling (spin + pulse)", "flingEnabled", function(enabled)
    if enabled then startFling() else stopFling() end
end)

-- Separate draggable TP window
createAction(scrollNot, "Teleport to Player", function()
    local tpGui = Instance.new("ScreenGui")
    tpGui.Name = "TPWindow"
    tpGui.ResetOnSpawn = false
    tpGui.Parent = PlayerGui

    local tpFrame = Instance.new("Frame")
    tpFrame.Size = UDim2.new(0, 340, 0, 420)
    tpFrame.Position = UDim2.new(0.5, -170, 0.5, -210)
    tpFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    tpFrame.BorderSizePixel = 0
    tpFrame.Parent = tpGui
    Instance.new("UICorner", tpFrame).CornerRadius = UDim.new(0, 14)

    local tpTitleBar = Instance.new("Frame")
    tpTitleBar.Size = UDim2.new(1,0,0,40)
    tpTitleBar.BackgroundColor3 = Color3.fromRGB(14,14,20)
    tpTitleBar.Parent = tpFrame

    local tpTitle = Instance.new("TextLabel")
    tpTitle.Size = UDim2.new(1,-50,1,0)
    tpTitle.BackgroundTransparency = 1
    tpTitle.Text = "Teleport to Player"
    tpTitle.TextColor3 = Color3.fromRGB(200,200,255)
    tpTitle.Font = Enum.Font.GothamBold
    tpTitle.TextSize = 18
    tpTitle.Parent = tpTitleBar

    local tpClose = Instance.new("TextButton")
    tpClose.Size = UDim2.new(0,36,0,36)
    tpClose.Position = UDim2.new(1,-42,0,2)
    tpClose.BackgroundColor3 = Color3.fromRGB(180,40,40)
    tpClose.Text = "×"
    tpClose.TextColor3 = Color3.new(1,1,1)
    tpClose.Font = Enum.Font.GothamBold
    tpClose.TextSize = 22
    tpClose.Parent = tpTitleBar
    Instance.new("UICorner", tpClose).CornerRadius = UDim.new(0,10)

    local tpScroll = Instance.new("ScrollingFrame")
    tpScroll.Size = UDim2.new(1,-20,1,-50)
    tpScroll.Position = UDim2.new(0,10,0,45)
    tpScroll.BackgroundTransparency = 1
    tpScroll.ScrollBarThickness = 6
    tpScroll.ScrollBarImageColor3 = Color3.fromRGB(90,90,110)
    tpScroll.Parent = tpFrame

    local tpLayout = Instance.new("UIListLayout")
    tpLayout.Padding = UDim.new(0,8)
    tpLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tpLayout.Parent = tpScroll

    local function fillList()
        for _, child in ipairs(tpScroll:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end

        local plist = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if isValidTarget(p) then table.insert(plist, p) end
        end
        table.sort(plist, function(a,b) return a.Name:lower() < b.Name:lower() end)

        for _, p in ipairs(plist) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1,0,0,48)
            btn.BackgroundColor3 = Color3.fromRGB(35,35,45)
            btn.Text = p.Name
            btn.TextColor3 = Color3.new(1,1,1)
            btn.Font = Enum.Font.GothamSemibold
            btn.TextSize = 20
            btn.TextScaled = true
            btn.Parent = tpScroll
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0,10)

            btn.MouseEnter:Connect(function()
                TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(55,55,70)}):Play()
            end)
            btn.MouseLeave:Connect(function()
                TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(35,35,45)}):Play()
            end)

            btn.MouseButton1Click:Connect(function()
                tpTo(p)
            end)
        end

        tpScroll.CanvasSize = UDim2.new(0,0,0, #plist * 56)
    end

    fillList()

    tpClose.MouseButton1Click:Connect(function()
        tpGui:Destroy()
    end)

    local dragging, dragStart, startPos
    tpTitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = tpFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    tpTitleBar.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            tpFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    task.delay(0.3, fillList)
end)

-- Custom speed (only textbox, no slider)
local speedFrame = Instance.new("Frame")
speedFrame.Size = UDim2.new(1,0,0,56)  -- Reduced height since no slider
speedFrame.BackgroundTransparency = 1
speedFrame.Parent = scrollNot

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0.6,0,0,24)
speedLabel.Position = UDim2.new(0.05,0,0,0)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Custom Speed: " .. math.floor(state.customSpeedValue)
speedLabel.TextColor3 = Color3.fromRGB(190,190,200)
speedLabel.Font = Enum.Font.Gotham
speedLabel.TextSize = 13
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = speedFrame

local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(0.3,0,0,30)
speedBox.Position = UDim2.new(0.65,0,0,0)
speedBox.BackgroundColor3 = Color3.fromRGB(24,24,32)
speedBox.TextColor3 = Color3.new(1,1,1)
speedBox.Font = Enum.Font.Gotham
speedBox.TextSize = 13
speedBox.Text = tostring(state.customSpeedValue)
speedBox.ClearTextOnFocus = false
speedBox.Parent = speedFrame
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0,8)

speedBox.FocusLost:Connect(function()
    local num = tonumber(speedBox.Text)
    if num then
        state.customSpeedValue = math.clamp(num, 1, 100000)
        speedLabel.Text = "Custom Speed: " .. state.customSpeedValue
        speedBox.Text = tostring(state.customSpeedValue)
        if currentHumanoid and state.customSpeedEnabled then
            currentHumanoid.WalkSpeed = state.customSpeedValue
        end
    else
        speedBox.Text = tostring(state.customSpeedValue)
    end
end)

-- Custom jump UI
local jumpFrame = Instance.new("Frame")
jumpFrame.Size = UDim2.new(1,0,0,56)
jumpFrame.BackgroundTransparency = 1
jumpFrame.Parent = scrollNot

local jumpLabel = Instance.new("TextLabel")
jumpLabel.Size = UDim2.new(0.6,0,0,24)
jumpLabel.Position = UDim2.new(0.05,0,0,0)
jumpLabel.BackgroundTransparency = 1
jumpLabel.Text = "Jump Power: " .. tostring(state.customJumpValue)
jumpLabel.TextColor3 = Color3.fromRGB(190,190,200)
jumpLabel.Font = Enum.Font.Gotham
jumpLabel.TextSize = 13
jumpLabel.TextXAlignment = Enum.TextXAlignment.Left
jumpLabel.Parent = jumpFrame

local jumpBox = Instance.new("TextBox")
jumpBox.Size = UDim2.new(0.3,0,0,30)
jumpBox.Position = UDim2.new(0.65,0,0,0)
jumpBox.BackgroundColor3 = Color3.fromRGB(24,24,32)
jumpBox.TextColor3 = Color3.new(1,1,1)
jumpBox.Font = Enum.Font.Gotham
jumpBox.TextSize = 13
jumpBox.Text = tostring(state.customJumpValue)
jumpBox.ClearTextOnFocus = false
jumpBox.Parent = jumpFrame
Instance.new("UICorner", jumpBox).CornerRadius = UDim.new(0,8)

jumpBox.FocusLost:Connect(function()
    local num = tonumber(jumpBox.Text)
    if num then
        state.customJumpValue = math.clamp(num, 1, 1000)
        jumpLabel.Text = "Jump Power: " .. tostring(state.customJumpValue)
        jumpBox.Text = tostring(state.customJumpValue)
        if currentHumanoid and state.customJumpEnabled then
            currentHumanoid.JumpPower = state.customJumpValue
        end
    else
        jumpBox.Text = tostring(state.customJumpValue)
    end
end)

-- Fly speed UI
local flyFrame = Instance.new("Frame")
flyFrame.Size = UDim2.new(1,0,0,56)
flyFrame.BackgroundTransparency = 1
flyFrame.Parent = scrollNot

local flyLabel = Instance.new("TextLabel")
flyLabel.Size = UDim2.new(0.6,0,0,24)
flyLabel.Position = UDim2.new(0.05,0,0,0)
flyLabel.BackgroundTransparency = 1
flyLabel.Text = "Fly Speed: " .. tostring(state.customFlySpeed)
flyLabel.TextColor3 = Color3.fromRGB(190,190,200)
flyLabel.Font = Enum.Font.Gotham
flyLabel.TextSize = 13
flyLabel.TextXAlignment = Enum.TextXAlignment.Left
flyLabel.Parent = flyFrame

local flyBox = Instance.new("TextBox")
flyBox.Size = UDim2.new(0.3,0,0,30)
flyBox.Position = UDim2.new(0.65,0,0,0)
flyBox.BackgroundColor3 = Color3.fromRGB(24,24,32)
flyBox.TextColor3 = Color3.new(1,1,1)
flyBox.Font = Enum.Font.Gotham
flyBox.TextSize = 13
flyBox.Text = tostring(state.customFlySpeed)
flyBox.ClearTextOnFocus = false
flyBox.Parent = flyFrame
Instance.new("UICorner", flyBox).CornerRadius = UDim.new(0,8)

flyBox.FocusLost:Connect(function()
    local num = tonumber(flyBox.Text)
    if num then
        state.customFlySpeed = math.clamp(num, 1, 1000000000)
        flyLabel.Text = "Fly Speed: " .. tostring(state.customFlySpeed)
        flyBox.Text = tostring(state.customFlySpeed)
    else
        flyBox.Text = tostring(state.customFlySpeed)
    end
end)

-- Reset All
createAction(scrollNot, "Reset All", function()
    state.speedEnabled = false
    state.customSpeedEnabled = false
    state.customJumpEnabled = false
    state.flyEnabled = false
    state.noclipEnabled = false
    state.flingEnabled = false
    stopFling()
    if currentHumanoid then
        currentHumanoid.WalkSpeed = DEFAULT_WALKSPEED
        currentHumanoid.JumpPower = DEFAULT_JUMPPOWER
    end
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
    for _, fn in ipairs(toggleUpdateFns) do fn() end
end)

-- Heartbeat
local bodyVelocity, bodyGyro
RunService.Heartbeat:Connect(function()
    if not currentHumanoid or currentHumanoid.Health <= 0 then
        if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
        if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
        return
    end

    if state.speedEnabled then
        currentHumanoid.WalkSpeed = SPEED_27_7
    elseif state.customSpeedEnabled then
        currentHumanoid.WalkSpeed = state.customSpeedValue
    end

    if state.customJumpEnabled then
        currentHumanoid.JumpPower = state.customJumpValue
    end

    if state.flyEnabled and currentRootPart then
        if not bodyVelocity then
            bodyVelocity = Instance.new("BodyVelocity")
            bodyVelocity.MaxForce = Vector3.new(1e6,1e6,1e6)
            bodyVelocity.Parent = currentRootPart
        end
        if not bodyGyro then
            bodyGyro = Instance.new("BodyGyro")
            bodyGyro.MaxTorque = Vector3.new(1e6,1e6,1e6)
            bodyGyro.P = 15000
            bodyGyro.Parent = currentRootPart
        end

        local moveDir = Vector3.new()
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += Vector3.new(0,0,-1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir += Vector3.new(0,0,1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir += Vector3.new(-1,0,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += Vector3.new(1,0,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir += Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir += Vector3.new(0,-1,0) end

        local cam = workspace.CurrentCamera
        if cam then
            local worldMove = cam.CFrame:VectorToWorldSpace(moveDir) * state.customFlySpeed
            bodyVelocity.Velocity = worldMove
            bodyGyro.CFrame = cam.CFrame
        end
    else
        if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
        if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
    end

    if state.noclipEnabled and character then
        for _, p in ipairs(character:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end
end)

print("LBB Hub loaded | Custom speed now textbox-only | UI resize handle active")
