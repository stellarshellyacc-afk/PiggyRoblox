-- piggy_escape.lua v8 — Book 1 coordinate walker, Delta-tuned
-- Movement: PathfindingService with hardcoded chapter coordinates
-- UI: animated neon panel from v7
-- Interaction: prompt + clickdetector + touch

local plr   = game:GetService("Players").LocalPlayer
local rs    = game:GetService("RunService")
local Tween = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")

local char  = plr.Character or plr.CharacterAdded:Wait()
local hrp   = char:WaitForChild("HumanoidRootPart")
local hum   = char:WaitForChild("Humanoid")

local fti = firetouchinterest
local fpp = fireproximityprompt
local fcd = fireclickdetector
local gc  = getconnections

-- ============================================================
-- CONFIG
-- ============================================================
local CONF = {
    Speed      = 22,
    Godmode    = true,
    AutoRun    = false,
    Retreat    = 40,
}

-- ============================================================
-- BOOK 1 COORDINATE TABLE (chapters 1-12)
-- ============================================================
local ChapterData = {
    [1]  = {Name="House",   Exit=Vector3.new(-12,3,45),    KeyRooms={Vector3.new(5,12,-2),   Vector3.new(-20,0,15)}},
    [2]  = {Name="Station", Exit=Vector3.new(45,2,-110),   KeyRooms={Vector3.new(10,2,-50),  Vector3.new(32,10,-75)}},
    [3]  = {Name="Gallery", Exit=Vector3.new(0,1,85),      KeyRooms={Vector3.new(-30,8,12),  Vector3.new(25,1,-40)}},
    [4]  = {Name="Forest",  Exit=Vector3.new(-150,0,210),  KeyRooms={Vector3.new(-60,2,80),  Vector3.new(-90,-5,140)}},
    [5]  = {Name="School",  Exit=Vector3.new(3,4,-15),     KeyRooms={Vector3.new(50,15,-10), Vector3.new(-45,4,30)}},
    [6]  = {Name="Hospital",Exit=Vector3.new(88,1,12),     KeyRooms={Vector3.new(88,25,-20), Vector3.new(12,12,5)}},
    [7]  = {Name="Metro",   Exit=Vector3.new(-5,-12,130),  KeyRooms={Vector3.new(-5,5,40),   Vector3.new(-40,-12,80)}},
    [8]  = {Name="Carnival",Exit=Vector3.new(110,0,-25),   KeyRooms={Vector3.new(20,0,-25),  Vector3.new(65,15,10)}},
    [9]  = {Name="City",    Exit=Vector3.new(-15,2,-65),   KeyRooms={Vector3.new(-70,24,15), Vector3.new(40,2,35)}},
    [10] = {Name="Mall",    Exit=Vector3.new(0,2,-5),      KeyRooms={Vector3.new(-55,16,-80),Vector3.new(55,30,20)}},
    [11] = {Name="Outpost", Exit=Vector3.new(210,4,85),    KeyRooms={Vector3.new(115,4,-30), Vector3.new(165,20,45)}},
    [12] = {Name="Plant",   Exit=Vector3.new(0,-30,-15),   KeyRooms={Vector3.new(45,10,-90), Vector3.new(-45,-15,60)}},
}

local GameState = {
    CurrentChapter = 1,
    HoldingItem    = "None",
    ObjectiveActive= false,
}

-- ============================================================
-- MAP DETECTION (matches current loaded chapter)
-- ============================================================
local function detectChapterIndex()
    for idx, data in pairs(ChapterData) do
        for _, v in ipairs(workspace:GetDescendants()) do
            if v.Name:lower():find(data.Name:lower(), 1, true) then
                return idx
            end
        end
    end
    return 1  -- default to House
end

GameState.CurrentChapter = detectChapterIndex()

-- ============================================================
-- ANTI-CHEAT / GODMODE
-- ============================================================
local function neutraliseWatchdogs()
    if not gc then return end
    for _, sig in ipairs({char.ChildAdded, hrp.Changed, hum.StateChanged}) do
        for _, c in ipairs(gc(sig)) do
            if c.Function then pcall(function() c:Disconnect() end) end
        end
    end
end

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

