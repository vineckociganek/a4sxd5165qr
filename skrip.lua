_G.Status = "Ready!"
wait(2)

-- Anti-Cheat Bypass
setthreadidentity(2)
for i, v in pairs(getgc(true)) do
    if typeof(v) == "table" then
        local DetectFunc = rawget(v, "Detected")
        local KillFunc = rawget(v, "Kill")
        if typeof(DetectFunc) == "function" then hookfunction(DetectFunc, function() return true end) end
        if typeof(KillFunc) == "function" then hookfunction(KillFunc, function() return nil end) end
    end
end
setthreadidentity(7)
wait(2)

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua"))()

local Window = Library:CreateWindow({
    Title = "VaporWare - discord.gg/AAnmrCTRk6",
    Center = true,
    AutoShow = true,
})

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local CurrentCamera = Workspace.CurrentCamera

getgenv().ForceMouseUnlock = true

-- ====================== VARIABLES ======================
local SilentAim = {
    Enabled = false, TargetPart = "Head", HealthCheck = true,
    PassiveCheck = false, WallCheck = false,
    FOV = { Radius = 60, Visible = false, Color = Color3.fromRGB(171, 0, 255) },
    Tracer = { Enabled = false, Color = Color3.fromRGB(171, 0, 255), Thickness = 1 }
}

local SilentAimFOVCircle, TracerLine
local IsTargeting = false
local originalIndex
local wallCheckCache = {}
local lastWallCheck = 0

local objectMoverEnabled = false
local movedObjectsFolder = nil
local thirdPersonEnabled = false
local thirdPersonWasEnabled = false

local autoShootEnabled = false
local autoShootConnection = nil

local isInfAmmoEnabled = false
local infAmmoConnections = {}

local fullBrightEnabled = false
local brightConnection = nil

-- ESP
local playerEspEnabled = true
local showDistance = true
local playerEspCache = {}

-- Sky Options
local skyOptions = {
    ["Default"] = {},
    ["Space"] = {SkyboxBk = "rbxassetid://159454286", SkyboxDn = "rbxassetid://159454299", SkyboxFt = "rbxassetid://159454293", SkyboxLf = "rbxassetid://159454286", SkyboxRt = "rbxassetid://159454300", SkyboxUp = "rbxassetid://159454288"},
    ["Night"] = {SkyboxBk = "rbxassetid://12064107", SkyboxDn = "rbxassetid://12064107", SkyboxFt = "rbxassetid://12064107", SkyboxLf = "rbxassetid://12064107", SkyboxRt = "rbxassetid://12064107", SkyboxUp = "rbxassetid://12064107"},
    ["Pink Clouds"] = {SkyboxBk = "rbxassetid://271042596", SkyboxDn = "rbxassetid://271042596", SkyboxFt = "rbxassetid://271042596", SkyboxLf = "rbxassetid://271042596", SkyboxRt = "rbxassetid://271042596", SkyboxUp = "rbxassetid://271042596"},
    ["Cyberpunk"] = {SkyboxBk = "rbxassetid://600830446", SkyboxDn = "rbxassetid://600830446", SkyboxFt = "rbxassetid://600830446", SkyboxLf = "rbxassetid://600830446", SkyboxRt = "rbxassetid://600830446", SkyboxUp = "rbxassetid://600830446"},
}

-- ====================== CORE FUNCTIONS ======================
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
    local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
    if not tool then return nil end
    for _, name in ipairs({"Flash","FlashPart","FirePoint","Muzzle"}) do
        local flash = tool:FindFirstChild(name, true)
        if flash and flash:IsA("BasePart") then return flash end
    end
    return tool:FindFirstChild("Handle")
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
    local success = not res or not res.Instance.CanCollide or (res.Instance.Transparency or 0) > 0.9
    wallCheckCache[cacheKey] = success
    lastWallCheck = tick()
    return success
end

local function FindBestTarget()
    if not SilentAim.Enabled then return nil end
    local flash = getFlashPart()
    local origin = flash and flash.Position or CurrentCamera.CFrame.Position
    local best, closest = nil, math.huge
    local center = Vector2.new(CurrentCamera.ViewportSize.X/2, CurrentCamera.ViewportSize.Y/2)

    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        local char = p.Character
        if not char then continue end
        if SilentAim.PassiveCheck and char:FindFirstChildOfClass("ForceField") then continue end
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 or (SilentAim.HealthCheck and hum.Health <= 1) then continue end

        local tPart = char:FindFirstChild(SilentAim.TargetPart) or char:FindFirstChild("Head")
        if not tPart then continue end
        if not WallCheck(origin, tPart.Position) then continue end

        local screen, onScreen = CurrentCamera:WorldToViewportPoint(tPart.Position)
        if not onScreen then continue end
        local dist = (Vector2.new(screen.X, screen.Y) - center).Magnitude
        if dist < SilentAim.FOV.Radius and dist < closest then
            closest = dist
            best = {PredictedPosition = tPart.Position}
        end
    end
    IsTargeting = best ~= nil
    return best
