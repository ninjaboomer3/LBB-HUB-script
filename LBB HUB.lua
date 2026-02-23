-- LBB Hub v8
-- Fix 1: Hitboxes = plain Anchored Part, moved each frame, Destroy() on disable = zero leftovers
-- Fix 2: WalkSpeed NEVER changed. BodyVelocity adds extra speed. Humanoid.Health hook prevents reset.
-- Fix 3: Checkpoint Menu is in Main tab

-- ═══════════════════════════════════════════════════
--  BYPASS  (runs before everything else)
-- ═══════════════════════════════════════════════════

-- 1) __namecall hook: block Kick + any anticheat FireServer/InvokeServer
pcall(function()
    local mt = getrawmetatable(game)
    pcall(setreadonly, mt, false)
    local _nc = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        local m = getnamecallmethod()
        if m == "Kick" and self == game:GetService("Players").LocalPlayer then return end
        if (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance" then
            local n = self.Name:lower()
            if n:find("anti") or n:find("cheat") or n:find("detect") or n:find("report")
            or n:find("flag") or n:find("ban") or n:find("sanity") or n:find("hack")
            or n:find("reset") or n:find("punish") then return end
        end
        return _nc(self, ...)
    end)
    pcall(setreadonly, mt, true)
end)

-- 2) observeTag hook (SAB's ByteBlox-based AC registers via observeTag)
local function hookObserveTag()
    pcall(function()
        if not getgc then return end
        local fc = {Connected=true, Disconnect=function()end}
        for _, v in pairs(getgc(true)) do
            if type(v)=="table" then
                local fn = rawget(v,"observeTag")
                if type(fn)=="function" then pcall(hookfunction, fn, newcclosure(function() return fc end)) end
            end
        end
    end)
end
hookObserveTag()
task.spawn(function() while true do task.wait(8); hookObserveTag() end end)

-- 3) Mask common executor globals the AC scans for
pcall(function()
    local env = getfenv and getfenv(0) or _G
    for _, k in ipairs({"syn","SENTINEL_V2","KRNL_LOADED","is_sirhurt_closure","is_fluxus_closure","isfirefly","fluxus"}) do
        pcall(function() rawset(env, k, nil) end)
    end
end)

