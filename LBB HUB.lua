-- LBB Hub v5
-- + Fixed hitbox (floating SelectionBox around each player, updated every frame)
-- + Anti-detection: CoreGui/gethui protection, randomised names, metamethod bypass,
--   anti-kick hook, speed/jump property bypass, local-only part hiding

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local RS           = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TpService    = game:GetService("TeleportService")
local Lighting     = game:GetService("Lighting")
local HttpService  = game:GetService("HttpService")
local CoreGui      = game:GetService("CoreGui")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════
--  BYPASS / ANTI-DETECTION
-- ═══════════════════════════════════════════════

-- Random string for naming instances so scanners can't find them by name
local function rname()
    local s = {}
    local pool = "abcdefghijklmnopqrstuvwxyz0123456789"
    for _ = 1, math.random(10, 18) do
        local i = math.random(1, #pool)
        s[#s+1] = pool:sub(i, i)
    end
    return table.concat(s)
end

-- Protected GUI parent: tries syn → gethui → CoreGui → PlayerGui
local function safeParent(gui)
    gui.Name = rname()
    if syn and syn.protect_gui then
        pcall(syn.protect_gui, gui)
        pcall(function() gui.Parent = CoreGui end)
    elseif gethui then
        pcall(function() gui.Parent = gethui() end)
    else
        pcall(function() gui.Parent = CoreGui end)
        if not gui.Parent or gui.Parent == nil then
            gui.Parent = PlayerGui
        end
    end
end

-- Metamethod property bypass: set properties through rawset to dodge __newindex hooks
-- Falls back gracefully if executor doesn't support getrawmetatable
local bypassSet
do
    local ok, mt = pcall(getrawmetatable, game)
    if ok and mt then
        local ro = pcall(setreadonly, mt, false) -- some executors expose this
        local oldNI = rawget(mt, "__newindex")
        if oldNI then
            bypassSet = function(obj, prop, val)
                -- call original __newindex directly, bypassing any game hook layered on top
                pcall(oldNI, obj, prop, val)
            end
            if ro then pcall(setreadonly, mt, true) end
        end
    end
    -- safe fallback
    if not bypassSet then
        bypassSet = function(obj, prop, val)
            pcall(function() obj[prop] = val end)
        end
    end
end

-- Anti-kick hook: silently swallow Kick calls on the local player
pcall(function()
    local mt = getrawmetatable(game)
    pcall(setreadonly, mt, false)
    local oldNC = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "Kick" and self == player then
            return -- swallow kick
        end
        return oldNC(self, ...)
    end)
    pcall(setreadonly, mt, true)
end)

-- Safe property setter for humanoid values (wraps bypass)
local function setProp(obj, prop, val)
    if not obj then return end
    bypassSet(obj, prop, val)
end

-- ═══════════════════════════════════════════════
--  CONFIG PERSISTENCE
-- ═══════════════════════════════════════════════
local CONFIG_PATH = "LBBHub_" .. tostring(player.UserId) .. ".json"

local state = {
    currentBind       = Enum.KeyCode.Q,
    waitingForKey     = false,
    speedEnabled      = false,
    customSpeedEnabled= false,
    customSpeedValue  = 27.7,
    configSpeedEnabled= false,
    customJumpEnabled = false,
    customJumpValue   = 50,
    flyEnabled        = false,
    noclipEnabled     = false,
    customFlySpeed    = 65,
    flingEnabled      = false,
    infiniteJumpEnabled = false,
    noFallDamage      = false,
    fullbright        = false,
    playerESP         = false,
    autoRejoin        = false,
    checkpointPos     = nil,
    checkpointIndicator = nil,
    checkpointKeybind = nil,
    floatEnabled      = false,
    antiRagdollEnabled= false,
    autoBatEnabled    = false,
    noAnimEnabled     = false,
    walkFlingEnabled  = false,
    spinEnabled       = false,
    floatUpEnabled    = false,
    aimbotEnabled     = false,
    hitboxEnabled     = false,
    autoGrabEnabled   = false,
    tallHipsEnabled   = false,
    medusaCounterEnabled = false,
    misplaceEnabled   = false,
    invisEnabled      = false,
    autoPlayEnabled   = false,
    configSpeed       = 58,
    configSteal       = 29,
    configJump        = 10,
    originalTransparencies = {},
}

local SAVEABLE = {
    "speedEnabled","customSpeedEnabled","customSpeedValue","configSpeedEnabled",
    "customJumpEnabled","customJumpValue","flyEnabled","noclipEnabled","customFlySpeed",
    "flingEnabled","infiniteJumpEnabled","noFallDamage","fullbright","playerESP",
    "autoRejoin","floatEnabled","antiRagdollEnabled","autoBatEnabled","noAnimEnabled",
    "walkFlingEnabled","spinEnabled","floatUpEnabled","aimbotEnabled","hitboxEnabled",
    "autoGrabEnabled","tallHipsEnabled","medusaCounterEnabled","misplaceEnabled",
    "invisEnabled","autoPlayEnabled","configSpeed","configSteal","configJump","currentBind",
}

local function saveConfig()
    local cfg = {}
    for _, k in ipairs(SAVEABLE) do
        cfg[k] = (k == "currentBind") and state[k].Name or state[k]
    end
    pcall(writefile, CONFIG_PATH, HttpService:JSONEncode(cfg))
end

local function loadConfig()
    local ok, raw = pcall(readfile, CONFIG_PATH)
    if not ok or not raw or raw == "" then return end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(data) ~= "table" then return end
    for _, k in ipairs(SAVEABLE) do
        if data[k] ~= nil then
            if k == "currentBind" then
                local kc = Enum.KeyCode[data[k]]
                if kc then state.currentBind = kc end
            else
                state[k] = data[k]
            end
        end
    end
end
loadConfig()

-- ═══════════════════════════════════════════════
--  CONSTANTS / REFS
-- ═══════════════════════════════════════════════
local SPEED_277       = 27.7
local DEFAULT_SPEED   = 16
local DEFAULT_JUMP    = 50
local TALL_HIP_OFFSET = 2.0

local currentHumanoid  = nil
local currentRootPart  = nil
local character        = nil
local animateScript    = nil
local trueHipHeight    = 2   -- set once per spawn, never touched by toggles

local antiRagdollConns = {}

-- ═══════════════════════════════════════════════
--  HITBOX SYSTEM  (floating visual boxes, client-only)
-- ═══════════════════════════════════════════════
-- Each entry: { box=Part, sel=SelectionBox }
local hitboxObjects = {}   -- [Player] = { box, sel }

local function clearHitboxes()
    for p, obj in pairs(hitboxObjects) do
        pcall(obj.box.Destroy, obj.box)
        hitboxObjects[p] = nil
    end
end

local function ensureHitbox(p)
    if hitboxObjects[p] then return end
    local root = p.Character and (p.Character:FindFirstChild("HumanoidRootPart") or p.Character:FindFirstChild("Torso"))
    if not root then return end

    -- Floating Part (local, CanCollide=false, not replicated server-side when made in LocalScript)
    local box = Instance.new("Part")
    box.Name        = rname()
    box.Size        = Vector3.new(14, 14, 14)
    box.Anchored    = true          -- anchored so we reposition it manually each frame
    box.CanCollide  = false
    box.CanQuery    = false
    box.CanTouch    = false
    box.Transparency = 0.78
    box.BrickColor  = BrickColor.new("Bright red")
    box.Material    = Enum.Material.Neon
    box.CastShadow  = false
    box.CFrame      = root.CFrame  -- initial position
    box.Parent      = workspace

    -- SelectionBox outline on top
    local sel = Instance.new("SelectionBox")
    sel.Name               = rname()
    sel.Adornee            = box
    sel.Color3             = Color3.fromRGB(255, 40, 40)
    sel.LineThickness       = 0.06
    sel.SurfaceTransparency = 1        -- hide fill, keep outline
    sel.SurfaceColor3      = Color3.fromRGB(255, 40, 40)
    sel.Parent             = workspace

    hitboxObjects[p] = { box = box, sel = sel }
end

local function updateHitboxPositions()
    for p, obj in pairs(hitboxObjects) do
        -- Remove if player left / died / invalid
        if not p or not p.Parent or not p.Character then
            pcall(obj.box.Destroy, obj.box)
            hitboxObjects[p] = nil
        else
            local root = p.Character:FindFirstChild("HumanoidRootPart")
                      or p.Character:FindFirstChild("Torso")
            if root then
                -- Float the box exactly at the player's root, centred on their body
                obj.box.CFrame = root.CFrame
            else
                pcall(obj.box.Destroy, obj.box)
                hitboxObjects[p] = nil
            end
        end
    end
end

local function refreshHitboxes()
    if not state.hitboxEnabled then clearHitboxes(); return end

    -- Add missing
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local hum = p.Character and p.Character:FindFirstChildWhichIsA("Humanoid")
            if hum and hum.Health > 0 then
                ensureHitbox(p)
            end
        end
    end

    -- Remove stale
    for p, obj in pairs(hitboxObjects) do
        local hum = p.Character and p.Character:FindFirstChildWhichIsA("Humanoid")
        if not hum or hum.Health <= 0 or not p.Parent then
            pcall(obj.box.Destroy, obj.box)
            hitboxObjects[p] = nil
        end
    end
end

-- ═══════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════
local function getAllTools()
    local t = {}
    local bp = player:FindFirstChild("Backpack")
    if bp then for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") then t[#t+1]=v end end end
    if player.Character then for _,v in ipairs(player.Character:GetChildren()) do if v:IsA("Tool") then t[#t+1]=v end end end
    return t
end

local function useEverything()
    for _,t in ipairs(getAllTools()) do
        pcall(function() t.Parent = player.Character; if t.Activate then t:Activate() end end)
    end
end

local function getRoot(char)
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function isValidTarget(p)
    if p == player then return false end
    local char = p.Character; if not char then return false end
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    return hum and hum.Health > 0
end

local function tpTo(target)
    local mr = getRoot(player.Character); local tr = getRoot(target.Character)
    if mr and tr then mr.CFrame = tr.CFrame * CFrame.new(0,5,0) end
end

local function getNearestPlayer()
    if not currentRootPart then return nil end
    local best, bestD = nil, math.huge
    for _,p in ipairs(Players:GetPlayers()) do
        if isValidTarget(p) then
            local r = getRoot(p.Character)
            if r then
                local d = (r.Position - currentRootPart.Position).Magnitude
                if d < bestD then bestD=d; best=r end
            end
        end
    end
    return best
end

local function stopAllAnims()
    if not currentHumanoid then return end
    local anim = currentHumanoid:FindFirstChildOfClass("Animator")
    if not anim then return end
    for _, track in ipairs(anim:GetPlayingAnimationTracks()) do track:Stop(0) end
end

-- ═══════════════════════════════════════════════
--  ANTI RAGDOLL
-- ═══════════════════════════════════════════════
local function applyAntiRagdoll(char)
    for _,c in ipairs(antiRagdollConns) do c:Disconnect() end
    antiRagdollConns = {}
    if not char then return end

    local function fix()
        for _,v in ipairs(char:GetDescendants()) do
            if v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint") then v.Enabled = false end
            if v:IsA("Motor6D") then v.Enabled = true end
        end
    end
    fix()

    antiRagdollConns[#antiRagdollConns+1] = char.DescendantAdded:Connect(function(d)
        if not state.antiRagdollEnabled then return end
        if d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint") then d.Enabled = false end
        if d:IsA("Motor6D") then d.Enabled = true end
    end)

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        antiRagdollConns[#antiRagdollConns+1] = hum.StateChanged:Connect(function(_, new)
            if not state.antiRagdollEnabled then return end
            if new == Enum.HumanoidStateType.Ragdoll
            or new == Enum.HumanoidStateType.FallingDown
            or new == Enum.HumanoidStateType.Physics then
                fix()
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end)
    end
end

-- ═══════════════════════════════════════════════
--  MEDUSA COUNTER
-- ═══════════════════════════════════════════════
local medusaCooldown = false
local function tryMedusa()
    if medusaCooldown then return end
    for _,t in ipairs(getAllTools()) do
        if t.Name:lower():find("medusa") then
            medusaCooldown = true
            pcall(function() t.Parent = player.Character; task.wait(0.05); if t.Activate then t:Activate() end end)
            task.delay(1.5, function() medusaCooldown = false end)
            return
        end
    end
end

local medusaDescConn, medusaStateConn
local function hookMedusa(char)
    if medusaDescConn then medusaDescConn:Disconnect() end
    if medusaStateConn then medusaStateConn:Disconnect() end
    if not char then return end

    medusaDescConn = char.DescendantAdded:Connect(function(d)
        if not state.medusaCounterEnabled then return end
        local n = d.Name:lower()
        if n:find("stone") or n:find("petrif") or n:find("medusa") or n:find("frozen") or n:find("stun") then
            task.spawn(function() task.wait(0.05); tryMedusa(); pcall(d.Destroy, d) end)
        end
    end)

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        medusaStateConn = hum.StateChanged:Connect(function(_, new)
            if not state.medusaCounterEnabled then return end
            if new == Enum.HumanoidStateType.Physics then tryMedusa() end
        end)
    end
end

-- ═══════════════════════════════════════════════
--  CHARACTER HOOK
-- ═══════════════════════════════════════════════
local function hookCharacter(char)
    character        = char
    currentHumanoid  = nil
    currentRootPart  = nil
    animateScript    = nil
    state.originalTransparencies = {}

    if not char then return end
    currentHumanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    currentRootPart = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
    animateScript   = char:FindFirstChild("Animate")

    if currentHumanoid then trueHipHeight = currentHumanoid.HipHeight end

    -- Re-apply active states
    if state.speedEnabled       then setProp(currentHumanoid,"WalkSpeed",SPEED_277) end
    if state.customSpeedEnabled then setProp(currentHumanoid,"WalkSpeed",state.customSpeedValue) end
    if state.configSpeedEnabled then setProp(currentHumanoid,"WalkSpeed",state.configSpeed) end
    if state.customJumpEnabled  then setProp(currentHumanoid,"JumpPower",state.customJumpValue) end
    if state.tallHipsEnabled    then setProp(currentHumanoid,"HipHeight",trueHipHeight + TALL_HIP_OFFSET) end
    if state.noAnimEnabled and animateScript then animateScript.Disabled = true end
    if state.noclipEnabled then
        for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end
    end
    if state.invisEnabled then
        for _,p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") or p:IsA("Decal") then
                state.originalTransparencies[p] = p.LocalTransparencyModifier
                p.LocalTransparencyModifier = 1
            end
        end
    end
    if state.antiRagdollEnabled then applyAntiRagdoll(char) end

    hookMedusa(char)

    char.DescendantAdded:Connect(function(d)
        if d.Name == "Animate" then animateScript = d; if state.noAnimEnabled then d.Disabled = true end end
        if d:IsA("BasePart") then
            if state.noclipEnabled  then d.CanCollide = false end
            if state.invisEnabled   then d.LocalTransparencyModifier = 1 end
        end
    end)
end

if player.Character then hookCharacter(player.Character) end
player.CharacterAdded:Connect(function(char)
    hookCharacter(char)
    task.wait(1.2)
    if state.flingEnabled then startFling() end
    if state.checkpointPos then task.delay(0.5, setCheckpoint) end
end)

-- ═══════════════════════════════════════════════
--  CHECKPOINT
-- ═══════════════════════════════════════════════
local checkpointWaitingForKey = false

function setCheckpoint()
    if not currentRootPart then return end
    state.checkpointPos = currentRootPart.Position
    if state.checkpointIndicator then state.checkpointIndicator:Destroy(); state.checkpointIndicator = nil end

    local part = Instance.new("Part")
    part.Name = rname(); part.Size = Vector3.new(1,1,1); part.Position = state.checkpointPos
    part.Anchored = true; part.CanCollide = false; part.Transparency = 1; part.Parent = workspace

    local bb = Instance.new("BillboardGui")
    bb.Adornee = part; bb.Size = UDim2.new(0,140,0,50); bb.StudsOffset = Vector3.new(0,4,0)
    bb.AlwaysOnTop = true; bb.Parent = part

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.Text = "✦ Checkpoint"
    lbl.TextColor3 = Color3.fromRGB(0,255,150); lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 20; lbl.Parent = bb

    local glow = Instance.new("PointLight")
    glow.Color = Color3.fromRGB(0,255,150); glow.Brightness = 3; glow.Range = 20; glow.Parent = part

    state.checkpointIndicator = part
end

local function teleportToCheckpoint()
    if state.checkpointPos and currentRootPart then
        currentRootPart.CFrame = CFrame.new(state.checkpointPos + Vector3.new(0,5,0))
    end
end

-- ═══════════════════════════════════════════════
--  FLING (self)
-- ═══════════════════════════════════════════════
local flingConn = nil
function startFling()
    if flingConn then return end
    flingConn = RS.Heartbeat:Connect(function()
        if not currentRootPart or not currentRootPart.Parent then return end
        local sc = currentRootPart.CFrame
        local sl = currentRootPart.AssemblyLinearVelocity
        local sa = currentRootPart.AssemblyAngularVelocity
        currentRootPart.AssemblyLinearVelocity = Vector3.new((math.random()-.5)*240000,144000+math.random()*72000,(math.random()-.5)*240000)
        currentRootPart.AssemblyAngularVelocity = Vector3.new(math.random(-3000,3000),math.random(-6000,6000),math.random(-3000,3000))
        RS.RenderStepped:Wait()
        currentRootPart.CFrame = sc * CFrame.Angles(0,math.rad(30000),0)
        currentRootPart.AssemblyLinearVelocity = sl
        currentRootPart.AssemblyAngularVelocity = sa
        currentRootPart.AssemblyLinearVelocity += Vector3.new(0,0.15,0)
    end)
end

local function stopFling()
    if flingConn then flingConn:Disconnect(); flingConn = nil end
    if currentRootPart then
        currentRootPart.AssemblyLinearVelocity = Vector3.zero
        currentRootPart.AssemblyAngularVelocity = Vector3.zero
    end
end
player.CharacterRemoving:Connect(stopFling)

-- ═══════════════════════════════════════════════
--  GUI
-- ═══════════════════════════════════════════════
local sg = Instance.new("ScreenGui")
sg.ResetOnSpawn = false
sg.DisplayOrder = 999
safeParent(sg)  -- protected parent (CoreGui/gethui)

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0,385,0,490)
mainFrame.Position = UDim2.new(0.5,-192,0.5,-245)
mainFrame.BackgroundColor3 = Color3.fromRGB(13,13,15)
mainFrame.BorderSizePixel = 0; mainFrame.Parent = sg
Instance.new("UICorner",mainFrame).CornerRadius = UDim.new(0,13)
local stroke = Instance.new("UIStroke",mainFrame)
stroke.Color = Color3.fromRGB(40,40,52); stroke.Thickness = 1.3

-- Gradient accent line at top
local accent = Instance.new("Frame",mainFrame)
accent.Size = UDim2.new(1,0,0,3); accent.BackgroundColor3 = Color3.fromRGB(80,120,255)
accent.BorderSizePixel = 0; accent.ZIndex = 5
Instance.new("UIGradient",accent).Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(80,100,255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160,80,255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(80,100,255)),
}
Instance.new("UICorner",accent).CornerRadius = UDim.new(0,13)

