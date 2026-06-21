_G.Status = "Ready!"
wait(2)

local getinfo = getinfo or debug.getinfo
local DEBUG = false
local Hooked = {}

local Detected, Kill
setthreadidentity(2)

for i, v in pairs(getgc(true)) do
    if typeof(v) == "table" then
        local DetectFunc = rawget(v, "Detected")
        local KillFunc = rawget(v, "Kill")
        if typeof(DetectFunc) == "function" and not Detected then
            Detected = DetectFunc
            hookfunction(DetectFunc, function() return true end)
        end
        if typeof(KillFunc) == "function" and not Kill then
            Kill = KillFunc
            hookfunction(KillFunc, function() return nil end)
        end
    end
end
setthreadidentity(7)
wait(2)

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua"))()

local Window = Library:CreateWindow({
    Title = "TownV1.3",
    Center = true,
    AutoShow = true,
})

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local CurrentCamera = Workspace.CurrentCamera

getgenv().ForceMouseUnlock = true

local SilentAim = {
    Enabled = false,
    TargetPart = "Head",
    HealthCheck = true,
    PassiveCheck = false,
    WallCheck = false,
    Kent = false,
    FOV = { Radius = 60, Visible = false, Color = Color3.fromRGB(171, 0, 255) },
    Tracer = { Enabled = false, Color = Color3.fromRGB(171, 0, 255), Thickness = 1 },
    FlashPartNames = {"Flash", "FlashPart", "FirePoint", "Muzzle"},
}

local SilentAimFOVCircle, TracerLine
local IsTargeting = false
local originalIndex
local lastWallCheck = 0
local wallCheckCache = {}

local function InitSilentAimDrawings()
    SilentAimFOVCircle = SilentAimFOVCircle or Drawing.new("Circle")
    TracerLine = TracerLine or Drawing.new("Line")
    SilentAimFOVCircle.Transparency = 0.7
    SilentAimFOVCircle.Thickness = 1
    SilentAimFOVCircle.Filled = false
    SilentAimFOVCircle.Color = SilentAim.FOV.Color
    TracerLine.Transparency = 1
    TracerLine.Thickness = SilentAim.Tracer.Thickness
    TracerLine.Color = SilentAim.Tracer.Color
end

local function getFlashPart()
    if not player.Character then return nil end
    local tool = player.Character:FindFirstChildOfClass("Tool")
    if not tool then return nil end
    for _, name in ipairs(SilentAim.FlashPartNames) do
        local flash = tool:FindFirstChild(name, true)
        if flash and flash:IsA("BasePart") then return flash end
    end
    local handle = tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then return handle end
    return nil
end

local function hasForceField(char) return char and char:FindFirstChildOfClass("ForceField") end
local function hasGunScript()
    local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
    return tool and tool:FindFirstChild("GunScript")
end

local function getCursorCenter()
    local vp = CurrentCamera.ViewportSize
    return Vector2.new(vp.X/2, vp.Y/2)
end

local function WallCheck(origin, destination)
    if not SilentAim.WallCheck then return true end
    local cacheKey = tostring(origin)..tostring(destination)
    if wallCheckCache[cacheKey] and tick() - lastWallCheck < 0.1 then return wallCheckCache[cacheKey] end
    local dir = (destination - origin)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {player.Character, CurrentCamera}
    params.IgnoreWater = true
    local res = workspace:Raycast(origin, dir.Unit * dir.Magnitude, params)
    local success = not res or res.Instance.CanCollide == false or (res.Instance.Transparency or 0) > 0.9
    wallCheckCache[cacheKey] = success
    lastWallCheck = tick()
    return success
end

local function FindBestTarget()
    if not SilentAim.Enabled then return nil end
    local flash = getFlashPart()
    local origin = flash and flash.Position or CurrentCamera.CFrame.Position
    local best, closest = nil, math.huge
    local center = getCursorCenter()

    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        local char = p.Character
        if not char then continue end
        if SilentAim.PassiveCheck and hasForceField(char) then continue end
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 or (SilentAim.HealthCheck and hum.Health <= 1) then continue end

        local tPart = char:FindFirstChild(SilentAim.TargetPart) or char:FindFirstChild("Head")
        if not tPart then continue end

        local predPos = tPart.Position
        if not WallCheck(origin, predPos) then continue end

        local screen, onScreen = CurrentCamera:WorldToViewportPoint(predPos)
        if not onScreen then continue end
        local dist = (Vector2.new(screen.X, screen.Y) - center).Magnitude
        if dist < SilentAim.FOV.Radius and dist < closest then
            closest = dist
            best = {PredictedPosition = predPos}
        end
    end
    IsTargeting = best ~= nil
    return best