-- ============================================================
-- WALKER — coordinate-based, Delta-safe
-- ============================================================
local function walkTo(destinationPosition)
    if not hrp or not hrp.Parent or not hum.Parent then return false end
    hum.WalkSpeed = CONF.Speed

    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
    })

    local ok = pcall(function()
        path:ComputeAsync(hrp.Position, destinationPosition)
    end)

    if ok and path.Status == Enum.PathStatus.Success then
        for _, waypoint in ipairs(path:GetWaypoints()) do
            if not hrp.Parent then return false end
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                hum.Jump = true
            end
            hum:MoveTo(waypoint.Position)
            -- bounded wait instead of MoveToFinished:Wait (which hangs forever)
            local t0 = tick()
            repeat
                task.wait(0.1)
                if not hrp or not hrp.Parent then return false end
                local d = (waypoint.Position - hrp.Position).Magnitude
                if d < 4 then break end
            until tick() - t0 > 4
        end
    else
        -- fallback straight line
        hum:MoveTo(destinationPosition)
        local t0 = tick()
        repeat
            task.wait(0.1)
            if not hrp or not hrp.Parent then return false end
        until (hrp.Position - destinationPosition).Magnitude < 4 or tick() - t0 > 6
    end
    return true
end

-- ============================================================
-- INTERACTION (prompt + clickdetector + touch)
-- ============================================================
local function interact(part)
    if not part then return end
    local acted = false
    local prompt = part:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        for _, d in ipairs(part:GetDescendants()) do
            if d:IsA("ProximityPrompt") then prompt = d; break end
        end
    end
    if prompt and fpp then pcall(function() fpp(prompt) end); acted = true end
    local cd = part:FindFirstChildOfClass("ClickDetector")
    if not cd then
        for _, d in ipairs(part:GetDescendants()) do
            if d:IsA("ClickDetector") then cd = d; break end
        end
    end
    if cd and fcd then pcall(function() fcd(cd) end); acted = true end
    if not acted and fti then
        pcall(function() fti(hrp, part, 0); task.wait(0.08); fti(hrp, part, 1) end)
    end
end

-- ============================================================
-- ITEM SCANNER
-- ============================================================
local function scanForItems()
    local best, bd = nil, math.huge
    for _, item in ipairs(workspace:GetDescendants()) do
        local isTarget = item:IsA("Tool")
            or item:IsA("ClickDetector")
            or item.Name:match("Key")
            or item.Name:match("Wrench")
            or item.Name:match("Hammer")
            or item.Name:match("Battery")
            or item.Name:match("Gas")
        if isTarget then
            local handle = item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart")
            if handle then
                local d = (hrp.Position - handle.Position).Magnitude
                if d < bd then best, bd = item, d end
            end
        end
    end
    return best
end

-- ============================================================
-- MAIN SEQUENCE
-- ============================================================
local running = false

local function escapeSequence()
    while running do
        task.wait(0.5)
        if not hrp or not hrp.Parent then return end

        -- bot retreat first
        local bot, bd = nearestBot()
        if bd and bd < CONF.Retreat then
            walkTo(hrp.Position + (hrp.Position - bot.HumanoidRootPart.Position).Unit * 50)
            continue
        end

        local activeChapter = ChapterData[GameState.CurrentChapter]
        if not activeChapter then return end

        local nearby = scanForItems()

        if nearby and GameState.HoldingItem == "None" then
            local handle = nearby:FindFirstChild("Handle") or nearby:FindFirstChildWhichIsA("BasePart")
            if handle then
                walkTo(handle.Position)
                interact(handle)
                GameState.HoldingItem = nearby.Name
            end

        elseif GameState.HoldingItem ~= "None" and not GameState.ObjectiveActive then
            for _, roomPos in ipairs(activeChapter.KeyRooms) do
                if not running then return end
                walkTo(roomPos)
                task.wait(0.6)
            end
            if GameState.HoldingItem:match("White") or GameState.HoldingItem:match("Wrench") then
                GameState.ObjectiveActive = true
            end
            GameState.HoldingItem = "None"

        elseif GameState.ObjectiveActive then
            walkTo(activeChapter.Exit)
            task.wait(2)

        else
            for _, roomPos in ipairs(activeChapter.KeyRooms) do
                if not running then return end
                walkTo(roomPos)
                if scanForItems() then break end
            end
        end
    end
end

-- ============================================================
-- ANIMATED UI
-- ============================================================
local function tween(obj, time, props, style)
    local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local t = Tween:Create(obj, info, props)
    t:Play()
    return t
end