-- Resize handle
local resizing, resStartMouse, resStartSize = false, nil, nil
local rHandle = Instance.new("TextButton",mainFrame)
rHandle.Size = UDim2.new(0,22,0,22); rHandle.Position = UDim2.new(1,-22,1,-22)
rHandle.BackgroundColor3 = Color3.fromRGB(45,45,58); rHandle.Text = "↘"
rHandle.TextColor3 = Color3.fromRGB(160,160,190); rHandle.Font = Enum.Font.SourceSansBold
rHandle.TextSize = 15; rHandle.BorderSizePixel = 0; rHandle.ZIndex = 20
Instance.new("UICorner",rHandle).CornerRadius = UDim.new(0,5)
rHandle.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        resizing = true; resStartMouse = i.Position; resStartSize = mainFrame.AbsoluteSize
    end
end)
rHandle.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then resizing = false end
end)

-- Title bar
local titleBar = Instance.new("Frame",mainFrame)
titleBar.Size = UDim2.new(1,0,0,38); titleBar.BackgroundTransparency = 1

local titleLbl = Instance.new("TextLabel",titleBar)
titleLbl.Size = UDim2.new(1,-90,1,0); titleLbl.Position = UDim2.fromOffset(14,0)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = "LBB Hub"
titleLbl.TextColor3 = Color3.fromRGB(230,230,240); titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 16; titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local function mkTitleBtn(xOffset, bg, txt)
    local b = Instance.new("TextButton",titleBar)
    b.Size = UDim2.new(0,28,0,28); b.Position = UDim2.new(1,xOffset,0,5)
    b.BackgroundColor3 = bg; b.Text = txt; b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold; b.TextSize = 16; b.BorderSizePixel = 0
    Instance.new("UICorner",b).CornerRadius = UDim.new(0,7)
    return b
