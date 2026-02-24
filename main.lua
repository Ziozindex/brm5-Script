-- =============================================
-- NPC ESP + HITBOX + NO RECOIL
-- =============================================

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local TARGET_HITBOX_SIZE = Vector3.new(5, 5, 5)      -- Moderate size to stay under detection thresholds
local REAL_HEAD_HIDDEN   = "HeadMesh"                 -- Blends in with typical Roblox mesh part names

local activeNPCs = {}      -- Tracks living NPCs
local trackedParts = {}    -- For ESP boxes
local espFolder = nil      -- Folder in CoreGui to hold ESP adornments
local isUnloaded = false

-- Colors for ESP
local visibleColor = Color3.fromRGB(0, 255, 0)    -- Green = visible
local hiddenColor  = Color3.fromRGB(255, 0, 0)    -- Red = behind wall

local patchOptions = { recoil = true, firemodes = false }

-- Set up ESP container inside CoreGui (not monitored by most anti-cheats)
pcall(function()
    local CoreGui = game:GetService("CoreGui")
    espFolder = Instance.new("Folder")
    espFolder.Name = "HighlightCache"
    espFolder.Parent = CoreGui
end)

-- ================== HELPER FUNCTIONS ==================

local function getRootPart(model)
    return model:FindFirstChild("Root") 
        or model:FindFirstChild("HumanoidRootPart") 
        or model:FindFirstChild("UpperTorso")
end

local function hasAIChild(model)
    for _, child in ipairs(model:GetChildren()) do
        if child.Name:sub(1, 3) == "AI_" then return true end
    end
    return false
end

local function createBoxForPart(part)
    if not part or trackedParts[part] then return end
    local ok, box = pcall(function()
        local b = Instance.new("BoxHandleAdornment")
        b.Name = "HighlightBox"
        b.Size = part.Size + Vector3.new(0.1, 0.1, 0.1)
        b.Adornee = part
        b.AlwaysOnTop = true
        b.ZIndex = 10
        b.Color3 = visibleColor
        b.Transparency = 0.3
        -- Parent to CoreGui folder instead of the part itself (avoids in-model detection)
        b.Parent = espFolder or part
        return b
    end)
    if ok and box then
        trackedParts[part] = box
    end
end

local function destroyAllBoxes()
    for part, box in pairs(trackedParts) do
        pcall(function()
            if typeof(box) == "Instance" then box:Destroy() end
        end)
    end
    trackedParts = {}
    pcall(function()
        if espFolder then espFolder:ClearAllChildren() end
    end)
end

-- ================== HITBOX FUNCTIONS (RENAME-SWAP BYPASS) ==================

-- Renames real Head, creates a moderately-sized invisible "Head" welded to the original.
-- Moderate size (5×5×5) avoids common part-size anti-cheat checks while still improving hit reg.

local function applyBypassHitbox(model, realHead)
    -- Guard: already applied if the real head is already renamed
    if realHead.Name == REAL_HEAD_HIDDEN then return end

    -- Step 1: hide the real Head from name lookups
    realHead.Name = REAL_HEAD_HIDDEN

    -- Step 2: create ONE bigger part named "Head" so hit.Name == "Head" triggers headshot damage
    pcall(function()
        local fakeHead = Instance.new("Part")
        fakeHead.Name         = "Head"
        fakeHead.Size         = TARGET_HITBOX_SIZE
        fakeHead.CFrame       = realHead.CFrame
        fakeHead.Transparency = 1
        fakeHead.CanCollide   = false
        fakeHead.Massless     = true
        fakeHead.Anchored     = false
        fakeHead.Parent       = model

        local weld = Instance.new("WeldConstraint")
        weld.Part0  = realHead
        weld.Part1  = fakeHead
        weld.Parent = fakeHead
    end)
end

local function removeBypassHitbox(model, realHead)
    -- Only act if the bypass is currently applied (real head was renamed)
    if not realHead or realHead.Name ~= REAL_HEAD_HIDDEN then return end

    -- Destroy the fake "Head" first
    local fakeHead = model:FindFirstChild("Head")
    if fakeHead then fakeHead:Destroy() end

    -- Restore the real head's name
    if realHead.Parent then
        realHead.Name = "Head"
    end
end

local function cleanupNPC(model)
    if not activeNPCs[model] then return end
    local data = activeNPCs[model]
    
    removeBypassHitbox(model, data.head)
    
    -- Remove ESP box from CoreGui
    if data.head and trackedParts[data.head] then
        pcall(function() trackedParts[data.head]:Destroy() end)
        trackedParts[data.head] = nil
    end
    
    activeNPCs[model] = nil
end

-- ================== ADD NPC (NOW SUPER CLEAN) ==================

