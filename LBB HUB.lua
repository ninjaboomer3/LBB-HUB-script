-- LocalScript (full, drop-in replacement)
-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Single source of truth
local state = {
    currentBind = Enum.KeyCode.Q,
    waitingForKey = false,

    speedEnabled = false,         -- sets WalkSpeed to SPEED_27_7
    customSpeedEnabled = false,   -- sets WalkSpeed to customSpeedValue
    customSpeedValue = 27.7,

    customJumpEnabled = false,    -- sets JumpPower to customJumpValue
    customJumpValue = 50,         -- MAX now 1000

    flyEnabled = false,
    noclipEnabled = false,
    customFlySpeed = 65,          -- NEW: adjustable fly speed
}

local SPEED_27_7 = 27.7

-- Character / humanoid refs
local currentHumanoid = nil
local currentRootPart = nil
local character = nil

local function hookHumanoid(char)
    character = char
    currentHumanoid = nil
    currentRootPart = nil
    if not char then return end

    -- wait for humanoid and rootpart safely
    currentHumanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
    currentRootPart = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")

    -- apply only if toggles are active (do NOT force defaults otherwise)
    if currentHumanoid then
        if state.speedEnabled then currentHumanoid.WalkSpeed = SPEED_27_7 end
        if state.customSpeedEnabled then currentHumanoid.WalkSpeed = state.customSpeedValue end
        if state.customJumpEnabled then currentHumanoid.JumpPower = state.customJumpValue end
    end

    -- apply noclip immediately if active
    if state.noclipEnabled then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end

    -- ensure new parts added after spawn follow noclip state
    char.DescendantAdded:Connect(function(desc)
        if desc:IsA("BasePart") then
            if state.noclipEnabled then
                desc.CanCollide = false
            else
                -- don't forcibly restore if part added while noclip is off;
                -- restoring collisions on off is handled by toggle action itself.
            end
        end
    end)
end

if player.Character then hookHumanoid(player.Character) end
player.CharacterAdded:Connect(hookHumanoid)

-- Tools
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
            if type(t.Activate) == "function" then
                t:Activate()
            end
        end)
    end
end

-- UI creation (cleaned)
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

-- titlebar (with drag)
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

-- minimize circle (hidden until minimized)
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

-- minimize button
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

-- dragging for mainFrame (manual)
do
    local dragging, dragStart, startPos
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
end

-- dragging for bubble
do
    local dragging, dragStart, startPos
    bubble.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = bubble.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    bubble.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            bubble.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- Tabs
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
scrollNot.CanvasSize = UDim2.new(0,0,0,500)
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

-- Toggle & action creators
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
        btn.Text = labelText .. "   " .. (state[stateKey] and "[ON]" or "[OFF]")
        btn.BackgroundColor3 = state[stateKey] and Color3.fromRGB(28,44,70) or Color3.fromRGB(24,24,32)
    end
    update()

    btn.MouseButton1Click:Connect(function()
        state[stateKey] = not state[stateKey]

        -- exclusivity: speed & customSpeed
        if stateKey == "speedEnabled" and state[stateKey] then state.customSpeedEnabled = false end
        if stateKey == "customSpeedEnabled" and state[stateKey] then state.speedEnabled = false end

        -- immediate on-toggle behavior (do NOT force defaults on OFF)
        if onToggleImmediate then
            onToggleImmediate(state[stateKey])
        end

        -- refresh all toggle visuals
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

-- MAIN TAB items
createAction(scrollMain, "Use Everything", useEverything)

-- Keybind button
local keyBtn = Instance.new("TextButton")
keyBtn.Size = UDim2.new(1,0,0,46)
keyBtn.BackgroundColor3 = Color3.fromRGB(24,24,32)
keyBtn.Text = "Set Keybind   (Current: " .. state.currentBind.Name .. ")"
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if state.waitingForKey and input.UserInputType == Enum.UserInputType.Keyboard then
        state.currentBind = input.KeyCode
        keyBtn.Text = "Set Keybind   (Current: " .. state.currentBind.Name .. ")"
        state.waitingForKey = false
        return
    end
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == state.currentBind then
        useEverything()
    end
end)

-- main speed 27.7 toggle
createToggle(scrollMain, "Speed 27.7 (stealing)", "speedEnabled", function(enabled)
    if enabled then
        if currentHumanoid then currentHumanoid.WalkSpeed = SPEED_27_7 end
    end
end)

-- NOT FOR SAB tab toggles
createToggle(scrollNot, "Custom Speed", "customSpeedEnabled", function(enabled)
    if enabled then
        if currentHumanoid then currentHumanoid.WalkSpeed = state.customSpeedValue end
    end
end)

createToggle(scrollNot, "Custom Jump", "customJumpEnabled", function(enabled)
    if enabled then
        if currentHumanoid then currentHumanoid.JumpPower = state.customJumpValue end
    end
end)

-- noclip immediate handler
local function updateNoclip()
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = not state.noclipEnabled
        end
    end
end

createToggle(scrollNot, "Fly", "flyEnabled", function(enabled)
    -- no immediate forced behavior needed here; heartbeat will set BodyVelocity when enabled
end)

createToggle(scrollNot, "Noclip", "noclipEnabled", function(enabled)
    -- apply immediately ON or OFF
    updateNoclip()
end)

-- Reset All (clear toggles, visuals, and remove fly bodies; intentionally does NOT force WalkSpeed/JumpPower)
createAction(scrollNot, "Reset All", function()
    state.speedEnabled = false
    state.customSpeedEnabled = false
    state.customJumpEnabled = false
    state.flyEnabled = false
    state.noclipEnabled = false

    -- refresh toggle visuals
    for _, fn in ipairs(toggleUpdateFns) do fn() end
end)

