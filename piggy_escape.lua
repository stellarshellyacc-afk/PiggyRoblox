-- piggy_escape.lua v7 — v5 flows + PathWalker movement + animated UI
-- Delta / UNC. Mobile-tuned.

local plr   = game:GetService("Players").LocalPlayer
local rs    = game:GetService("RunService")
local UIS   = game:GetService("UserInputService")
local Tween = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")

local char  = plr.Character or plr.CharacterAdded:Wait()
local hrp   = char:WaitForChild("HumanoidRootPart")
local hum   = char:WaitForChild("Humanoid")

local fti = firetouchinterest
local fpp = fireproximityprompt
local fcd = fireclickdetector
local gc  = getconnections

-- ============================================================
-- PATHWALKER (inlined)
-- ============================================================
local PathWalker = {}
PathWalker.__index = PathWalker

local DEFAULTS = {
    AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, AgentCanClimb = false,
    WaypointSpacing = 4, Costs = nil,
    ReachRadius = 3, FinalRadius = 5, WaypointTimeout = 6, CheckInterval = 0.1,
    StuckWindow = 0.6, StuckDistance = 0.8, SidestepDistance = 4,
    JumpAssist = true, JumpAssistCooldown = 0.5, JumpAssistReach = 3, JumpAssistLowOffset = 1.5,
    MaxRepaths = 5, RepathDelay = 0.25, RepathTargetDistance = 8,
}

local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function jumpHeightOf(h)
    if h.UseJumpPower then return (h.JumpPower * h.JumpPower) / (2 * workspace.Gravity) end
    return h.JumpHeight
end

function PathWalker.new(model, config)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    assert(humanoid and root, "PathWalker: model needs Humanoid + HumanoidRootPart")
    local self = setmetatable({}, PathWalker)
    self.Model, self.Humanoid, self.Root = model, humanoid, root
    self.Config = table.clone(DEFAULTS)
    if config then for k,v in pairs(config) do self.Config[k]=v end end
    self._token = 0
    self._lastJump = 0
    self._rayParams = RaycastParams.new()
    self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
    self._rayParams.FilterDescendantsInstances = {model}
    self._rayParams.IgnoreWater = true
    return self
end

function PathWalker:_agentParams()
    local c = self.Config
    local p = {AgentRadius=c.AgentRadius, AgentHeight=c.AgentHeight,
               AgentCanJump=c.AgentCanJump, AgentCanClimb=c.AgentCanClimb,
               WaypointSpacing=c.WaypointSpacing}
    if c.Costs then p.Costs = c.Costs end
    return p
end

function PathWalker:_assistJump(toward)
    local c = self.Config
    if not c.JumpAssist then return end
    local now = os.clock()
    if now - self._lastJump < c.JumpAssistCooldown then return end
    local state = self.Humanoid:GetState()
    if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then return end
    local dir = flat(toward - self.Root.Position)
    if dir.Magnitude < 0.1 then return end
    dir = dir.Unit * c.JumpAssistReach
    local lowOrigin = self.Root.Position - Vector3.new(0, c.JumpAssistLowOffset, 0)
    local hit = workspace:Raycast(lowOrigin, dir, self._rayParams)
    if not (hit and hit.Instance.CanCollide) then return end
    local clearance = jumpHeightOf(self.Humanoid) * 0.9
    local highOrigin = lowOrigin + Vector3.new(0, clearance, 0)
    local highHit = workspace:Raycast(highOrigin, dir, self._rayParams)
    if not highHit then
        self.Humanoid.Jump = true
        self._lastJump = now
    end
end