end

local function UpdateSilentAimVisuals()
    local center = Vector2.new(CurrentCamera.ViewportSize.X/2, CurrentCamera.ViewportSize.Y/2)
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
            local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
            if not tool or not tool:FindFirstChild("GunScript") then return originalIndex(self, key) end
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

-- Auto Shoot
local function startAutoShoot()
    if autoShootConnection then return end
    autoShootConnection = RunService.Heartbeat:Connect(function()
        if not autoShootEnabled then return end
        local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
        if tool and tool:FindFirstChild("GunScript") and FindBestTarget() then
            mouse1click()
        end
    end)
end

local function stopAutoShoot()
    if autoShootConnection then autoShootConnection:Disconnect() autoShootConnection = nil end
end

-- Infinite Ammo
local function startInfiniteAmmo()
    isInfAmmoEnabled = true
    local function process(char)
        for _, tool in ipairs(char:GetDescendants()) do
            if tool:IsA("Tool") then
                local pf = Workspace:FindFirstChild(player.Name)
                local weapon = pf and pf:FindFirstChild(tool.Name, true)
                if weapon and weapon:FindFirstChild("GunScript") and weapon.GunScript:FindFirstChild("ClientAmmo") then
                    local ammo = weapon.GunScript.ClientAmmo
                    local orig = ammo.Value
                    local conn = ammo.Changed:Connect(function() ammo.Value = orig end)
                    table.insert(infAmmoConnections, conn)
                end
            end
        end
    end
    if player.Character then process(player.Character) end
    player.CharacterAdded:Connect(process)
end

local function stopInfiniteAmmo()
    isInfAmmoEnabled = false
    for _, c in ipairs(infAmmoConnections) do c:Disconnect() end
    infAmmoConnections = {}
end

-- WallBang
local function startWallBang()
    if objectMoverEnabled then return end
    objectMoverEnabled = true
    movedObjectsFolder = Instance.new("Folder")
    movedObjectsFolder.Name = "WallBang"
    movedObjectsFolder.Parent = Camera

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("BasePart") or obj:IsA("Model")) and obj.Name ~= "Baseplate" and not obj:FindFirstChildOfClass("Humanoid") and obj.Parent ~= player.Character then
            pcall(function() obj.Parent = movedObjectsFolder end)
        end
    end
end

local function stopWallBang()
    objectMoverEnabled = false
    if movedObjectsFolder then movedObjectsFolder:Destroy() movedObjectsFolder = nil end
end

-- Third Person
local function toggleThirdPerson(v)
    thirdPersonEnabled = v
    thirdPersonWasEnabled = v
    local camClient = player.PlayerGui:FindFirstChild("CameraClient")
    if camClient then camClient.Enabled = not v end
end

player.CharacterRemoving:Connect(function()
    if thirdPersonEnabled then
        thirdPersonEnabled = false
        local camClient = player.PlayerGui:FindFirstChild("CameraClient")
        if camClient then camClient.Enabled = true end
        task.wait(1)
        if thirdPersonWasEnabled and player.Character then
            toggleThirdPerson(true)
        end
    end
end)

-- Instant Equip
local function instantEquip()
    for _, tool in ipairs(player.Backpack:GetChildren()) do
        if tool:IsA("Tool") then
            local stats = tool:FindFirstChild("Stats") or (tool:FindFirstChild("AttachmentFolder") and tool.AttachmentFolder:FindFirstChild("Tool") and tool.AttachmentFolder.Tool:FindFirstChild("Stats"))
            if stats and stats:FindFirstChild("EquipSpeed") then
                stats.EquipSpeed.Value = 0.00001
            end
        end
    end
end

-- Full Bright
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

-- Custom Sky
local function setCustomSky(skyType)
    local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
    sky.Parent = Lighting
    local data = skyOptions[skyType] or {}
    for prop, val in pairs(data) do
        sky[prop] = val
    end
end

-- ====================== ESP SYSTEM (FIXED) ======================
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
    hl.Parent = adornee
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
    if not playerEspEnabled then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then setupPlayerESP(p) end
    end
end

local function updateESPLabels()
    if not playerEspEnabled then return end
    local camPos = Camera.CFrame.Position
    for p, data in pairs(playerEspCache) do
        if not p.Character or not p.Character.Parent then
            cleanupPlayerESP(p)
        else
            local pos = getPlayerPosition(data.character)
            if pos then
                local dist = (pos - camPos).Magnitude * 0.36
                local hp = getPlayerHealth(data.character)
                if showDistance then
                    data.label.Text = string.format("%s\nHP: %d | %.0fm", p.Name, hp, dist)
                else
                    data.label.Text = string.format("%s\nHP: %d", p.Name, hp)
                end
            end
        end
    end
end

-- ====================== TABS ======================
local Tabs = {
    Combat = Window:AddTab("Combat"),
    Modifications = Window:AddTab("Modifications"),
    Exploits = Window:AddTab("Exploits"),
    Visuals = Window:AddTab("Visuals"),
    Menu = Window:AddTab("Menu")
}