end

local closeBtn = mkTitleBtn(-36, Color3.fromRGB(185,45,45), "×")
closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

local minBtn = mkTitleBtn(-70, Color3.fromRGB(38,38,50), "–")

local bubble = Instance.new("TextButton",sg)
bubble.Size = UDim2.fromOffset(52,52); bubble.Position = mainFrame.Position
bubble.BackgroundColor3 = Color3.fromRGB(22,22,32); bubble.Text = "LBB"
bubble.TextColor3 = Color3.fromRGB(200,200,240); bubble.Font = Enum.Font.GothamBold
bubble.TextSize = 13; bubble.Visible = false
Instance.new("UICorner",bubble).CornerRadius = UDim.new(1,0)
Instance.new("UIStroke",bubble).Color = Color3.fromRGB(80,80,180)

minBtn.MouseButton1Click:Connect(function() bubble.Position=mainFrame.Position; mainFrame.Visible=false; bubble.Visible=true end)
bubble.MouseButton1Click:Connect(function() mainFrame.Position=bubble.Position; bubble.Visible=false; mainFrame.Visible=true end)

-- Drag helpers
local function makeDraggable(handle, target)
    local drag, ds, dp = false, nil, nil
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag=true; ds=i.Position; dp=target.Position
            i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then drag=false end end)
        end
    end)
    handle.InputChanged:Connect(function(i)
        if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
            local d=i.Position-ds
            target.Position=UDim2.new(dp.X.Scale,dp.X.Offset+d.X,dp.Y.Scale,dp.Y.Offset+d.Y)
        end
    end)
end
makeDraggable(titleBar, mainFrame)
makeDraggable(bubble, bubble)

-- Tabs
local tabBar = Instance.new("Frame",mainFrame)
tabBar.Size = UDim2.new(1,0,0,32); tabBar.Position = UDim2.new(0,0,0,39)
tabBar.BackgroundColor3 = Color3.fromRGB(18,18,24); tabBar.BorderSizePixel = 0
local tabDiv = Instance.new("Frame",tabBar)
tabDiv.Size = UDim2.new(1,0,0,1); tabDiv.Position = UDim2.new(0,0,1,-1)
tabDiv.BackgroundColor3 = Color3.fromRGB(50,50,70); tabDiv.BorderSizePixel = 0