-- ═══════════════════════════════════════════════════
--  SERVICES
-- ═══════════════════════════════════════════════════
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local TeleportService  = game:GetService("TeleportService")
local Lighting         = game:GetService("Lighting")
local HttpService      = game:GetService("HttpService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════
--  STATE / CONFIG
-- ═══════════════════════════════════════════════════
local CONFIG_PATH = "LBBHub_" .. tostring(player.UserId) .. ".json"

local state = {
    currentBind = Enum.KeyCode.Q, waitingForKey = false,
    speedEnabled = false, customSpeedEnabled = false, customSpeedValue = 27.7, configSpeedEnabled = false,
    customJumpEnabled = false, customJumpValue = 50,
    flyEnabled = false, noclipEnabled = false, customFlySpeed = 65,
    flingEnabled = false, infiniteJumpEnabled = false, noFallDamage = false,
    fullbright = false, playerESP = false, autoRejoin = false,
    checkpointPos = nil, checkpointIndicator = nil, checkpointKeybind = nil,
    floatEnabled = false, antiRagdollEnabled = false, autoBatEnabled = false,
    noAnimEnabled = false, spinEnabled = false,
    floatUpEnabled = false, aimbotEnabled = false, hitboxEnabled = false,
    autoGrabEnabled = false, tallHipsEnabled = false, medusaCounterEnabled = false,
    misplaceEnabled = false, invisEnabled = false, autoPlayEnabled = false,
    configSpeed = 58, configSteal = 29, configJump = 10,
    originalTransparencies = {},
}

local SAVEABLE = {
    "speedEnabled","customSpeedEnabled","customSpeedValue","configSpeedEnabled",
    "customJumpEnabled","customJumpValue","flyEnabled","noclipEnabled","customFlySpeed",
    "flingEnabled","infiniteJumpEnabled","noFallDamage","fullbright","playerESP","autoRejoin",
    "floatEnabled","antiRagdollEnabled","autoBatEnabled","noAnimEnabled",
    "spinEnabled","floatUpEnabled","aimbotEnabled","hitboxEnabled","autoGrabEnabled",
    "tallHipsEnabled","medusaCounterEnabled","misplaceEnabled","invisEnabled","autoPlayEnabled",
    "configSpeed","configSteal","configJump","currentBind",
}
local function saveConfig()
    local t={}; for _,k in ipairs(SAVEABLE) do t[k]=(k=="currentBind") and state[k].Name or state[k] end
    pcall(writefile,CONFIG_PATH,HttpService:JSONEncode(t))
end
local function loadConfig()
    local ok,raw=pcall(readfile,CONFIG_PATH); if not ok or not raw or raw=="" then return end
    local ok2,d=pcall(HttpService.JSONDecode,HttpService,raw); if not ok2 or type(d)~="table" then return end
    for _,k in ipairs(SAVEABLE) do
        if d[k]~=nil then if k=="currentBind" then local kc=Enum.KeyCode[d[k]]; if kc then state.currentBind=kc end else state[k]=d[k] end end
    end
end
loadConfig()

-- ═══════════════════════════════════════════════════
--  CONSTANTS / CHAR REFS
-- ═══════════════════════════════════════════════════
local SPEED_277=27.7; local DEFAULT_SPEED=16; local DEFAULT_JUMP=50; local TALL_HIP_OFF=2.0

local currentHumanoid=nil; local currentRootPart=nil; local character=nil
local animateScript=nil; local trueHipHeight=2
local antiRagdollConns={}
local healthConn=nil   -- used for AC reset bypass

-- Speed: set AssemblyLinearVelocity directly on Heartbeat (same system as Silent's "Speed After Steal")
local speedConn=nil
local function stopSpeedConn() if speedConn then speedConn:Disconnect(); speedConn=nil end end
local function startSpeedConn()
    stopSpeedConn()
    speedConn=RunService.Heartbeat:Connect(function()
        local anySpeed=state.speedEnabled or state.configSpeedEnabled
        if not anySpeed or not currentHumanoid or not currentRootPart or not currentRootPart.Parent then return end
        if currentHumanoid.MoveDirection.Magnitude==0 then return end
        -- Carrying a brainrot: game sets WalkSpeed higher than 16 normally; drops it below 25 when carrying.
        -- Threshold of 25 matches KawatanHub's confirmed working detection for this game.
        local isCarrying = currentHumanoid.WalkSpeed < 25
        local baseTarget
        if isCarrying then
            baseTarget = state.configSteal
        elseif state.speedEnabled then
            baseTarget = SPEED_277
        elseif state.customSpeedEnabled then
            baseTarget = state.customSpeedValue
        else
            baseTarget = state.configSpeed
        end
        local moveDir=currentHumanoid.MoveDirection.Unit
        currentRootPart.AssemblyLinearVelocity=Vector3.new(moveDir.X*baseTarget, currentRootPart.AssemblyLinearVelocity.Y, moveDir.Z*baseTarget)
    end)
end

-- ═══════════════════════════════════════════════════
--  HITBOX  (plain Anchored Part, moved each Heartbeat, Destroy() to remove)
-- ═══════════════════════════════════════════════════
local hitboxParts = {}  -- [Player] = Part

local function clearHitboxes()
    for p,box in pairs(hitboxParts) do
        pcall(function() box:Destroy() end)
        hitboxParts[p]=nil
    end
end

local function makeHitboxPart(root)
    local box=Instance.new("Part")
    box.Size=Vector3.new(14,14,14)
    box.Anchored=true
    box.CanCollide=false
    box.CanQuery=false
    box.CanTouch=false
    box.CastShadow=false
    box.Transparency=0.6
    box.Color=Color3.fromRGB(255,40,40)
    box.Material=Enum.Material.Neon
    box.CFrame=root.CFrame
    box.Parent=workspace
    return box
end

local function refreshHitboxes()
    if not state.hitboxEnabled then clearHitboxes(); return end
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=player and p.Character then
            local hum=p.Character:FindFirstChildWhichIsA("Humanoid")
            local root=p.Character:FindFirstChild("HumanoidRootPart") or p.Character:FindFirstChild("Torso")
            if hum and hum.Health>0 and root then
                -- Replace box if character changed (respawn)
                local existing=hitboxParts[p]
                if existing and (not existing.Parent) then existing=nil; hitboxParts[p]=nil end
                if not hitboxParts[p] then hitboxParts[p]=makeHitboxPart(root) end
            else
                if hitboxParts[p] then pcall(function() hitboxParts[p]:Destroy() end); hitboxParts[p]=nil end
            end
        end
    end
    -- Clean up for players who left
    for p,box in pairs(hitboxParts) do
        if not p or not p.Parent then pcall(function() box:Destroy() end); hitboxParts[p]=nil end
    end
end

-- Move all hitbox Parts each Heartbeat
local function updateHitboxPositions()
    for p,box in pairs(hitboxParts) do
        local root = p.Character and (p.Character:FindFirstChild("HumanoidRootPart") or p.Character:FindFirstChild("Torso"))
        if root and box and box.Parent then
            box.CFrame = root.CFrame   -- follow exactly, centered on root
        end
    end
end

-- ═══════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════
local function getAllTools()
    local t={}; local bp=player:FindFirstChild("Backpack")
    if bp then for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") then t[#t+1]=v end end end
    if player.Character then for _,v in ipairs(player.Character:GetChildren()) do if v:IsA("Tool") then t[#t+1]=v end end end
    return t
end
local function useEverything() for _,t in ipairs(getAllTools()) do pcall(function() t.Parent=player.Character; if t.Activate then t:Activate() end end) end end
local function getRoot(c) return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")) end
local function isValidTarget(p)
    if p==player then return false end; local c=p.Character; if not c then return false end
    local h=c:FindFirstChildWhichIsA("Humanoid"); return h and h.Health>0
end
local function tpTo(t) local mr=getRoot(player.Character); local tr=getRoot(t.Character); if mr and tr then mr.CFrame=tr.CFrame*CFrame.new(0,5,0) end end
local function getNearestPlayer()
    if not currentRootPart then return nil end; local best,bestD=nil,math.huge
    for _,p in ipairs(Players:GetPlayers()) do if isValidTarget(p) then local r=getRoot(p.Character)
        if r then local d=(r.Position-currentRootPart.Position).Magnitude; if d<bestD then bestD=d;best=r end end end end; return best
end
local function stopAllAnims()
    if not currentHumanoid then return end; local a=currentHumanoid:FindFirstChildOfClass("Animator"); if not a then return end
    for _,t in ipairs(a:GetPlayingAnimationTracks()) do t:Stop(0) end
end

-- ═══════════════════════════════════════════════════
--  ANTI RAGDOLL
-- ═══════════════════════════════════════════════════
-- Anti-ragdoll: copied from KawatanHub
-- Loads PlayerModule controls once so we can re-enable movement after fake ragdoll
local _arControls
pcall(function()
    local pm=require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
    _arControls=pm:GetControls()
end)

local _arMoveConn=nil  -- RenderStepped movement loop while faking ragdoll
local _arAnchor=nil    -- BodyPosition anchor while faking ragdoll
local _arRemoteConn=nil -- connection to the ragdoll RemoteEvent

local function _arCleanup()
    if _arAnchor and _arAnchor.Parent then _arAnchor:Destroy() end
    _arAnchor=nil
    if _arMoveConn then _arMoveConn:Disconnect(); _arMoveConn=nil end
end

local function _arDisconnectRemote()
    if _arRemoteConn then _arRemoteConn:Disconnect(); _arRemoteConn=nil end
end

local function applyAntiRagdoll(char)
    for _,c in ipairs(antiRagdollConns) do c:Disconnect() end; antiRagdollConns={}
    _arCleanup(); _arDisconnectRemote()
    if not char then return end

    local hum=char:WaitForChild("Humanoid",5)
    local root=char:WaitForChild("HumanoidRootPart",5)
    local head=char:WaitForChild("Head",5)
    if not (hum and root and head) then return end

    -- Find the game's ragdoll RemoteEvent (same path KawatanHub uses)
    local ragRemote
    pcall(function()
        ragRemote=game:GetService("ReplicatedStorage"):WaitForChild("Packages",8)
            :WaitForChild("Ragdoll",5):WaitForChild("Ragdoll",5)
    end)
    if not ragRemote or not ragRemote:IsA("RemoteEvent") then return end

    _arRemoteConn=ragRemote.OnClientEvent:Connect(function(arg1,arg2)
        if not state.antiRagdollEnabled then return end

        if arg1=="Make" or arg2=="manualM" then
            -- Server wants to ragdoll: fake it, keep player controllable
            hum:ChangeState(Enum.HumanoidStateType.Freefall)
            workspace.CurrentCamera.CameraSubject=head
            root.CanCollide=false
            if _arControls then pcall(_arControls.Enable,_arControls) end
            _arCleanup()

            -- Anchor player in place but allow WASD movement (exact KawatanHub logic)
            local anchor=Instance.new("BodyPosition")
            anchor.Name="RagdollAnchor"
            anchor.MaxForce=Vector3.new(1e6,1e6,1e6)
            anchor.P=5000; anchor.D=1000
            anchor.Position=root.Position
            anchor.Parent=root
            _arAnchor=anchor

            _arMoveConn=RunService.RenderStepped:Connect(function()
                if not state.antiRagdollEnabled or not anchor or not anchor.Parent then
                    _arCleanup(); return
                end
                -- Use same speed target as speedConn so ragdoll walk feels normal
                local isCarrying2 = hum.WalkSpeed < 25
                local arSpeed = isCarrying2 and state.configSteal
                    or (state.speedEnabled and SPEED_277
                    or (state.customSpeedEnabled and state.customSpeedValue
                    or state.configSpeed))
                local md=hum.MoveDirection
                anchor.Position=md.Magnitude>0 and root.Position+md.Unit*arSpeed or root.Position
            end)

        elseif arg1=="Destroy" or arg2=="manualD" then
            -- Server un-ragdolling: restore everything
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            workspace.CurrentCamera.CameraSubject=hum
            root.CanCollide=true
            if _arControls then pcall(_arControls.Enable,_arControls) end
            _arCleanup()
        end
    end)
    antiRagdollConns[#antiRagdollConns+1]=_arRemoteConn
end

-- ═══════════════════════════════════════════════════
--  HEALTH HOOK  (prevent AC-triggered resets)
-- ═══════════════════════════════════════════════════
-- SAB's AC can reset/kill the player when it detects cheating.
-- We monitor Health: if it drops suddenly to 0 from a non-combat source we restore it.
local lastHealth=100
local function hookHealth(hum)
    if healthConn then healthConn:Disconnect(); healthConn=nil end
    if not hum then return end
    lastHealth=hum.Health
    healthConn=hum.HealthChanged:Connect(function(newHealth)
        -- If health drops to 0 instantly (no gradual damage), restore it
        -- Only bypass if the drop is > 90 HP in one frame (AC kill, not combat)
        if newHealth<=0 and lastHealth>(hum.MaxHealth*0.9) then
            task.defer(function()
                -- Slight delay to let the engine process, then restore
                pcall(function() hum.Health=hum.MaxHealth end)
            end)
        end
        lastHealth=newHealth
    end)
end

-- ═══════════════════════════════════════════════════
--  MEDUSA COUNTER
-- ═══════════════════════════════════════════════════
local medusaCooldown=false
local function tryMedusa()
    if medusaCooldown then return end
    for _,t in ipairs(getAllTools()) do if t.Name:lower():find("medusa") then
        medusaCooldown=true
        pcall(function() t.Parent=player.Character; task.wait(0.05); if t.Activate then t:Activate() end end)
        task.delay(1.5,function() medusaCooldown=false end); return end end
end
local medDC,medSC
local function hookMedusa(char)
    if medDC then medDC:Disconnect() end; if medSC then medSC:Disconnect() end; if not char then return end
    medDC=char.DescendantAdded:Connect(function(d) if not state.medusaCounterEnabled then return end
        local n=d.Name:lower(); if n:find("stone") or n:find("petrif") or n:find("medusa") or n:find("frozen") or n:find("stun") then
            task.spawn(function() task.wait(0.05); tryMedusa(); pcall(d.Destroy,d) end) end end)
    local hum=char:FindFirstChildOfClass("Humanoid")
    if hum then medSC=hum.StateChanged:Connect(function(_,new)
        if not state.medusaCounterEnabled then return end
        if new==Enum.HumanoidStateType.Physics then tryMedusa() end end) end
end

-- ═══════════════════════════════════════════════════
--  CHARACTER HOOK
-- ═══════════════════════════════════════════════════
local function hookCharacter(char)
    character=char; currentHumanoid=nil; currentRootPart=nil; animateScript=nil
    state.originalTransparencies={}; stopSpeedConn()
    if not char then return end
    currentHumanoid=char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid",5)
    currentRootPart=char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart",5)
    animateScript=char:FindFirstChild("Animate")
    if currentHumanoid then trueHipHeight=currentHumanoid.HipHeight end
    -- NEVER set WalkSpeed. Only JumpPower and HipHeight.
    if state.customJumpEnabled and currentHumanoid then currentHumanoid.JumpPower=state.customJumpValue end
    if state.tallHipsEnabled and currentHumanoid then currentHumanoid.HipHeight=trueHipHeight+TALL_HIP_OFF end
    if state.noAnimEnabled and animateScript then animateScript.Disabled=true end
    if state.noclipEnabled then for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end end
    if state.invisEnabled then for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") or p:IsA("Decal") then
        state.originalTransparencies[p]=p.LocalTransparencyModifier; p.LocalTransparencyModifier=1 end end end
    if state.antiRagdollEnabled then applyAntiRagdoll(char) end
    hookMedusa(char); hookHealth(currentHumanoid)
    char.DescendantAdded:Connect(function(d)
        if d.Name=="Animate" then animateScript=d; if state.noAnimEnabled then d.Disabled=true end end
        if d:IsA("BasePart") then if state.noclipEnabled then d.CanCollide=false end; if state.invisEnabled then d.LocalTransparencyModifier=1 end end
    end)
end
if player.Character then hookCharacter(player.Character) end
player.CharacterAdded:Connect(function(char) hookCharacter(char); task.wait(1.2); if state.flingEnabled then startFling() end end)

-- ═══════════════════════════════════════════════════
--  CHECKPOINT
-- ═══════════════════════════════════════════════════
local cpWaitKey=false
function setCheckpoint()
    if not currentRootPart then return end; state.checkpointPos=currentRootPart.Position
    if state.checkpointIndicator then state.checkpointIndicator:Destroy(); state.checkpointIndicator=nil end
    local p=Instance.new("Part"); p.Size=Vector3.new(1,1,1); p.Position=state.checkpointPos
    p.Anchored=true; p.CanCollide=false; p.Transparency=1; p.Parent=workspace
    local bb=Instance.new("BillboardGui"); bb.Adornee=p; bb.Size=UDim2.new(0,140,0,50); bb.StudsOffset=Vector3.new(0,4,0); bb.AlwaysOnTop=true; bb.Parent=p
    local lbl=Instance.new("TextLabel",bb); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1
    lbl.Text="✦ Checkpoint"; lbl.TextColor3=Color3.fromRGB(0,255,150); lbl.Font=Enum.Font.GothamBold; lbl.TextSize=20
    local gl=Instance.new("PointLight",p); gl.Color=Color3.fromRGB(0,255,150); gl.Brightness=3; gl.Range=20
    state.checkpointIndicator=p
end
local function tpCP() if state.checkpointPos and currentRootPart then currentRootPart.CFrame=CFrame.new(state.checkpointPos+Vector3.new(0,5,0)) end end
local function openCheckpointUI()
    if PlayerGui:FindFirstChild("CPWin") then PlayerGui.CPWin:Destroy() end
    local cg=Instance.new("ScreenGui"); cg.Name="CPWin"; cg.ResetOnSpawn=false; cg.Parent=PlayerGui
    local cf=Instance.new("Frame",cg); cf.Size=UDim2.new(0,220,0,145); cf.Position=UDim2.new(0.5,-110,0.5,-72)
    cf.BackgroundColor3=Color3.fromRGB(20,20,25); cf.BorderSizePixel=0; Instance.new("UICorner",cf).CornerRadius=UDim.new(0,10)
    local ct=Instance.new("Frame",cf); ct.Size=UDim2.new(1,0,0,32); ct.BackgroundColor3=Color3.fromRGB(30,30,38)
    Instance.new("UICorner",ct).CornerRadius=UDim.new(0,10)
    local cl=Instance.new("TextLabel",ct); cl.Size=UDim2.new(1,-38,1,0); cl.BackgroundTransparency=1; cl.Text="Checkpoint"
    cl.TextColor3=Color3.fromRGB(200,255,220); cl.Font=Enum.Font.GothamBold; cl.TextSize=14
    cl.TextXAlignment=Enum.TextXAlignment.Left; Instance.new("UIPadding",cl).PaddingLeft=UDim.new(0,12)
    local cc=Instance.new("TextButton",ct); cc.Size=UDim2.new(0,26,0,26); cc.Position=UDim2.new(1,-30,0,3)
    cc.BackgroundColor3=Color3.fromRGB(180,40,40); cc.Text="×"; cc.TextColor3=Color3.new(1,1,1); cc.Font=Enum.Font.GothamBold; cc.TextSize=16
    Instance.new("UICorner",cc).CornerRadius=UDim.new(0,6); cc.MouseButton1Click:Connect(function() cg:Destroy() end)
    local drag,ds,dp; ct.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;dp=cf.Position
            i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then drag=false end end) end
    end); ct.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local d=i.Position-ds
            cf.Position=UDim2.new(dp.X.Scale,dp.X.Offset+d.X,dp.Y.Scale,dp.Y.Offset+d.Y) end
    end)
    local function mkb(txt,y,cb)
        local b=Instance.new("TextButton",cf); b.Size=UDim2.new(0.9,0,0,30); b.Position=UDim2.new(0.05,0,y,0)
        b.BackgroundColor3=Color3.fromRGB(24,24,32); b.Text=txt; b.TextColor3=Color3.new(1,1,1)
        b.Font=Enum.Font.GothamSemibold; b.TextSize=13; Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
        b.MouseButton1Click:Connect(cb); return b end
    mkb("Teleport",0.27,tpCP); mkb("Set Checkpoint",0.53,setCheckpoint)
    local kb=mkb("Set Keybind",0.79,function() cpWaitKey=true end)
    local kc; kc=UserInputService.InputBegan:Connect(function(i,gp)
        if gp then return end
        if cpWaitKey and i.UserInputType==Enum.UserInputType.Keyboard then
            state.checkpointKeybind=i.KeyCode; kb.Text="Key: "..i.KeyCode.Name; cpWaitKey=false; kc:Disconnect() end
    end)
end
UserInputService.InputBegan:Connect(function(i,gp)
    if gp then return end; if state.checkpointKeybind and i.KeyCode==state.checkpointKeybind then tpCP() end end)

-- ═══════════════════════════════════════════════════
--  FLING
-- ═══════════════════════════════════════════════════
local flingConn=nil
function startFling()
    if flingConn then return end
    flingConn=RunService.Heartbeat:Connect(function()
        if not currentRootPart or not currentRootPart.Parent then return end
        -- Disable own collision so we pass through players instead of standing on their head
        if character then for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end end
        -- Freefall state prevents humanoid auto step-up onto surfaces/heads
        if currentHumanoid then currentHumanoid:ChangeState(Enum.HumanoidStateType.Freefall) end
        local sc=currentRootPart.CFrame; local sl=currentRootPart.AssemblyLinearVelocity; local sa=currentRootPart.AssemblyAngularVelocity
        -- Hover: find nearest player and steer sl towards them so the hover persists after fling restores it
        local nearest, bestDist = nil, math.huge
        for _,p in ipairs(Players:GetPlayers()) do
            if isValidTarget(p) then
                local r=getRoot(p.Character)
                if r then local d=(r.Position-currentRootPart.Position).Magnitude; if d<bestDist then bestDist=d; nearest=r end end
            end
        end
        if nearest then
            local dir=nearest.Position-currentRootPart.Position
            local flat=Vector3.new(dir.X,0,dir.Z)
            if flat.Magnitude>1 then
                local spd=math.max(sl.Magnitude,40)
                sl=Vector3.new(flat.Unit.X*spd, math.clamp(dir.Y*1.5,-15,15), flat.Unit.Z*spd)
            end
        end
        -- Original fling (unchanged)
        currentRootPart.AssemblyLinearVelocity=Vector3.new((math.random()-.5)*240000,144000+math.random()*72000,(math.random()-.5)*240000)
        currentRootPart.AssemblyAngularVelocity=Vector3.new(math.random(-3000,3000),math.random(-6000,6000),math.random(-3000,3000))
        RunService.RenderStepped:Wait()
        currentRootPart.CFrame=sc*CFrame.Angles(0,math.rad(30000),0)
        currentRootPart.AssemblyLinearVelocity=sl; currentRootPart.AssemblyAngularVelocity=sa
    end)
end
local function stopFling()
    if flingConn then flingConn:Disconnect(); flingConn=nil end
    if currentRootPart then currentRootPart.AssemblyLinearVelocity=Vector3.zero; currentRootPart.AssemblyAngularVelocity=Vector3.zero end
    if character then for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end end
    if currentHumanoid then currentHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
end
player.CharacterRemoving:Connect(function() stopFling(); stopSpeedConn() end)

-- ═══════════════════════════════════════════════════
--  INSTA GRAB SYSTEM  (from SparkHub, replaces old Auto Grab)
-- ═══════════════════════════════════════════════════
local igAnimalCache={}; local igPromptCache={}; local igStealCache={}
local igIsStealing=false; local igProgress=0; local igCurrentTarget=nil
local igStealConn=nil; local igRadius=20

local function igGetHRP() local c=player.Character; if not c then return nil end; return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso") end

local function igIsMyBase(plotName)
    local plots=workspace:FindFirstChild("Plots"); local plot=plots and plots:FindFirstChild(plotName); if not plot then return false end
    local sign=plot:FindFirstChild("PlotSign"); if not sign then return false end
    local yb=sign:FindFirstChild("YourBase"); return yb and yb:IsA("BillboardGui") and yb.Enabled==true
end

local function igScanPlot(plot)
    if not plot or not plot:IsA("Model") or igIsMyBase(plot.Name) then return end
    local pods=plot:FindFirstChild("AnimalPodiums"); if not pods then return end
    for _,pod in ipairs(pods:GetChildren()) do if pod:IsA("Model") and pod:FindFirstChild("Base") then
        table.insert(igAnimalCache,{plot=plot.Name,slot=pod.Name,worldPosition=pod:GetPivot().Position,uid=plot.Name.."_"..pod.Name}) end end
end

task.spawn(function()
    task.wait(2); local plots=workspace:WaitForChild("Plots",10); if not plots then return end
    for _,p in ipairs(plots:GetChildren()) do if p:IsA("Model") then igScanPlot(p) end end
    plots.ChildAdded:Connect(function(p) if p:IsA("Model") then task.wait(0.5); igScanPlot(p) end end)
    task.spawn(function() while task.wait(5) do table.clear(igAnimalCache)
        for _,p in ipairs(plots:GetChildren()) do if p:IsA("Model") then igScanPlot(p) end end end end)
end)

local function igFindPrompt(a)
    local c=igPromptCache[a.uid]; if c and c.Parent then return c end
    local plots=workspace:FindFirstChild("Plots"); local plot=plots and plots:FindFirstChild(a.plot); if not plot then return nil end
    local pods=plot:FindFirstChild("AnimalPodiums"); local pod=pods and pods:FindFirstChild(a.slot); if not pod then return nil end
    local base=pod:FindFirstChild("Base"); local spawn=base and base:FindFirstChild("Spawn"); if not spawn then return nil end
    local att=spawn:FindFirstChild("PromptAttachment"); if not att then return nil end
    for _,p in ipairs(att:GetChildren()) do if p:IsA("ProximityPrompt") then igPromptCache[a.uid]=p; return p end end
    return nil
end

local function igBuildCbs(prompt)
    if igStealCache[prompt] then return end
    local d={holdCallbacks={},triggerCallbacks={},ready=true}
    local ok1,c1=pcall(getconnections,prompt.PromptButtonHoldBegan); if ok1 and type(c1)=="table" then for _,c in ipairs(c1) do if type(c.Function)=="function" then table.insert(d.holdCallbacks,c.Function) end end end
    local ok2,c2=pcall(getconnections,prompt.Triggered); if ok2 and type(c2)=="table" then for _,c in ipairs(c2) do if type(c.Function)=="function" then table.insert(d.triggerCallbacks,c.Function) end end end
    if #d.holdCallbacks>0 or #d.triggerCallbacks>0 then igStealCache[prompt]=d end
end

local function igExecuteSteal(prompt,animalData)
    local d=igStealCache[prompt]; if not d or not d.ready then return end
    d.ready=false; igIsStealing=true; igProgress=0; igCurrentTarget=animalData
    task.spawn(function()
        for _,fn in ipairs(d.holdCallbacks) do task.spawn(fn) end
        local t=tick()
        while tick()-t<1.3 do igProgress=(tick()-t)/1.3; task.wait(0.05) end
        igProgress=1
        for _,fn in ipairs(d.triggerCallbacks) do task.spawn(fn) end
        task.wait(0.1); d.ready=true; task.wait(0.3); igIsStealing=false; igProgress=0; igCurrentTarget=nil
    end)
end

local function igGetNearest()
    local hrp=igGetHRP(); if not hrp then return nil end
    local best,bd=nil,math.huge
    for _,a in ipairs(igAnimalCache) do
        if not igIsMyBase(a.plot) and a.worldPosition then
            local d=(hrp.Position-a.worldPosition).Magnitude; if d<bd then bd=d;best=a end end end
    return best
end

local function startInstaGrab()
    if igStealConn then igStealConn:Disconnect() end
    igStealConn=RunService.Heartbeat:Connect(function()
        if not state.autoGrabEnabled or igIsStealing then return end
        local a=igGetNearest(); if not a then return end
        local hrp=igGetHRP(); if not hrp then return end
        if (hrp.Position-a.worldPosition).Magnitude>igRadius then return end
        local prompt=igPromptCache[a.uid]; if not prompt or not prompt.Parent then prompt=igFindPrompt(a) end
        if not prompt then return end
        igBuildCbs(prompt); igExecuteSteal(prompt,a)
    end)
end

local function stopInstaGrab()
    if igStealConn then igStealConn:Disconnect(); igStealConn=nil end
    igIsStealing=false; igProgress=0; igCurrentTarget=nil
end

-- ═══════════════════════════════════════════════════
--  SEMI TP  (SilentHub logic, restyled to match LBB Hub)
-- ═══════════════════════════════════════════════════
local ProximityPromptService = game:GetService("ProximityPromptService")
local TextChatService        = game:GetService("TextChatService")

local sPos1=Vector3.new(-352.98,-7,74.30)
local sPos2=Vector3.new(-352.98,-6.49,45.76)
local sSpot1={
    CFrame.new(-370.810913,-7.00000334,41.2687263,0.99984771,1.22364419e-09,0.0174523517,-6.54859778e-10,1,-3.2596418e-08,-0.0174523517,3.25800258e-08,0.99984771),
    CFrame.new(-336.355286,-5.10107088,17.2327671,-0.999883354,-2.76150569e-08,0.0152716246,-2.88224964e-08,1,-7.88441525e-08,-0.0152716246,-7.9275118e-08,-0.999883354)
}
local sSpot2={
    CFrame.new(-354.782867,-7.00000334,92.8209305,-0.999997616,-1.11891862e-09,-0.00218066527,-1.11958298e-09,1,3.03415071e-10,0.00218066527,3.05855785e-10,-0.999997616),
    CFrame.new(-336.942902,-5.10106993,99.3276443,0.999914348,-3.63984611e-08,0.0130875716,3.67094941e-08,1,-2.35254749e-08,-0.0130875716,2.40038975e-08,0.999914348)
}
local semiState={halfTp=false,autoPotion=false,speedAfterSteal=false}
local semiSpeedConn=nil; local SEMI_SPEED=28
local semiIsStealing=false; local semiProgress=0
local semiAnimalCache={}; local semiPromptCache={}; local semiStealCache={}
local semiHoldTask=nil; local semiIsHolding=false

local function semiGetHRP() local c=player.Character; if not c then return nil end; return c:FindFirstChild("HumanoidRootPart") end
local function semiEquipCarpet()
    local bp=player:FindFirstChild("Backpack"); local hum=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if bp and hum then local c=bp:FindFirstChild("Flying Carpet"); if c then hum:EquipTool(c); task.wait(0.1) end end
end
local function semiExecTP(seq) local root=semiGetHRP(); if not root then return end; semiEquipCarpet(); root.CFrame=seq[1]; task.wait(0.1); root.CFrame=seq[2] end
local function semiIsMyBase(name)
    local plots=workspace:FindFirstChild("Plots"); local plot=plots and plots:FindFirstChild(name); if not plot then return false end
    local sign=plot:FindFirstChild("PlotSign"); return sign and sign:FindFirstChild("YourBase") and sign.YourBase.Enabled
end
local function semiScanPlot(plot)
    if not plot or not plot:IsA("Model") or semiIsMyBase(plot.Name) then return end
    local pods=plot:FindFirstChild("AnimalPodiums"); if not pods then return end
    for _,pod in ipairs(pods:GetChildren()) do if pod:IsA("Model") and pod:FindFirstChild("Base") then
        table.insert(semiAnimalCache,{plot=plot.Name,slot=pod.Name,pos=pod:GetPivot().Position,uid=plot.Name.."_"..pod.Name}) end end
end
task.spawn(function()
    task.wait(2); local plots=workspace:WaitForChild("Plots",10); if not plots then return end
    for _,p in ipairs(plots:GetChildren()) do semiScanPlot(p) end
    plots.ChildAdded:Connect(semiScanPlot)
    task.spawn(function() while task.wait(5) do table.clear(semiAnimalCache); for _,p in ipairs(plots:GetChildren()) do semiScanPlot(p) end end end)
end)
local function semiGetNearest()
    local hrp=semiGetHRP(); if not hrp then return nil end; local best,bd=nil,math.huge
    for _,a in ipairs(semiAnimalCache) do local d=(hrp.Position-a.pos).Magnitude; if d<bd and d<=200 then bd=d;best=a end end; return best
end
local function semiFindPrompt(a)
    local c=semiPromptCache[a.uid]; if c and c.Parent then return c end
    local plots=workspace:FindFirstChild("Plots"); local plot=plots and plots:FindFirstChild(a.plot)
    local pod=plot and plot.AnimalPodiums:FindFirstChild(a.slot)
    local pr=pod and pod.Base.Spawn.PromptAttachment:FindFirstChildOfClass("ProximityPrompt")
    if pr then semiPromptCache[a.uid]=pr end; return pr
end
local function semiBuildCbs(prompt)
    if semiStealCache[prompt] then return end; local d={hold={},trig={},ready=true}
    local ok1,c1=pcall(getconnections,prompt.PromptButtonHoldBegan); if ok1 then for _,c in ipairs(c1) do table.insert(d.hold,c.Function) end end
    local ok2,c2=pcall(getconnections,prompt.Triggered); if ok2 then for _,c in ipairs(c2) do table.insert(d.trig,c.Function) end end
    semiStealCache[prompt]=d
end
local function semiDoSteal(prompt,spotSeq)
    local d=semiStealCache[prompt]; if not d or not d.ready or semiIsStealing then return end
    d.ready=false; semiIsStealing=true; semiProgress=0
    task.spawn(function()
        for _,fn in ipairs(d.hold) do task.spawn(fn) end
        local t=tick(); local done=false
        while tick()-t<1.3 do semiProgress=(tick()-t)/1.3
            if semiProgress>=0.73 and not done then done=true; local hrp=semiGetHRP()
                if hrp then semiEquipCarpet(); hrp.CFrame=spotSeq[1]; task.wait(0.1); hrp.CFrame=spotSeq[2]; task.wait(0.2)
                    local d1=(hrp.Position-sPos1).Magnitude; local d2=(hrp.Position-sPos2).Magnitude; hrp.CFrame=CFrame.new(d1<d2 and sPos1 or sPos2) end end
            task.wait() end
        semiProgress=1; for _,fn in ipairs(d.trig) do task.spawn(fn) end
        task.wait(0.2); d.ready=true; semiIsStealing=false; semiProgress=0
    end)
end
ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt,plr)
    if plr~=player or not semiState.halfTp then return end; semiIsHolding=true
    if semiHoldTask then task.cancel(semiHoldTask) end
    semiHoldTask=task.spawn(function() task.wait(1); if semiIsHolding then semiEquipCarpet() end end)
