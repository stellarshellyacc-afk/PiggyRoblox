-- piggy_escape.lua
-- Delta executor. Chapter-agnostic auto-escape with survival + AC bypass.
-- Repo root. Raw-fetchable.

local plr  = game:GetService("Players").LocalPlayer
local rs   = game:GetService("RunService")
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp  = char:WaitForChild("HumanoidRootPart")
local hum  = char:WaitForChild("Humanoid")

local fti = firetouchinterest
local gc  = getconnections
local shp = sethiddenproperty

local STEP  = 7
local TICK  = 0.028
local running = true

local EXIT_PATTERNS = {
    "Exit","ExitPad","ExitDoor","Escape","EscapeZone",
    "ExtractionZone","EscapeDoor"
}
local PICKUP_PATTERNS = {
    "Key","Fuse","Carrot","Battery","Gear","Cog"
}
local HAZARD_PATTERNS = {
    "Track","Coaster","Rail","Car","Kill","Lava","Spike"
}

-- ---------- anti-cheat bypass ----------

local function neutraliseWatchdogs()
    if not gc then return end
    for _, sig in ipairs({char.ChildAdded, hrp.Changed, hum.StateChanged}) do
        for _, c in ipairs(gc(sig)) do
            if c.Function then pcall(function() c:Disconnect() end) end
        end
    end
end

local function shadowPhysics()
    if shp then pcall(function() shp(hrp, "Massless", true) end) end
end

-- ---------- survival ----------

local function bindGodmode()
    hum.HealthChanged:Connect(function(h)
        if h < hum.MaxHealth then hum.Health = hum.MaxHealth end
    end)
    hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
        hum.Health = hum.MaxHealth
    end)
end

local function nearestBot()
    local best, bd = nil, math.huge
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Model") and v ~= char
           and v:FindFirstChild("HumanoidRootPart")
           and (v.Name:match("Piggy") or v.Name:match("Bot") or v.Name:match("Monster")) then
            local d = (v.HumanoidRootPart.Position - hrp.Position).Magnitude
            if d < bd then best, bd = v, d end
        end
    end
    return best, bd
end

-- ---------- movement ----------

local function isHazard(part)
    for _, p in ipairs(HAZARD_PATTERNS) do
        if part.Name:find(p, 1, true) then return true end
    end
    return false
end

local function stepTo(target)
    if not hrp or not hrp.Parent then return end
    if hrp.Anchored then hrp.Anchored = false end
    local dist = (target - hrp.Position).Magnitude
    if dist < 3 then return end
    local steps = math.ceil(dist / STEP)
    local dir   = (target - hrp.Position).Unit
    for i = 1, steps do
        if not running then return end
        if isHazard(hrp) then return end
        hrp.CFrame = CFrame.new(hrp.Position + dir * STEP)
        rs.Heartbeat:Wait()
        if i % 3 == 0 then task.wait(TICK) end
    end
end

local function touch(part)
    if fti then
        pcall(function()
            fti(hrp, part, 0)
            task.wait(0.05)
            fti(hrp, part, 1)
        end)
    end
end

-- ---------- target discovery ----------

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

-- ---------- main loop ----------

local function boot()
    neutraliseWatchdogs()
    shadowPhysics()
    bindGodmode()

    spawn(function()
        while running and task.wait(0.3) do
            if not hrp or not hrp.Parent then return end

            local bot, bd = nearestBot()
            if bd and bd < 30 then
                local away = hrp.Position + (hrp.Position - bot.HumanoidRootPart.Position).Unit * 40
                stepTo(away)
            else
                for _, item in ipairs(findByName(PICKUP_PATTERNS)) do
                    stepTo(item.Position)
                    touch(item)
                end
                local exits = findByName(EXIT_PATTERNS)
                if #exits > 0 then
                    local exit = exits[1]
                    stepTo(exit.Position + Vector3.new(0, 3, 0))
                    touch(exit)
                end
            end
        end
    end)
end

boot()

plr.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    running = true
    boot()
end)

plr.CharacterRemoving:Connect(function()
    running = false
end)