-- Custom speed UI (slider + textbox)
local speedFrame = Instance.new("Frame")
speedFrame.Size = UDim2.new(1,0,0,84)
speedFrame.BackgroundTransparency = 1
speedFrame.Parent = scrollNot

local sliderBg = Instance.new("Frame")
sliderBg.Size = UDim2.new(0.9,0,0,8)
sliderBg.Position = UDim2.new(0.05,0,0,34)
sliderBg.BackgroundColor3 = Color3.fromRGB(30,30,38)
sliderBg.Parent = speedFrame
Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(1,0)

local sliderFill = Instance.new("Frame")
sliderFill.Size = UDim2.new(state.customSpeedValue/1000,0,1,0)
sliderFill.BackgroundColor3 = Color3.fromRGB(80,130,255)
sliderFill.BorderSizePixel = 0
sliderFill.Parent = sliderBg
Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1,0)

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0.5,0,0,24)
speedLabel.Position = UDim2.new(0.05,0,0,0)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Custom Speed: " .. math.floor(state.customSpeedValue)
speedLabel.TextColor3 = Color3.fromRGB(190,190,200)
speedLabel.Font = Enum.Font.Gotham
speedLabel.TextSize = 13
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = speedFrame

local draggingSlider = false
sliderBg.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingSlider = true end
end)
sliderBg.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingSlider = false end
end)
UserInputService.InputChanged:Connect(function(input)
    if draggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
        local rel = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
        sliderFill.Size = UDim2.new(rel, 0, 1, 0)
        state.customSpeedValue = math.floor(rel * 100000 + 0.5)
        speedLabel.Text = "Custom Speed: " .. state.customSpeedValue
        if currentHumanoid and state.customSpeedEnabled then
            currentHumanoid.WalkSpeed = state.customSpeedValue
        end
    end
end)

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
        sliderFill.Size = UDim2.new(state.customSpeedValue/100000, 0, 1, 0)
        speedLabel.Text = "Custom Speed: " .. state.customSpeedValue
        speedBox.Text = tostring(state.customSpeedValue)
        if currentHumanoid and state.customSpeedEnabled then
            currentHumanoid.WalkSpeed = state.customSpeedValue
        end
    else
        speedBox.Text = tostring(state.customSpeedValue)
    end
end)

-- Custom jump UI (simple textbox + toggle exists above)
local jumpFrame = Instance.new("Frame")
jumpFrame.Size = UDim2.new(1,0,0,56)
jumpFrame.BackgroundTransparency = 1
jumpFrame.Parent = scrollNot

local jumpLabel = Instance.new("TextLabel")
jumpLabel.Size = UDim2.new(0.5,0,0,24)
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
        state.customJumpValue = math.clamp(num, 1, 1000)  -- MAX jump 1000 now
        jumpLabel.Text = "Jump Power: " .. tostring(state.customJumpValue)
        jumpBox.Text = tostring(state.customJumpValue)
        if currentHumanoid and state.customJumpEnabled then
            currentHumanoid.JumpPower = state.customJumpValue
        end
    else
        jumpBox.Text = tostring(state.customJumpValue)
    end
end)

-- NEW: Custom Fly Speed UI
local flyFrame = Instance.new("Frame")
flyFrame.Size = UDim2.new(1,0,0,56)
flyFrame.BackgroundTransparency = 1
flyFrame.Parent = scrollNot

local flyLabel = Instance.new("TextLabel")
flyLabel.Size = UDim2.new(0.5,0,0,24)
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

-- Heartbeat: apply fly, enforce noclip while active, and apply speeds/jumps only while toggles active
local bodyVelocity, bodyGyro
RunService.Heartbeat:Connect(function()
    -- clean when no humanoid
    if not currentHumanoid or currentHumanoid.Health <= 0 then
        if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
        if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
        return
    end

    -- Speed handling: only write when toggles active (do NOT force defaults otherwise)
    if state.speedEnabled then
        if currentHumanoid.WalkSpeed ~= SPEED_27_7 then currentHumanoid.WalkSpeed = SPEED_27_7 end
    elseif state.customSpeedEnabled then
        if currentHumanoid.WalkSpeed ~= state.customSpeedValue then currentHumanoid.WalkSpeed = state.customSpeedValue end
    end

    -- Jump handling: only when customJumpEnabled
    if state.customJumpEnabled then
        if currentHumanoid.JumpPower ~= state.customJumpValue then currentHumanoid.JumpPower = state.customJumpValue end
    end

    -- Fly handling
    if state.flyEnabled and currentRootPart then
        if not bodyVelocity then
            bodyVelocity = Instance.new("BodyVelocity")
            bodyVelocity.MaxForce = Vector3.new(1e6,1e6,1e6)
            bodyVelocity.Velocity = Vector3.new()
            bodyVelocity.Parent = currentRootPart
        end
        if not bodyGyro then
            bodyGyro = Instance.new("BodyGyro")
            bodyGyro.MaxTorque = Vector3.new(1e6,1e6,1e6)
            bodyGyro.P = 15000
            bodyGyro.Parent = currentRootPart
        end

        local moveDir = Vector3.new()
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Vector3.new(0,0,-1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir + Vector3.new(0,0,1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir + Vector3.new(-1,0,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Vector3.new(1,0,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir + Vector3.new(0,-1,0) end

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

    -- Noclip enforcement while enabled (keeps new/renamed parts handled)
    if state.noclipEnabled and character then
        for _, p in ipairs(character:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                p.CanCollide = false
            end
        end
    end
end)