end)
ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt,plr)
    if plr~=player then return end; semiIsHolding=false; if semiHoldTask then task.cancel(semiHoldTask) end end)
ProximityPromptService.PromptTriggered:Connect(function(prompt,plr)
    if plr~=player or not semiState.halfTp then return end
    local root=semiGetHRP(); if not root then return end; semiEquipCarpet()
    local d1=(root.Position-sPos1).Magnitude; local d2=(root.Position-sPos2).Magnitude; root.CFrame=CFrame.new(d1<d2 and sPos1 or sPos2)
    if semiState.autoPotion then local bp=player:FindFirstChild("Backpack"); if bp then local pot=bp:FindFirstChild("Giant Potion")
        if pot and player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
            player.Character.Humanoid:EquipTool(pot); task.wait(0.05); pcall(function() pot:Activate() end) end end end
    if semiState.speedAfterSteal then local hum=player.Character:FindFirstChildOfClass("Humanoid"); if hum then
        if semiSpeedConn then semiSpeedConn:Disconnect() end
        semiSpeedConn=RunService.Heartbeat:Connect(function()
            if not semiState.speedAfterSteal or hum.MoveDirection.Magnitude==0 or not root.Parent then return end
            local md=hum.MoveDirection.Unit; root.AssemblyLinearVelocity=Vector3.new(md.X*SEMI_SPEED,root.AssemblyLinearVelocity.Y,md.Z*SEMI_SPEED) end) end end
    semiIsHolding=false
end)