end

local function UpdateSilentAimVisuals()
    local center = getCursorCenter()
    if SilentAimFOVCircle then
        SilentAimFOVCircle.Position = center
        SilentAimFOVCircle.Visible = SilentAim.Enabled and SilentAim.FOV.Visible
        SilentAimFOVCircle.Radius = SilentAim.FOV.Radius
    end
    if TracerLine and SilentAim.Tracer.Enabled and IsTargeting then
        local tgt = FindBestTarget()
        if tgt then
            local sp = CurrentCamera:WorldToViewportPoint(tgt.PredictedPosition)
            TracerLine.From = center
            TracerLine.To = Vector2.new(sp.X, sp.Y)
            TracerLine.Visible = true
        end
    elseif TracerLine then TracerLine.Visible = false end
end

if not originalIndex then
    originalIndex = hookmetamethod(game, "__index", function(self, key)
        if not SilentAim.Enabled then return originalIndex(self, key) end
        if self:IsA("Mouse") and key == "Hit" then
            if not hasGunScript() then return originalIndex(self, key) end
            local tgt = FindBestTarget()
            if tgt then
                IsTargeting = true
                return CFrame.new(tgt.PredictedPosition)
            end
            IsTargeting = false
        end
        return originalIndex(self, key)
    end)
end

local flyEnabled = false
local desyncEnabled = false
local flySpeed = 50
local flyConnection = nil
local bodyVelocity = nil
local desyncOffset = 5

local function startFly()
    if flyEnabled then return end
    flyEnabled = true
    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end

    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bodyVelocity.Velocity = Vector3.new(0,0,0)
    bodyVelocity.Parent = char.HumanoidRootPart

    flyConnection = RunService.Heartbeat:Connect(function()
        if not flyEnabled then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local moveDir = Vector3.new()
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0,1,0) end

        if moveDir.Magnitude > 0 then
            moveDir = moveDir.Unit * flySpeed
        end

        if desyncEnabled then
            local desyncVec = Vector3.new(math.random(-desyncOffset, desyncOffset), 0, math.random(-desyncOffset, desyncOffset))
            bodyVelocity.Velocity = moveDir + desyncVec
        else
            bodyVelocity.Velocity = moveDir
        end
    end)
end

local function stopFly()
    flyEnabled = false
    desyncEnabled = false
    if flyConnection then flyConnection:Disconnect() end
    if bodyVelocity then bodyVelocity:Destroy() end
end

local autoShootEnabled = false
local autoShootConnection = nil

local function startAutoShoot()
    if autoShootConnection then return end
    autoShootConnection = RunService.Heartbeat:Connect(function()
        if not autoShootEnabled then return end
        local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
        if tool and tool:FindFirstChild("GunScript") then
            local target = FindBestTarget()
            if target then mouse1click() end
        end
    end)
end

local function stopAutoShoot()
    if autoShootConnection then autoShootConnection:Disconnect() end
    autoShootConnection = nil
end

local isEnabled = false
local connections = {}

local function cleanup()
    for _, c in ipairs(connections) do if c then c:Disconnect() end end
    connections = {}
end

local function FindWeaponInWorkspace(tool)
    if not tool then return nil end
    local pf = Workspace:FindFirstChild(player.Name)
    return pf and pf:FindFirstChild(tool.Name, true)
end

local function IsWeaponReady(weapon)
    return weapon and weapon:FindFirstChild("GunScript") and weapon.GunScript:FindFirstChild("ClientAmmo")
end

local function freezeAmmo(weapon)
    if not IsWeaponReady(weapon) then return end
    local ammo = weapon.GunScript.ClientAmmo
    local orig = ammo.Value
    local conn = ammo.Changed:Connect(function()
        if ammo.Value ~= orig then ammo.Value = orig end
    end)
    table.insert(connections, conn)
end