local function mkTab(txt, xScale)
    local b = Instance.new("TextButton",tabBar)
    b.Size = UDim2.new(0.5,0,1,0); b.Position = UDim2.new(xScale,0,0,0)
    b.BackgroundTransparency = 1; b.Text = txt
    b.Font = Enum.Font.GothamSemibold; b.TextSize = 12
    return b
end
local tabMain = mkTab("Main", 0)
local tabNot  = mkTab("NOT FOR SAB!", 0.5)

local scrollMain = Instance.new("ScrollingFrame",mainFrame)
scrollMain.Size = UDim2.new(1,-14,1,-85); scrollMain.Position = UDim2.new(0,7,0,80)
scrollMain.BackgroundTransparency = 1; scrollMain.ScrollBarThickness = 3
scrollMain.ScrollBarImageColor3 = Color3.fromRGB(80,80,120)
scrollMain.CanvasSize = UDim2.new(0,0,0,1800)
local lMain = Instance.new("UIListLayout",scrollMain)
lMain.Padding = UDim.new(0,7); lMain.SortOrder = Enum.SortOrder.LayoutOrder

local scrollNot = Instance.new("ScrollingFrame",mainFrame)
scrollNot.Size = UDim2.new(1,-14,1,-85); scrollNot.Position = UDim2.new(0,7,0,80)
scrollNot.BackgroundTransparency = 1; scrollNot.ScrollBarThickness = 3
scrollNot.ScrollBarImageColor3 = Color3.fromRGB(80,80,120)
scrollNot.CanvasSize = UDim2.new(0,0,0,1800); scrollNot.Visible = false
local lNot = Instance.new("UIListLayout",scrollNot)
lNot.Padding = UDim.new(0,7); lNot.SortOrder = Enum.SortOrder.LayoutOrder

local function switchTab(toMain)
    scrollMain.Visible = toMain; scrollNot.Visible = not toMain
    tabMain.TextColor3 = toMain and Color3.fromRGB(110,170,255) or Color3.fromRGB(130,130,150)
    tabNot.TextColor3  = toMain and Color3.fromRGB(130,130,150) or Color3.fromRGB(110,170,255)
end
switchTab(true)
tabMain.MouseButton1Click:Connect(function() switchTab(true) end)
tabNot.MouseButton1Click:Connect(function() switchTab(false) end)

-- ═══════════════════════════════════════════════
--  WIDGET HELPERS
-- ═══════════════════════════════════════════════
local toggleUpdateFns = {}

local ACTIVE_CLR   = Color3.fromRGB(24,50,90)
local INACTIVE_CLR = Color3.fromRGB(22,22,30)

local function createToggle(parent, label, key, onToggle)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,44); btn.BackgroundColor3 = INACTIVE_CLR
    btn.TextColor3 = Color3.fromRGB(215,215,225); btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 13; btn.TextXAlignment = Enum.TextXAlignment.Left; btn.Parent = parent
    Instance.new("UIPadding",btn).PaddingLeft = UDim.new(0,14)
    Instance.new("UICorner",btn).CornerRadius = UDim.new(0,9)

    -- Pill indicator on the right
    local pill = Instance.new("Frame",btn)
    pill.Size = UDim2.new(0,36,0,18); pill.Position = UDim2.new(1,-50,0.5,-9)
    pill.BackgroundColor3 = Color3.fromRGB(50,50,65); pill.BorderSizePixel = 0
    Instance.new("UICorner",pill).CornerRadius = UDim.new(1,0)
    local dot = Instance.new("Frame",pill)
    dot.Size = UDim2.new(0,14,0,14); dot.Position = UDim2.new(0,2,0.5,-7)
    dot.BackgroundColor3 = Color3.fromRGB(120,120,150); dot.BorderSizePixel = 0
    Instance.new("UICorner",dot).CornerRadius = UDim.new(1,0)

    local function update()
        local on = state[key]
        btn.Text = label
        btn.BackgroundColor3 = on and ACTIVE_CLR or INACTIVE_CLR
        pill.BackgroundColor3 = on and Color3.fromRGB(40,90,200) or Color3.fromRGB(50,50,65)
        dot.BackgroundColor3  = on and Color3.fromRGB(180,220,255) or Color3.fromRGB(120,120,150)
        TweenService:Create(dot, TweenInfo.new(0.15), {
            Position = on and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
        }):Play()
    end
    update()

    btn.MouseButton1Click:Connect(function()
        state[key] = not state[key]

        -- Speed mutual exclusion
        if key=="speedEnabled"       and state[key] then state.customSpeedEnabled=false; state.configSpeedEnabled=false
        elseif key=="customSpeedEnabled" and state[key] then state.speedEnabled=false; state.configSpeedEnabled=false
        elseif key=="configSpeedEnabled" and state[key] then state.speedEnabled=false; state.customSpeedEnabled=false
        end

        local on = state[key]
        -- OFF cleanups
        if not on then
            if (key=="speedEnabled" or key=="customSpeedEnabled" or key=="configSpeedEnabled") and currentHumanoid then
                setProp(currentHumanoid,"WalkSpeed",DEFAULT_SPEED)
            end
            if key=="customJumpEnabled" and currentHumanoid then setProp(currentHumanoid,"JumpPower",DEFAULT_JUMP) end
            if key=="noclipEnabled" and character then
                for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end
            end
            if key=="flingEnabled" then stopFling() end
            if key=="fullbright" then
                Lighting.Brightness=1; Lighting.GlobalShadows=true; Lighting.FogEnd=100000; Lighting.Ambient=Color3.new(.5,.5,.5)
            end
            if key=="playerESP" then
                for _,p in ipairs(Players:GetPlayers()) do
                    if p.Character then local h=p.Character:FindFirstChild("Head"); if h and h:FindFirstChild("ESP") then h.ESP:Destroy() end end
                end
            end
            if key=="tallHipsEnabled" and currentHumanoid then
                setProp(currentHumanoid,"HipHeight",trueHipHeight)
            end
            if key=="hitboxEnabled" then clearHitboxes() end
            if key=="invisEnabled" and character then
                for part,trans in pairs(state.originalTransparencies) do
                    if part and part.Parent then part.LocalTransparencyModifier = trans end
                end
                state.originalTransparencies = {}
            end
            if key=="antiRagdollEnabled" then
                for _,c in ipairs(antiRagdollConns) do c:Disconnect() end; antiRagdollConns={}
                if character then
                    for _,v in ipairs(character:GetDescendants()) do
                        if v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint") then v.Enabled=true end
                    end
                end
            end
            if key=="noAnimEnabled" then
                if animateScript then animateScript.Disabled = false end
            end
        else
            -- ON setups
            if key=="speedEnabled"       and currentHumanoid then setProp(currentHumanoid,"WalkSpeed",SPEED_277) end
            if key=="customSpeedEnabled" and currentHumanoid then setProp(currentHumanoid,"WalkSpeed",state.customSpeedValue) end
            if key=="configSpeedEnabled" and currentHumanoid then setProp(currentHumanoid,"WalkSpeed",state.configSpeed) end
            if key=="customJumpEnabled"  and currentHumanoid then setProp(currentHumanoid,"JumpPower",state.customJumpValue) end
            if key=="flingEnabled" then startFling() end
            if key=="tallHipsEnabled" and currentHumanoid then
                setProp(currentHumanoid,"HipHeight",trueHipHeight + TALL_HIP_OFFSET)
            end
            if key=="invisEnabled" and character then
                state.originalTransparencies = {}
                for _,p in ipairs(character:GetDescendants()) do
                    if p:IsA("BasePart") or p:IsA("Decal") then
                        state.originalTransparencies[p]=p.LocalTransparencyModifier; p.LocalTransparencyModifier=1
                    end
                end
            end
            if key=="antiRagdollEnabled" and character then applyAntiRagdoll(character) end
            if key=="noclipEnabled" and character then
                for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end
            end
            if key=="fullbright" then
                Lighting.Brightness=2; Lighting.GlobalShadows=false; Lighting.FogEnd=9999; Lighting.Ambient=Color3.new(1,1,1)
            end
            if key=="noAnimEnabled" then
                if animateScript then animateScript.Disabled = true end
                stopAllAnims()
            end
        end

        if onToggle then onToggle(on) end
        for _,fn in ipairs(toggleUpdateFns) do fn() end
    end)

    table.insert(toggleUpdateFns, update)
    return btn, update