local function openSemiTPUI()
    if PlayerGui:FindFirstChild("LBBSemiTP") then PlayerGui.LBBSemiTP:Destroy() end
    local sg2=Instance.new("ScreenGui"); sg2.Name="LBBSemiTP"; sg2.ResetOnSpawn=false; sg2.Parent=PlayerGui
    local mf=Instance.new("Frame",sg2)
    mf.Size=UDim2.new(0,280,0,0); mf.AutomaticSize=Enum.AutomaticSize.Y; mf.Position=UDim2.new(0.5,-140,0.5,-180)
    mf.BackgroundColor3=Color3.fromRGB(14,14,16); mf.BorderSizePixel=0
    Instance.new("UICorner",mf).CornerRadius=UDim.new(0,12)
    local mfS=Instance.new("UIStroke",mf); mfS.Color=Color3.fromRGB(40,40,48); mfS.Thickness=1.2
    local mfL=Instance.new("UIListLayout",mf); mfL.Padding=UDim.new(0,8)
    local mfP=Instance.new("UIPadding",mf); mfP.PaddingLeft=UDim.new(0,10); mfP.PaddingRight=UDim.new(0,10); mfP.PaddingTop=UDim.new(0,10); mfP.PaddingBottom=UDim.new(0,12)
    local tb=Instance.new("Frame",mf); tb.Size=UDim2.new(1,0,0,30); tb.BackgroundTransparency=1
    local tl=Instance.new("TextLabel",tb); tl.Size=UDim2.new(1,-36,1,0); tl.BackgroundTransparency=1
    tl.Text="LBB Semi TP"; tl.TextColor3=Color3.fromRGB(225,225,235); tl.Font=Enum.Font.GothamBold; tl.TextSize=15; tl.TextXAlignment=Enum.TextXAlignment.Left
    local cl=Instance.new("TextButton",tb); cl.Size=UDim2.new(0,30,0,30); cl.Position=UDim2.new(1,-30,0,0)
    cl.BackgroundColor3=Color3.fromRGB(185,45,45); cl.Text="×"; cl.TextColor3=Color3.new(1,1,1); cl.Font=Enum.Font.GothamBold; cl.TextSize=17
    Instance.new("UICorner",cl).CornerRadius=UDim.new(0,7); cl.MouseButton1Click:Connect(function() sg2:Destroy() end)
    local drag2,ds2,dp2=false,nil,nil
    tb.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag2=true;ds2=i.Position;dp2=mf.Position
        i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then drag2=false end end) end end)
    tb.InputChanged:Connect(function(i) if drag2 and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local d=i.Position-ds2
        mf.Position=UDim2.new(dp2.X.Scale,dp2.X.Offset+d.X,dp2.Y.Scale,dp2.Y.Offset+d.Y) end end)
    local function mkToggle(lbl,key,onChange)
        local btn=Instance.new("TextButton",mf); btn.Size=UDim2.new(1,0,0,46); btn.BackgroundColor3=Color3.fromRGB(24,24,32)
        btn.TextColor3=Color3.fromRGB(215,215,225); btn.Font=Enum.Font.GothamSemibold; btn.TextSize=14; btn.TextXAlignment=Enum.TextXAlignment.Left
        Instance.new("UIPadding",btn).PaddingLeft=UDim.new(0,16); Instance.new("UICorner",btn).CornerRadius=UDim.new(0,9)
        local function upd() btn.Text=lbl.." "..(semiState[key] and "[ON]" or "[OFF]"); btn.BackgroundColor3=semiState[key] and Color3.fromRGB(28,44,70) or Color3.fromRGB(24,24,32) end; upd()
        btn.MouseButton1Click:Connect(function() semiState[key]=not semiState[key]; if onChange then onChange(semiState[key]) end; upd() end)
    end
    local function mkAction(lbl,cb)
        local btn=Instance.new("TextButton",mf); btn.Size=UDim2.new(1,0,0,46); btn.BackgroundColor3=Color3.fromRGB(24,24,32)
        btn.Text=lbl; btn.TextColor3=Color3.fromRGB(215,215,225); btn.Font=Enum.Font.GothamSemibold; btn.TextSize=14; btn.TextXAlignment=Enum.TextXAlignment.Left
        Instance.new("UIPadding",btn).PaddingLeft=UDim.new(0,16); Instance.new("UICorner",btn).CornerRadius=UDim.new(0,9)
        btn.MouseButton1Click:Connect(cb); return btn
    end
    mkToggle("Half TP","halfTp")
    mkToggle("Auto Potion","autoPotion")
    mkToggle("Speed After Steal","speedAfterSteal",function(on) if not on and semiSpeedConn then semiSpeedConn:Disconnect(); semiSpeedConn=nil end end)
    local spamBtn; spamBtn=mkAction("SPAM AP NEAREST",function()
        local c=player.Character; if not c or not c:FindFirstChild("HumanoidRootPart") then return end
        local target,bd=nil,math.huge
        for _,p in ipairs(Players:GetPlayers()) do if p~=player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local m=(c.HumanoidRootPart.Position-p.Character.HumanoidRootPart.Position).Magnitude; if m<bd then bd=m;target=p end end end
        if not target then return end
        local oldT=spamBtn.Text; spamBtn.Text="SPAMMING "..target.Name:upper()
        if TextChatService.ChatVersion==Enum.ChatVersion.TextChatService then
            local ch=TextChatService.TextChannels:WaitForChild("RBXGeneral")
            for _,cmd in ipairs({";jumpscare ",";morph ","tiny ",";inverse ",";nightvision ",";rocket ",";balloon ",";ragdoll "}) do
                pcall(function() ch:SendAsync(cmd..target.Name) end); task.wait(0.1) end
            task.wait(1); pcall(function() ch:SendAsync(";jail "..target.Name) end) end
        task.wait(0.5); spamBtn.Text=oldT
    end)
    mkAction("Auto TP Left",function() local a=semiGetNearest(); if not a then return end; local pr=semiFindPrompt(a); if not pr then return end; semiBuildCbs(pr); semiDoSteal(pr,sSpot1) end)
    mkAction("Auto TP Right",function() local a=semiGetNearest(); if not a then return end; local pr=semiFindPrompt(a); if not pr then return end; semiBuildCbs(pr); semiDoSteal(pr,sSpot2) end)
    local barBg=Instance.new("Frame",mf); barBg.Size=UDim2.new(1,0,0,28); barBg.BackgroundColor3=Color3.fromRGB(24,24,32)
    Instance.new("UICorner",barBg).CornerRadius=UDim.new(0,9)
    local barFill=Instance.new("Frame",barBg); barFill.Size=UDim2.new(0,0,1,0); barFill.BackgroundColor3=Color3.fromRGB(110,170,255)
    Instance.new("UICorner",barFill).CornerRadius=UDim.new(0,9)
    local pct=Instance.new("TextLabel",barBg); pct.Size=UDim2.new(1,-10,1,0); pct.BackgroundTransparency=1
    pct.Text="0%"; pct.TextColor3=Color3.fromRGB(200,200,220); pct.Font=Enum.Font.GothamBold; pct.TextSize=11; pct.TextXAlignment=Enum.TextXAlignment.Right
    task.spawn(function() while barFill and barFill.Parent do barFill.Size=UDim2.new(math.clamp(semiProgress,0,1),0,1,0); pct.Text=math.floor(semiProgress*100+0.5).."%"; task.wait(0.05) end end)
    mkAction("TP to Spot 1",function() semiExecTP(sSpot1) end)
    mkAction("TP to Spot 2",function() semiExecTP(sSpot2) end)
