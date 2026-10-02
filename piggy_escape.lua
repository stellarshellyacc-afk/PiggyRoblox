-- piggy_escape.lua — mobile-tuned, UI, chapter-aware
-- Delta / UNC. Auto-escape + survival + AC bypass + on-screen control panel.

local plr   = game:GetService("Players").LocalPlayer
local rs    = game:GetService("RunService")
local UIS   = game:GetService("UserInputService")
local plrg  = game:GetService("Players")
local char  = plr.Character or plr.CharacterAdded:Wait()
local hrp   = char:WaitForChild("HumanoidRootPart")
local hum   = char:WaitForChild("Humanoid")
local cam   = workspace.CurrentCamera

local fti = firetouchinterest
local gc  = getconnections
local shp = sethiddenproperty

-- ---------- TUNABLES (mobile) ----------
local CONF = {
    Step        = 3,       -- studs per tick. 3 is safe on mobile AC.
    Tick        = 0.05,    -- 20Hz. Was 0.028, too fast for phone.
    BotRetreat  = 35,      -- studs
    RetreatStep = 4,
    GroundRay   = 12,      -- raycast down distance
    StickToFloor= true,    -- raycast snap after each step
    AutoRun     = false,   -- UI toggle
    Godmode     = true,
    ShowExit    = true,
}

-- ---------- CHAPTER TABLE ----------
-- Match by workspace child names present at boot. Extend as you find forks.
local CHAPTERS = {
    ["House"]     = { pickups = {"Key","Hammer","Wrench"}, exits = {"Exit","ExitDoor"} },
    ["Station"]   = { pickups = {"Key","Fuse","Card"},     exits = {"Exit","Train"} },
    ["Gallery"]   = { pickups = {"Key","Battery"},          exits = {"Exit","Door"} },
    ["Forest"]    = { pickups = {"Key","Axe","Wood"},       exits = {"Exit","Gate"} },
    ["School"]    = { pickups = {"Key","Book","Pencil"},    exits = {"Exit","Gate"} },
    ["Hospital"]  = { pickups = {"Key","Medkit","Fuse"},    exits = {"Exit","Ambulance"} },
    ["Carnival"]  = { pickups = {"Key","Ticket","Coin"},    exits = {"Exit","Gate"}, hazards={"Track","Coaster","Rail"} },
    ["City"]      = { pickups = {"Key","Fuse","Chip"},      exits = {"Exit","Car"},   hazards={"Car","Kill"} },
    ["Plant"]     = { pickups = {"Key","Fuse","Valve"},     exits = {"Exit","Gate"},  hazards={"Vine","Grab"} },
    ["Winter"]    = { pickups = {"Key","Gift","Bell"},      exits = {"Exit","Sleigh"} },
    ["Distorted"] = { pickups = {"Key","Memory"},           exits = {"Portal","Rift","Exit"} },
}

local DEFAULT_CHAPTER = {
    pickups = {"Key","Fuse","Battery","Gear","Cog","Carrot","Chip","Card","Ticket","Coin","Book","Hammer","Wrench","Axe","Valve","Gift","Bell","Memory","Medkit"},
    exits   = {"Exit","ExitPad","ExitDoor","Escape","EscapeZone","ExtractionZone","EscapeDoor","Gate","Portal","Rift","Train","Car","Ambulance","Sleigh"},
    hazards = {"Track","Coaster","Rail","Lava","Spike","Kill"},
}

local function detectChapter()
    for name, tbl in pairs(CHAPTERS) do
        for _, v in ipairs(workspace:GetChildren()) do
            if v.Name:find(name, 1, true) then return name, tbl end
        end
    end
    return "Unknown", DEFAULT_CHAPTER
end

local CHAPTER_NAME, CHAPTER = detectChapter()

-- ---------- ANTI-CHEAT ----------

local function neutraliseWatchdogs()
    if not gc then return end
    for _, sig in ipairs({char.ChildAdded, hrp.Changed, hum.StateChanged}) do
        for _, c in ipairs(gc(sig)) do
            if c.Function then pcall(function() c:Disconnect() end) end
        end
    end
end

local function shadowPhysics()
    if shp then
        pcall(function() shp(hrp, "Massless", true) end)
        pcall(function() shp(hrp, "CanCollide", false) end)
    end
    hrp.CanCollide = false
end

-- ---------- SURVIVAL ----------

local function bindGodmode()
    hum.HealthChanged:Connect(function(h)
        if CONF.Godmode and h < hum.MaxHealth then hum.Health = hum.MaxHealth end
    end)
end

