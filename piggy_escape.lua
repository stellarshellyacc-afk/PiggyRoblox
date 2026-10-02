-- piggy_escape.lua v6 — PathWalker integrated
local plr   = game:GetService("Players").LocalPlayer
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
-- PATHWALKER (inlined from Claude's module)
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
local CONF = { Speed = 22, BotRetreat = 40, AutoRun = false, Godmode = true }

-- ============================================================
-- CHAPTERS (steps same as v5, trimmed here)
-- ============================================================
local CHAPTERS = {
    ["Station"] = { steps = {
        {t="pickup", n={"Wrench","Battery","Gas","GasCan","RedKey","Hammer"}},
        {t="use",    n={"WrenchPanel","Generator","Panel"}, via="clickdetector"},
        {t="pickup", n={"Battery","Gas","GasCan"}},
        {t="use",    n={"Car","Garage","Vehicle"}, via="clickdetector"},
        {t="touch",  n={"Exit","Garage","Car"}},
    }},
    ["Forest"] = { steps = {
        {t="pickup", n={"GreenKey","RedKey","BlueKey","OrangeKey","YellowKey","WhiteKey","PurpleKey","Hammer","Plank","Wrench"}},
        {t="use",    n={"Generator","Gen"}, via="clickdetector"},
        {t="use",    n={"Exit","Gate"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["House"] = { steps = {
        {t="pickup", n={"GreenKey","RedKey","BlueKey","YellowKey","SilverKey","Wrench","Hammer","Gear"}},
        {t="use",    n={"WrenchPanel","Wrench","Generator"}, via="clickdetector"},
        {t="touch",  n={"Exit","ExitDoor"}},
    }},
    ["Carnival"] = { steps = {
        {t="pickup", n={"Key","Ticket","Coin","Wrench","Hammer"}},
        {t="use",    n={"WrenchPanel","Panel","Lever"}, via="clickdetector"},
        {t="touch",  n={"Exit","Gate"}},
    }},
    ["City"] = { steps = {
        {t="pickup", n={"Key","Fuse","Chip","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","FuseBox"}, via="clickdetector"},
        {t="touch",  n={"Exit","Train"}},
    }},
    ["Gallery"] = { steps = {
        {t="pickup", n={"Key","Battery","Wrench"}},
        {t="use",    n={"WrenchPanel","Panel","Lever"}, via="clickdetector"},
        {t="touch",  n={"Exit","Door"}},
    }},
}
-- Add the rest of your chapter list here from v5 (School, Hospital, etc.)

local DEFAULT_CHAPTER = { steps = {
    {t="pickup", n={"Key","Fuse","Battery","Gear","Cog","Carrot","Chip","Card","Ticket","Coin","Book","Hammer","Wrench","Axe","Valve","Gift","Bell","Memory","Medkit","Relic","Gem","Sample","Crate","Wood"}},
    {t="use",    n={"WrenchPanel","Panel","Generator","FuseBox","Lever","Button","Switch","Gate","Door","Exit"}, via="clickdetector"},
    {t="touch",  n={"Exit","ExitPad","ExitDoor","Escape","EscapeZone","ExtractionZone","EscapeDoor","Gate","Portal","Rift","Train","Car","Ambulance","Sleigh","Ship","Lifeboat","Manhole"}},
}}

local function detectChapter()
    for chapterName in pairs(CHAPTERS) do
        for _, v in ipairs(workspace:GetDescendants()) do
            if v.Name:lower():find(chapterName:lower(), 1, true) then
                return chapterName, CHAPTERS[chapterName]
            end
        end
    end
    return "Unknown", DEFAULT_CHAPTER
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
            if n:find("piggy") or n:find("bot") or n:find("monster") then
                local d = (v.HumanoidRootPart.Position - hrp.Position).Magnitude
                if d < bd then best, bd = v, d end
            end
        end
    end
    return best, bd
end

-- ============================================================
-- INTERACTION
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

local function findByName(patterns)
    local out = {}
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") or v:IsA("Model") then
            for _, p in ipairs(patterns) do
                if v.Name:lower():find(p:lower(), 1, true) then
                    table.insert(out, v); break
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

local function loop()
    currentStep = 1
    while running do
        task.wait(0.3)
        if not hrp or not hrp.Parent then return end
        local bot, bd = nearestBot()
        if bd and bd < CONF.BotRetreat then
            local away = hrp.Position + (hrp.Position - bot.HumanoidRootPart.Position).Unit * 50
            walker:WalkTo(away)
        else
            if currentStep > #CHAPTER.steps then currentStep = 1 end
            local step = CHAPTER.steps[currentStep]
            local found = findByName(step.n)
            if #found > 0 then
                for _, target in ipairs(found) do
                    local pos = target:IsA("BasePart") and target.Position or target:GetModelCFrame().Position
                    local ok = walker:WalkTo(pos)
                    if ok then interact(target) end
                end
                local still = findByName(step.n)
                if #still == 0 then currentStep = currentStep + 1 end
            else
                currentStep = currentStep + 1
            end
        end
    end
end

-- ============================================================
-- UI (same v5 animated panel — see previous message, copy here)
-- ============================================================
-- [paste the buildUI() from v5, unchanged]

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
    walker = PathWalker.new(char, { AgentRadius=2, AgentHeight=5, AgentCanJump=true,
        ReachRadius=3, FinalRadius=4, CheckInterval=0.1, JumpAssist=true, MaxRepaths=5 })
    neutraliseWatchdogs()
    if CONF.Godmode then bindGodmode() end
    hum.WalkSpeed = CONF.Speed
end)