local function forceReload(character)
    if not character then return end
    for _, tool in ipairs(character:GetDescendants()) do
        if tool:IsA("Tool") then
            local weapon = FindWeaponInWorkspace(tool)
            if weapon and weapon:FindFirstChild("ReloadEvent") then
                local re = weapon.ReloadEvent
                re:FireServer({[11] = "startReload"})
                re:FireServer({[14] = 0, [11] = "magMath"})
                re:FireServer({[14] = 3, [11] = "insertMag"})
                re:FireServer({[14] = 3, [11] = "stopReload"})
            end
        end
    end
end

local function processWeapons(char)
    if not char then return end
    for _, tool in ipairs(char:GetDescendants()) do
        if tool:IsA("Tool") then
            local w = FindWeaponInWorkspace(tool)
            if IsWeaponReady(w) then freezeAmmo(w) end
        end
    end
    forceReload(char)
end

local function mainLoop()
    while isEnabled do
        local char = player.Character or player.CharacterAdded:Wait()
        processWeapons(char)
        task.wait(0.1)
    end
end

local playerEspEnabled = false
local Distance = false
local playerEspCache = {}

local function getPlayerPosition(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or (char:FindFirstChild("Head") and char.Head.Position)
end

local function getPlayerHealth(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and math.floor(hum.Health) or 0
end

local function createHighlight(adornee, color)
    local hl = Instance.new("Highlight")
    hl.FillColor = color
    hl.FillTransparency = 0.7
    hl.OutlineColor = color
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = adornee
    hl.Enabled = true
    return hl
end

local function setupPlayerESP(p)
    if playerEspCache[p] then return end
    local char = p.Character
    if not char then return end

    local mainContainer = Instance.new("ScreenGui")
    mainContainer.Name = "ESP_" .. p.Name
    mainContainer.Parent = CoreGui

    local teamColor = p.Team and p.Team.TeamColor.Color or Color3.new(1,1,1)
    local hl = createHighlight(char, teamColor)

    local head = char:FindFirstChild("Head")
    if head then
        local bb = Instance.new("BillboardGui")
        bb.Adornee = head
        bb.Size = UDim2.new(0, 160, 0, 45)
        bb.AlwaysOnTop = true
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.Parent = mainContainer

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1,0,1,0)
        label.Font = Enum.Font.SourceSansSemibold
        label.TextSize = 13
        label.TextColor3 = teamColor
        label.TextStrokeTransparency = 0.4
        label.Parent = bb

        playerEspCache[p] = {mainContainer = mainContainer, label = label, character = char, highlight = hl}
    end
end

local function cleanupPlayerESP(p)
    local data = playerEspCache[p]
    if data and data.mainContainer then data.mainContainer:Destroy() end
    playerEspCache[p] = nil
end

local function refreshPlayerESP()
    for p in pairs(playerEspCache) do cleanupPlayerESP(p) end
    if playerEspEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player then setupPlayerESP(p) end
        end
    end
end

local function updateESPLabels()
    local camPos = Camera.CFrame.Position
    for p, data in pairs(playerEspCache) do
        if not p.Character or not p.Character.Parent then
            cleanupPlayerESP(p)
        else
            local pos = getPlayerPosition(data.character)
            if pos then
                local dist = (pos - camPos).Magnitude * 0.36
                local hp = getPlayerHealth(data.character)
                if Distance then
                    data.label.Text = string.format("%s\nHP: %d | %.0fm", p.Name, hp, dist)
                else
                    data.label.Text = string.format("%s\nHP: %d", p.Name, hp)
                end
            end
        end
    end
end

local spinbotEnabled = false
local spinConnection = nil
local spinSpeed = 50

local function startSpinbot()
    if spinConnection then return end
    spinConnection = RunService.Heartbeat:Connect(function()
        if not spinbotEnabled or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
        local root = player.Character.HumanoidRootPart
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(spinSpeed), 0)
    end)
end

local function stopSpinbot()
    spinbotEnabled = false
    if spinConnection then spinConnection:Disconnect() spinConnection = nil end
end

local thirdPersonEnabled = false
local fullBrightEnabled = false
local brightConnection = nil

local function toggleThirdPerson(v)
    thirdPersonEnabled = v
    local camClient = player.PlayerGui:FindFirstChild("CameraClient")
    if camClient then camClient.Enabled = not v end
end

