-- piggy_escape.lua v5 — per-chapter flows, click detectors, animated UI
-- Delta / UNC. Mobile-tuned.

local plr   = game:GetService("Players").LocalPlayer
local rs    = game:GetService("RunService")
local UIS   = game:GetService("UserInputService")
local Tween = game:GetService("TweenService")

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
    BotRetreat = 40,
    AutoRun    = false,
    Godmode    = true,
}

-- ============================================================
-- CHAPTER FLOWS
-- Each chapter is a sequence of steps. Step = { type, targets, extra }
-- type: "pickup" | "use" | "touch" | "walk" | "wait"
-- ============================================================
local CHAPTERS = {
    ["House"] = {
        steps = {
            {t="pickup", n={"GreenKey","RedKey","BlueKey","YellowKey","SilverKey","WoodPlank","Wrench","Hammer","Gear"}},
            {t="use",    n={"WrenchPanel","Wrench","Generator"}, via="clickdetector"},
            {t="use",    n={"GreenLock","RedLock","BlueLock","YellowSafe","SilverLock"}, via="clickdetector"},
            {t="use",    n={"FrontDoor","ExitDoor","Exit"}, via="clickdetector"},
            {t="touch",  n={"Exit","ExitDoor"}},
        }
    },
    ["Station"] = {
        steps = {
            {t="pickup", n={"Wrench","Battery","Gas","GasCan","RedKey","Hammer"}},
            {t="use",    n={"WrenchPanel","Generator","Panel"}, via="clickdetector"},
            {t="pickup", n={"Battery","Gas","GasCan"}},
            {t="use",    n={"Car","Garage","Vehicle"}, via="clickdetector"},
            {t="touch",  n={"Exit","Garage","Car"}},
        }
    },
    ["Forest"] = {
        steps = {
            {t="pickup", n={"GreenKey","RedKey","BlueKey","OrangeKey","YellowKey","WhiteKey","PurpleKey","Hammer","Plank","Wrench","Torch","Gun","Ammo"}},
            {t="use",    n={"Generator","Gen"}, via="clickdetector"},
            {t="use",    n={"IceBlock","Cave"}, via="clickdetector"},
            {t="use",    n={"Exit","Gate"}, via="clickdetector"},
            {t="touch",  n={"Exit","Gate"}},
        }
    },
    ["Carnival"] = {
        steps = {
            {t="pickup", n={"Key","Ticket","Coin","Wrench","Hammer"}},
            {t="use",    n={"WrenchPanel","Panel"}, via="clickdetector"},
            {t="use",    n={"Lever","Button","Switch"}, via="clickdetector"},
            {t="use",    n={"Gate","Exit"}, via="clickdetector"},
            {t="touch",  n={"Exit","Gate"}},
        }
    },
    ["City"] = {
        steps = {
            {t="pickup", n={"Key","Fuse","Chip","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","FuseBox"}, via="clickdetector"},
            {t="use",    n={"Lever","Button","Train"}, via="clickdetector"},
            {t="touch",  n={"Exit","Train"}},
        }
    },
    ["Gallery"] = {
        steps = {
            {t="pickup", n={"Key","Battery","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel"}, via="clickdetector"},
            {t="use",    n={"Lever","Door","Exit"}, via="clickdetector"},
            {t="touch",  n={"Exit","Door"}},
        }
    },
    ["School"] = {
        steps = {
            {t="pickup", n={"Key","Book","Pencil","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","Lever","Gate"}, via="clickdetector"},
            {t="touch",  n={"Exit","Gate"}},
        }
    },
    ["Hospital"] = {
        steps = {
            {t="pickup", n={"Key","Medkit","Fuse","Battery","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","BatterySlot"}, via="clickdetector"},
            {t="use",    n={"Lever","Door","Ambulance"}, via="clickdetector"},
            {t="touch",  n={"Exit","Ambulance"}},
        }
    },
    ["Plant"] = {
        steps = {
            {t="pickup", n={"Key","Fuse","Valve","Wrench","Battery"}},
            {t="use",    n={"WrenchPanel","Valve","FuseBox","Panel"}, via="clickdetector"},
            {t="use",    n={"Lever","Gate","Exit"}, via="clickdetector"},
            {t="touch",  n={"Exit","Gate"}},
        }
    },
    ["Winter"] = {
        steps = {
            {t="pickup", n={"Key","Gift","Bell","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","Bell","Lever"}, via="clickdetector"},
            {t="touch",  n={"Exit","Sleigh"}},
        }
    },
    ["Alleys"] = {
        steps = {
            {t="pickup", n={"Key","Trash","Bottle","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","Lever"}, via="clickdetector"},
            {t="touch",  n={"Exit","Gate"}},
        }
    },
    ["Store"] = {
        steps = {
            {t="pickup", n={"Key","Fuse","Card","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","FuseBox"}, via="clickdetector"},
            {t="use",    n={"Lever","Door","Exit"}, via="clickdetector"},
            {t="touch",  n={"Exit","Door"}},
        }
    },
    ["Refinery"] = {
        steps = {
            {t="pickup", n={"Key","Barrel","Valve","Wrench","Battery"}},
            {t="use",    n={"WrenchPanel","Valve","Panel","Lever"}, via="clickdetector"},
            {t="touch",  n={"Exit","Gate"}},
        }
    },
    ["Sewers"] = {
        steps = {
            {t="pickup", n={"Key","Valve","Gear","Wrench"}},
            {t="use",    n={"WrenchPanel","Valve","Panel","GearSlot"}, via="clickdetector"},
            {t="touch",  n={"Exit","Manhole"}},
        }
    },
    ["Factory"] = {
        steps = {
            {t="pickup", n={"Key","Gear","Cog","WoodSword","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","GearSlot","Pony"}, via="clickdetector"},
            {t="touch",  n={"Exit","Gate"}},
        }
    },
    ["Port"] = {
        steps = {
            {t="pickup", n={"Key","Crate","Hook","Battery","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","BatterySlot","Lighthouse"}, via="clickdetector"},
            {t="touch",  n={"Exit","Ship","Lifeboat"}},
        }
    },
    ["Ship"] = {
        steps = {
            {t="pickup", n={"Key","Crate","Anchor","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","Anchor","Lever"}, via="clickdetector"},
            {t="touch",  n={"Exit","Lifeboat"}},
        }
    },
    ["Docks"] = {
        steps = {
            {t="pickup", n={"Key","Crate","Hook","Wrench","Battery"}},
            {t="use",    n={"WrenchPanel","Panel","Lever","BatterySlot"}, via="clickdetector"},
            {t="touch",  n={"Exit","Gate"}},
        }
    },
    ["Temple"] = {
        steps = {
            {t="pickup", n={"Key","Relic","Gem","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","RelicSlot","GemSlot"}, via="clickdetector"},
            {t="touch",  n={"Exit","Portal"}},
        }
    },
    ["Camp"] = {
        steps = {
            {t="pickup", n={"Key","Wood","Flint","Wrench"}},
            {t="use",    n={"WrenchPanel","Panel","Fire","Lever"}, via="clickdetector"},
            {t="touch",  n={"Exit","Gate"}},
        }
    },
    ["Lab"] = {
        steps = {
            {t="pickup", n={"Key","Fuse","Sample","Battery","Wrench","Dynamite","FireExtinguisher"}},
            {t="use",    n={"WrenchPanel","Panel","FuseBox","DynamiteSpot"}, via="clickdetector"},
            {t="use",    n={"Lever","Reactor","Exit"}, via="clickdetector"},
            {t="touch",  n={"Exit","Door"}},
        }
    },
    ["Distorted"] = {
        steps = {
            {t="pickup", n={"Key","Memory","Toy","Robot"}},
            {t="use",    n={"Lever","Portal","Rift","Coffin"}, via="clickdetector"},
            {t="touch",  n={"Portal","Rift","Exit"}},
        }
    },
}