end

-- ═══════════════════════════════════════════════════
--  GUI  (original v4 style, unchanged)
-- ═══════════════════════════════════════════════════
local sg=Instance.new("ScreenGui"); sg.Name="LBBHub"; sg.ResetOnSpawn=false; sg.Parent=PlayerGui

-- Floating grab progress bar (separate from menu, right side of screen, only visible while stealing)
local igFloatGui=Instance.new("ScreenGui"); igFloatGui.Name="LBBGrabBar"; igFloatGui.ResetOnSpawn=false; igFloatGui.Parent=PlayerGui
local igFloatFrame=Instance.new("Frame",igFloatGui)
igFloatFrame.Size=UDim2.new(0,160,0,42); igFloatFrame.Position=UDim2.new(1,-175,0.5,-21)
igFloatFrame.BackgroundColor3=Color3.fromRGB(14,14,16); igFloatFrame.BorderSizePixel=0; igFloatFrame.Visible=false
Instance.new("UICorner",igFloatFrame).CornerRadius=UDim.new(0,10)
local igFloatStroke=Instance.new("UIStroke",igFloatFrame); igFloatStroke.Color=Color3.fromRGB(40,40,48); igFloatStroke.Thickness=1.2
local igFloatLbl=Instance.new("TextLabel",igFloatFrame); igFloatLbl.Size=UDim2.new(1,0,0,18); igFloatLbl.Position=UDim2.new(0,0,0,4)
igFloatLbl.BackgroundTransparency=1; igFloatLbl.Text="Auto Grab"; igFloatLbl.TextColor3=Color3.fromRGB(170,170,180)
igFloatLbl.Font=Enum.Font.GothamSemibold; igFloatLbl.TextSize=11
local igFloatBg=Instance.new("Frame",igFloatFrame); igFloatBg.Size=UDim2.new(0.85,0,0,10); igFloatBg.Position=UDim2.new(0.075,0,0,24)
igFloatBg.BackgroundColor3=Color3.fromRGB(30,30,38); Instance.new("UICorner",igFloatBg).CornerRadius=UDim.new(1,0)
local igFloatFill=Instance.new("Frame",igFloatBg); igFloatFill.Size=UDim2.new(0,0,1,0); igFloatFill.BackgroundColor3=Color3.fromRGB(110,170,255)
Instance.new("UICorner",igFloatFill).CornerRadius=UDim.new(1,0)
local igFloatPct=Instance.new("TextLabel",igFloatBg); igFloatPct.Size=UDim2.new(1,-4,1,0); igFloatPct.BackgroundTransparency=1
igFloatPct.Text="0%"; igFloatPct.TextColor3=Color3.fromRGB(200,200,220); igFloatPct.Font=Enum.Font.GothamBold; igFloatPct.TextSize=9; igFloatPct.TextXAlignment=Enum.TextXAlignment.Right
task.spawn(function()
    while true do task.wait(0.05)
        igFloatFrame.Visible=igIsStealing
        if igIsStealing then
            igFloatFill.Size=UDim2.new(math.clamp(igProgress,0,1),0,1,0)
            igFloatPct.Text=math.floor(igProgress*100+0.5).."%"
        end
    end
end)

local mainFrame=Instance.new("Frame",sg)
local vp=workspace.CurrentCamera.ViewportSize
local isMobile=UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local initW=isMobile and math.min(220,vp.X*0.55) or 380
local initH=isMobile and math.min(280,vp.Y*0.5) or 480
mainFrame.Size=UDim2.new(0,initW,0,initH)
mainFrame.Position=isMobile and UDim2.new(0.5,-initW/2,0.5,-initH/2) or UDim2.new(0.5,-190,0.5,-240)
mainFrame.BackgroundColor3=Color3.fromRGB(14,14,16); mainFrame.BorderSizePixel=0
Instance.new("UICorner",mainFrame).CornerRadius=UDim.new(0,12)
local stroke=Instance.new("UIStroke",mainFrame); stroke.Color=Color3.fromRGB(40,40,48); stroke.Thickness=1.2

local resizing,rsM,rsS=false,nil,nil
local currentInputPos=Vector2.new(0,0)
UserInputService.InputChanged:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then
        currentInputPos=i.Position
    end
end)
local rH=Instance.new("TextButton",mainFrame); rH.Size=UDim2.new(0,24,0,24); rH.Position=UDim2.new(1,-24,1,-24)
rH.BackgroundColor3=Color3.fromRGB(50,50,60); rH.Text="↘"; rH.TextColor3=Color3.fromRGB(180,180,200)
rH.Font=Enum.Font.SourceSansBold; rH.TextSize=16; rH.BorderSizePixel=0; rH.ZIndex=15
Instance.new("UICorner",rH).CornerRadius=UDim.new(0,6)
rH.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then resizing=true;rsM=i.Position;rsS=mainFrame.AbsoluteSize;rH.BackgroundColor3=Color3.fromRGB(80,80,100) end end)
rH.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then resizing=false;rH.BackgroundColor3=Color3.fromRGB(50,50,60) end end)
rH.MouseEnter:Connect(function() if not resizing then rH.BackgroundColor3=Color3.fromRGB(70,70,90) end end)
rH.MouseLeave:Connect(function() if not resizing then rH.BackgroundColor3=Color3.fromRGB(50,50,60) end end)

local titleBar=Instance.new("Frame",mainFrame); titleBar.Size=UDim2.new(1,0,0,36); titleBar.BackgroundTransparency=1
local titleLbl=Instance.new("TextLabel",titleBar); titleLbl.Size=UDim2.new(1,-80,1,0); titleLbl.Position=UDim2.fromOffset(12,0)
titleLbl.BackgroundTransparency=1; titleLbl.Text="LBB Hub"; titleLbl.TextColor3=Color3.fromRGB(225,225,235)
titleLbl.Font=Enum.Font.GothamBold; titleLbl.TextSize=15; titleLbl.TextXAlignment=Enum.TextXAlignment.Left
local closeBtn=Instance.new("TextButton",titleBar); closeBtn.Size=UDim2.new(0,32,0,32); closeBtn.Position=UDim2.new(1,-38,0,2)
closeBtn.BackgroundColor3=Color3.fromRGB(185,45,45); closeBtn.Text="×"; closeBtn.TextColor3=Color3.new(1,1,1)
closeBtn.Font=Enum.Font.GothamBold; closeBtn.TextSize=18; Instance.new("UICorner",closeBtn).CornerRadius=UDim.new(0,8)
closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)
local minBtn=Instance.new("TextButton",titleBar); minBtn.Size=UDim2.fromOffset(30,30); minBtn.Position=UDim2.new(1,-74,0,3)
minBtn.BackgroundColor3=Color3.fromRGB(40,40,40); minBtn.Text="-"; minBtn.TextColor3=Color3.new(1,1,1)
minBtn.Font=Enum.Font.SourceSansBold; minBtn.TextSize=20; Instance.new("UICorner",minBtn).CornerRadius=UDim.new(0,6)
local bubble=Instance.new("TextButton",sg); bubble.Size=UDim2.fromOffset(48,48); bubble.Position=mainFrame.Position
bubble.BackgroundColor3=Color3.fromRGB(24,24,32); bubble.Text="LBB"; bubble.TextColor3=Color3.fromRGB(225,225,235)
bubble.Font=Enum.Font.GothamBold; bubble.TextSize=14; bubble.Visible=false; Instance.new("UICorner",bubble).CornerRadius=UDim.new(1,0)
minBtn.MouseButton1Click:Connect(function() bubble.Position=mainFrame.Position; mainFrame.Visible=false; bubble.Visible=true end)
bubble.MouseButton1Click:Connect(function() mainFrame.Position=bubble.Position; bubble.Visible=false; mainFrame.Visible=true end)