function PathWalker:_followWaypoint(wp, token, ctx)
    local c = self.Config
    local humanoid, root = self.Humanoid, self.Root
    if wp.Action == Enum.PathWaypointAction.Jump then
        humanoid.Jump = true
        self._lastJump = os.clock()
    end
    humanoid:MoveTo(wp.Position)
    local started = os.clock()
    local sampleT = started
    local samplePos = root.Position
    local stuckLevel = 0
    while true do
        task.wait(c.CheckInterval)
        if token ~= self._token then return "Cancelled" end
        if humanoid.Health <= 0 or not root.Parent then return "Dead" end
        local now = os.clock()
        local horiz = (flat(wp.Position) - flat(root.Position)).Magnitude
        local vert = math.abs(wp.Position.Y - root.Position.Y)
        if horiz < c.ReachRadius and vert < 4 then return "Reached" end
        if ctx.blocked then return "Blocked" end
        if ctx.targetPart and (ctx.targetPart.Position - ctx.targetPos).Magnitude > c.RepathTargetDistance then
            return "TargetMoved"
        end
        if now - started > c.WaypointTimeout then return "Timeout" end
        self:_assistJump(wp.Position)
        if now - sampleT >= c.StuckWindow then
            local moved = (root.Position - samplePos).Magnitude
            if moved < c.StuckDistance then
                stuckLevel += 1
                if stuckLevel == 1 then
                    humanoid.Jump = true
                    self._lastJump = now
                elseif stuckLevel == 2 then
                    local travel = flat(wp.Position - root.Position)
                    if travel.Magnitude > 0.1 then
                        local side = travel.Unit:Cross(Vector3.yAxis)
                        if math.random() < 0.5 then side = -side end
                        humanoid:MoveTo(root.Position + side * c.SidestepDistance)
                        task.wait(0.35)
                        if token ~= self._token then return "Cancelled" end
                        humanoid:MoveTo(wp.Position)
                    end
                else
                    return "Stuck"
                end
            else
                stuckLevel = 0
            end
            sampleT = now
            samplePos = root.Position
        end
    end
end

function PathWalker:_directFallback(targetPos, token, ctx)
    local origin = self.Root.Position
    local hit = workspace:Raycast(origin, targetPos - origin, self._rayParams)
    if hit then return false end
    local fake = {Position=targetPos, Action=Enum.PathWaypointAction.Walk}
    return self:_followWaypoint(fake, token, ctx) == "Reached"
end

function PathWalker:Cancel()
    self._token += 1
    pcall(function() self.Humanoid:MoveTo(self.Root.Position) end)
end

function PathWalker:WalkTo(target)
    local c = self.Config
    local targetPart, targetPos
    if typeof(target) == "Vector3" then
        targetPos = target
    elseif typeof(target) == "Instance" and target:IsA("BasePart") then
        targetPart = target; targetPos = target.Position
    else
        return false, "BadTarget"
    end
    self._token += 1
    local token = self._token
    for attempt = 1, c.MaxRepaths + 1 do
        if token ~= self._token then return false, "Cancelled" end
        if self.Humanoid.Health <= 0 or not self.Root.Parent then return false, "Dead" end
        if targetPart then targetPos = targetPart.Position end
        if (flat(targetPos) - flat(self.Root.Position)).Magnitude < c.FinalRadius then
            return true, "Reached"
        end
        local ctx = {blocked=false, index=0, targetPart=targetPart, targetPos=targetPos}
        local path = PathfindingService:CreatePath(self:_agentParams())
        local ok = pcall(function() path:ComputeAsync(self.Root.Position, targetPos) end)
        if not ok or path.Status ~= Enum.PathStatus.Success then
            if self:_directFallback(targetPos, token, ctx) then return true, "Reached" end
            if attempt > c.MaxRepaths then return false, "NoPath" end
            task.wait(c.RepathDelay)
            continue
        end
        local waypoints = path:GetWaypoints()
        local blockedConn = path.Blocked:Connect(function(bi)
            if bi >= ctx.index then ctx.blocked = true end
        end)
        local result = "Reached"
        for i = 2, #waypoints do
            ctx.index = i
            result = self:_followWaypoint(waypoints[i], token, ctx)
            if result ~= "Reached" then break end
        end
        blockedConn:Disconnect()
        if result == "Cancelled" or result == "Dead" then return false, result end
        if result == "Reached" then
            if (flat(targetPos) - flat(self.Root.Position)).Magnitude < c.FinalRadius then
                return true, "Reached"
            end
        end
        task.wait(c.RepathDelay)
    end
    return false, "MaxRepaths"
end

