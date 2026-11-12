local Config = {
    ReloadUrl = "",
    DeveloperFolder = "TheBestFolderEverCreated",
    ConfigFolder = "area51-hub",
}

local okRayfield, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

if not okRayfield or not Rayfield then
    warn("[SnowHub] Rayfield Gen2 加载失败:", Rayfield)
    return
end

local ESPLibrary
do
    local ok, library = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/mstudio45/MSESP/refs/heads/main/source.luau"))()
    end)
    if ok then
        ESPLibrary = library
    else
        warn("[SnowHub] MSESP 加载失败:", library)
    end
end

local PlayersService = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = PlayersService.LocalPlayer

local Cleanups = {}
local function onUnload(callback)
    Cleanups[#Cleanups + 1] = callback
end

local function latch(callback)
    local current = false
    return function(value)
        value = value and true or false
        if value == current then
            return
        end
        current = value
        callback(value)
    end
end

local function fetchToken()
    local okRequest, body = pcall(function()
        return game:HttpGet("https://script-loader-one.vercel.app/api/token", true)
    end)
    if not okRequest then
        error(body)
    end

    local okDecode, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not okDecode or type(decoded) ~= "table" or type(decoded.token) ~= "string" then
        error("Failed to retrieve a valid token")
    end

    return decoded.token
end

local function getEntityLibrarySource()
    if shared.SnowhubDeveloper then
        local path = Config.DeveloperFolder .. "/EntityLibrary.lua"
        if isfile(path) then
            return readfile(path)
        end
        error("EntityLibrary.lua not found in " .. path)
    end

    local token = fetchToken()
    local okRequest, source = pcall(function()
        return game:HttpGet(
            "https://script-loader-one.vercel.app/api/entitylibrary?token=" .. HttpService:UrlEncode(token),
            true
        )
    end)
    if not okRequest then
        error(source)
    end
    if type(source) ~= "string" or source == "" or source == "404: Not Found" then
        error("Failed to download EntityLibrary.lua: " .. tostring(source))
    end

    return source
end

local EntityLibrary = loadstring(getEntityLibrarySource())()

local GameModules
do
    local ok, result = pcall(function()
        local weaponModule = ReplicatedStorage:FindFirstChild("Weapon")
        return {
            Weapon = require(weaponModule),
            Flamethrower = require(weaponModule:FindFirstChild("Flamethrower")),
            Inventory = require(
                EntityLibrary.Local.entity.Player:FindFirstChild("PlayerScripts"):FindFirstChild("Inventory")
            ),
        }
    end)
    if ok then
        GameModules = result
    else
        warn("[SnowHub] 游戏模块加载失败，枪械/热键栏功能不可用:", result)
    end
end

do
    local killers = workspace:FindFirstChild("Killers")
    if killers then
        local function register(model)
            if model.Name ~= "Jane" then
                EntityLibrary.addEntity(model, nil)
            end
        end

        for _, model in ipairs(killers:GetChildren()) do
            register(model)
        end

        local added = killers.ChildAdded:Connect(register)
        local removed = killers.ChildRemoved:Connect(function(model)
            EntityLibrary.removeEntity(model)
        end)
        onUnload(function()
            added:Disconnect()
            removed:Disconnect()
        end)
    end
end

local State = {
    WalkSpeed = 16,
    JumpPower = 50,
    FlySpeed = 16,
    Fly = false,
    GunMods = false,
    FireRate = 100,
    FullAutomatic = false,
    FastReload = false,
    InfiniteAmmo = false,
    NoRecoil = false,
    AutoGetAllWeapons = false,
    PersistentHotbar = false,
    Brightness = 3,
    ESPType = "Highlight",
    RainbowESP = false,
    ExcludeOwnTeam = false,
    UseTeamColor = true,
    ESPComponents = { Text = true, Highlight = true },
    ShowDistance = true,
    TextFontFace = "RobotoCondensed",
    TextFontSize = 16,
    HighlightTransparency = 0.75,
    HighlightFillTransparency = 0.75,
    HighlightOutlineTransparency = 0,
    TracerStartPosition = "Bottom",
    ArrowCenterOffset = 300,
    FilledBox = false,
    Box2DThickness = 1,
    Box2DTransparency = 0.5,
    Box3DThickness = 1,
    Box3DTransparency = 0.5, 
    SkeletonThickness = 1,
    SkeletonTransparency = 0.5,
    PlayerESPColor = Color3.new(1, 1, 1),
    KillerESPColor = Color3.new(1, 0, 0),
}

local invisibleCFrame

local hideOnLoadPath = Config.ConfigFolder .. "/hideonload.txt"

local function readHideOnLoad()
    local ok, result = pcall(function()
        return isfile(hideOnLoadPath) and readfile(hideOnLoadPath) == "true"
    end)
    return ok and result or false
end

local function writeHideOnLoad(value)
    pcall(function()
        if not isfolder(Config.ConfigFolder) then
            makefolder(Config.ConfigFolder)
        end
        writefile(hideOnLoadPath, tostring(value))
    end)
end

local subtitle = "游戏：无法获取游戏信息 | " .. game.PlaceId
local productOk, productInfo = pcall(function()
    return MarketplaceService:GetProductInfo(game.PlaceId)
end)
if productOk then
    subtitle = "游戏：" .. productInfo.Name .. " | " .. game.PlaceId
end

local window = Rayfield:CreateWindow({
    name = "大战51区",
    subtitle = subtitle,
    theme = "frost",
    sidebarLayout = true,
    profile = "大战51区",
    showName = "大战51区",

    configuration = {
        autoSave = true,
        autoLoad = true,
        fileName = "Area51_" .. tostring(game.PlaceId),
        customFolder = Config.ConfigFolder,
    },
})

local function notify(title, content, duration)
    window:Notify({
        title = title,
        content = content,
        duration = duration,
    })
end

if not productOk then
    notify("大战51区", "无法获取游戏信息。", 8)
end

local function confirmClick(label, action)
    local armedAt = -math.huge
    return function()
        if os.clock() - armedAt <= 3 then
            armedAt = -math.huge
            action()
        else
            armedAt = os.clock()
            notify(label, "3 秒内再次点击以确认。", 3)
        end
    end
end

local function addToggle(tab, flag, name, default, handler, extra)
    local latched = handler and latch(handler) or nil
    State[flag] = default

    local props = {
        name = name,
        flag = flag,
        value = default,
        callback = function(value)
            State[flag] = value
            if latched then
                latched(value)
            end
        end,
    }
    if extra then
        for key, value in pairs(extra) do
            props[key] = value
        end
    end

    local handle = tab:CreateToggle(props)
    State[flag] = handle.value
    if latched then
        latched(handle.value) 
        onUnload(function()
            State[flag] = false
            latched(false)
        end)
    end

    return handle
end

local function addSlider(tab, flag, name, min, max, default, increment, suffix, onChange)
    State[flag] = default

    local handle = tab:CreateSlider({
        name = name,
        flag = flag,
        range = { min, max },
        increment = increment,
        value = default,
        suffix = suffix,
        callback = function(value, dragging)
            State[flag] = value
            if onChange then
                onChange(value, dragging)
            end
        end,
    })

    State[flag] = handle.value
    return handle
end

local function addToggleKeybind(tab, flag, name, keyCode, toggleHandle)
    tab:CreateKeybind({
        name = name,
        flag = flag,
        value = keyCode,
        callback = function()
            if UserInputService:GetFocusedTextBox() then
                return
            end
            toggleHandle:Set(not toggleHandle.value)
        end,
    })
end

local function toSet(list)
    local set = {}
    for _, item in ipairs(list) do
        set[item] = true
    end
    return set
end

local Home = window:CreateTab({ name = "公告" })
local Main = window:CreateTab({ name = "主要" })
local Exploits = window:CreateTab({ name = "武器与自动" })
local Visuals = window:CreateTab({ name = "视觉" })
local ESPSettings = window:CreateTab({ name = "透视设置" })
local Settings = window:CreateTab({ name = "设置" })
local Info = window:CreateTab({ name = "关于" })

Home:CreateSection({ name = "公告" })

Home:CreateSection({
    name = "欢迎使用"
})

Home:CreateText({
    name = "大战51区脚本",
})

Home:CreateText({
    name = "来自MingHe",
})

Main:CreateSection({ name = "玩家" })

addSlider(Main, "WalkSpeed", "移动速度", 0, 100, 16, 1)
addSlider(Main, "JumpPower", "跳跃力度", 0, 200, 50, 1)

do
    local connection

    addToggle(Main, "SpeedHack", "速度修改", false, function(enabled)
        if enabled then
            connection = RunService.PreSimulation:Connect(function()
                if EntityLibrary.isAlive and not State.Fly then
                    local root = EntityLibrary.character.RootPart
                    local humanoid = EntityLibrary.character.Humanoid
                    if humanoid:GetState() == Enum.HumanoidStateType.Climbing then
                        return
                    end

                    local velocity = humanoid.MoveDirection * State.WalkSpeed
                    root.AssemblyLinearVelocity = Vector3.new(velocity.X, root.AssemblyLinearVelocity.Y, velocity.Z)
                end
            end)
        elseif connection then
            connection:Disconnect()
            connection = nil
        end
    end)
end

do
    local connection

    addToggle(Main, "JumpPowerHack", "跳跃修改", false, function(enabled)
        if enabled then
            connection = RunService.RenderStepped:Connect(function()
                if not UserInputService:GetFocusedTextBox() and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                    local state = if EntityLibrary.isAlive then EntityLibrary.character.Humanoid:GetState() else nil

                    if state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed then
                        local root = EntityLibrary.character.RootPart

                        EntityLibrary.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                        root.AssemblyLinearVelocity = Vector3.new(
                            root.AssemblyLinearVelocity.X,
                            State.JumpPower + 50,
                            root.AssemblyLinearVelocity.Z
                        )
                    end
                end
            end)
        elseif connection then
            connection:Disconnect()
            connection = nil
        end
    end)
end

do
    local connection

    addToggle(Main, "InfJump", "无限跳跃", false, function(enabled)
        if enabled then
            local busy = false
            connection = UserInputService.JumpRequest:Connect(function()
                if busy then
                    return
                end
                busy = true
                EntityLibrary.Local:getHumanoid():ChangeState(Enum.HumanoidStateType.Jumping)
                task.wait()
                busy = false
            end)
        elseif connection then
            connection:Disconnect()
            connection = nil
        end
    end)
end

Main:CreateDivider()

do
    local disabled = {}

    addToggle(Main, "AntiAfk", "防挂机踢出", false, function(enabled)
        if enabled then
            if #disabled > 0 then
                return
            end
            for _, connection in ipairs(getconnections(LocalPlayer.Idled)) do
                connection:Disable()
                disabled[#disabled + 1] = connection
            end
        else
            for _, connection in ipairs(disabled) do
                connection:Enable()
            end
            table.clear(disabled)
        end
    end)
end

do
    local animTrack
    local renderStepName
    local connections = {}
    local active = false
    local start, stop

    local function playInvisibleAnimation()
        if not EntityLibrary.Local.isAlive then
            return
        end

        local entity = EntityLibrary.Local.entity
        local isR15 = entity.Humanoid.RigType == Enum.HumanoidRigType.R15

        local animation = Instance.new("Animation")
        animation.AnimationId = "rbxassetid://" .. (if isR15 then "18537363391" else "215384594")

        local track = entity.Humanoid.Animator:LoadAnimation(animation)
        animTrack = track
        track.Priority = Enum.AnimationPriority.Action4
        track:Play(0, 0.001, 0)
        animation:Destroy()

        task.delay(0, function()
            track.TimePosition = if isR15 then 0.77 else 0.38
        end)

        connections[#connections + 1] = track.Stopped:Connect(function()
            if active and EntityLibrary.Local.isAlive then
                playInvisibleAnimation()
            end
        end)
    end

    start = function()
        active = true
        playInvisibleAnimation()
        invisibleCFrame = nil

        renderStepName = HttpService:GenerateGUID(true)
        RunService:BindToRenderStep(renderStepName, 0, function()
            if EntityLibrary.Local.isAlive and invisibleCFrame and animTrack then
                EntityLibrary.Local.entity.RootPart.CFrame = invisibleCFrame
                animTrack:AdjustWeight(0.001)
            end
        end)

        connections[#connections + 1] = RunService.Heartbeat:Connect(function()
            if not EntityLibrary.Local.isAlive then
                return
            end

            local entity = EntityLibrary.Local.entity
            local humanoid = entity.Humanoid
            local root = entity.RootPart
            local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
            local state = humanoid:GetState()

            if state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.Ragdoll then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end

            local lowered = root.CFrame - Vector3.new(0, humanoid.HipHeight + (root.Size.Y / 2) - 1, 0)
            invisibleCFrame = root.CFrame
            root.CFrame = lowered * CFrame.Angles(math.rad(if isR15 then 180 else 90), 0, 0)
            if animTrack then
                animTrack:AdjustWeight(100)
            end
        end)

        connections[#connections + 1] = EntityLibrary.Events.LocalSpawned:Connect(function(entity)
            local animator = entity.Humanoid:FindFirstChildOfClass("Animator")
            if animator and active then
                invisibleCFrame = nil
                stop()
                start()
            end
        end)
    end

    stop = function()
        active = false

        if renderStepName then
            RunService:UnbindFromRenderStep(renderStepName)
            renderStepName = nil
        end

        for _, connection in pairs(connections) do
            connection:Disconnect()
        end
        table.clear(connections)

        if animTrack then
            animTrack:Stop()
            animTrack:Destroy()
            animTrack = nil
        end

        if EntityLibrary.Local.isAlive and invisibleCFrame then
            EntityLibrary.Local.entity.RootPart.CFrame = invisibleCFrame
        end
    end

    addToggle(Main, "Invisible", "隐身", false, function(enabled)
        if enabled then
            start()
        else
            stop()
        end
    end)
end

Main:CreateDivider()

do
    local connection
    local touched = {}

    local noclipToggle = addToggle(Main, "Noclip", "穿墙", false, function(enabled)
        if enabled then
            connection = RunService.Stepped:Connect(function()
                local character = LocalPlayer.Character
                if not character then
                    return
                end
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        touched[part] = true
                        part.CanCollide = false
                    end
                end
            end)
        else
            if connection then
                connection:Disconnect()
                connection = nil
            end
            for part in pairs(touched) do
                part.CanCollide = true
            end
            table.clear(touched)
        end
    end)

    addToggleKeybind(Main, "NoclipKeybind", "穿墙快捷键", Enum.KeyCode.G, noclipToggle)
end

do
    local connection

    local flyToggle = addToggle(Main, "Fly", "飞行", false, function(enabled)
        if enabled then
            connection = RunService.Heartbeat:Connect(function(deltaTime)
                if not EntityLibrary.Local.isAlive then
                    return
                end

                local character = EntityLibrary.character
                local humanoid = character.Humanoid
                local root = character.RootPart

                humanoid.AutoRotate = false
                humanoid:ChangeState(Enum.HumanoidStateType.Physics)

                local camera = workspace.CurrentCamera
                local cameraCFrame = camera.CFrame
                local direction = Vector3.zero

                if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                    direction += cameraCFrame.LookVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                    direction -= cameraCFrame.LookVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                    direction += cameraCFrame.RightVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                    direction -= cameraCFrame.RightVector
                end

                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                    direction += Vector3.yAxis
                elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                    direction -= Vector3.yAxis
                end

                if direction.Magnitude > 0 then
                    direction = direction.Unit
                end

                local speed = State.FlySpeed or 10
                local step = direction * speed * deltaTime
                local hover = Vector3.yAxis * 0.9 * deltaTime
                local target = root.Position + step + hover

                root.CFrame = CFrame.lookAt(target, target + cameraCFrame.LookVector)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        else
            if connection then
                connection:Disconnect()
                connection = nil
            end

            if EntityLibrary.Local.isAlive then
                local humanoid = EntityLibrary.character.Humanoid
                humanoid.AutoRotate = true
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

                EntityLibrary.character.RootPart.AssemblyLinearVelocity = Vector3.zero
                EntityLibrary.character.RootPart.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end)

    addToggleKeybind(Main, "FlyKeybind", "飞行快捷键", Enum.KeyCode.F, flyToggle)
    addSlider(Main, "FlySpeed", "飞行速度", 1, 100, 16, 1)
end

if GameModules then
    local Inventory = GameModules.Inventory
    local originalChangeInteractability
    local originalNamecall

    Main:CreateDivider()

    addToggle(Main, "PersistentHotbar", "保持物品栏", false, function(enabled)
        if not enabled then
            return
        end

        if not originalChangeInteractability then
            originalChangeInteractability = hookfunction(
                Inventory.change_interactability,
                function(self, interactable, ...)
                    if State.PersistentHotbar then
                        interactable = true
                    end
                    return originalChangeInteractability(self, interactable, ...)
                end
            )
        end

        if not originalNamecall then
            originalNamecall = hookmetamethod(
                game,
                "__namecall",
                newcclosure(function(self, ...)
                    if State.PersistentHotbar and not checkcaller() then
                        local method = getnamecallmethod()
                        if method == "UnequipTools" then
                            local callingScript = getcallingscript()
                            if
                                callingScript
                                and callingScript.Name == "CommonGamemodeSetup"
                                and self:GetState() == Enum.HumanoidStateType.Physics
                            then
                                return
                            end
                            if setnamecallmethod then
                                setnamecallmethod(method)
                            end
                        end
                    end
                    return originalNamecall(self, ...)
                end)
            )
        end

        Inventory:change_interactability(true)
    end)
end

Main:CreateSection({ name = "传送" })

do
    local lookup = {}

    local dropdown = Main:CreateDropdown({
        name = "选择玩家",
        flag = "TeleportToPlayerDropdown",
        options = {},
        placeholder = "请选择玩家",
        forgetState = true,
        callback = function() end,
    })

    local function refreshPlayers()
        table.clear(lookup)
        local options = {}

        for _, entity in ipairs(EntityLibrary.List) do
            if entity.Player and entity.Player ~= LocalPlayer then
                local label = string.format("%s (@%s)", entity.Player.DisplayName, entity.Player.Name)
                lookup[label] = entity.Player.Name
                options[#options + 1] = label
            end
        end

        table.sort(options)
        dropdown:Refresh(options)
    end

    Main:CreateButton({
        name = "传送到玩家",
        description = "传送到所选玩家身边。",
        callback = function()
            local label = dropdown.value[1]
            local playerName = label and lookup[label]
            local player = playerName and PlayersService:FindFirstChild(playerName)
            local entity = player and EntityLibrary.getEntity(player)

            if entity and EntityLibrary.isAlive then
                invisibleCFrame = nil
                EntityLibrary.character.RootPart.CFrame = entity.RootPart.CFrame
            else
                notify("传送", "请先选择有效的玩家。", 3)
            end
        end,
    })

    local added = EntityLibrary.Events.EntityAdded:Connect(refreshPlayers)
    local removed = EntityLibrary.Events.EntityRemoved:Connect(refreshPlayers)
    onUnload(function()
        added:Disconnect()
        removed:Disconnect()
    end)
    refreshPlayers()
end

Main:CreateSection({ name = "其他" })

Main:CreateButton({
    name = "自杀重置",
    description = "让角色死亡，需连续点击两次确认。",
    callback = confirmClick("自杀重置", function()
        if EntityLibrary.isAlive then
            EntityLibrary.character.Humanoid:ChangeState(Enum.HumanoidStateType.Dead)
        end
    end),
})

Exploits:CreateSection({ name = "枪械修改" })

if GameModules then
    local Weapon = GameModules.Weapon
    local Flamethrower = GameModules.Flamethrower

    local original = {
        fire_wait = Weapon.fire_wait,
        is_auto = Weapon.is_auto,
        reload_wait = Weapon.reload_wait,
        move_camera = Weapon.move_camera,
        fire = Weapon.fire,
        flameFire = Flamethrower.fire,
    }

    local shellBox
    local lastScan = 0

    local function findShellBox()
        if shellBox and shellBox:IsDescendantOf(workspace) then
            return shellBox
        end

        shellBox = nil

        if os.clock() - lastScan < 1 then
            return nil
        end
        lastScan = os.clock()

        for _, descendant in workspace:GetDescendants() do
            if descendant.Name == "Box of Shells" then
                local part = descendant:FindFirstChild("Box") or descendant:FindFirstChildWhichIsA("BasePart", true)
                if part and part:IsA("BasePart") then
                    shellBox = part
                    return part
                end
            end
        end

        return nil
    end

    local function resetShellBox()
        shellBox = nil
        lastScan = 0
    end

    local spawned = EntityLibrary.Events.LocalSpawned:Connect(resetShellBox)
    local despawned = EntityLibrary.Events.LocalDespawned:Connect(resetShellBox)
    onUnload(function()
        spawned:Disconnect()
        despawned:Disconnect()
    end)

    local function applyFireRate()
        if not State.GunMods then
            Weapon.fire_wait = original.fire_wait
            return
        end

        local multiplier = math.max(State.FireRate / 100, 0.01)
        Weapon.fire_wait = function(seconds)
            return task.wait(seconds / multiplier)
        end
    end

    local function applyFullAutomatic()
        if not State.GunMods then
            Weapon.is_auto = original.is_auto
            return
        end
        Weapon.is_auto = State.FullAutomatic
    end

    local function applyFastReload()
        if State.GunMods and State.FastReload then
            Weapon.reload_wait = function()
                return task.wait(0)
            end
        else
            Weapon.reload_wait = original.reload_wait
        end
    end

    local function applyNoRecoil()
        if State.GunMods and State.NoRecoil then
            Weapon.move_camera = function() end
        else
            Weapon.move_camera = original.move_camera
        end
    end

    local function wrapFire(originalFire, usesHeat)
        return function(self, ...)
            if not (State.GunMods and State.InfiniteAmmo) then
                return originalFire(self, ...)
            end

            local ammo = self.ammo
            local storedAmmo = self.stored_ammo
            local heat = usesHeat and self.heat or nil

            local results = table.pack(originalFire(self, ...))

            self.ammo = ammo
            self.stored_ammo = storedAmmo
            if usesHeat then
                self.heat = heat
            end

            if self.update_ammo_gui then
                self:update_ammo_gui()
            end

            return table.unpack(results, 1, results.n)
        end
    end

    local wrappedFire = wrapFire(original.fire, false)
    local wrappedFlameFire = wrapFire(original.flameFire, true)

    local function applyInfiniteAmmo()
        if State.GunMods and State.InfiniteAmmo then
            Weapon.fire = wrappedFire
            Flamethrower.fire = wrappedFlameFire
        else
            Weapon.fire = original.fire
            Flamethrower.fire = original.flameFire
        end
    end

    local function applyAll()
        applyFireRate()
        applyFullAutomatic()
        applyFastReload()
        applyNoRecoil()
        applyInfiniteAmmo()
    end

    addToggle(Exploits, "GunMods", "启用", false, applyAll)
    addSlider(Exploits, "FireRate", "射速倍率", 75, 500, 100, 1, "%", applyFireRate)
    addToggle(Exploits, "FullAutomatic", "全自动", false, applyFullAutomatic)
    addToggle(Exploits, "FastReload", "快速换弹", false, applyFastReload)
    addToggle(Exploits, "InfiniteAmmo", "无限弹药", false, applyInfiniteAmmo)
    addToggle(Exploits, "NoRecoil", "无后坐力", false, applyNoRecoil)

    task.spawn(function()
        while not window.unloaded do
            if State.GunMods and State.InfiniteAmmo and EntityLibrary.Local.isAlive then
                local root = EntityLibrary.Local:getRootPart()
                local humanoid = EntityLibrary.Local:getHumanoid()
                local box = findShellBox()

                if humanoid and humanoid.Health > 0 and root and root.Parent and box then
                    firetouchinterest(root, box, 0)
                    firetouchinterest(root, box, 1)
                end
            end
            task.wait(2)
        end
    end)

    onUnload(function()
        State.GunMods = false
        applyAll()
    end)
else
    Exploits:CreateText({ name = "枪械修改", text = "游戏武器模块加载失败。" })
end

Exploits:CreateSection({ name = "自动化" })

do
    local function hasWeapon(name)
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        return backpack
            and (
                backpack:FindFirstChild(name)
                or (EntityLibrary.character and EntityLibrary.character.Character:FindFirstChild(name))
            )
    end

    local function collectAllWeapons()
        local weapons = workspace:FindFirstChild("Weapons")
        if not weapons or not EntityLibrary.isAlive then
            return
        end

        local root = EntityLibrary.character.RootPart

        for _, weapon in weapons:GetChildren() do
            if hasWeapon(weapon.Name) then
                continue
            end

            local hitbox = weapon:FindFirstChild("Hitbox")
            if hitbox then
                pcall(function()
                    firetouchinterest(root, hitbox, 0)
                    firetouchinterest(root, hitbox, 1)
                end)
            end
        end
    end

    addToggle(Exploits, "AutoGetAllWeapons", "自动获取所有武器", false, function(enabled)
        if enabled and EntityLibrary.isAlive then
            collectAllWeapons()
        end
    end, { description = "重生后自动获取所有武器。" })

    local spawned = EntityLibrary.Events.LocalSpawned:Connect(function()
        if State.AutoGetAllWeapons then
            task.wait(0.5)
            collectAllWeapons()
        end
    end)
    onUnload(function()
        spawned:Disconnect()
    end)
end

local ESPRefreshers = {}

local function refreshAllESP()
    for refresh in pairs(ESPRefreshers) do
        refresh()
    end
end

local function hasComponent(name)
    return State.ESPComponents[name] == true
end

local function buildESPSettings(entity, color, name)
    return {
        Name = name,
        Model = entity.Character,
        TextModel = entity.Head,
        Color = color,
        ESPType = State.ESPType,
        FillColor = color,
        OutlineColor = color,

        TextSize = State.TextFontSize,

        FillTransparency = State.HighlightFillTransparency,
        OutlineTransparency = State.HighlightOutlineTransparency,
        Transparency = State.HighlightTransparency,

        Tracer = { Enabled = true, Color = color, From = State.TracerStartPosition },
        Arrow = { Enabled = true, Color = color, CenterOffset = State.ArrowCenterOffset },
        Box2D = {
            Enabled = true,
            Color = color,
            Filled = State.FilledBox,
            Thickness = State.Box2DThickness,
            Transparency = State.Box2DTransparency,
        },
        Box3D = {
            Enabled = true,
            Color = color,
            Thickness = State.Box3DThickness,
            Transparency = State.Box3DTransparency,
        },
        Skeleton = {
            Enabled = true,
            Color = color,
            Thickness = State.SkeletonThickness,
            Transparency = State.SkeletonTransparency,
        },
    }
end

local function createESPController(opts)
    local enabled = false
    local objects = {}
    local tasks = {}

    local function remove(entity)
        local object = objects[entity]
        if not object then
            return
        end
        object:Destroy()
        objects[entity] = nil
    end

    local function add(entity)
        if not enabled or not ESPLibrary then
            return
        end
        if not opts.accepts(entity) then
            remove(entity)
            return
        end
        if objects[entity] then
            return
        end
        objects[entity] = ESPLibrary:Add(buildESPSettings(entity, opts.getColor(entity), opts.getName(entity)))
    end

    local function update()
        for entity, object in pairs(objects) do
            if not opts.accepts(entity) then
                remove(entity)
                continue
            end

            object:SetEveryColor(opts.getColor(entity), true)

            local settings = object.CurrentSettings
            settings.Name = opts.getName(entity)
            settings.TextSize = State.TextFontSize
            settings.FillTransparency = State.HighlightFillTransparency
            settings.OutlineTransparency = State.HighlightOutlineTransparency
            settings.Transparency = State.HighlightTransparency
        end
    end

    local function refresh()
        if not enabled then
            return
        end
        for _, entity in ipairs(EntityLibrary.List) do
            remove(entity)
            add(entity)
        end
    end

    local function setEnabled(value)
        if value == enabled then
            return
        end

        if value and not ESPLibrary then
            notify("透视", "MSESP 加载失败。", 5)
            return
        end

        enabled = value

        if value then
            for _, entity in ipairs(EntityLibrary.List) do
                add(entity)
            end

            tasks[#tasks + 1] = EntityLibrary.Events.EntityAdded:Connect(add)
            if EntityLibrary.Events.EntityRemoved then
                tasks[#tasks + 1] = EntityLibrary.Events.EntityRemoved:Connect(remove)
            end
            tasks[#tasks + 1] = task.spawn(function()
                while enabled do
                    update()
                    task.wait(0.1)
                end
            end)

            ESPRefreshers[refresh] = true
        else
            ESPRefreshers[refresh] = nil

            for _, item in ipairs(tasks) do
                if typeof(item) == "RBXScriptConnection" then
                    item:Disconnect()
                elseif typeof(item) == "thread" then
                    task.cancel(item)
                end
            end
            table.clear(tasks)

            for entity, object in pairs(objects) do
                object:Destroy()
                objects[entity] = nil
            end
        end
    end

    return { setEnabled = setEnabled, update = update }
end

local PlayerESP = createESPController({
    accepts = function(entity)
        if entity.NPC or not entity.Character then
            return false
        end
        if State.ExcludeOwnTeam and not EntityLibrary.Util.isTargetable(entity) then
            return false
        end
        return true
    end,
    getColor = function(entity)
        if State.UseTeamColor then
            return EntityLibrary.Util.getTeamColor(entity) or State.PlayerESPColor
        end
        return State.PlayerESPColor or EntityLibrary.getEntityColor(entity)
    end,
    getName = function(entity)
        return if entity.Player then entity.Player.Name else entity.Character.Name
    end,
})

local KillerESP = createESPController({
    accepts = function(entity)
        return not entity.Player and entity.Character ~= nil
    end,
    getColor = function()
        return State.KillerESPColor or Color3.new(1, 0, 0)
    end,
    getName = function(entity)
        return entity.NPC and entity.Character.Name
    end,
})

task.spawn(function()
    repeat
        if ESPLibrary then
            local config = ESPLibrary.GlobalConfig
            local textOn = hasComponent("Text")

            config.Rainbow = State.RainbowESP
            config.Font = Enum.Font[State.TextFontFace]
            config.Billboards = textOn
            config.Distance = textOn and State.ShowDistance
            config.Highlighters = hasComponent("Highlight")
            config.Tracers = hasComponent("Tracer")
            config.Arrows = hasComponent("Arrow")
            config.Boxes2D = hasComponent("Box 2D")
            config.Boxes3D = hasComponent("Box 3D")
            config.Skeleton = hasComponent("Skeleton")
        end
        task.wait(0.1)
    until window.unloaded
end)

Visuals:CreateSection({ name = "透视" })

addToggle(Visuals, "PlayerESP", "玩家透视", false, function(enabled)
    PlayerESP.setEnabled(enabled)
end)

Visuals:CreateColorPicker({
    name = "玩家透视颜色",
    flag = "PlayerESPColorPicker",
    color = State.PlayerESPColor,
    callback = function(color)
        State.PlayerESPColor = color
        PlayerESP.update()
    end,
})

addToggle(Visuals, "KillerESP", "杀手透视", false, function(enabled)
    KillerESP.setEnabled(enabled)
end)

Visuals:CreateColorPicker({
    name = "杀手透视颜色",
    flag = "KillerESPColorPicker",
    color = State.KillerESPColor,
    callback = function(color)
        State.KillerESPColor = color
        KillerESP.update()
    end,
})

Visuals:CreateSection({ name = "环境" })

do
    local connection
    local saved = {}
    local busy = false

    local function applyFullbright()
        if busy then
            return
        end

        busy = true
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.Brightness = State.Brightness or 3
        RunService.RenderStepped:Wait()
        busy = false
    end

    local fullbrightToggle = addToggle(Visuals, "Fullbright", "全亮", false, function(enabled)
    if enabled then
        for _, property in ipairs({ "Ambient", "OutdoorAmbient", "Brightness" }) do
            saved[property] = Lighting[property]
        end

        connection = Lighting.Changed:Connect(applyFullbright)
        task.spawn(applyFullbright)
    else
        if connection then
            connection:Disconnect()
            connection = nil
        end

        busy = false
        for property, value in pairs(saved) do
            Lighting[property] = value
        end
        table.clear(saved)
    end
end)

local defaultBrightness = math.floor(math.clamp(Lighting.Brightness, 0, 3) * 10 + 0.5) / 10
addSlider(Visuals, "Brightness", "亮度", 0, 3, defaultBrightness, 0.1, nil, function()
    if fullbrightToggle.value then
        task.spawn(applyFullbright)
    end
end)

end

do
    local connection
    local originalFogEnd = Lighting.FogEnd
    local busy = false

    local function clearFog()
        if busy then
            return
        end

        busy = true
        Lighting.FogEnd = math.huge
        RunService.RenderStepped:Wait()
        busy = false
    end

    addToggle(Visuals, "noFog", "去除雾气", false, function(enabled)
        if enabled then
            originalFogEnd = Lighting.FogEnd
            connection = Lighting.Changed:Connect(clearFog)
            task.spawn(clearFog)
        else
            if connection then
                connection:Disconnect()
                connection = nil
            end
            busy = false
            Lighting.FogEnd = originalFogEnd
        end
    end)
end

ESPSettings:CreateSection({ name = "常规" })

do
    local function settingCallback(flag, transform)
        return function(value, dragging)
            State[flag] = if transform then transform(value) else value
            if dragging ~= true then
                refreshAllESP()
            end
        end
    end

    ESPSettings:CreateDropdown({
        name = "透视类型",
        flag = "ESPType",
        options = { "Highlight", "SphereAdornment", "CylinderAdornment", "Adornment", "SelectionBox" },
        value = "Highlight",
        callback = settingCallback("ESPType"),
    })

    ESPSettings:CreateToggle({
        name = "彩虹透视",
        flag = "RainbowESP",
        value = false,
        callback = function(value)
            State.RainbowESP = value
        end,
    })

    ESPSettings:CreateToggle({
        name = "排除己方队伍",
        flag = "ExcludeOwnTeam",
        value = false,
        callback = settingCallback("ExcludeOwnTeam"),
    })

    ESPSettings:CreateToggle({
        name = "使用队伍颜色",
        flag = "UseTeamColor",
        value = true,
        callback = settingCallback("UseTeamColor"),
    })

    ESPSettings:CreateDropdown({
        name = "透视组件",
        flag = "ESPComponents",
        multiSelect = true,
        options = { "Text", "Highlight", "Tracer", "Arrow", "Box 2D", "Box 3D", "Skeleton" },
        value = { "Text", "Highlight" },
        callback = settingCallback("ESPComponents", toSet),
    })

    ESPSettings:CreateSection({ name = "文字设置" })

    ESPSettings:CreateToggle({
        name = "显示距离",
        flag = "ShowDistance",
        value = true,
        callback = function(value)
            State.ShowDistance = value
        end,
    })

    local fonts = {}
    for _, font in ipairs(Enum.Font:GetEnumItems()) do
        table.insert(fonts, font.Name)
    end

    ESPSettings:CreateDropdown({
        name = "文字字体",
        flag = "TextFontFace",
        options = fonts,
        value = "RobotoCondensed",
        callback = function(value)
            State.TextFontFace = value
        end,
    })

    ESPSettings:CreateSlider({
        name = "文字大小",
        flag = "TextFontSize",
        range = { 10, 26 },
        increment = 1,
        value = 16,
        callback = settingCallback("TextFontSize"),
    })

    ESPSettings:CreateSection({ name = "高亮设置" })

    ESPSettings:CreateSlider({
        name = "透明度",
        flag = "HighlightTransparency",
        range = { 0, 1 },
        increment = 0.01,
        value = 0.75,
        callback = settingCallback("HighlightTransparency"),
    })

    ESPSettings:CreateSlider({
        name = "填充透明度",
        flag = "HighlightFillTransparency",
        range = { 0, 1 },
        increment = 0.01,
        value = 0.75,
        callback = settingCallback("HighlightFillTransparency"),
    })

    ESPSettings:CreateSlider({
        name = "轮廓透明度",
        flag = "HighlightOutlineTransparency",
        range = { 0, 1 },
        increment = 0.01,
        value = 0,
        callback = settingCallback("HighlightOutlineTransparency"),
    })

    ESPSettings:CreateSection({ name = "射线设置" })

    ESPSettings:CreateDropdown({
        name = "射线起点",
        flag = "TracerStartPosition",
        options = { "Bottom", "Center", "Top", "Mouse" },
        value = "Bottom",
        callback = settingCallback("TracerStartPosition"),
    })

    ESPSettings:CreateSection({ name = "箭头设置" })

    ESPSettings:CreateSlider({
        name = "箭头中心偏移",
        flag = "ArrowCenterOffset",
        range = { 0, 500 },
        increment = 1,
        value = 300,
        callback = settingCallback("ArrowCenterOffset"),
    })

    ESPSettings:CreateSection({ name = "2D 方框设置" })

    ESPSettings:CreateToggle({
        name = "填充方框",
        flag = "FilledBox",
        value = false,
        callback = settingCallback("FilledBox"),
    })

    ESPSettings:CreateSlider({
        name = "2D 方框粗细",
        flag = "Box2DThickness",
        range = { 1, 5 },
        increment = 1,
        value = 1,
        callback = settingCallback("Box2DThickness"),
    })

    ESPSettings:CreateSlider({
        name = "2D 方框透明度",
        flag = "Box2DTransparency",
        range = { 0, 1 },
        increment = 0.01,
        value = 0.5,
        callback = settingCallback("Box2DTransparency"),
    })

    ESPSettings:CreateSection({ name = "3D 方框设置" })

    ESPSettings:CreateSlider({
        name = "3D 方框粗细",
        flag = "Box3DThickness",
        range = { 1, 5 },
        increment = 1,
        value = 1,
        callback = settingCallback("Box3DThickness"),
    })

    ESPSettings:CreateSection({ name = "骨骼设置" })

    ESPSettings:CreateSlider({
        name = "骨骼粗细",
        flag = "SkeletonThickness",
        range = { 1, 5 },
        increment = 1,
        value = 1,
        callback = settingCallback("SkeletonThickness"),
    })

    ESPSettings:CreateSlider({
        name = "骨骼透明度",
        flag = "SkeletonTransparency",
        range = { 0, 1 },
        increment = 0.01,
        value = 0.5,
        callback = settingCallback("SkeletonTransparency"),
    })
end

Settings:CreateSection({ name = "常规" })

do
    local queueFunction = queue_on_teleport or queueonteleport
    local canQueue = queueFunction ~= nil and (shared.SnowhubDeveloper or Config.ReloadUrl ~= "")

    local function buildQueuedScript()
        local loader
        if shared.SnowhubDeveloper then
            loader = ("shared.SnowhubDeveloper = true\nloadstring(readfile(%q))()"):format(
                Config.DeveloperFolder .. "/loader.lua"
            )
        else
            loader = ("loadstring(game:HttpGet(%q))()"):format(Config.ReloadUrl)
        end

        return "if shared.__SnowhubTeleportLoaded then return end\n"
            .. "shared.__SnowhubTeleportLoaded = true\n"
            .. loader
    end

    local teleportConnection
    local queued = false

    local toggle = addToggle(Settings, "ExecuteOnTeleport", "传送后自动执行", canQueue, function(enabled)
        if teleportConnection then
            teleportConnection:Disconnect()
            teleportConnection = nil
        end

        if not (enabled and canQueue) then
            return
        end

        queued = false
        teleportConnection = LocalPlayer.OnTeleport:Connect(function(state)
            if queued or state == Enum.TeleportState.Failed then
                return
            end

            queued = true
            local ok, err = pcall(queueFunction, buildQueuedScript())
            if not ok then
                queued = false
                warn("[ExecuteOnTeleport] queue failed: " .. tostring(err))
            end
        end)
    end)

    if not canQueue then
        toggle:Lock(
            if queueFunction == nil
                then "你的注入器不支持 queue_on_teleport。"
                else "请在脚本顶部填写 Config.ReloadUrl 后才能启用。"
        )
    end
end

Settings:CreateButton({
    name = "卸载",
    description = "卸载界面并关闭所有功能，需连续点击两次确认。",
    callback = confirmClick("卸载", function()
        pcall(function()
            window:Unload()
        end)
    end),
})

if shared.SnowhubDeveloper then
    Settings:CreateButton({
        name = "重新注入",
        description = "重新注入界面，需连续点击两次确认。",
        callback = confirmClick("重新注入", function()
            pcall(function()
                window:Unload()
                loadfile(Config.DeveloperFolder .. "/loader.lua")()
            end)
        end),
    })
end

Settings:CreateSection({ name = "界面" })

Settings:CreateDropdown({
    name = "界面主题",
    flag = "UITheme",
    options = { "default", "cobalt", "ember", "amethyst", "frost", "rose" },
    value = "frost",
    callback = function(theme)
        window:ChangeTheme(theme)
    end,
})

Settings:CreateKeybind({
    name = "菜单快捷键",
    description = "显示 / 隐藏菜单。",
    flag = "MenuKeybind",
    value = Enum.KeyCode.RightShift,
    callback = function()
        window:ToggleHide()
    end,
})

local hideOnLoad = readHideOnLoad()
Settings:CreateToggle({
    name = "启动时隐藏",
    description = "启动后菜单保持收起状态。",
    flag = "HideOnLoad",
    value = hideOnLoad,
    forgetState = true,
    callback = function(value)
        writeHideOnLoad(value)
    end,
})

Info:CreateSection({ name = "关于" })

Info:CreateSection({
    name = "开发者信息"
})

Info:CreateText({
    name = "MH中心",
    text = "版本：2026/11/13\n作者：MingHe"
})

task.spawn(function()
    while not window.unloaded do
        task.wait(0.25)
    end

    for _, cleanup in ipairs(Cleanups) do
        pcall(cleanup)
    end

    local genv = getgenv and getgenv()
    if genv and genv.mstudio45_ESP then
        pcall(function()
            genv.mstudio45_ESP:Destroy()
        end)
    end
end)

if hideOnLoad then
    window:Hide()
end

notify("大战51区", "加载完成。", 4)