-- COMBAT
local CombatLeft = Tabs.Combat:AddLeftGroupbox("Silent Aim")
CombatLeft:AddToggle("SilentAimToggle", {Text = "Silent Aim", Default = false, Callback = function(v) SilentAim.Enabled = v; if v then InitSilentAimDrawings() end end})
CombatLeft:AddToggle("SilentFOVToggle", {Text = "Show FOV", Default = false, Callback = function(v) SilentAim.FOV.Visible = v end})
CombatLeft:AddSlider("SilentFOVSize", {Text = "FOV Size", Default = 60, Min = 10, Max = 800, Rounding = 0, Callback = function(v) SilentAim.FOV.Radius = v end})
CombatLeft:AddToggle("SilentTracerToggle", {Text = "Show Tracer", Default = false, Callback = function(v) SilentAim.Tracer.Enabled = v end})
CombatLeft:AddToggle("SilentWallCheckToggle", {Text = "Wall Check", Default = false, Callback = function(v) SilentAim.WallCheck = v end})
CombatLeft:AddDropdown("SilentTargetPart", {Text = "Target Part", Default = "Head", Values = {"Head", "Torso"}, Callback = function(v) SilentAim.TargetPart = v end})
CombatLeft:AddToggle("AutoShootToggle", {Text = "Auto Shoot", Default = false, Callback = function(v) autoShootEnabled = v; if v then startAutoShoot() else stopAutoShoot() end end})

-- MODIFICATIONS
local ModsRight = Tabs.Modifications:AddRightGroupbox("Movement & Others")
ModsRight:AddToggle("WallBangToggle", {Text = "WallBang", Default = false, Callback = function(v) if v then startWallBang() else stopWallBang() end end})
ModsRight:AddToggle("InfiniteAmmoToggle", {Text = "Infinite Ammo", Default = false, Callback = function(v) if v then startInfiniteAmmo() else stopInfiniteAmmo() end end})
ModsRight:AddToggle("InstantEquipToggle", {Text = "Instant Equip", Default = false, Callback = function(v) if v then spawn(function() while v do instantEquip() task.wait(0.5) end end) end end})
ModsRight:AddToggle("ThirdPersonToggle", {Text = "Third Person", Default = false, Callback = toggleThirdPerson})

-- EXPLOITS
local ExpLeft = Tabs.Exploits:AddLeftGroupbox("Healing")
ExpLeft:AddToggle("InstaMedkit", {Text = "Instant Medkit (Self)", Default = false, Callback = function(v)
    spawn(function()
        while v do
            local medkit = player.Character and player.Character:FindFirstChild("Medkit")
            if medkit and medkit:FindFirstChild("ActionMain") then
                medkit.ActionMain:FireServer("heal", player.Character)
            end
            task.wait(0.05)
        end
    end)
end})

-- VISUALS
local VisLeft = Tabs.Visuals:AddLeftGroupbox("ESP")
VisLeft:AddToggle("ESPEnable", {Text = "Enable ESP", Default = false, Callback = function(v) playerEspEnabled = v; refreshPlayerESP() end})
VisLeft:AddToggle("ESPDistanceToggle", {Text = "Show Distance", Default = false, Callback = function(v) showDistance = v end})

local VisRight = Tabs.Visuals:AddRightGroupbox("World")
VisRight:AddToggle("FullBrightToggle", {Text = "Full Bright", Default = false, Callback = toggleFullBright})
VisRight:AddDropdown("CustomSkyDropdown", {Text = "Custom Sky", Default = "Default", Values = {"Default","Vaporwave","Space","Night","Sunset","Pink Clouds","Cyberpunk"}, Callback = setCustomSky})

-- MENU
local MenuBox = Tabs.Menu:AddLeftGroupbox("GUI Settings")
ThemeManager:SetLibrary(Library)
ThemeManager:ApplyToTab(Tabs.Menu)
SaveManager:SetLibrary(Library)
SaveManager:BuildConfigSection(Tabs.Menu)
SaveManager:LoadAutoloadConfig()

-- ====================== CONNECTIONS (FIXED) ======================
RunService.Heartbeat:Connect(UpdateSilentAimVisuals)
RunService.RenderStepped:Connect(updateESPLabels)

-- Better Player Detection
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        task.wait(1)
        if playerEspEnabled then setupPlayerESP(p) end
    end)
    task.wait(1)
    if playerEspEnabled then setupPlayerESP(p) end
end)

-- Initial ESP Setup
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= player then
        if p.Character then setupPlayerESP(p) end
        p.CharacterAdded:Connect(function() task.wait(1); if playerEspEnabled then setupPlayerESP(p) end end)
    end
end

player.CharacterAdded:Connect(function()
    task.wait(1)
    refreshPlayerESP()
end)

task.wait(1)
InitSilentAimDrawings()
print("VaporWare - Loaded!")