-- ============================================================
-- CONFIG
-- ============================================================
local CONF = {
    Speed      = 22,
    BotRetreat = 40,
    AutoRun    = true,
    Godmode    = true,
}

-- ============================================================
-- CHAPTER FLOWS
-- ============================================================
local CHAPTERS = {
    ["House"] = { steps = {
        {t="pickup", n={"GreenKey","RedKey","BlueKey","YellowKey","SilverKey","WoodPlank","Wrench","Hammer","Gear"}},
        {t="use",    n={"WrenchPanel","Wrench","Generator"}, via="clickdetector"},
        {t="use",    n={"GreenLock","RedLock","BlueLock","YellowSafe","SilverLock"}, via="clickdetector"},
        {t="use",    n={"FrontDoor","ExitDoor","Exit"}, via="clickdetector"},
        {t="touch",  n={"Exit","ExitDoor"}},
    }},
    ["Station"] = { steps = {
        {t="pickup", n={"Wrench","Battery","Gas","GasCan","RedKey","Hammer"}},
        {t="use",    n={"WrenchPanel","Generator","Panel"}, via="clickdetector"},
        {t="pickup", n={"Battery","Gas","GasCan"}},
        {t="use",    n={"Car","Garage","Vehicle"}, via="clickdetector"},
        {t="touch",  n={"Exit","Garage","Car"}},
    }},
    ["Forest"] = { steps = {
        {t="pickup", n={"GreenKey","RedKey","BlueKey","OrangeKey","YellowKey","WhiteKey","PurpleKey","Hammer","Plank","Wrench","Torch","Gun","Ammo"}},
        {t="use",    n={"Generator","Gen"}, via="clickdetector"},
        {t="use",    n={"IceBlock","Cave"}, via="clickdetector"},
        {t="use",    n={"Exit","Gate"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["Carnival"] = { steps = {
        {t="pickup", n={"Key","Ticket","Coin","Wrench","Hammer"}},
        {t="use",    n={"WrenchPanel","Panel"}, via="clickdetector"},
        {t="use",    n={"Lever","Button","Switch"}, via="clickdetector"},
        {t="use",    n={"Gate","Exit"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["City"] = { steps = {
        {t="pickup", n={"Key","Fuse","Chip","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","FuseBox"}, via="clickdetector"},
        {t="use",    n={"Lever","Button","Train"}, via="clickdetector"},
        {t="touch",  n={"Exit","Train"}},
    }},
    ["Gallery"] = { steps = {
        {t="pickup", n={"Key","Battery","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel"}, via="clickdetector"},
        {t="use",    n={"Lever","Door","Exit"}, via="clickdetector"},
        {t="touch",  n={"Exit","Door"}},
    }},
    ["School"] = { steps = {
        {t="pickup", n={"Key","Book","Pencil","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","Lever","Gate"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["Hospital"] = { steps = {
        {t="pickup", n={"Key","Medkit","Fuse","Battery","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","BatterySlot"}, via="clickdetector"},
        {t="use",    n={"Lever","Door","Ambulance"}, via="clickdetector"},
        {t="touch",  n={"Exit","Ambulance"}},
    }},
    ["Plant"] = { steps = {
        {t="pickup", n={"Key","Fuse","Valve","Wrench","Battery"}},
        {t="use",    n={"WrenchPanel","Valve","FuseBox","Panel"}, via="clickdetector"},
        {t="use",    n={"Lever","Gate","Exit"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["Winter"] = { steps = {
        {t="pickup", n={"Key","Gift","Bell","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","Bell","Lever"}, via="clickdetector"},
        {t="touch",  n={"Exit","Sleigh"}},
    }},
    ["Alleys"] = { steps = {
        {t="pickup", n={"Key","Trash","Bottle","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","Lever"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["Store"] = { steps = {
        {t="pickup", n={"Key","Fuse","Card","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","FuseBox"}, via="clickdetector"},
        {t="use",    n={"Lever","Door","Exit"}, via="clickdetector"},
        {t="touch",  n={"Exit","Door"}},
    }},
    ["Refinery"] = { steps = {
        {t="pickup", n={"Key","Barrel","Valve","Wrench","Battery"}},
        {t="use",    n={"WrenchPanel","Valve","Panel","Lever"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["Sewers"] = { steps = {
        {t="pickup", n={"Key","Valve","Gear","Wrench"}},
        {t="use",    n={"WrenchPanel","Valve","Panel","GearSlot"}, via="clickdetector"},
        {t="touch",  n={"Exit","Manhole"}},
    }},
    ["Factory"] = { steps = {
        {t="pickup", n={"Key","Gear","Cog","WoodSword","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","GearSlot","Pony"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["Port"] = { steps = {
        {t="pickup", n={"Key","Crate","Hook","Battery","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","BatterySlot","Lighthouse"}, via="clickdetector"},
        {t="touch",  n={"Exit","Ship","Lifeboat"}},
    }},
    ["Ship"] = { steps = {
        {t="pickup", n={"Key","Crate","Anchor","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","Anchor","Lever"}, via="clickdetector"},
        {t="touch",  n={"Exit","Lifeboat"}},
    }},
    ["Docks"] = { steps = {
        {t="pickup", n={"Key","Crate","Hook","Wrench","Battery"}},
        {t="use",    n={"WrenchPanel","Panel","Lever","BatterySlot"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["Temple"] = { steps = {
        {t="pickup", n={"Key","Relic","Gem","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","RelicSlot","GemSlot"}, via="clickdetector"},
        {t="touch",  n={"Exit","Portal"}},
    }},
    ["Camp"] = { steps = {
        {t="pickup", n={"Key","Wood","Flint","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","Fire","Lever"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["Lab"] = { steps = {
        {t="pickup", n={"Key","Fuse","Sample","Battery","Wrench","Dynamite","FireExtinguisher"}},
        {t="use",    n={"WrenchPanel","Panel","FuseBox","DynamiteSpot"}, via="clickdetector"},
        {t="use",    n={"Lever","Reactor","Exit"}, via="clickdetector"},
        {t="touch",  n={"Exit","Door"}},
    }},
    ["Distorted"] = { steps = {
        {t="pickup", n={"Key","Memory","Toy","Robot"}},
        {t="use",    n={"Lever","Portal","Rift","Coffin"}, via="clickdetector"},
        {t="touch",  n={"Portal","Rift","Exit"}},
    }},
}

local DEFAULT_CHAPTER = { steps = {
    {t="pickup", n={"Key","Fuse","Battery","Gear","Cog","Carrot","Chip","Card",
                    "Ticket","Coin","Book","Hammer","Wrench","Axe","Valve","Gift",
                    "Bell","Memory","Medkit","Relic","Gem","Sample","Crate","Wood",
                    "Torch","Gun","Ammo","Dynamite","FireExtinguisher","Plank","Wrench"}},
    {t="use",    n={"WrenchPanel","Panel","Generator","FuseBox","Lever","Button","Switch","Gate","Door","Exit"}, via="clickdetector"},
    {t="touch",  n={"Exit","ExitPad","ExitDoor","Escape","EscapeZone","ExtractionZone","EscapeDoor","Gate","Portal","Rift","Train","Car","Ambulance","Sleigh","Ship","Lifeboat","Manhole"}},
}}

-- ============================================================
-- MAP DETECTION
-- ============================================================
local function normaliseMapName(name)
    return tostring(name):lower():gsub("[^%w]", "")
end

local function exactChapterName(name)
    local wanted = normaliseMapName(name)
    for chapterName in pairs(CHAPTERS) do
        if normaliseMapName(chapterName) == wanted then
            return chapterName, CHAPTERS[chapterName]
        end
    end
    return nil
end

local function detectChapter()
    -- Best option: set workspace:SetAttribute("PiggyChapter", "Plant")
    -- from the map loader, or tag the active map model "Chapter_Plant".
    -- This is intentionally checked before item-name scanning.
    local attributeName = workspace:GetAttribute("PiggyChapter")
    if typeof(attributeName) == "string" then
        local chapterName, chapter = exactChapterName(attributeName)
        if chapterName then return chapterName, chapter end
    end

    local containers = {}
    for _, containerName in ipairs({"Map", "CurrentMap", "ActiveMap", "MapFolder"}) do
        local container = workspace:FindFirstChild(containerName)
        if container then
            table.insert(containers, container)
        end
    end

    -- Only inspect the active map container first. This prevents a random
    -- descendant named Station from winning while playing Plant.
    for _, container in ipairs(containers) do
            local taggedName
            for chapterName in pairs(CHAPTERS) do
                if CollectionService:HasTag(container, "Chapter_" .. chapterName) then
                    return chapterName, CHAPTERS[chapterName]
                end
            end
            local exactName, exactChapter = exactChapterName(container.Name)
            if exactName then return exactName, exactChapter end
            for _, child in ipairs(container:GetChildren()) do
                local childName, childChapter = exactChapterName(child.Name)
                if childName then return childName, childChapter end
                if CollectionService:HasTag(child, "ActiveMap") then
                    for chapterName in pairs(CHAPTERS) do
                        if normaliseMapName(child.Name):find(normaliseMapName(chapterName), 1, true) then
                            return chapterName, CHAPTERS[chapterName]
                        end
                    end
                end
            end
        end
    end

    -- Then inspect only direct Workspace children for an exact map name.
    for _, child in ipairs(workspace:GetChildren()) do
        local childName, childChapter = exactChapterName(child.Name)
        if childName then return childName, childChapter end
        for chapterName in pairs(CHAPTERS) do
            if CollectionService:HasTag(child, "Chapter_" .. chapterName) then
                return chapterName, CHAPTERS[chapterName]
            end
        end
    end

    -- Last-resort compatibility fallback: choose the chapter with the most
    -- matching named targets, rather than returning the first pairs() result.
    local bestName, bestChapter, bestScore = "Unknown", DEFAULT_CHAPTER, 0
    for chapterName, chapter in pairs(CHAPTERS) do
        local score = 0
        for _, step in ipairs(chapter.steps) do
            for _, pattern in ipairs(step.n) do
                for _, instance in ipairs(workspace:GetDescendants()) do
                    if (instance:IsA("BasePart") or instance:IsA("Model"))
                        and instance.Name:lower():find(pattern:lower(), 1, true) then
                        score += 1
                        break
                    end
                end
            end
        end
        if score > bestScore then
            bestName, bestChapter, bestScore = chapterName, chapter, score
        end
    end
    return bestName, bestChapter
end

local CHAPTER_NAME, CHAPTER = detectChapter()

-- ============================================================
-- WALKER INSTANCE
-- ============================================================
local walker = PathWalker.new(char, {
    AgentRadius = 2, AgentHeight = 5, AgentCanJump = true,
    ReachRadius = 3, FinalRadius = 4, CheckInterval = 0.1,
    JumpAssist = true, MaxRepaths = 5,
})

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
-- INTERACTION (prompt + clickdetector + touch)
-- ============================================================
local function interact(part)
    if not part or not part.Parent then return false end
    local acted = false
    local prompt = part:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        for _, d in ipairs(part:GetDescendants()) do
            if d:IsA("ProximityPrompt") then prompt = d; break end
        end
    end
    if prompt and fpp then
        local ok = pcall(function() fpp(prompt) end)
        acted = ok or acted
    end
    local cd = part:FindFirstChildOfClass("ClickDetector")
    if not cd then
        for _, d in ipairs(part:GetDescendants()) do
            if d:IsA("ClickDetector") then cd = d; break end
        end
    end
    if cd and fcd then
        local ok = pcall(function() fcd(cd) end)
        acted = ok or acted
    end
    if not acted and fti and part:IsA("BasePart") then
        local ok = pcall(function()
            fti(hrp, part, 0)
            task.wait(0.08)
            fti(hrp, part, 1)
        end)
        acted = ok or acted
    end
    return acted
end

-- ============================================================
-- DISCOVERY
-- ============================================================
local function getWalkTarget(instance)
    if not instance or not instance.Parent then
        return nil
    end
    if instance:IsA("BasePart") then
        return instance
    end
    if instance:IsA("Model") then
        return instance.PrimaryPart
            or instance:FindFirstChild("HumanoidRootPart")
            or instance:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function findTaggedOrNamed(patterns)
    local out, seen = {}, {}

    -- Tags are preferred. A chapter target can have tags such as Use_ExitDoor.
    for _, pattern in ipairs(patterns) do
        local possibleTags = {pattern, "Spawn_" .. pattern, "Use_" .. pattern}
        for _, tag in ipairs(possibleTags) do
            for _, instance in ipairs(CollectionService:GetTagged(tag)) do
                if instance:IsDescendantOf(workspace) and not seen[instance] then
                    seen[instance] = true
                    table.insert(out, instance)
                end
            end
        end
    end

    -- Keep the old name fallback for existing maps.
    if #out == 0 then
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") or v:IsA("Model") then
                local lowerName = v.Name:lower()
                for _, p in ipairs(patterns) do
                    if lowerName:find(p:lower(), 1, true) then
                        table.insert(out, v)
                        break
                    end
                end
            end
        end
    end
    return out
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local running = false
local currentStep = 1
local handledTargets = {}
local activeHighlights = {}

local function clearHighlights()
    for target, highlight in pairs(activeHighlights) do
        if highlight then highlight:Destroy() end
        activeHighlights[target] = nil
    end
end

local function highlightTarget(target, color)
    if activeHighlights[target] or not target or not target.Parent then return end
    local h = Instance.new("Highlight")
    h.Name = "KestrelObjectiveHighlight"
    h.Adornee = target
    h.FillColor = color
    h.OutlineColor = Color3.fromRGB(255, 255, 255)
    h.FillTransparency = 0.45
    h.OutlineTransparency = 0
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = target
    activeHighlights[target] = h
end

local function loop()
    currentStep = 1
    handledTargets = {}
    while running do
        task.wait(0.4)
        if not hrp or not hrp.Parent then return end
        local bot, bd = nearestBot()
        if bd and bd < CONF.BotRetreat then
            clearHighlights()
            local awayDirection = hrp.Position - bot.HumanoidRootPart.Position
            if awayDirection.Magnitude > 0.1 then
                walker:WalkTo(hrp.Position + awayDirection.Unit * 50)
            end
        else
            if currentStep > #CHAPTER.steps then
                clearHighlights()
                running = false
                break
            end

            local step = CHAPTER.steps[currentStep]
            local found = findTaggedOrNamed(step.n)
            local remaining = 0
            clearHighlights()

            local color = step.t == "pickup"
                and Color3.fromRGB(0, 255, 120)
                or Color3.fromRGB(255, 170, 0)

            for _, target in ipairs(found) do
                if not handledTargets[target] and target.Parent then
                    remaining += 1
                    highlightTarget(target, color)
                end
            end

            if remaining == 0 then
                currentStep += 1
                handledTargets = {}
            else
                for _, target in ipairs(found) do
                    if not handledTargets[target] and target.Parent then
                        local walkTarget = getWalkTarget(target)
                        if walkTarget then
                            local ok, reason = walker:WalkTo(walkTarget)
                            if ok then
                                -- Mark it handled locally so static objects do
                                -- not make the bot repeat the same interaction.
                                interact(target)
                                handledTargets[target] = true
                                task.wait(0.15)
                            else
                                warn("PathWalker failed:", target:GetFullName(), reason)
                            end
                        else
                            handledTargets[target] = true
                        end
                    end
                end
            end
        end
    end
    clearHighlights()
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
    title.Text = "KESTREL-7  //  " .. CHAPTER_NAME .. "  //  AUTO"
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
            if not running then running = true; spawn(loop) end
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

-- Start automatically when AutoRun is enabled.
if CONF.AutoRun and not running then
    running = true
    task.spawn(loop)
end

plr.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    task.wait(1)
    walker = PathWalker.new(char, {
        AgentRadius = 2, AgentHeight = 5, AgentCanJump = true,
        ReachRadius = 3, FinalRadius = 4, CheckInterval = 0.1,
        JumpAssist = true, MaxRepaths = 5,
    })
    neutraliseWatchdogs()
    if CONF.Godmode then bindGodmode() end
    hum.WalkSpeed = CONF.Speed
end)