local DEFAULT_CHAPTER = {
    steps = {
        {t="pickup", n={"Key","Fuse","Battery","Gear","Cog","Carrot","Chip","Card",
                        "Ticket","Coin","Book","Hammer","Wrench","Axe","Valve","Gift",
                        "Bell","Memory","Medkit","Relic","Gem","Sample","Crate","Wood",
                        "Torch","Gun","Ammo","Dynamite","FireExtinguisher","Plank","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","Generator","FuseBox","Lever","Button","Switch","Gate","Door","Exit"}, via="clickdetector"},
        {t="touch",  n={"Exit","ExitPad","ExitDoor","Escape","EscapeZone","ExtractionZone","EscapeDoor","Gate","Portal","Rift","Train","Car","Ambulance","Sleigh","Ship","Lifeboat","Manhole"}},
    }
}

-- ============================================================
-- MAP DETECTION
-- ============================================================
local function detectChapter()
    for chapterName in pairs(CHAPTERS) do
        for _, v in ipairs(workspace:GetDescendants()) do
            if v.Name:lower():find(chapterName:lower(), 1, true) then
                return chapterName, CHAPTERS[chapterName]
            end
        end
    end
    -- fallback: count key items to guess
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.Name:lower():find("wrench", 1, true) then
            return "Unknown (has Wrench)", DEFAULT_CHAPTER
        end
    end
    return "Unknown", DEFAULT_CHAPTER
end