local function buildUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "K7_PiggyUI"
    sg.ResetOnSpawn = false
    sg.Parent = plr:WaitForChild("PlayerGui")

    local CYAN = Color3.fromRGB(0, 255, 220)
    local PINK = Color3.fromRGB(255, 60, 160)
    local BG   = Color3.fromRGB(8, 10, 18)
    local PANEL= Color3.fromRGB(14, 18, 30)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 260, 0, 300)
    frame.Position = UDim2.new(0, 20, 0.5, -150)
    frame.BackgroundColor3 = BG
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = sg
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke")
    stroke.Color = CYAN; stroke.Thickness = 1.5; stroke.Transparency = 0.2
    stroke.Parent = frame

    spawn(function()
        while frame.Parent do
            tween(stroke, 0.8, {Transparency = 0.6}, Enum.EasingStyle.Sine)
            tween(stroke, 0.8, {Transparency = 0.2}, Enum.EasingStyle.Sine)
            task.wait(0.8)
        end
    end)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 14, 24)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 6, 12)),
    }
    grad.Rotation = 135
    grad.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 36)
    title.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
    title.BackgroundTransparency = 0.3
    title.BorderSizePixel = 0
    title.Text = "KESTREL-7  //  " .. (ChapterData[GameState.CurrentChapter] and ChapterData[GameState.CurrentChapter].Name or "?")
    title.TextColor3 = CYAN
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.Parent = frame
    Instance.new("UICorner", title).CornerRadius = UDim.new(0,12)

    title.TextTransparency = 1
    tween(title, 0.6, {TextTransparency = 0})

    local y = 46
    local function makeToggle(label, key, default)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1,-20,0,34)
        row.Position = UDim2.new(0,10,0,y)
        row.BackgroundColor3 = PANEL
        row.BackgroundTransparency = 0.2
        row.BorderSizePixel = 0
        row.Parent = frame
        Instance.new("UICorner", row).CornerRadius = UDim.new(0,6)
        local s = Instance.new("UIStroke", row); s.Color = CYAN; s.Thickness = 1; s.Transparency = 0.7

        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(0.65,0,1,0); txt.Position = UDim2.new(0,10,0,0)
        txt.BackgroundTransparency = 1; txt.Text = label
        txt.TextColor3 = Color3.fromRGB(200,210,230)
        txt.Font = Enum.Font.Code; txt.TextSize = 13
        txt.TextXAlignment = Enum.TextXAlignment.Left
        txt.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0,64,0,22); btn.Position = UDim2.new(1,-74,0.5,-11)
        btn.BackgroundColor3 = default and Color3.fromRGB(0,120,90) or Color3.fromRGB(30,34,46)
        btn.BorderSizePixel = 0
        btn.Text = default and "ON" or "OFF"
        btn.TextColor3 = default and CYAN or Color3.fromRGB(120,130,150)
        btn.Font = Enum.Font.Code; btn.TextSize = 12
        btn.Parent = row
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,5)
        local bs = Instance.new("UIStroke", btn); bs.Color = default and CYAN or Color3.fromRGB(60,70,90); bs.Thickness = 1; bs.Transparency = 0.3

        btn.MouseButton1Click:Connect(function()
            CONF[key] = not CONF[key]
            btn.Text = CONF[key] and "ON" or "OFF"
            btn.TextColor3 = CONF[key] and CYAN or Color3.fromRGB(120,130,150)
            btn.BackgroundColor3 = CONF[key] and Color3.fromRGB(0,120,90) or Color3.fromRGB(30,34,46)
            bs.Color = CONF[key] and CYAN or Color3.fromRGB(60,70,90)
            tween(btn, 0.1, {Size = UDim2.new(0,58,0,20)})
            tween(btn, 0.15, {Size = UDim2.new(0,64,0,22)})
            if key == "Godmode" and CONF.Godmode then bindGodmode() end
        end)

        row.Position = UDim2.new(0, -280, 0, y)
        tween(row, 0.4, {Position = UDim2.new(0,10,0,y)}, Enum.EasingStyle.Back)
        y = y + 40
    end

    makeToggle("Auto Run", "AutoRun", false)
    makeToggle("Godmode",  "Godmode", true)

    local srow = Instance.new("Frame")
    srow.Size = UDim2.new(1,-20,0,52)
    srow.Position = UDim2.new(0,10,0,y)
    srow.BackgroundColor3 = PANEL
    srow.BackgroundTransparency = 0.2
    srow.BorderSizePixel = 0
    srow.Parent = frame
    Instance.new("UICorner", srow).CornerRadius = UDim.new(0,6)
    local ss = Instance.new("UIStroke", srow); ss.Color = PINK; ss.Thickness = 1; ss.Transparency = 0.5

    local slab = Instance.new("TextLabel")
    slab.Size = UDim2.new(1,-20,0,22); slab.Position = UDim2.new(0,10,0,2)
    slab.BackgroundTransparency = 1
    slab.Text = "Speed: " .. CONF.Speed
    slab.TextColor3 = PINK
    slab.Font = Enum.Font.Code; slab.TextSize = 13
    slab.TextXAlignment = Enum.TextXAlignment.Left
    slab.Parent = srow

    local function mkBtn(txt, x)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0,64,0,24); b.Position = UDim2.new(0,x,0,26)
        b.BackgroundColor3 = Color3.fromRGB(30,34,46)
        b.BorderSizePixel = 0
        b.Text = txt
        b.TextColor3 = PINK
        b.Font = Enum.Font.Code; b.TextSize = 16
        b.Parent = srow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,5)
        local s = Instance.new("UIStroke", b); s.Color = PINK; s.Thickness = 1; s.Transparency = 0.4
        return b
    end

    local minus = mkBtn("-", 10)
    local plus  = mkBtn("+", 82)

    minus.MouseButton1Click:Connect(function()
        CONF.Speed = math.max(16, CONF.Speed - 2)
        slab.Text = "Speed: " .. CONF.Speed
        hum.WalkSpeed = CONF.Speed
        tween(minus, 0.1, {Size = UDim2.new(0,58,0,22)})
        tween(minus, 0.15, {Size = UDim2.new(0,64,0,24)})
    end)
    plus.MouseButton1Click:Connect(function()
        CONF.Speed = math.min(60, CONF.Speed + 2)
        slab.Text = "Speed: " .. CONF.Speed
        hum.WalkSpeed = CONF.Speed
        tween(plus, 0.1, {Size = UDim2.new(0,58,0,22)})
        tween(plus, 0.15, {Size = UDim2.new(0,64,0,24)})
    end)

    y = y + 58

    local runBtn = Instance.new("TextButton")
    runBtn.Size = UDim2.new(1,-20,0,40)
    runBtn.Position = UDim2.new(0,10,0,y)
    runBtn.BackgroundColor3 = Color3.fromRGB(90,20,60)
    runBtn.BorderSizePixel = 0
    runBtn.Text = "START"
    runBtn.TextColor3 = Color3.fromRGB(255,200,230)
    runBtn.Font = Enum.Font.Code; runBtn.TextSize = 16
    runBtn.Parent = frame
    Instance.new("UICorner", runBtn).CornerRadius = UDim.new(0,6)
    local rs3 = Instance.new("UIStroke", runBtn); rs3.Color = PINK; rs3.Thickness = 1.5; rs3.Transparency = 0.2

    runBtn.MouseButton1Click:Connect(function()
        CONF.AutoRun = not CONF.AutoRun
        if CONF.AutoRun then
            runBtn.Text = "STOP"
            runBtn.BackgroundColor3 = Color3.fromRGB(0,120,90)
            runBtn.TextColor3 = CYAN
            rs3.Color = CYAN
            if not running then running = true; spawn(escapeSequence) end
            tween(runBtn, 0.15, {Size = UDim2.new(1,-20,0,44)})
            tween(runBtn, 0.2, {Size = UDim2.new(1,-20,0,40)})
        else
            runBtn.Text = "START"
            runBtn.BackgroundColor3 = Color3.fromRGB(90,20,60)
            runBtn.TextColor3 = Color3.fromRGB(255,200,230)
            rs3.Color = PINK
            running = false
        end
    end)

    local min = Instance.new("TextButton")
    min.Size = UDim2.new(0,24,0,24); min.Position = UDim2.new(1,-30,0,6)
    min.BackgroundColor3 = Color3.fromRGB(20,24,36)
    min.BorderSizePixel = 0
    min.Text = "–"
    min.TextColor3 = CYAN
    min.Font = Enum.Font.Code; min.TextSize = 14
    min.Parent = title
    Instance.new("UICorner", min).CornerRadius = UDim.new(0,5)
    local ms = Instance.new("UIStroke", min); ms.Color = CYAN; ms.Thickness = 1; ms.Transparency = 0.4

    local minimized = false
    min.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            tween(frame, 0.3, {Size = UDim2.new(0,260,0,36)}, Enum.EasingStyle.Quart)
        else
            tween(frame, 0.3, {Size = UDim2.new(0,260,0,300)}, Enum.EasingStyle.Quart)
        end
        for _, c in ipairs(frame:GetChildren()) do
            if c ~= title and c:IsA("GuiObject") then c.Visible = not minimized end
        end
    end)
end

-- ============================================================
-- BOOT
-- ============================================================
neutraliseWatchdogs()
if CONF.Godmode then bindGodmode() end
hum.WalkSpeed = CONF.Speed
buildUI()

plr.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    task.wait(1)
    neutraliseWatchdogs()
    if CONF.Godmode then bindGodmode() end
    hum.WalkSpeed = CONF.Speed
end)