end

local function createAction(parent, txt, cb, clr)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,44); btn.BackgroundColor3 = clr or INACTIVE_CLR
    btn.Text = txt; btn.TextColor3 = Color3.fromRGB(215,215,225)
    btn.Font = Enum.Font.GothamSemibold; btn.TextSize = 13
    btn.TextXAlignment = Enum.TextXAlignment.Left; btn.Parent = parent
    Instance.new("UIPadding",btn).PaddingLeft = UDim.new(0,14)
    Instance.new("UICorner",btn).CornerRadius = UDim.new(0,9)
    btn.MouseButton1Click:Connect(cb)
    return btn
end

local function createSection(parent, title)
    local f = Instance.new("Frame",parent)
    f.Size = UDim2.new(1,0,0,0); f.BackgroundTransparency = 1
    f.AutomaticSize = Enum.AutomaticSize.Y

    local hdr = Instance.new("TextLabel",f)
    hdr.Size = UDim2.new(1,0,0,24); hdr.BackgroundColor3 = Color3.fromRGB(28,28,38)
    hdr.Text = "  " .. title; hdr.TextColor3 = Color3.fromRGB(160,170,255)
    hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 12
    hdr.TextXAlignment = Enum.TextXAlignment.Left; hdr.BorderSizePixel = 0
    Instance.new("UICorner",hdr).CornerRadius = UDim.new(0,7)

    local list = Instance.new("Frame",f)
    list.Size = UDim2.new(1,0,0,0); list.BackgroundTransparency = 1
    list.AutomaticSize = Enum.AutomaticSize.Y
    local ll = Instance.new("UIListLayout",list)
    ll.Padding = UDim.new(0,6); ll.SortOrder = Enum.SortOrder.LayoutOrder
    return list
end

local function createValueRow(parent, lbl, init, minV, maxV, onChange)
    local row = Instance.new("Frame",parent)
    row.Size = UDim2.new(1,0,0,34); row.BackgroundTransparency = 1
    local l = Instance.new("TextLabel",row)
    l.Size = UDim2.new(0.55,0,1,0); l.BackgroundTransparency = 1; l.Text = lbl
    l.TextColor3 = Color3.fromRGB(180,180,200); l.Font = Enum.Font.Gotham
    l.TextSize = 12; l.TextXAlignment = Enum.TextXAlignment.Left
    local box = Instance.new("TextBox",row)
    box.Size = UDim2.new(0.42,0,0,26); box.Position = UDim2.new(0.57,0,0.5,-13)
    box.BackgroundColor3 = Color3.fromRGB(28,28,40); box.TextColor3 = Color3.new(1,1,1)
    box.Font = Enum.Font.Gotham; box.TextSize = 12; box.Text = tostring(init)
    box.ClearTextOnFocus = false
    Instance.new("UICorner",box).CornerRadius = UDim.new(0,6)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then n=math.clamp(n,minV,maxV); box.Text=tostring(n); onChange(n)
        else box.Text=tostring(init) end
    end)
    return row
end

-- ═══════════════════════════════════════════════
--  MAIN TAB
-- ═══════════════════════════════════════════════
createAction(scrollMain, "⚡ Use Everything", useEverything)

local keyBtn = Instance.new("TextButton",scrollMain)
keyBtn.Size = UDim2.new(1,0,0,44); keyBtn.BackgroundColor3 = INACTIVE_CLR
keyBtn.Text = "🎮 Keybind: " .. state.currentBind.Name
keyBtn.TextColor3 = Color3.fromRGB(215,215,225); keyBtn.Font = Enum.Font.GothamSemibold
keyBtn.TextSize = 13; keyBtn.TextXAlignment = Enum.TextXAlignment.Left
Instance.new("UIPadding",keyBtn).PaddingLeft = UDim.new(0,14)
Instance.new("UICorner",keyBtn).CornerRadius = UDim.new(0,9)
keyBtn.MouseButton1Click:Connect(function()
    state.waitingForKey = true; keyBtn.Text = "🎮 Press any key..."
end)
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if state.waitingForKey and input.UserInputType == Enum.UserInputType.Keyboard then
        state.currentBind = input.KeyCode
        keyBtn.Text = "🎮 Keybind: " .. state.currentBind.Name
        state.waitingForKey = false; return
    end
    if input.KeyCode == state.currentBind and not state.waitingForKey then useEverything() end
end)

createToggle(scrollMain, "Speed 27.7 (stealing)", "speedEnabled")
createToggle(scrollMain, "Inf Jump", "infiniteJumpEnabled")
createToggle(scrollMain, "Float", "floatEnabled")
createToggle(scrollMain, "Anti Ragdoll", "antiRagdollEnabled", function(on)
    if on and character then applyAntiRagdoll(character) end
end)
createToggle(scrollMain, "Auto Bat", "autoBatEnabled")
createToggle(scrollMain, "No Anim", "noAnimEnabled", function(on)
    if animateScript then animateScript.Disabled = on end
    if on then stopAllAnims() end
end)
createToggle(scrollMain, "Walk Fling (others)", "walkFlingEnabled")
createToggle(scrollMain, "Spin", "spinEnabled")
createToggle(scrollMain, "Float Up", "floatUpEnabled")
createToggle(scrollMain, "Aimbot (face nearest)", "aimbotEnabled")
createToggle(scrollMain, "Hitbox Visualizer", "hitboxEnabled", function(on)
    if not on then clearHitboxes() end
end)
createToggle(scrollMain, "Auto Grab", "autoGrabEnabled")
createAction(scrollMain, "Loser Emote", function() pcall(function() player:Chat("/e loser") end) end)
createToggle(scrollMain, "Tall Hips", "tallHipsEnabled", function(on)
    if currentHumanoid then
        setProp(currentHumanoid, "HipHeight", on and (trueHipHeight + TALL_HIP_OFFSET) or trueHipHeight)
    end
end)
createToggle(scrollMain, "Medusa Counter", "medusaCounterEnabled")
createToggle(scrollMain, "Misplace Character", "misplaceEnabled")
createToggle(scrollMain, "Invis Brainrot", "invisEnabled")
createAction(scrollMain, "TP to Brainrot (ragdoll)", function()
    local n = getNearestPlayer()
    if n and currentRootPart then
        currentRootPart.CFrame = n.CFrame * CFrame.new(0,5,0)
        if currentHumanoid then
            currentHumanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
            task.delay(.5, function() if currentHumanoid then currentHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end end)
        end
    end
end)

-- Config panel
local cfgFrame = Instance.new("Frame",scrollMain)
cfgFrame.Size = UDim2.new(1,0,0,0); cfgFrame.AutomaticSize = Enum.AutomaticSize.Y
cfgFrame.BackgroundColor3 = Color3.fromRGB(18,18,26)
Instance.new("UICorner",cfgFrame).CornerRadius = UDim.new(0,9)
local cfgLayout = Instance.new("UIListLayout",cfgFrame)
cfgLayout.Padding = UDim.new(0,5); cfgLayout.SortOrder = Enum.SortOrder.LayoutOrder
local cfgPad = Instance.new("UIPadding",cfgFrame)
cfgPad.PaddingLeft=UDim.new(0,10); cfgPad.PaddingRight=UDim.new(0,10)
cfgPad.PaddingTop=UDim.new(0,8); cfgPad.PaddingBottom=UDim.new(0,8)