local CHAPTER_NAME, CHAPTER = detectChapter()

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
-- MOVEMENT (walk, not fly)
-- ============================================================
local function walkTo(pos)
    if not hrp or not hrp.Parent or not hum.Parent then return false end
    hum.WalkSpeed = CONF.Speed
    hum:MoveTo(pos)

    local t0 = tick()
    local timeout = 6
    local lastPos = hrp.Position
    local stuckT = tick()
    repeat
        task.wait(0.1)
        if not hrp or not hrp.Parent then return false end
        local d = (Vector3.new(pos.X, hrp.Position.Y, pos.Z) - hrp.Position).Magnitude
        if d < 4 then return true end
        if (hrp.Position - lastPos).Magnitude < 0.5 then
            if tick() - stuckT > 2 then return false end
        else
            stuckT = tick()
        end
        lastPos = hrp.Position
    until tick() - t0 > timeout
    return false
end

-- ============================================================
-- INTERACTION (prompt + clickdetector + touch)
-- ============================================================
local function interact(part)
    if not part then return end
    local acted = false

    -- ProximityPrompt
    local prompt = part:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        for _, d in ipairs(part:GetDescendants()) do
            if d:IsA("ProximityPrompt") then prompt = d; break end
        end
    end
    if prompt and fpp then
        pcall(function() fpp(prompt) end)
        acted = true
    end

    -- ClickDetector
    local cd = part:FindFirstChildOfClass("ClickDetector")
    if not cd then
        for _, d in ipairs(part:GetDescendants()) do
            if d:IsA("ClickDetector") then cd = d; break end
        end
    end
    if cd and fcd then
        pcall(function() fcd(cd) end)
        acted = true
    end

    -- Touch fallback
    if not acted and fti then
        pcall(function()
            fti(hrp, part, 0); task.wait(0.08); fti(hrp, part, 1)
        end)
    end
end

-- ============================================================
-- DISCOVERY
-- ============================================================
local function findByName(patterns)
    local out = {}
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") or v:IsA("Model") then
            for _, p in ipairs(patterns) do
                if v.Name:lower():find(p:lower(), 1, true) then
                    table.insert(out, v)
                    break
                end
            end
        end
    end
    return out
end

-- ============================================================
-- MAIN LOOP — runs chapter steps in sequence
-- ============================================================
local running = false
local currentStep = 1

local function loop()
    currentStep = 1
    while running do
        task.wait(0.4)
        if not hrp or not hrp.Parent then return end

        local bot, bd = nearestBot()
        if bd and bd < CONF.BotRetreat then
            local away = hrp.Position + (hrp.Position - bot.HumanoidRootPart.Position).Unit * 50
            walkTo(away)
        else
            if currentStep > #CHAPTER.steps then currentStep = 1 end
            local step = CHAPTER.steps[currentStep]
            local found = findByName(step.n)

            if #found > 0 then
                for _, target in ipairs(found) do
                    if walkTo(target.Position) then
                        if step.t == "touch" then
                            interact(target)
                        else
                            interact(target)
                        end
                    end
                end
                -- only advance if nothing left to interact with
                local still = findByName(step.n)
                if #still == 0 then currentStep = currentStep + 1 end
            else
                currentStep = currentStep + 1
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
    frame.Size = UDim2.new(0, 260, 0, 340)
    frame.Position = UDim2.new(0, 20, 0.5, -170)
    frame.BackgroundColor3 = BG
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = sg
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke")
    stroke.Color = CYAN; stroke.Thickness = 1.5; stroke.Transparency = 0.2
    stroke.Parent = frame

    -- pulse animation on the border
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
    title.Text = "KESTREL-7  //  " .. CHAPTER_NAME
    title.TextColor3 = CYAN
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.Parent = frame
    Instance.new("UICorner", title).CornerRadius = UDim.new(0,12)

    -- fade in the title
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
            -- animate the press
            tween(btn, 0.1, {Size = UDim2.new(0,58,0,20)})
            tween(btn, 0.15, {Size = UDim2.new(0,64,0,22)})
            if key == "Godmode" and CONF.Godmode then bindGodmode() end
        end)

        -- slide-in animation
        row.Position = UDim2.new(0, -280, 0, y)
        tween(row, 0.4, {Position = UDim2.new(0,10,0,y)}, Enum.EasingStyle.Back)
        y = y + 40
    end

    makeToggle("Auto Run", "AutoRun", false)
    makeToggle("Godmode",  "Godmode", true)

    -- speed slider
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
            if not running then running = true; spawn(loop) end
            -- pulse
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

    -- minimize
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
            tween(frame, 0.3, {Size = UDim2.new(0,260,0,340)}, Enum.EasingStyle.Quart)
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
