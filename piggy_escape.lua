-- piggy_escape.lua v4 — walk + grab + map detect + futuristic UI
-- Delta / UNC. Mobile-tuned.

local plr   = game:GetService("Players").LocalPlayer
local rs    = game:GetService("RunService")
local char  = plr.Character or plr.CharacterAdded:Wait()
local hrp   = char:WaitForChild("HumanoidRootPart")
local hum   = char:WaitForChild("Humanoid")

local fti = firetouchinterest
local fpp = fireproximityprompt
local gc  = getconnections

-- ---------- TUNABLES ----------
local CONF = {
    Speed        = 24,
    BotRetreat   = 40,
    AutoRun      = false,
    Godmode      = true,
}

-- ---------- MAP DETECTION ----------
-- Piggy clones the chapter into workspace under a name. Detect by scanning
-- for the Map folder, then matching its child names against known chapters.
local CHAPTERS = {
    Forest       = { pickups={"Key","Axe","Wood"},       exits={"Exit","Gate"} },
    House        = { pickups={"Key","Hammer","Wrench"},  exits={"Exit","ExitDoor"} },
    Station      = { pickups={"Key","Fuse","Card"},      exits={"Exit","Train"} },
    Gallery      = { pickups={"Key","Battery"},          exits={"Exit","Door"} },
    School       = { pickups={"Key","Book","Pencil"},    exits={"Exit","Gate"} },
    Hospital     = { pickups={"Key","Medkit","Fuse"},    exits={"Exit","Ambulance"} },
    Carnival     = { pickups={"Key","Ticket","Coin"},    exits={"Exit","Gate"} },
    City         = { pickups={"Key","Fuse","Chip"},      exits={"Exit","Car"} },
    Plant        = { pickups={"Key","Fuse","Valve"},     exits={"Exit","Gate"} },
    Winter       = { pickups={"Key","Gift","Bell"},      exits={"Exit","Sleigh"} },
    Alleys       = { pickups={"Key","Trash","Bottle"},   exits={"Exit","Gate"} },
    Store        = { pickups={"Key","Fuse","Card"},      exits={"Exit","Door"} },
    Refinery     = { pickups={"Key","Barrel","Valve"},   exits={"Exit","Gate"} },
    Safe         = { pickups={"Key","Code","Button"},    exits={"Exit","Door"} },
    Sewers       = { pickups={"Key","Valve","Gear"},     exits={"Exit","Manhole"} },
    Factory      = { pickups={"Key","Gear","Cog"},       exits={"Exit","Gate"} },
    Port         = { pickups={"Key","Crate","Hook"},     exits={"Exit","Ship"} },
    Ship         = { pickups={"Key","Crate","Anchor"},   exits={"Exit","Lifeboat"} },
    Docks        = { pickups={"Key","Crate","Hook"},     exits={"Exit","Gate"} },
    Temple       = { pickups={"Key","Relic","Gem"},      exits={"Exit","Portal"} },
    Camp         = { pickups={"Key","Wood","Flint"},     exits={"Exit","Gate"} },
    Lab          = { pickups={"Key","Fuse","Sample"},    exits={"Exit","Door"} },
    Distorted    = { pickups={"Key","Memory"},           exits={"Portal","Rift","Exit"} },
}
local DEFAULT_CHAPTER = {
    pickups = {"Key","Fuse","Battery","Gear","Cog","Carrot","Chip","Card",
               "Ticket","Coin","Book","Hammer","Wrench","Axe","Valve","Gift",
               "Bell","Memory","Medkit","Relic","Gem","Sample","Crate","Wood"},
    exits   = {"Exit","ExitPad","ExitDoor","Escape","EscapeZone","ExtractionZone",
               "EscapeDoor","Gate","Portal","Rift","Train","Car","Ambulance",
               "Sleigh","Ship","Lifeboat","Manhole"},
}

local function detectMap()
    -- scan all workspace descendants for the chapter clone
    local best, bestScore = nil, 0
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Model") or v:IsA("Folder") then
            local n = v.Name:lower()
            for chapterName in pairs(CHAPTERS) do
                if n:find(chapterName:lower(), 1, true) then
                    return chapterName, CHAPTERS[chapterName]
                end
            end
        end
    end
    -- fallback: scan for keys/exits directly
    return "Unknown", DEFAULT_CHAPTER
end

local CHAPTER_NAME, CHAPTER = detectMap()

-- ---------- ANTI-CHEAT ----------
local function neutraliseWatchdogs()
    if not gc then return end
    for _, sig in ipairs({char.ChildAdded, hrp.Changed, hum.StateChanged}) do
        for _, c in ipairs(gc(sig)) do
            if c.Function then pcall(function() c:Disconnect() end) end
        end
    end
end

-- ---------- GODMODE ----------
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