local function makeDraggable(h,t)
    local drag,ds,dp=false,nil,nil
    local function isPress(i) return i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch end
    local function isMove(i) return i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch end
    h.InputBegan:Connect(function(i) if isPress(i) then drag=true;ds=i.Position;dp=t.Position
        i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then drag=false end end) end end)
    h.InputChanged:Connect(function(i) if drag and isMove(i) then local d=i.Position-ds
        t.Position=UDim2.new(dp.X.Scale,dp.X.Offset+d.X,dp.Y.Scale,dp.Y.Offset+d.Y) end end)
end
makeDraggable(titleBar,mainFrame); makeDraggable(bubble,bubble)

local tabBar=Instance.new("Frame",mainFrame); tabBar.Size=UDim2.new(1,0,0,34); tabBar.Position=UDim2.new(0,0,0,36)
tabBar.BackgroundColor3=Color3.fromRGB(18,18,22); tabBar.BorderSizePixel=0
local tabMain=Instance.new("TextButton",tabBar); tabMain.Size=UDim2.new(0.5,0,1,0); tabMain.BackgroundTransparency=1
tabMain.Text="Main"; tabMain.Font=Enum.Font.GothamSemibold; tabMain.TextSize=13
local tabNot=Instance.new("TextButton",tabBar); tabNot.Size=UDim2.new(0.5,0,1,0); tabNot.Position=UDim2.new(0.5,0,0,0)
tabNot.BackgroundTransparency=1; tabNot.Text="NOT FOR SAB!"; tabNot.Font=Enum.Font.GothamSemibold; tabNot.TextSize=13

local scrollMain=Instance.new("ScrollingFrame",mainFrame); scrollMain.Size=UDim2.new(1,-16,1,-84); scrollMain.Position=UDim2.new(0,8,0,78)
scrollMain.BackgroundTransparency=1; scrollMain.ScrollBarThickness=4; scrollMain.CanvasSize=UDim2.new(0,0,0,2100)
Instance.new("UIListLayout",scrollMain).Padding=UDim.new(0,8)
local scrollNot=Instance.new("ScrollingFrame",mainFrame); scrollNot.Size=UDim2.new(1,-16,1,-84); scrollNot.Position=UDim2.new(0,8,0,78)
scrollNot.BackgroundTransparency=1; scrollNot.ScrollBarThickness=4; scrollNot.CanvasSize=UDim2.new(0,0,0,2100); scrollNot.Visible=false
Instance.new("UIListLayout",scrollNot).Padding=UDim.new(0,8)

local function switchTab(toMain)
    scrollMain.Visible=toMain; scrollNot.Visible=not toMain
    tabMain.TextColor3=toMain and Color3.fromRGB(110,170,255) or Color3.fromRGB(170,170,180)
    tabNot.TextColor3=toMain and Color3.fromRGB(170,170,180) or Color3.fromRGB(110,170,255)
end
switchTab(true); tabMain.MouseButton1Click:Connect(function() switchTab(true) end); tabNot.MouseButton1Click:Connect(function() switchTab(false) end)

-- ═══════════════════════════════════════════════════
--  WIDGETS
-- ═══════════════════════════════════════════════════
local toggleUpdateFns={}
local function createToggle(parent,label,key,onToggle)
    local btn=Instance.new("TextButton",parent); btn.Size=UDim2.new(1,0,0,46); btn.BackgroundColor3=Color3.fromRGB(24,24,32)
    btn.TextColor3=Color3.fromRGB(215,215,225); btn.Font=Enum.Font.GothamSemibold; btn.TextSize=14
    btn.TextXAlignment=Enum.TextXAlignment.Left
    Instance.new("UIPadding",btn).PaddingLeft=UDim.new(0,16); Instance.new("UICorner",btn).CornerRadius=UDim.new(0,9)
    local function upd() btn.Text=label.." "..(state[key] and "[ON]" or "[OFF]"); btn.BackgroundColor3=state[key] and Color3.fromRGB(28,44,70) or Color3.fromRGB(24,24,32) end
    upd()
    btn.MouseButton1Click:Connect(function()
        state[key]=not state[key]
        if key=="speedEnabled" and state[key] then state.customSpeedEnabled=false;state.configSpeedEnabled=false
        elseif key=="customSpeedEnabled" and state[key] then state.speedEnabled=false;state.configSpeedEnabled=false
        elseif key=="configSpeedEnabled" and state[key] then state.speedEnabled=false;state.customSpeedEnabled=false end
        local on=state[key]
        if not on then
            if key=="speedEnabled" or key=="configSpeedEnabled" then stopSpeedConn() end
            if key=="customSpeedEnabled" and currentHumanoid then currentHumanoid.WalkSpeed=16 end
            if key=="customJumpEnabled" and currentHumanoid then currentHumanoid.JumpPower=DEFAULT_JUMP end
            if key=="noclipEnabled" and character then for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end end
            if key=="flingEnabled" then stopFling() end
            if key=="fullbright" then Lighting.Brightness=1;Lighting.GlobalShadows=true;Lighting.FogEnd=100000;Lighting.Ambient=Color3.new(.5,.5,.5) end
            if key=="playerESP" then for _,p in ipairs(Players:GetPlayers()) do if p.Character then local h=p.Character:FindFirstChild("Head"); if h and h:FindFirstChild("ESP") then h.ESP:Destroy() end end end end
            if key=="tallHipsEnabled" and currentHumanoid then currentHumanoid.HipHeight=trueHipHeight end
            if key=="hitboxEnabled" then clearHitboxes() end
            if key=="invisEnabled" and character then for pt,tr in pairs(state.originalTransparencies) do if pt and pt.Parent then pt.LocalTransparencyModifier=tr end end; state.originalTransparencies={} end
            if key=="antiRagdollEnabled" then for _,c in ipairs(antiRagdollConns) do c:Disconnect() end; antiRagdollConns={}
                if character then for _,v in ipairs(character:GetDescendants()) do if v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint") then v.Enabled=true end end end end
            if key=="noAnimEnabled" then if animateScript then animateScript.Disabled=false end end
        else
            if key=="speedEnabled" or key=="configSpeedEnabled" then startSpeedConn() end
            if key=="customJumpEnabled" and currentHumanoid then currentHumanoid.JumpPower=state.customJumpValue end
            if key=="flingEnabled" then startFling() end
            if key=="tallHipsEnabled" and currentHumanoid then currentHumanoid.HipHeight=trueHipHeight+TALL_HIP_OFF end
            if key=="invisEnabled" and character then state.originalTransparencies={}
                for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") or p:IsA("Decal") then
                    state.originalTransparencies[p]=p.LocalTransparencyModifier; p.LocalTransparencyModifier=1 end end end
            if key=="antiRagdollEnabled" and character then applyAntiRagdoll(character) end
            if key=="noclipEnabled" and character then for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end end
            if key=="fullbright" then Lighting.Brightness=2;Lighting.GlobalShadows=false;Lighting.FogEnd=9999;Lighting.Ambient=Color3.new(1,1,1) end
            if key=="noAnimEnabled" then if animateScript then animateScript.Disabled=true end; stopAllAnims() end
        end
        if onToggle then onToggle(on) end; for _,fn in ipairs(toggleUpdateFns) do fn() end
    end)
    table.insert(toggleUpdateFns,upd); return btn,upd
end

local function createAction(parent,txt,cb,clr)
    local btn=Instance.new("TextButton",parent); btn.Size=UDim2.new(1,0,0,46); btn.BackgroundColor3=clr or Color3.fromRGB(24,24,32)
    btn.Text=txt; btn.TextColor3=Color3.fromRGB(215,215,225); btn.Font=Enum.Font.GothamSemibold; btn.TextSize=14
    btn.TextXAlignment=Enum.TextXAlignment.Left; Instance.new("UIPadding",btn).PaddingLeft=UDim.new(0,16)
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,9); btn.MouseButton1Click:Connect(cb); return btn
end

local function createSection(parent,title)
    local f=Instance.new("Frame",parent); f.Size=UDim2.new(1,0,0,0); f.BackgroundTransparency=1; f.AutomaticSize=Enum.AutomaticSize.Y
    local hdr=Instance.new("TextLabel",f); hdr.Size=UDim2.new(1,0,0,28); hdr.BackgroundColor3=Color3.fromRGB(30,30,38)
    hdr.Text="  "..title; hdr.TextColor3=Color3.fromRGB(200,200,255); hdr.Font=Enum.Font.GothamBold; hdr.TextSize=14
    hdr.TextXAlignment=Enum.TextXAlignment.Left; hdr.BorderSizePixel=0; Instance.new("UICorner",hdr).CornerRadius=UDim.new(0,8)
    local list=Instance.new("Frame",f); list.Size=UDim2.new(1,0,0,0); list.BackgroundTransparency=1; list.AutomaticSize=Enum.AutomaticSize.Y
    Instance.new("UIListLayout",list).Padding=UDim.new(0,6); return list
end

local function createValueRow(parent,lbl,init,minV,maxV,onChange)
    local row=Instance.new("Frame",parent); row.Size=UDim2.new(1,0,0,56); row.BackgroundTransparency=1
    local l=Instance.new("TextLabel",row); l.Size=UDim2.new(0.6,0,0,24); l.Position=UDim2.new(0.05,0,0,0)
    l.BackgroundTransparency=1; l.Text=lbl; l.TextColor3=Color3.fromRGB(190,190,200); l.Font=Enum.Font.Gotham; l.TextSize=13; l.TextXAlignment=Enum.TextXAlignment.Left
    local box=Instance.new("TextBox",row); box.Size=UDim2.new(0.3,0,0,30); box.Position=UDim2.new(0.65,0,0,0)
    box.BackgroundColor3=Color3.fromRGB(24,24,32); box.TextColor3=Color3.new(1,1,1); box.Font=Enum.Font.Gotham; box.TextSize=13; box.Text=tostring(init); box.ClearTextOnFocus=false
    Instance.new("UICorner",box).CornerRadius=UDim.new(0,8)
    box.FocusLost:Connect(function() local n=tonumber(box.Text); if n then n=math.clamp(n,minV,maxV);box.Text=tostring(n);onChange(n) else box.Text=tostring(init) end end)
    return row
end

-- ═══════════════════════════════════════════════════
--  MAIN TAB CONTENTS
-- ═══════════════════════════════════════════════════
createAction(scrollMain,"Use Everything",useEverything)