local cfgHdr = Instance.new("TextLabel",cfgFrame)
cfgHdr.Size=UDim2.new(1,0,0,20); cfgHdr.BackgroundTransparency=1
cfgHdr.Text="  ⚙ Config"; cfgHdr.TextColor3=Color3.fromRGB(160,170,255)
cfgHdr.Font=Enum.Font.GothamBold; cfgHdr.TextSize=12
cfgHdr.TextXAlignment=Enum.TextXAlignment.Left

createValueRow(cfgFrame,"speed", state.configSpeed, 1, 99999, function(v) state.configSpeed=v end)
createValueRow(cfgFrame,"steal", state.configSteal, 1, 99999, function(v) state.configSteal=v end)
createValueRow(cfgFrame,"jump",  state.configJump,  1, 99999, function(v) state.configJump=v end)

createToggle(cfgFrame, "Enable Speed", "configSpeedEnabled", function(on)
    if currentHumanoid then
        setProp(currentHumanoid, "WalkSpeed", on and state.configSpeed or DEFAULT_SPEED)
    end
end)

local saveBtn = Instance.new("TextButton",cfgFrame)
saveBtn.Size=UDim2.new(1,0,0,34); saveBtn.BackgroundColor3=Color3.fromRGB(15,60,25)
saveBtn.Text="💾 Save Config"; saveBtn.TextColor3=Color3.fromRGB(160,255,170)
saveBtn.Font=Enum.Font.GothamSemibold; saveBtn.TextSize=12
Instance.new("UICorner",saveBtn).CornerRadius=UDim.new(0,7)
saveBtn.MouseButton1Click:Connect(function()
    saveConfig()
    saveBtn.Text="✓ Saved!"; saveBtn.BackgroundColor3=Color3.fromRGB(15,90,25)
    task.delay(2, function() saveBtn.Text="💾 Save Config"; saveBtn.BackgroundColor3=Color3.fromRGB(15,60,25) end)
end)

createToggle(cfgFrame, "Auto Play", "autoPlayEnabled")

-- ═══════════════════════════════════════════════
--  NOT FOR SAB TAB
-- ═══════════════════════════════════════════════
local movSec = createSection(scrollNot, "Movement")
local visSec = createSection(scrollNot, "Visuals")
local utlSec = createSection(scrollNot, "Utility")

createToggle(movSec, "Custom Speed", "customSpeedEnabled", function(on)
    if on and currentHumanoid then setProp(currentHumanoid,"WalkSpeed",state.customSpeedValue) end
end)
createValueRow(movSec,"Speed Value",state.customSpeedValue,1,100000,function(v)
    state.customSpeedValue=v; if currentHumanoid and state.customSpeedEnabled then setProp(currentHumanoid,"WalkSpeed",v) end
end)
createToggle(movSec, "Custom Jump", "customJumpEnabled", function(on)
    if on and currentHumanoid then setProp(currentHumanoid,"JumpPower",state.customJumpValue) end
end)
createValueRow(movSec,"Jump Power",state.customJumpValue,1,1000,function(v)
    state.customJumpValue=v; if currentHumanoid and state.customJumpEnabled then setProp(currentHumanoid,"JumpPower",v) end
end)
createToggle(movSec, "Fly", "flyEnabled")
createValueRow(movSec,"Fly Speed",state.customFlySpeed,1,1e9,function(v) state.customFlySpeed=v end)
createToggle(movSec, "Noclip", "noclipEnabled", function(on)
    if character then for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=not on end end end
end)
createToggle(movSec, "Fling (self)", "flingEnabled", function(on)
    if on then startFling() else stopFling() end
end)
createToggle(movSec, "No Fall Damage", "noFallDamage")

createToggle(visSec, "Fullbright", "fullbright", function(on)
    if on then Lighting.Brightness=2; Lighting.GlobalShadows=false; Lighting.FogEnd=9999; Lighting.Ambient=Color3.new(1,1,1)
    else Lighting.Brightness=1; Lighting.GlobalShadows=true; Lighting.FogEnd=100000; Lighting.Ambient=Color3.new(.5,.5,.5) end
end)
createToggle(visSec, "Player ESP", "playerESP", function(on)
    if not on then
        for _,p in ipairs(Players:GetPlayers()) do
            if p.Character then local h=p.Character:FindFirstChild("Head"); if h and h:FindFirstChild("ESP") then h.ESP:Destroy() end end
        end
    end
end)

local function openCheckpointUI()
    local cpg = Instance.new("ScreenGui"); cpg.ResetOnSpawn=false; safeParent(cpg)
    local cpf = Instance.new("Frame",cpg)
    cpf.Size=UDim2.new(0,220,0,145); cpf.Position=UDim2.new(0.5,-110,0.5,-72)
    cpf.BackgroundColor3=Color3.fromRGB(18,18,24); cpf.BorderSizePixel=0
    Instance.new("UICorner",cpf).CornerRadius=UDim.new(0,10)
    local cpt=Instance.new("Frame",cpf); cpt.Size=UDim2.new(1,0,0,30); cpt.BackgroundColor3=Color3.fromRGB(24,24,34)
    Instance.new("UICorner",cpt).CornerRadius=UDim.new(0,10)
    local cpl=Instance.new("TextLabel",cpt); cpl.Size=UDim2.new(1,-36,1,0); cpl.BackgroundTransparency=1
    cpl.Text="Checkpoint"; cpl.TextColor3=Color3.fromRGB(180,255,220); cpl.Font=Enum.Font.GothamBold; cpl.TextSize=13
    cpl.TextXAlignment=Enum.TextXAlignment.Left; Instance.new("UIPadding",cpl).PaddingLeft=UDim.new(0,10)
    local cpc=Instance.new("TextButton",cpt); cpc.Size=UDim2.new(0,26,0,26); cpc.Position=UDim2.new(1,-30,0,2)
    cpc.BackgroundColor3=Color3.fromRGB(170,35,35); cpc.Text="×"; cpc.TextColor3=Color3.new(1,1,1); cpc.Font=Enum.Font.GothamBold; cpc.TextSize=16
    Instance.new("UICorner",cpc).CornerRadius=UDim.new(0,6); cpc.MouseButton1Click:Connect(function() cpg:Destroy() end)
    makeDraggable(cpt, cpf)
    local function mkb(t,y,cb) local b=Instance.new("TextButton",cpf); b.Size=UDim2.new(.88,0,0,28); b.Position=UDim2.new(.06,0,y,0)
        b.BackgroundColor3=INACTIVE_CLR; b.Text=t; b.TextColor3=Color3.new(1,1,1); b.Font=Enum.Font.GothamSemibold; b.TextSize=12
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,7); b.MouseButton1Click:Connect(cb); return b end
    mkb("Teleport",0.26,teleportToCheckpoint); mkb("Set Checkpoint",0.52,setCheckpoint)
    local kb=mkb("Set Keybind",0.78,function() checkpointWaitingForKey=true end)
    local kc; kc=UIS.InputBegan:Connect(function(i,gp)
        if gp then return end
        if checkpointWaitingForKey and i.UserInputType==Enum.UserInputType.Keyboard then
            state.checkpointKeybind=i.KeyCode; kb.Text="Key: "..i.KeyCode.Name; checkpointWaitingForKey=false; kc:Disconnect()
        end
    end)
end

UIS.InputBegan:Connect(function(i,gp)
    if gp then return end
    if state.checkpointKeybind and i.KeyCode==state.checkpointKeybind then teleportToCheckpoint() end
end)

createAction(utlSec, "Checkpoint Menu", openCheckpointUI)