local function toggleFullBright(v)
    fullBrightEnabled = v
    if v then
        brightConnection = RunService.RenderStepped:Connect(function()
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
            Lighting.OutdoorAmbient = Color3.fromRGB(128,128,128)
        end)
    else
        if brightConnection then brightConnection:Disconnect() end
    end
end

local objectMoverEnabled = false
local movedObjectsFolder = nil

local function startWallBang()
    if objectMoverEnabled then return end
    objectMoverEnabled = true
    movedObjectsFolder = Instance.new("Folder")
    movedObjectsFolder.Name = "MovedFromWorkspace"
    movedObjectsFolder.Parent = Camera

end

local function stopWallBang()
    objectMoverEnabled = false
    if movedObjectsFolder then movedObjectsFolder:Destroy() end
end

local FirstTestTab = Window:AddTab("First Test")

local Combat = FirstTestTab:AddLeftGroupbox("Combat")
local Visuals = FirstTestTab:AddRightGroupbox("Visuals")
local Movement = FirstTestTab:AddRightGroupbox("Movement")

-- Silent Aim
Combat:AddToggle("SilentAimToggle", {Text = "Silent Aim", Default = false, Callback = function(v) SilentAim.Enabled = v; if v then InitSilentAimDrawings() end end})
Combat:AddSlider("SilentFOVSize", {Text = "Silent Aim FOV", Default = 60, Min = 10, Max = 800, Rounding = 0, Callback = function(v) SilentAim.FOV.Radius = v end})
Combat:AddToggle("SilentFOV", {Text = "Show FOV", Default = false, Callback = function(v) SilentAim.FOV.Visible = v end})
Combat:AddToggle("SilentTracer", {Text = "Show Tracer", Default = false, Callback = function(v) SilentAim.Tracer.Enabled = v end})
Combat:AddToggle("SilentWallCheck", {Text = "Wall Check", Default = false, Callback = function(v) SilentAim.WallCheck = v end})
Combat:AddToggle("AutoShoot", {Text = "Auto Shoot", Default = false, Callback = function(v) autoShootEnabled = v; if v then startAutoShoot() else stopAutoShoot() end end})
Combat:AddToggle("InfAmmoToggle", {Text = "Infinite Ammo", Default = false, Callback = function(v) isEnabled = v; if v then spawn(mainLoop) else cleanup() end end})
Combat:AddButton({Text = "Enable WallBang", Func = startWallBang})

Movement:AddToggle("SpinbotToggle", {Text = "Spinbot", Default = false, Callback = function(v) spinbotEnabled = v; if v then startSpinbot() else stopSpinbot() end end})
Movement:AddSlider("SpinSpeed", {Text = "Spin Speed", Default = 50, Min = 10, Max = 200, Rounding = 0, Callback = function(v) spinSpeed = v end})

Movement:AddToggle("FlyToggle", {Text = "Fly Hack", Default = false, Callback = function(v)
    if v then startFly() else stopFly() end
end})

Movement:AddToggle("DesyncToggle", {Text = "Desync (with Fly)", Default = false, Callback = function(v)
    desyncEnabled = v
end})

Movement:AddSlider("FlySpeed", {Text = "Fly Speed", Default = 50, Min = 10, Max = 200, Rounding = 0, Callback = function(v) flySpeed = v end})

Movement:AddToggle("ThirdPerson", {Text = "Third Person", Default = false, Callback = toggleThirdPerson})
Movement:AddToggle("FullBright", {Text = "Full Bright", Default = false, Callback = toggleFullBright})

Visuals:AddToggle("ESPToggle", {Text = "Enable ESP", Default = false, Callback = function(v) playerEspEnabled = v; refreshPlayerESP() end})
Visuals:AddToggle("ESPDistance", {Text = "Show Distance", Default = false, Callback = function(v) Distance = v end})

RunService.Heartbeat:Connect(UpdateSilentAimVisuals)
RunService.RenderStepped:Connect(updateESPLabels)

Players.PlayerAdded:Connect(function(p)
    task.wait(1)
    if playerEspEnabled then setupPlayerESP(p) end
end)

player.CharacterAdded:Connect(function(char)
    task.wait(1)
    if isEnabled then processWeapons(char) end
end)

task.wait(1)
InitSilentAimDrawings()
print("✅ anti-shit bypassed and well enjoy :)")