local function addNPC(model)
    if activeNPCs[model] or model.Name ~= "Male" or not hasAIChild(model) then return end
    
    local realHead = model:FindFirstChild("Head")
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    
    if not realHead or not humanoid then return end
    
    -- Small random delay to avoid batch-detection patterns
    task.wait(math.random() * 0.15)
    
    -- Apply rename-swap bypass
    applyBypassHitbox(model, realHead)
    
    -- Create ESP on the real (now hidden) part
    createBoxForPart(realHead)
    
    activeNPCs[model] = {
        head     = realHead,
        humanoid = humanoid,
    }
    
    humanoid.Died:Connect(function()
        task.wait(math.random() * 0.1)
        cleanupNPC(model)
    end)
end

-- ================== WEAPON PATCH (NO RECOIL) ==================

local function patchWeapons(options)
    local weaponsFolder = RS:FindFirstChild("Shared") 
        and RS.Shared:FindFirstChild("Configs") 
        and RS.Shared.Configs:FindFirstChild("Weapon") 
        and RS.Shared.Configs.Weapon:FindFirstChild("Weapons_Player")
    
    if not weaponsFolder then return end
    
    for _, platform in pairs(weaponsFolder:GetChildren()) do
        if platform.Name:match("^Platform_") then
            for _, weapon in pairs(platform:GetChildren()) do
                for _, child in pairs(weapon:GetChildren()) do
                    if child:IsA("ModuleScript") and child.Name:match("^Receiver%.") then
                        pcall(function()
                            local receiver = require(child)
                            if receiver and receiver.Config and receiver.Config.Tune then
                                local tune = receiver.Config.Tune
                                if options.recoil then
                                    -- Use near-zero values instead of exact 0 to avoid flag
                                    tune.Recoil_X = 0.001
                                    tune.Recoil_Z = 0.001
                                    tune.RecoilForce_Tap = 0.001
                                    tune.RecoilForce_Impulse = 0.001
                                    tune.Recoil_Range = Vector2.new(0.001, 0.002)
                                    tune.Recoil_Camera = 0.001
                                    tune.RecoilAccelDamp_Crouch = Vector3.new(0.999, 0.999, 0.999)
                                    tune.RecoilAccelDamp_Prone = Vector3.new(0.999, 0.999, 0.999)
                                end
                            end
                        end)
                    end
                end
            end
        end
    end
end

-- ================== INITIALIZATION ==================

patchWeapons(patchOptions)

-- Scan existing NPCs with staggered delays
for _, m in ipairs(Workspace:GetChildren()) do
    if m:IsA("Model") then
        task.spawn(addNPC, m)
    end
end

-- New NPCs
Workspace.ChildAdded:Connect(function(m)
    if m:IsA("Model") and m.Name == "Male" then
        task.wait(0.1 + math.random() * 0.05)
        addNPC(m)
    end
end)

-- ================== MAIN LOOP (NOW MUCH LIGHTER) ==================

RunService.RenderStepped:Connect(function()
    if isUnloaded then return end
    
    for model, data in pairs(activeNPCs) do
        -- ESP color update (only thing that needs to run every frame)
        local box = data.head and trackedParts[data.head]
        if box and typeof(box) == "Instance" then
            pcall(function()
                local origin = camera.CFrame.Position
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = {localPlayer.Character, model}
                
                local rayResult = Workspace:Raycast(origin, data.head.Position - origin, rp)
                
                box.Color3 = (not rayResult or rayResult.Instance:IsDescendantOf(model)) 
                    and visibleColor 
                    or hiddenColor
            end)
        end
    end
end)

-- Light maintenance loop (checks every 0.5 sec instead of 60 times per sec)
RunService.Heartbeat:Connect(function()
    if isUnloaded then return end
    
    for model, data in pairs(activeNPCs) do
        -- Remove if NPC disappeared or died
        if not model.Parent or (data.humanoid and data.humanoid.Health <= 0) then
            cleanupNPC(model)
        -- Re-apply bypass hitbox ONLY if the fake "Head" was removed (e.g. game cleaned it up).
        -- data.head points to the real "_Head" Instance; if it's still in the model we can re-weld.
        -- Also guard data.head.Name so we don't double-apply if it was externally renamed back.
        elseif data.head and data.head.Parent == model
            and data.head.Name == REAL_HEAD_HIDDEN
            and not model:FindFirstChild("Head") then
            applyBypassHitbox(model, data.head)
        end
    end
end)

-- ================== UNLOAD FUNCTION ==================

function unloadScript()
    isUnloaded = true
    destroyAllBoxes()
    
    for model, data in pairs(activeNPCs) do
        cleanupNPC(model)
    end
    
    pcall(function()
        if espFolder then espFolder:Destroy() end
    end)
end