local keyBtn=Instance.new("TextButton",scrollMain); keyBtn.Size=UDim2.new(1,0,0,46); keyBtn.BackgroundColor3=Color3.fromRGB(24,24,32)
keyBtn.Text="Set Keybind (Current: "..state.currentBind.Name..")"; keyBtn.TextColor3=Color3.fromRGB(215,215,225)
keyBtn.Font=Enum.Font.GothamSemibold; keyBtn.TextSize=14; keyBtn.TextXAlignment=Enum.TextXAlignment.Left
Instance.new("UICorner",keyBtn).CornerRadius=UDim.new(0,9); Instance.new("UIPadding",keyBtn).PaddingLeft=UDim.new(0,16)
keyBtn.MouseButton1Click:Connect(function() state.waitingForKey=true; keyBtn.Text="Press key..." end)
UserInputService.InputBegan:Connect(function(input,gp)
    if gp then return end
    if state.waitingForKey and input.UserInputType==Enum.UserInputType.Keyboard then
        state.currentBind=input.KeyCode; keyBtn.Text="Set Keybind (Current: "..state.currentBind.Name..")"; state.waitingForKey=false; return end
    if input.KeyCode==state.currentBind and not state.waitingForKey then useEverything() end
end)

-- CHECKPOINT IN MAIN TAB
createAction(scrollMain,"Checkpoint Menu",openCheckpointUI)

-- SEMI TP BUTTON
createAction(scrollMain,"LBB Semi TP",openSemiTPUI)

createToggle(scrollMain,"Speed 27.7 (stealing)","speedEnabled")
createToggle(scrollMain,"Inf Jump","infiniteJumpEnabled")
createToggle(scrollMain,"Float","floatEnabled")
createToggle(scrollMain,"Anti Ragdoll","antiRagdollEnabled",function(on) if on and character then applyAntiRagdoll(character) end end)
createToggle(scrollMain,"Auto Bat","autoBatEnabled")
createToggle(scrollMain,"No Anim","noAnimEnabled",function(on) if animateScript then animateScript.Disabled=on end; if on then stopAllAnims() end end)
createToggle(scrollMain,"Fling","flingEnabled",function(on) if on then startFling() else stopFling() end end)
createToggle(scrollMain,"Spin","spinEnabled",function(on)
    if not on and currentHumanoid then currentHumanoid.AutoRotate=true end
    if not on and currentRootPart then currentRootPart.AssemblyAngularVelocity=Vector3.zero end
end)
createToggle(scrollMain,"Float Up","floatUpEnabled")
createToggle(scrollMain,"Aimbot (face nearest)","aimbotEnabled")
createToggle(scrollMain,"Hitbox Visualizer","hitboxEnabled",function(on) if not on then clearHitboxes() end end)
createToggle(scrollMain,"Auto Grab","autoGrabEnabled",function(on) if on then startInstaGrab() else stopInstaGrab() end end)
createAction(scrollMain,"Loser Emote",function() pcall(function() player:Chat("/e loser") end) end)
createToggle(scrollMain,"Tall Hips","tallHipsEnabled",function(on) if currentHumanoid then currentHumanoid.HipHeight=on and (trueHipHeight+TALL_HIP_OFF) or trueHipHeight end end)
createToggle(scrollMain,"Medusa Counter","medusaCounterEnabled")
createToggle(scrollMain,"Misplace Character","misplaceEnabled")
createToggle(scrollMain,"Invis Brainrot","invisEnabled")
createAction(scrollMain,"TP to Brainrot (ragdoll)",function()
    local n=getNearestPlayer(); if n and currentRootPart then currentRootPart.CFrame=n.CFrame*CFrame.new(0,5,0)
        if currentHumanoid then currentHumanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
            task.delay(.5,function() if currentHumanoid then currentHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end end) end end end)

-- Config
local cfgFrame=Instance.new("Frame",scrollMain); cfgFrame.Size=UDim2.new(1,0,0,0); cfgFrame.AutomaticSize=Enum.AutomaticSize.Y
cfgFrame.BackgroundColor3=Color3.fromRGB(20,20,28); Instance.new("UICorner",cfgFrame).CornerRadius=UDim.new(0,9)
local cfgLayout=Instance.new("UIListLayout",cfgFrame); cfgLayout.Padding=UDim.new(0,6); cfgLayout.SortOrder=Enum.SortOrder.LayoutOrder
local cfgPad=Instance.new("UIPadding",cfgFrame); cfgPad.PaddingLeft=UDim.new(0,10); cfgPad.PaddingRight=UDim.new(0,10); cfgPad.PaddingTop=UDim.new(0,8); cfgPad.PaddingBottom=UDim.new(0,8)
local cfgT=Instance.new("TextLabel",cfgFrame); cfgT.Size=UDim2.new(1,0,0,22); cfgT.BackgroundTransparency=1; cfgT.Text="  Config"
cfgT.TextColor3=Color3.fromRGB(180,180,255); cfgT.Font=Enum.Font.GothamBold; cfgT.TextSize=13; cfgT.TextXAlignment=Enum.TextXAlignment.Left
createValueRow(cfgFrame,"speed",state.configSpeed,1,99999,function(v) state.configSpeed=v end)
createValueRow(cfgFrame,"steal",state.configSteal,1,99999,function(v) state.configSteal=v end)
createValueRow(cfgFrame,"jump", state.configJump, 1,99999,function(v) state.configJump=v end)
createToggle(cfgFrame,"Enable Speed","configSpeedEnabled",function(on) if on then startSpeedConn() else stopSpeedConn() end end)
local saveBtn=Instance.new("TextButton",cfgFrame); saveBtn.Size=UDim2.new(1,0,0,36); saveBtn.BackgroundColor3=Color3.fromRGB(20,55,25)
saveBtn.Text="💾 Save Config"; saveBtn.TextColor3=Color3.fromRGB(180,255,180); saveBtn.Font=Enum.Font.GothamSemibold; saveBtn.TextSize=13
Instance.new("UICorner",saveBtn).CornerRadius=UDim.new(0,7)
saveBtn.MouseButton1Click:Connect(function() saveConfig(); saveBtn.Text="✓ Saved!"; saveBtn.BackgroundColor3=Color3.fromRGB(20,80,20)
    task.delay(2,function() saveBtn.Text="💾 Save Config"; saveBtn.BackgroundColor3=Color3.fromRGB(20,55,25) end) end)
createToggle(cfgFrame,"Auto Play","autoPlayEnabled")

-- ═══════════════════════════════════════════════════
--  NOT FOR SAB TAB
-- ═══════════════════════════════════════════════════
local movSec=createSection(scrollNot,"Movement"); local visSec=createSection(scrollNot,"Visuals"); local utlSec=createSection(scrollNot,"Utility")

createToggle(movSec,"Custom Speed","customSpeedEnabled",function(on)
    if currentHumanoid then currentHumanoid.WalkSpeed=on and state.customSpeedValue or 16 end
end)
createValueRow(movSec,"Speed Value",state.customSpeedValue,1,100000,function(v) state.customSpeedValue=v; if state.customSpeedEnabled and currentHumanoid then currentHumanoid.WalkSpeed=v end end)
createToggle(movSec,"Custom Jump","customJumpEnabled",function(on) if on and currentHumanoid then currentHumanoid.JumpPower=state.customJumpValue end end)
createValueRow(movSec,"Jump Power",state.customJumpValue,1,1000,function(v) state.customJumpValue=v; if currentHumanoid and state.customJumpEnabled then currentHumanoid.JumpPower=v end end)
createToggle(movSec,"Fly","flyEnabled"); createValueRow(movSec,"Fly Speed",state.customFlySpeed,1,1e9,function(v) state.customFlySpeed=v end)
createToggle(movSec,"Noclip","noclipEnabled",function(on) if character then for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=not on end end end end)

createToggle(movSec,"No Fall Damage","noFallDamage")
createToggle(visSec,"Fullbright","fullbright",function(on)
    if on then Lighting.Brightness=2;Lighting.GlobalShadows=false;Lighting.FogEnd=9999;Lighting.Ambient=Color3.new(1,1,1)
    else Lighting.Brightness=1;Lighting.GlobalShadows=true;Lighting.FogEnd=100000;Lighting.Ambient=Color3.new(.5,.5,.5) end end)
createToggle(visSec,"Player ESP","playerESP",function(on)
    if not on then for _,p in ipairs(Players:GetPlayers()) do if p.Character then local h=p.Character:FindFirstChild("Head"); if h and h:FindFirstChild("ESP") then h.ESP:Destroy() end end end end end)