local function nearestBot()
    local best, bd = nil, math.huge
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Model") and v ~= char and v:FindFirstChild("HumanoidRootPart") then
            local n = v.Name:lower()
            if n:find("piggy") or n:find("bot") or n:find("monster") or n:find("zombie") then
                local d = (v.HumanoidRootPart.Position - hrp.Position).Magnitude
                if d < bd then best, bd = v, d end
            end
        end
    end
    return best, bd
end

-- ---------- MOVEMENT (grounded, mobile-safe) ----------

local function groundY(x, z, yRef)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    local origin = Vector3.new(x, yRef + CONF.GroundRay, z)
    local dir    = Vector3.new(0, -(CONF.GroundRay * 2), 0)
    local hit    = workspace:Raycast(origin, dir, params)
    if hit then return hit.Position.Y end
    return nil
end

local function isHazard(part)
    if not part then return false end
    for _, p in ipairs(CHAPTER.hazards or {}) do
        if part.Name:find(p, 1, true) then return true end
    end
    return false
end

local function stepTo(target)
    if not hrp or not hrp.Parent then return end
    if hrp.Anchored then hrp.Anchored = false end

    local flat = Vector3.new(target.X, hrp.Position.Y, target.Z)
    local dist = (flat - hrp.Position).Magnitude
    if dist < 3 then return end

    local steps = math.ceil(dist / CONF.Step)
    local dir   = (flat - hrp.Position).Unit

    for i = 1, steps do
        if not CONF.AutoRun and i > 1 then return end
        local nextPos = hrp.Position + dir * CONF.Step
        if CONF.StickToFloor then
            local gy = groundY(nextPos.X, nextPos.Z, hrp.Position.Y)
            if gy then nextPos = Vector3.new(nextPos.X, gy + 3, nextPos.Z) end
        end
        hrp.CFrame = CFrame.new(nextPos)
        rs.Heartbeat:Wait()
        if i % 2 == 0 then task.wait(CONF.Tick) end
    end
end

local function touch(part)
    if not fti or not part then return end
    pcall(function()
        fti(hrp, part, 0)
        task.wait(0.08)
        fti(hrp, part, 1)
    end)
end

-- ---------- DISCOVERY ----------

local function findByName(patterns)
    local out = {}
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") and not isHazard(v) then
            for _, p in ipairs(patterns) do
                if v.Name:find(p, 1, true) then table.insert(out, v); break end
            end
        end
    end
    return out
end

-- ---------- MAIN LOOP ----------

local running = false

local function loop()
    while running do
        task.wait(0.4)
        if not hrp or not hrp.Parent then return end

        local bot, bd = nearestBot()
        if bd and bd < CONF.BotRetreat then
            local away = hrp.Position + (hrp.Position - bot.HumanoidRootPart.Position).Unit * 40
            local saved = CONF.Step
            CONF.Step = CONF.RetreatStep
            stepTo(away)
            CONF.Step = saved
        else
            for _, item in ipairs(findByName(CHAPTER.pickups)) do
                stepTo(item.Position)
                touch(item)
            end
            local exits = findByName(CHAPTER.exits)
            if #exits > 0 then
                stepTo(exits[1].Position)
                touch(exits[1])
            end
        end
    end
end

-- ---------- UI ----------

