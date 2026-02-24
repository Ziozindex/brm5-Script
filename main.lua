-- =============================================
-- NPC ESP + HITBOX + NO RECOIL
-- =============================================

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local TARGET_HITBOX_SIZE = Vector3.new(15, 15, 15)   -- Change this number if you want smaller/bigger
local REAL_HEAD_HIDDEN   = "_Head"                   -- Real Head is renamed to this while bypass is active

local activeNPCs = {}      -- Tracks living NPCs
local trackedParts = {}    -- For ESP boxes
local isUnloaded = false

-- Colors for ESP
local visibleColor = Color3.fromRGB(0, 255, 0)    -- Green = visible
local hiddenColor  = Color3.fromRGB(255, 0, 0)    -- Red = behind wall

local patchOptions = { recoil = true, firemodes = false }

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
    if not part or part:FindFirstChild("Wall_Box") then return end
    local box = Instance.new("BoxHandleAdornment")
    box.Name = "Wall_Box"
    box.Size = part.Size + Vector3.new(0.1, 0.1, 0.1)
    box.Adornee = part
    box.AlwaysOnTop = true
    box.ZIndex = 10
    box.Color3 = visibleColor
    box.Transparency = 0.3
    box.Parent = part
    trackedParts[part] = true
end

local function destroyAllBoxes()
    for part in pairs(trackedParts) do
        if part and part:FindFirstChild("Wall_Box") then
            pcall(function() part.Wall_Box:Destroy() end)
        end
    end
    trackedParts = {}
end

-- ================== HITBOX FUNCTIONS (RENAME-SWAP BYPASS) ==================

-- How it works:
--   1. Rename the real Head to "_Head" so only ONE part named "Head" exists in the model.
--   2. Create a big invisible Part named "Head" welded to "_Head".
--   3. The game's raycast hits the big "Head" → hit.Name == "Head" → headshot damage registers.
--   4. On cleanup: destroy the fake "Head", rename "_Head" back to "Head".
--
-- Previous attempts that failed:
--   • Direct head.Size expansion           → instant ban (anti-cheat monitors native part sizes)
--   • Separate part named "SilentHitbox"   → no ban, but hits never registered (wrong name)
--   • Cloned head (two "Head" parts)       → confuses detection; shots hit the tiny original
--   • External Workspace part              → not inside the model; character lookup fails

local function applyBypassHitbox(model, realHead)
    -- Guard: already applied if the real head is already renamed
    if realHead.Name == REAL_HEAD_HIDDEN then return end

    -- Step 1: hide the real Head from name lookups
    realHead.Name = REAL_HEAD_HIDDEN

    -- Step 2: create ONE big part named "Head" so hit.Name == "Head" triggers headshot damage
    local fakeHead = Instance.new("Part")
    fakeHead.Name         = "Head"
    fakeHead.Size         = TARGET_HITBOX_SIZE
    fakeHead.CFrame       = realHead.CFrame
    fakeHead.Transparency = 1
    fakeHead.CanCollide   = false
    fakeHead.Massless     = true     -- prevents physics mass from being added to the NPC
    fakeHead.Anchored     = false
    fakeHead.Parent       = model   -- must be inside the model for damage character lookup

    local weld = Instance.new("WeldConstraint")
    weld.Part0  = realHead
    weld.Part1  = fakeHead
    weld.Parent = fakeHead
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
    
    -- Remove ESP box (head may still be named "_Head" at this point, that's fine)
    if data.head and data.head:FindFirstChild("Wall_Box") then
        pcall(function() data.head.Wall_Box:Destroy() end)
        trackedParts[data.head] = nil
    end
    
    activeNPCs[model] = nil
end

-- ================== ADD NPC (NOW SUPER CLEAN) ==================

local function addNPC(model)
    if activeNPCs[model] or model.Name ~= "Male" or not hasAIChild(model) then return end
    
    local realHead = model:FindFirstChild("Head")   -- grab ref before bypass renames it
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    
    if not realHead or not humanoid then return end
    
    -- Apply rename-swap bypass: renames real Head → "_Head", creates big "Head" weld
    applyBypassHitbox(model, realHead)
    
    -- Create ESP on the real (now "_Head") part — stays accurate to visual head position
    createBoxForPart(realHead)
    
    -- Store realHead reference (valid even after rename; Lua holds the Instance object)
    activeNPCs[model] = {
        head     = realHead,
        humanoid = humanoid,
    }
    
    -- Auto clean when NPC dies
    humanoid.Died:Connect(function()
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
                        local success, receiver = pcall(require, child)
                        if success and receiver and receiver.Config and receiver.Config.Tune then
                            local tune = receiver.Config.Tune
                            if options.recoil then
                                tune.Recoil_X = 0
                                tune.Recoil_Z = 0
                                tune.RecoilForce_Tap = 0
                                tune.RecoilForce_Impulse = 0
                                tune.Recoil_Range = Vector2.zero
                                tune.Recoil_Camera = 0
                                tune.RecoilAccelDamp_Crouch = Vector3.new(1, 1, 1)
                                tune.RecoilAccelDamp_Prone = Vector3.new(1, 1, 1)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ================== INITIALIZATION ==================

print("Script Loaded - ESP + Clean Hitbox + No Recoil")

patchWeapons(patchOptions)
print("✅ No Recoil: ENABLED")

-- Scan existing NPCs
for _, m in ipairs(Workspace:GetChildren()) do
    if m:IsA("Model") then
        task.spawn(addNPC, m)  -- faster and safer
    end
end

print("✅ NPC Detection + Hitbox: ENABLED ")
print("✅ NPC ESP: ENABLED")

-- New NPCs
Workspace.ChildAdded:Connect(function(m)
    if m:IsA("Model") and m.Name == "Male" then
        task.wait(0.1)  -- tiny delay, more reliable
        addNPC(m)
    end
end)

-- ================== MAIN LOOP (NOW MUCH LIGHTER) ==================

RunService.RenderStepped:Connect(function()
    if isUnloaded then return end
    
    for model, data in pairs(activeNPCs) do
        -- ESP color update (only thing that needs to run every frame)
        if data.head and data.head:FindFirstChild("Wall_Box") then
            local origin = camera.CFrame.Position
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Blacklist
            rp.FilterDescendantsInstances = {localPlayer.Character, model}
            
            local rayResult = Workspace:Raycast(origin, data.head.Position - origin, rp)
            
            data.head.Wall_Box.Color3 = (not rayResult or rayResult.Instance:IsDescendantOf(model)) 
                and visibleColor 
                or hiddenColor
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
    
    print("❌ Script unloaded - Everything cleaned up")
end

print("✅ Script ready!")