-- ---------- MOVEMENT (walk, no fly) ----------
local function walkTo(pos)
    if not hrp or not hrp.Parent or not hum.Parent then return false end
    if hum.WalkSpeed < CONF.Speed then hum.WalkSpeed = CONF.Speed end

    hum:MoveTo(pos)
    local t0 = tick()
    local timeout = 8
    repeat
        task.wait(0.1)
        if not hrp or not hrp.Parent then return false end
        local d = (Vector3.new(pos.X, hrp.Position.Y, pos.Z) - hrp.Position).Magnitude
        if d < 4 then return true end
        -- stuck check: if position hasn't changed for 1.5s, abort
    until tick() - t0 > timeout
    return false
end

-- ---------- GRAB ----------
local function grab(part)
    if not part then return end
    -- ProximityPrompt first (modern Piggy)
    local prompt = part:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        for _, d in ipairs(part:GetDescendants()) do
            if d:IsA("ProximityPrompt") then prompt = d; break end
        end
    end
    if prompt and fpp then
        pcall(function() fpp(prompt) end)
        return
    end
    -- fallback: touch
    if fti then
        pcall(function()
            fti(hrp, part, 0); task.wait(0.08); fti(hrp, part, 1)
        end)
    end
end

local function findByName(patterns)
    local out = {}
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") then
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
        task.wait(0.3)
        if not hrp or not hrp.Parent then return end

        local bot, bd = nearestBot()
        if bd and bd < CONF.BotRetreat then
            local away = hrp.Position + (hrp.Position - bot.HumanoidRootPart.Position).Unit * 50
            walkTo(away)
        else
            for _, item in ipairs(findByName(CHAPTER.pickups)) do
                if walkTo(item.Position) then grab(item) end
            end
            local exits = findByName(CHAPTER.exits)
            if #exits > 0 then
                if walkTo(exits[1].Position) then grab(exits[1]) end
            end
        end
    end
end