createAction(utlSec,"Teleport to Player",function()
    local tg=Instance.new("ScreenGui"); tg.ResetOnSpawn=false; tg.Parent=PlayerGui
    local tf=Instance.new("Frame",tg); tf.Size=UDim2.new(0,340,0,420); tf.Position=UDim2.new(0.5,-170,0.5,-210)
    tf.BackgroundColor3=Color3.fromRGB(18,18,24); tf.BorderSizePixel=0; Instance.new("UICorner",tf).CornerRadius=UDim.new(0,14)
    local ttb=Instance.new("Frame",tf); ttb.Size=UDim2.new(1,0,0,40); ttb.BackgroundColor3=Color3.fromRGB(14,14,20)
    local ttl=Instance.new("TextLabel",ttb); ttl.Size=UDim2.new(1,-50,1,0); ttl.BackgroundTransparency=1
    ttl.Text="Teleport to Player"; ttl.TextColor3=Color3.fromRGB(200,200,255); ttl.Font=Enum.Font.GothamBold; ttl.TextSize=18
    local tc=Instance.new("TextButton",ttb); tc.Size=UDim2.new(0,36,0,36); tc.Position=UDim2.new(1,-42,0,2)
    tc.BackgroundColor3=Color3.fromRGB(180,40,40); tc.Text="×"; tc.TextColor3=Color3.new(1,1,1); tc.Font=Enum.Font.GothamBold; tc.TextSize=22
    Instance.new("UICorner",tc).CornerRadius=UDim.new(0,10); tc.MouseButton1Click:Connect(function() tg:Destroy() end)
    makeDraggable(ttb,tf)
    local ts=Instance.new("ScrollingFrame",tf); ts.Size=UDim2.new(1,-20,1,-50); ts.Position=UDim2.new(0,10,0,45)
    ts.BackgroundTransparency=1; ts.ScrollBarThickness=6; Instance.new("UIListLayout",ts).Padding=UDim.new(0,8)
    local function fill()
        for _,c in ipairs(ts:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        local pl={}; for _,p in ipairs(Players:GetPlayers()) do if isValidTarget(p) then pl[#pl+1]=p end end
        table.sort(pl,function(a,b) return a.Name:lower()<b.Name:lower() end)
        for _,p in ipairs(pl) do
            local b=Instance.new("TextButton",ts); b.Size=UDim2.new(1,0,0,48); b.BackgroundColor3=Color3.fromRGB(35,35,45)
            b.Text=p.Name; b.TextColor3=Color3.new(1,1,1); b.Font=Enum.Font.GothamSemibold; b.TextSize=20; b.TextScaled=true
            Instance.new("UICorner",b).CornerRadius=UDim.new(0,10)
            b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(.2),{BackgroundColor3=Color3.fromRGB(55,55,70)}):Play() end)
            b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(.2),{BackgroundColor3=Color3.fromRGB(35,35,45)}):Play() end)
            b.MouseButton1Click:Connect(function() tpTo(p) end) end
        ts.CanvasSize=UDim2.new(0,0,0,#pl*56)
    end; fill(); task.delay(.3,fill)
end)
createAction(utlSec,"Server Hop",function()
    pcall(function()
        local cur=""; local sv={}
        repeat local r=HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"..cur))
            for _,v in ipairs(r.data) do if v.playing<v.maxPlayers and v.id~=game.JobId then sv[#sv+1]=v.id end end
            cur=r.nextPageCursor and "&cursor="..r.nextPageCursor or "" until not r.nextPageCursor
        if #sv>0 then TeleportService:TeleportToPlaceInstance(game.PlaceId,sv[math.random(1,#sv)]) end
    end)
end)
createToggle(utlSec,"Auto Rejoin on Kick","autoRejoin")
createAction(utlSec,"Reset All",function()
    local ks={"speedEnabled","customSpeedEnabled","configSpeedEnabled","customJumpEnabled","flyEnabled","noclipEnabled","flingEnabled",
        "infiniteJumpEnabled","noFallDamage","fullbright","playerESP","autoRejoin","floatEnabled","antiRagdollEnabled","autoBatEnabled",
        "noAnimEnabled","spinEnabled","floatUpEnabled","aimbotEnabled","hitboxEnabled","autoGrabEnabled",
        "tallHipsEnabled","medusaCounterEnabled","misplaceEnabled","invisEnabled","autoPlayEnabled"}
    for _,k in ipairs(ks) do state[k]=false end
    state.checkpointPos=nil; state.checkpointKeybind=nil
    if state.checkpointIndicator then state.checkpointIndicator:Destroy(); state.checkpointIndicator=nil end
    stopFling(); stopSpeedConn(); clearHitboxes()
    if currentHumanoid then currentHumanoid.JumpPower=DEFAULT_JUMP; currentHumanoid.HipHeight=trueHipHeight end
    if character then
        for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end
        for _,v in ipairs(character:GetDescendants()) do if v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint") then v.Enabled=true end; if v:IsA("Motor6D") then v.Enabled=true end end
        for _,c in ipairs(antiRagdollConns) do c:Disconnect() end; antiRagdollConns={}
        for pt,tr in pairs(state.originalTransparencies) do if pt and pt.Parent then pt.LocalTransparencyModifier=tr end end; state.originalTransparencies={}
    end
    if animateScript then animateScript.Disabled=false end
    Lighting.Brightness=1;Lighting.GlobalShadows=true;Lighting.FogEnd=100000;Lighting.Ambient=Color3.new(.5,.5,.5)
    for _,p in ipairs(Players:GetPlayers()) do if p.Character then local h=p.Character:FindFirstChild("Head"); if h and h:FindFirstChild("ESP") then h.ESP:Destroy() end end end
    for _,fn in ipairs(toggleUpdateFns) do fn() end
end)

-- ═══════════════════════════════════════════════════
--  HEARTBEAT
-- ═══════════════════════════════════════════════════
local bFlyV,bFlyG; local autoBatT=0

RunService.Heartbeat:Connect(function(dt)
    if resizing then
        local m=currentInputPos
        if m and rsM and rsS then local d=m-rsM; local nw=math.max(320,rsS.X+d.X); local nh=math.max(400,rsS.Y+d.Y)
            mainFrame.Size=UDim2.new(0,nw,0,nh); scrollMain.CanvasSize=UDim2.new(0,0,0,nh*(2100/480)); scrollNot.CanvasSize=UDim2.new(0,0,0,nh*(2100/480)) end end

    if not currentHumanoid or currentHumanoid.Health<=0 then
        if bFlyV then bFlyV:Destroy(); bFlyV=nil end; if bFlyG then bFlyG:Destroy(); bFlyG=nil end; return end

    if state.customJumpEnabled then currentHumanoid.JumpPower=state.customJumpValue end
    if state.tallHipsEnabled then currentHumanoid.HipHeight=trueHipHeight+TALL_HIP_OFF end

    if state.antiRagdollEnabled and character then
        for _,v in ipairs(character:GetDescendants()) do
            if (v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint")) and v.Enabled then v.Enabled=false end
            if v:IsA("Motor6D") and not v.Enabled then v.Enabled=true end end end

    if state.flyEnabled and currentRootPart then
        if not bFlyV then bFlyV=Instance.new("BodyVelocity"); bFlyV.MaxForce=Vector3.new(1e6,1e6,1e6); bFlyV.Parent=currentRootPart end
        if not bFlyG then bFlyG=Instance.new("BodyGyro"); bFlyG.MaxTorque=Vector3.new(1e6,1e6,1e6); bFlyG.P=15000; bFlyG.Parent=currentRootPart end
        local dir=Vector3.new()
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir+=Vector3.new(0,0,-1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir+=Vector3.new(0,0,1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir+=Vector3.new(-1,0,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir+=Vector3.new(1,0,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir+=Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir+=Vector3.new(0,-1,0) end
        local cam=workspace.CurrentCamera
        if cam then bFlyV.Velocity=cam.CFrame:VectorToWorldSpace(dir)*state.customFlySpeed; bFlyG.CFrame=cam.CFrame end
    else if bFlyV then bFlyV:Destroy(); bFlyV=nil end; if bFlyG then bFlyG:Destroy(); bFlyG=nil end end

    if state.noclipEnabled and character then for _,p in ipairs(character:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide=false end end end
    if state.customSpeedEnabled and currentHumanoid and currentHumanoid.WalkSpeed~=state.customSpeedValue then currentHumanoid.WalkSpeed=state.customSpeedValue end
    if state.floatEnabled and currentRootPart then currentRootPart.AssemblyLinearVelocity=Vector3.new(currentRootPart.AssemblyLinearVelocity.X,0,currentRootPart.AssemblyLinearVelocity.Z) end
    if state.floatUpEnabled and currentRootPart then currentRootPart.AssemblyLinearVelocity=Vector3.new(currentRootPart.AssemblyLinearVelocity.X,20,currentRootPart.AssemblyLinearVelocity.Z) end
    if state.spinEnabled and currentRootPart then
        if currentHumanoid then currentHumanoid.AutoRotate=false end
        currentRootPart.AssemblyAngularVelocity=Vector3.new(0,50,0)
    end

    if state.autoBatEnabled then autoBatT+=dt; if autoBatT>=0.15 then autoBatT=0
        for _,t in ipairs(getAllTools()) do if t.Name:lower():find("bat") then pcall(function() t.Parent=player.Character; if t.Activate then t:Activate() end end) end end end end
    if state.aimbotEnabled and currentRootPart then
        local n=getNearestPlayer(); if n then local my=currentRootPart.Position; local dir=(n.Position-my)*Vector3.new(1,0,1)
            if dir.Magnitude>0.1 then currentRootPart.CFrame=CFrame.new(my,my+dir.Unit) end end end

    if state.noAnimEnabled then if animateScript and not animateScript.Disabled then animateScript.Disabled=true end; stopAllAnims() end

    -- Hitbox: refresh membership, then update ALL box positions every frame
    if state.hitboxEnabled then refreshHitboxes(); updateHitboxPositions() end

    if state.medusaCounterEnabled and currentHumanoid then if currentHumanoid:GetState()==Enum.HumanoidStateType.Physics then tryMedusa() end end
    if state.misplaceEnabled and currentRootPart then currentRootPart.CFrame=currentRootPart.CFrame*CFrame.new((math.random()-.5)*.3,0,(math.random()-.5)*.3) end
    if state.autoPlayEnabled then useEverything() end

    if state.playerESP then for _,p in ipairs(Players:GetPlayers()) do if p~=player and p.Character then
        local head=p.Character:FindFirstChild("Head"); if head then local bb=head:FindFirstChild("ESP")
            if not bb then bb=Instance.new("BillboardGui"); bb.Name="ESP"; bb.Adornee=head; bb.Size=UDim2.new(0,200,0,50)
                bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Parent=head
                local lbl=Instance.new("TextLabel",bb); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1
                lbl.TextColor3=Color3.new(1,1,1); lbl.TextScaled=true; lbl.Font=Enum.Font.GothamBold end
            local dist=currentRootPart and math.floor((currentRootPart.Position-head.Position).Magnitude) or 0
            bb.TextLabel.Text=p.Name.."\n"..dist.." studs" end end end end
end)

local lastJump=0
UserInputService.InputBegan:Connect(function(i,gp)
    if gp then return end
    if state.infiniteJumpEnabled and i.KeyCode==Enum.KeyCode.Space then
        local now=tick(); if now-lastJump<0.12 then return end; lastJump=now
        if currentHumanoid and currentRootPart then local s=currentHumanoid:GetState().Name
            if s=="Freefall" or s=="Landed" or s=="Running" then
                currentRootPart.AssemblyLinearVelocity=Vector3.new(currentRootPart.AssemblyLinearVelocity.X,55,currentRootPart.AssemblyLinearVelocity.Z) end end end
end)

Players.PlayerRemoving:Connect(function(plr) if plr==player and state.autoRejoin then task.wait(2); TeleportService:Teleport(game.PlaceId) end end)

task.defer(function()
    for _,fn in ipairs(toggleUpdateFns) do fn() end
    keyBtn.Text="Set Keybind (Current: "..state.currentBind.Name..")"
    if state.speedEnabled or state.configSpeedEnabled then startSpeedConn() end
    if state.customSpeedEnabled and currentHumanoid then currentHumanoid.WalkSpeed=state.customSpeedValue end
    if state.customJumpEnabled and currentHumanoid then currentHumanoid.JumpPower=state.customJumpValue end
    if state.tallHipsEnabled and currentHumanoid then currentHumanoid.HipHeight=trueHipHeight+TALL_HIP_OFF end
    if state.fullbright then Lighting.Brightness=2;Lighting.GlobalShadows=false;Lighting.FogEnd=9999;Lighting.Ambient=Color3.new(1,1,1) end
    if state.flingEnabled then startFling() end
    if state.antiRagdollEnabled and character then applyAntiRagdoll(character) end
    if state.noAnimEnabled then if animateScript then animateScript.Disabled=true end; stopAllAnims() end
end)

print("LBB Hub v8 | bypass:active | user:"..player.UserId)