local function buildUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "K7_PiggyUI"
    sg.ResetOnSpawn = false
    sg.Parent = plr:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 260, 0, 340)
    frame.Position = UDim2.new(0, 20, 0.5, -170)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = sg

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 34)
    title.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
    title.BorderSizePixel = 0
    title.Text = "KESTREL-7  |  " .. CHAPTER_NAME
    title.TextColor3 = Color3.fromRGB(220, 220, 230)
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.Parent = frame
    local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 10); tc.Parent = title

    local y = 44
    local function makeToggle(label, key, default)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -20, 0, 34)
        row.Position = UDim2.new(0, 10, 0, y)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
        row.BorderSizePixel = 0
        row.Parent = frame
        local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = row

        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(0.65, 0, 1, 0)
        txt.Position = UDim2.new(0, 10, 0, 0)
        txt.BackgroundTransparency = 1
        txt.Text = label
        txt.TextColor3 = Color3.fromRGB(210, 210, 220)
        txt.Font = Enum.Font.Code
        txt.TextSize = 13
        txt.TextXAlignment = Enum.TextXAlignment.Left
        txt.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 60, 0, 22)
        btn.Position = UDim2.new(1, -70, 0.5, -11)
        btn.BackgroundColor3 = default and Color3.fromRGB(40, 160, 90) or Color3.fromRGB(60, 60, 70)
        btn.BorderSizePixel = 0
        btn.Text = default and "ON" or "OFF"
        btn.TextColor3 = Color3.fromRGB(240, 240, 240)
        btn.Font = Enum.Font.Code
        btn.TextSize = 12
        btn.Parent = row
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 5); bc.Parent = btn

        btn.MouseButton1Click:Connect(function()
            CONF[key] = not CONF[key]
            btn.Text = CONF[key] and "ON" or "OFF"
            btn.BackgroundColor3 = CONF[key] and Color3.fromRGB(40, 160, 90) or Color3.fromRGB(60, 60, 70)
        end)
        y = y + 40
        return btn
    end

    makeToggle("Auto Run",   "AutoRun",      false)
    makeToggle("Godmode",    "Godmode",      true)
    makeToggle("Stick Floor","StickToFloor", true)
    makeToggle("Show Exit",  "ShowExit",     true)

    -- step size slider row
    local srow = Instance.new("Frame")
    srow.Size = UDim2.new(1, -20, 0, 50)
    srow.Position = UDim2.new(0, 10, 0, y)
    srow.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    srow.BorderSizePixel = 0
    srow.Parent = frame
    local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 6); sc.Parent = srow

    local slab = Instance.new("TextLabel")
    slab.Size = UDim2.new(1, -20, 0, 22)
    slab.Position = UDim2.new(0, 10, 0, 2)
    slab.BackgroundTransparency = 1
    slab.Text = "Step: " .. CONF.Step .. " studs"
    slab.TextColor3 = Color3.fromRGB(210, 210, 220)
    slab.Font = Enum.Font.Code
    slab.TextSize = 13
    slab.TextXAlignment = Enum.TextXAlignment.Left
    slab.Parent = srow

    local minus = Instance.new("TextButton")
    minus.Size = UDim2.new(0, 60, 0, 22)
    minus.Position = UDim2.new(0, 10, 0, 24)
    minus.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    minus.BorderSizePixel = 0
    minus.Text = "-"
    minus.TextColor3 = Color3.fromRGB(240, 240, 240)
    minus.Font = Enum.Font.Code
    minus.TextSize = 14
    minus.Parent = srow
    local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 5); mc.Parent = minus

    local plus = Instance.new("TextButton")
    plus.Size = UDim2.new(0, 60, 0, 22)
    plus.Position = UDim2.new(0, 80, 0, 24)
    plus.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    plus.BorderSizePixel = 0
    plus.Text = "+"
    plus.TextColor3 = Color3.fromRGB(240, 240, 240)
    plus.Font = Enum.Font.Code
    plus.TextSize = 14
    plus.Parent = srow
    local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 5); pc.Parent = plus

    minus.MouseButton1Click:Connect(function()
        CONF.Step = math.max(1, CONF.Step - 1)
        slab.Text = "Step: " .. CONF.Step .. " studs"
    end)
    plus.MouseButton1Click:Connect(function()
        CONF.Step = math.min(10, CONF.Step + 1)
        slab.Text = "Step: " .. CONF.Step .. " studs"
    end)

    y = y + 56

    -- start/stop
    local runBtn = Instance.new("TextButton")
    runBtn.Size = UDim2.new(1, -20, 0, 40)
    runBtn.Position = UDim2.new(0, 10, 0, y)
    runBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
    runBtn.BorderSizePixel = 0
    runBtn.Text = "START"
    runBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    runBtn.Font = Enum.Font.Code
    runBtn.TextSize = 16
    runBtn.Parent = frame
    local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = runBtn

    runBtn.MouseButton1Click:Connect(function()
        CONF.AutoRun = not CONF.AutoRun
        if CONF.AutoRun then
            runBtn.Text = "STOP"
            runBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
            if not running then running = true; spawn(loop) end
        else
            runBtn.Text = "START"
            runBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
            running = false
        end
    end)

    -- minimize
    local min = Instance.new("TextButton")
    min.Size = UDim2.new(0, 22, 0, 22)
    min.Position = UDim2.new(1, -28, 0, 6)
    min.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    min.BorderSizePixel = 0
    min.Text = "–"
    min.TextColor3 = Color3.fromRGB(240, 240, 240)
    min.Font = Enum.Font.Code
    min.TextSize = 14
    min.Parent = title
    local minc = Instance.new("UICorner"); minc.CornerRadius = UDim.new(0, 5); minc.Parent = min

    local minimized = false
    min.MouseButton1Click:Connect(function()
        minimized = not minimized
        frame.Size = minimized and UDim2.new(0, 260, 0, 34) or UDim2.new(0, 260, 0, y + 50)
        for _, c in ipairs(frame:GetChildren()) do
            if c ~= title and c:IsA("GuiObject") then c.Visible = not minimized end
        end
    end)

    return sg
end

-- ---------- BOOT ----------

neutraliseWatchdogs()
shadowPhysics()
if CONF.Godmode then bindGodmode() end
buildUI()

plr.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    task.wait(1)
    neutraliseWatchdogs()
    shadowPhysics()
    if CONF.Godmode then bindGodmode() end
end)