createAction(utlSec, "Teleport to Player", function()
    local tg = Instance.new("ScreenGui"); tg.ResetOnSpawn=false; safeParent(tg)
    local tf = Instance.new("Frame",tg); tf.Size=UDim2.new(0,320,0,400); tf.Position=UDim2.new(0.5,-160,0.5,-200)
    tf.BackgroundColor3=Color3.fromRGB(16,16,22); tf.BorderSizePixel=0; Instance.new("UICorner",tf).CornerRadius=UDim.new(0,13)
    local ttb=Instance.new("Frame",tf); ttb.Size=UDim2.new(1,0,0,38); ttb.BackgroundColor3=Color3.fromRGB(12,12,18)
    Instance.new("UICorner",ttb).CornerRadius=UDim.new(0,13)
    local ttl=Instance.new("TextLabel",ttb); ttl.Size=UDim2.new(1,-50,1,0); ttl.BackgroundTransparency=1
    ttl.Text="Teleport to Player"; ttl.TextColor3=Color3.fromRGB(190,190,255); ttl.Font=Enum.Font.GothamBold; ttl.TextSize=16
    local tc=Instance.new("TextButton",ttb); tc.Size=UDim2.new(0,30,0,30); tc.Position=UDim2.new(1,-36,0,4)
    tc.BackgroundColor3=Color3.fromRGB(170,35,35); tc.Text="×"; tc.TextColor3=Color3.new(1,1,1); tc.Font=Enum.Font.GothamBold; tc.TextSize=18
    Instance.new("UICorner",tc).CornerRadius=UDim.new(0,8); tc.MouseButton1Click:Connect(function() tg:Destroy() end)
    makeDraggable(ttb,tf)
    local ts=Instance.new("ScrollingFrame",tf); ts.Size=UDim2.new(1,-16,1,-46); ts.Position=UDim2.new(0,8,0,42)
    ts.BackgroundTransparency=1; ts.ScrollBarThickness=4; Instance.new("UIListLayout",ts).Padding=UDim.new(0,7)
    local function fill()
        for _,c in ipairs(ts:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        local pl={}; for _,p in ipairs(Players:GetPlayers()) do if isValidTarget(p) then pl[#pl+1]=p end end
        table.sort(pl,function(a,b) return a.Name:lower()<b.Name:lower() end)
        for _,p in ipairs(pl) do
            local b=Instance.new("TextButton",ts); b.Size=UDim2.new(1,0,0,44); b.BackgroundColor3=Color3.fromRGB(28,28,40)
            b.Text=p.Name; b.TextColor3=Color3.new(1,1,1); b.Font=Enum.Font.GothamSemibold; b.TextSize=18; b.TextScaled=true
            Instance.new("UICorner",b).CornerRadius=UDim.new(0,9)
            b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(.15),{BackgroundColor3=Color3.fromRGB(45,45,65)}):Play() end)
            b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(.15),{BackgroundColor3=Color3.fromRGB(28,28,40)}):Play() end)
            b.MouseButton1Click:Connect(function() tpTo(p) end)
        end
        ts.CanvasSize=UDim2.new(0,0,0,#pl*51)
    end
    fill(); task.delay(.3,fill)
end)