-- ---------- FUTURISTIC UI ----------
local function buildUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "K7_PiggyUI"
    sg.ResetOnSpawn = false
    sg.Parent = plr:WaitForChild("PlayerGui")

    -- neon colors
    local CYAN   = Color3.fromRGB(0, 255, 220)
    local PINK   = Color3.fromRGB(255, 60, 160)
    local BG     = Color3.fromRGB(8, 10, 18)
    local PANEL  = Color3.fromRGB(14, 18, 30)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 260, 0, 310)
    frame.Position = UDim2.new(0, 20, 0.5, -155)
    frame.BackgroundColor3 = BG
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = sg

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    -- outer neon stroke
    local stroke = Instance.new("UIStroke")
    stroke.Color = CYAN
    stroke.Thickness = 1.5
    stroke.Transparency = 0.2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame

    -- gradient background
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 14, 24)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 6, 12)),
    }
    grad.Rotation = 135
    grad.Parent = frame

    -- title bar
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 36)
    title.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
    title.BackgroundTransparency = 0.3
    title.BorderSizePixel = 0
    title.Text = "KESTREL-7  //  " .. CHAPTER_NAME
    title.TextColor3 = CYAN
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.Parent = frame
    local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0,12); tc.Parent = title
    local ts = Instance.new("UIStroke"); ts.Color = CYAN; ts.Thickness = 1; ts.Transparency = 0.4; ts.Parent = title

    local y = 46
    local function makeToggle(label, key, default)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1,-20,0,34)
        row.Position = UDim2.new(0,10,0,y)
        row.BackgroundColor3 = PANEL
        row.BackgroundTransparency = 0.2
        row.BorderSizePixel = 0
        row.Parent = frame
        local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0,6); rc.Parent = row
        local rs2 = Instance.new("UIStroke"); rs2.Color = CYAN; rs2.Thickness = 1; rs2.Transparency = 0.7; rs2.Parent = row

        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(0.65,0,1,0)
        txt.Position = UDim2.new(0,10,0,0)
        txt.BackgroundTransparency = 1
        txt.Text = label
        txt.TextColor3 = Color3.fromRGB(200, 210, 230)
        txt.Font = Enum.Font.Code
        txt.TextSize = 13
        txt.TextXAlignment = Enum.TextXAlignment.Left
        txt.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0,64,0,22)
        btn.Position = UDim2.new(1,-74,0.5,-11)
        btn.BackgroundColor3 = default and Color3.fromRGB(0, 120, 90) or Color3.fromRGB(30, 34, 46)
        btn.BorderSizePixel = 0
        btn.Text = default and "ON" or "OFF"
        btn.TextColor3 = default and CYAN or Color3.fromRGB(120, 130, 150)
        btn.Font = Enum.Font.Code
        btn.TextSize = 12
        btn.Parent = row
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,5); bc.Parent = btn
        local bs = Instance.new("UIStroke"); bs.Color = default and CYAN or Color3.fromRGB(60, 70, 90); bs.Thickness = 1; bs.Transparency = 0.3; bs.Parent = btn

        btn.MouseButton1Click:Connect(function()
            CONF[key] = not CONF[key]
            btn.Text = CONF[key] and "ON" or "OFF"
            btn.TextColor3 = CONF[key] and CYAN or Color3.fromRGB(120, 130, 150)
            btn.BackgroundColor3 = CONF[key] and Color3.fromRGB(0, 120, 90) or Color3.fromRGB(30, 34, 46)
            bs.Color = CONF[key] and CYAN or Color3.fromRGB(60, 70, 90)
            if key == "Godmode" and CONF.Godmode then bindGodmode() end
        end)
        y = y + 40
    end

    makeToggle("Auto Run", "AutoRun",  false)
    makeToggle("Godmode",  "Godmode",  true)

    -- speed slider
    local srow = Instance.new("Frame")
    srow.Size = UDim2.new(1,-20,0,52)
    srow.Position = UDim2.new(0,10,0,y)
    srow.BackgroundColor3 = PANEL
    srow.BackgroundTransparency = 0.2
    srow.BorderSizePixel = 0
    srow.Parent = frame
    local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0,6); sc.Parent = srow
    local ss = Instance.new("UIStroke"); ss.Color = PINK; ss.Thickness = 1; ss.Transparency = 0.5; ss.Parent = srow

    local slab = Instance.new("TextLabel")
    slab.Size = UDim2.new(1,-20,0,22)
    slab.Position = UDim2.new(0,10,0,2)
    slab.BackgroundTransparency = 1
    slab.Text = "Speed: " .. CONF.Speed
    slab.TextColor3 = PINK
    slab.Font = Enum.Font.Code
    slab.TextSize = 13
    slab.TextXAlignment = Enum.TextXAlignment.Left
    slab.Parent = srow

    local function mkBtn(txt, x)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0,64,0,24)
        b.Position = UDim2.new(0,x,0,26)
        b.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
        b.BorderSizePixel = 0
        b.Text = txt
        b.TextColor3 = PINK
        b.Font = Enum.Font.Code
        b.TextSize = 16
        b.Parent = srow
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = b
        local s = Instance.new("UIStroke"); s.Color = PINK; s.Thickness = 1; s.Transparency = 0.4; s.Parent = b
        return b
    end

    local minus = mkBtn("-", 10)
    local plus  = mkBtn("+", 82)

    minus.MouseButton1Click:Connect(function()
        CONF.Speed = math.max(16, CONF.Speed - 2)
        slab.Text = "Speed: " .. CONF.Speed
        hum.WalkSpeed = CONF.Speed
    end)
    plus.MouseButton1Click:Connect(function()
        CONF.Speed = math.min(60, CONF.Speed + 2)
        slab.Text = "Speed: " .. CONF.Speed
        hum.WalkSpeed = CONF.Speed
    end)

    y = y + 58

    local runBtn = Instance.new("TextButton")
    runBtn.Size = UDim2.new(1,-20,0,40)
    runBtn.Position = UDim2.new(0,10,0,y)
    runBtn.BackgroundColor3 = Color3.fromRGB(90, 20, 60)
    runBtn.BorderSizePixel = 0
    runBtn.Text = "START"
    runBtn.TextColor3 = Color3.fromRGB(255, 200, 230)
    runBtn.Font = Enum.Font.Code
    runBtn.TextSize = 16
    runBtn.Parent = frame
    local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0,6); rc.Parent = runBtn
    local rs3 = Instance.new("UIStroke"); rs3.Color = PINK; rs3.Thickness = 1.5; rs3.Transparency = 0.2; rs3.Parent = runBtn

    runBtn.MouseButton1Click:Connect(function()
        CONF.AutoRun = not CONF.AutoRun
        if CONF.AutoRun then
            runBtn.Text = "STOP"
            runBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 90)
            runBtn.TextColor3 = CYAN
            rs3.Color = CYAN
            if not running then running = true; spawn(loop) end
        else
            runBtn.Text = "START"
            runBtn.BackgroundColor3 = Color3.fromRGB(90, 20, 60)
            runBtn.TextColor3 = Color3.fromRGB(255, 200, 230)
            rs3.Color = PINK
            running = false
        end
    end)

    -- minimize
    local min = Instance.new("TextButton")
    min.Size = UDim2.new(0,24,0,24)
    min.Position = UDim2.new(1,-30,0,6)
    min.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
    min.BorderSizePixel = 0
    min.Text = "–"
    min.TextColor3 = CYAN
    min.Font = Enum.Font.Code
    min.TextSize = 14
    min.Parent = title
    local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0,5); mc.Parent = min
    local ms = Instance.new("UIStroke"); ms.Color = CYAN; ms.Thickness = 1; ms.Transparency = 0.4; ms.Parent = min

    local minimized = false
    min.MouseButton1Click:Connect(function()
        minimized = not minimized
        frame.Size = minimized and UDim2.new(0,260,0,36) or UDim2.new(0,260,0,y+50)
        for _, c in ipairs(frame:GetChildren()) do
            if c ~= title and c:IsA("GuiObject") then c.Visible = not minimized end
        end
    end)
end

-- ---------- BOOT ----------
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