createAction(utlSec, "Server Hop", function()
    pcall(function()
        local cur=""; local svrs={}
        repeat
            local r=HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"..cur))
            for _,v in ipairs(r.data) do if v.playing<v.maxPlayers and v.id~=game.JobId then svrs[#svrs+1]=v.id end end
            cur=r.nextPageCursor and "&cursor="..r.nextPageCursor or ""
        until not r.nextPageCursor
        if #svrs>0 then TpService:TeleportToPlaceInstance(game.PlaceId,svrs[math.random(1,#svrs)]) end
    end)
end)
createToggle(utlSec, "Auto Rejoin on Kick", "autoRejoin")

createAction(utlSec, "Reset All", function()
    local keys={"speedEnabled","customSpeedEnabled","configSpeedEnabled","customJumpEnabled","flyEnabled","noclipEnabled",
        "flingEnabled","infiniteJumpEnabled","noFallDamage","fullbright","playerESP","autoRejoin","floatEnabled",
        "antiRagdollEnabled","autoBatEnabled","noAnimEnabled","walkFlingEnabled","spinEnabled","floatUpEnabled",
        "aimbotEnabled","hitboxEnabled","autoGrabEnabled","tallHipsEnabled","medusaCounterEnabled","misplaceEnabled","invisEnabled","autoPlayEnabled"}
    for _,k in ipairs(keys) do state[k]=false end
    state.checkpointPos=nil; state.checkpointKeybind=nil
    if state.checkpointIndicator then state.checkpointIndicator:Destroy(); state.checkpointIndicator=nil end
    stopFling(); clearHitboxes()
    if currentHumanoid then
        setProp(currentHumanoid,"WalkSpeed",DEFAULT_SPEED); setProp(currentHumanoid,"JumpPower",DEFAULT_JUMP)
        setProp(currentHumanoid,"HipHeight",trueHipHeight)
    end
    if character then
        for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end
        for _,v in ipairs(character:GetDescendants()) do
            if v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint") then v.Enabled=true end
            if v:IsA("Motor6D") then v.Enabled=true end
        end
        for _,c in ipairs(antiRagdollConns) do c:Disconnect() end; antiRagdollConns={}
        for part,trans in pairs(state.originalTransparencies) do if part and part.Parent then part.LocalTransparencyModifier=trans end end
        state.originalTransparencies={}
    end
    if animateScript then animateScript.Disabled=false end
    Lighting.Brightness=1; Lighting.GlobalShadows=true; Lighting.FogEnd=100000; Lighting.Ambient=Color3.new(.5,.5,.5)
    for _,p in ipairs(Players:GetPlayers()) do
        if p.Character then local h=p.Character:FindFirstChild("Head"); if h and h:FindFirstChild("ESP") then h.ESP:Destroy() end end
    end
    for _,fn in ipairs(toggleUpdateFns) do fn() end
end)

-- ═══════════════════════════════════════════════
--  HEARTBEAT
-- ═══════════════════════════════════════════════
local bodyVel, bodyGyro
local autoBatTimer = 0

RS.Heartbeat:Connect(function(dt)
    -- Resize logic
    if resizing then
        local mouse = UIS:GetMouseLocation()
        if mouse and resStartMouse and resStartSize then
            local d = mouse - resStartMouse
            local nw = math.max(320, resStartSize.X + d.X)
            local nh = math.max(400, resStartSize.Y + d.Y)
            mainFrame.Size = UDim2.new(0,nw,0,nh)
            scrollMain.CanvasSize = UDim2.new(0,0,0,nh*(1800/490))
            scrollNot.CanvasSize  = UDim2.new(0,0,0,nh*(1800/490))
        end
    end

    if not currentHumanoid or currentHumanoid.Health <= 0 then
        if bodyVel then bodyVel:Destroy(); bodyVel=nil end
        if bodyGyro then bodyGyro:Destroy(); bodyGyro=nil end
        return
    end

    -- Speed (use bypass setter every frame to counter anti-cheats that reset it)
    if state.speedEnabled then setProp(currentHumanoid,"WalkSpeed",SPEED_277)
    elseif state.customSpeedEnabled then setProp(currentHumanoid,"WalkSpeed",state.customSpeedValue)
    elseif state.configSpeedEnabled then setProp(currentHumanoid,"WalkSpeed",state.configSpeed)
    end
    if state.customJumpEnabled then setProp(currentHumanoid,"JumpPower",state.customJumpValue) end

    -- Tall Hips: locked to exact value every frame (no drift, no stack)
    if state.tallHipsEnabled then setProp(currentHumanoid,"HipHeight",trueHipHeight + TALL_HIP_OFFSET) end

    -- Anti Ragdoll: enforce joint states every frame
    if state.antiRagdollEnabled and character then
        for _,v in ipairs(character:GetDescendants()) do
            if (v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint")) and v.Enabled then v.Enabled=false end
            if v:IsA("Motor6D") and not v.Enabled then v.Enabled=true end
        end
    end

    -- Fly
    if state.flyEnabled and currentRootPart then
        if not bodyVel then bodyVel=Instance.new("BodyVelocity"); bodyVel.MaxForce=Vector3.new(1e6,1e6,1e6); bodyVel.Parent=currentRootPart end
        if not bodyGyro then bodyGyro=Instance.new("BodyGyro"); bodyGyro.MaxTorque=Vector3.new(1e6,1e6,1e6); bodyGyro.P=15000; bodyGyro.Parent=currentRootPart end
        local dir=Vector3.new()
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir+=Vector3.new(0,0,-1) end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir+=Vector3.new(0,0,1) end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir+=Vector3.new(-1,0,0) end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir+=Vector3.new(1,0,0) end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir+=Vector3.new(0,1,0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir+=Vector3.new(0,-1,0) end
        local cam=workspace.CurrentCamera
        if cam then bodyVel.Velocity=cam.CFrame:VectorToWorldSpace(dir)*state.customFlySpeed; bodyGyro.CFrame=cam.CFrame end
    else
        if bodyVel then bodyVel:Destroy(); bodyVel=nil end
        if bodyGyro then bodyGyro:Destroy(); bodyGyro=nil end
    end

    if state.noclipEnabled and character then
        for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide=false end end
    end
    if state.floatEnabled and currentRootPart then
        currentRootPart.AssemblyLinearVelocity=Vector3.new(currentRootPart.AssemblyLinearVelocity.X,0,currentRootPart.AssemblyLinearVelocity.Z)
    end
    if state.floatUpEnabled and currentRootPart then
        currentRootPart.AssemblyLinearVelocity=Vector3.new(currentRootPart.AssemblyLinearVelocity.X,20,currentRootPart.AssemblyLinearVelocity.Z)
    end
    if state.spinEnabled and currentRootPart then
        currentRootPart.CFrame=currentRootPart.CFrame*CFrame.Angles(0,math.rad(dt*720),0)
    end

    -- Walk Fling: fling nearby OTHER players
    if state.walkFlingEnabled and currentRootPart then
        local myV=currentRootPart.AssemblyLinearVelocity
        if Vector3.new(myV.X,0,myV.Z).Magnitude > 1 then
            for _,p in ipairs(Players:GetPlayers()) do
                if isValidTarget(p) then
                    local r=getRoot(p.Character)
                    if r and (r.Position-currentRootPart.Position).Magnitude < 8 then
                        r.AssemblyLinearVelocity=Vector3.new((math.random()-.5)*180000,70000+math.random()*40000,(math.random()-.5)*180000)
                        r.AssemblyAngularVelocity=Vector3.new(math.random(-2000,2000),math.random(-4000,4000),math.random(-2000,2000))
                    end
                end
            end
        end
    end

    -- Auto Bat
    if state.autoBatEnabled then
        autoBatTimer+=dt
        if autoBatTimer>=0.15 then autoBatTimer=0
            for _,t in ipairs(getAllTools()) do
                if t.Name:lower():find("bat") then pcall(function() t.Parent=player.Character; if t.Activate then t:Activate() end end) end
            end
        end
    end
    if state.autoGrabEnabled then
        for _,t in ipairs(getAllTools()) do
            if t.Name:lower():find("grab") then pcall(function() t.Parent=player.Character; if t.Activate then t:Activate() end end) end
        end
    end

    -- Aimbot: rotate character body (not camera) to face nearest player
    if state.aimbotEnabled and currentRootPart then
        local n=getNearestPlayer()
        if n then
            local my=currentRootPart.Position
            local dir=(n.Position-my)*Vector3.new(1,0,1)
            if dir.Magnitude>0.1 then
                currentRootPart.CFrame=CFrame.new(my, my+dir.Unit)
            end
        end
    end

    -- No Anim: enforce every frame
    if state.noAnimEnabled then
        if animateScript and not animateScript.Disabled then animateScript.Disabled=true end
        stopAllAnims()
    end

    -- Hitbox: update positions every frame for smooth tracking
    if state.hitboxEnabled then
        refreshHitboxes()
        updateHitboxPositions()
    end

    -- Medusa Counter
    if state.medusaCounterEnabled and currentHumanoid then
        if currentHumanoid:GetState()==Enum.HumanoidStateType.Physics then tryMedusa() end
    end

    if state.misplaceEnabled and currentRootPart then
        currentRootPart.CFrame=currentRootPart.CFrame*CFrame.new((math.random()-.5)*.3,0,(math.random()-.5)*.3)
    end
    if state.autoPlayEnabled then useEverything() end

    -- Player ESP
    if state.playerESP then
        for _,p in ipairs(Players:GetPlayers()) do
            if p~=player and p.Character then
                local head=p.Character:FindFirstChild("Head")
                if head then
                    local bb=head:FindFirstChild("ESP")
                    if not bb then
                        bb=Instance.new("BillboardGui"); bb.Name="ESP"; bb.Adornee=head
                        bb.Size=UDim2.new(0,200,0,50); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Parent=head
                        local lbl=Instance.new("TextLabel",bb); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1
                        lbl.TextColor3=Color3.new(1,1,1); lbl.TextScaled=true; lbl.Font=Enum.Font.GothamBold
                    end
                    local dist=currentRootPart and math.floor((currentRootPart.Position-head.Position).Magnitude) or 0
                    bb.TextLabel.Text=p.Name.."\n"..dist.." studs"
                end
            end
        end
    end
end)

-- Infinite Jump
local lastJump = 0
UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    if state.infiniteJumpEnabled and i.KeyCode==Enum.KeyCode.Space then
        local now=tick(); if now-lastJump<0.12 then return end; lastJump=now
        if currentHumanoid and currentRootPart then
            local s=currentHumanoid:GetState().Name
            if s=="Freefall" or s=="Landed" or s=="Running" then
                currentRootPart.AssemblyLinearVelocity=Vector3.new(currentRootPart.AssemblyLinearVelocity.X,55,currentRootPart.AssemblyLinearVelocity.Z)
            end
        end
    end
end)

-- Auto Rejoin
Players.PlayerRemoving:Connect(function(plr)
    if plr==player and state.autoRejoin then task.wait(2); TpService:Teleport(game.PlaceId) end
end)

-- Apply saved state after GUI ready
task.defer(function()
    for _,fn in ipairs(toggleUpdateFns) do fn() end
    keyBtn.Text = "🎮 Keybind: " .. state.currentBind.Name
    if state.speedEnabled and currentHumanoid then setProp(currentHumanoid,"WalkSpeed",SPEED_277) end
    if state.customSpeedEnabled and currentHumanoid then setProp(currentHumanoid,"WalkSpeed",state.customSpeedValue) end
    if state.configSpeedEnabled and currentHumanoid then setProp(currentHumanoid,"WalkSpeed",state.configSpeed) end
    if state.customJumpEnabled and currentHumanoid then setProp(currentHumanoid,"JumpPower",state.customJumpValue) end
    if state.tallHipsEnabled and currentHumanoid then setProp(currentHumanoid,"HipHeight",trueHipHeight+TALL_HIP_OFFSET) end
    if state.fullbright then Lighting.Brightness=2; Lighting.GlobalShadows=false; Lighting.FogEnd=9999; Lighting.Ambient=Color3.new(1,1,1) end
    if state.flingEnabled then startFling() end
    if state.antiRagdollEnabled and character then applyAntiRagdoll(character) end
    if state.noAnimEnabled then
        if animateScript then animateScript.Disabled=true end; stopAllAnims()
    end
end)

print("LBB Hub v5 | User: "..player.UserId.." | bypass: active | config: "..CONFIG_PATH)
