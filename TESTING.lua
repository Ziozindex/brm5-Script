-- DO NOT USE THIS IT WILL BAN YOU, JUST WAIT UNTIL I FIND A BYPASS IM ACTIVELY TRYING TO FIND A WAY TO FIND A BYPASS



-- =============================================
-- NPC HITBOX 
-- =============================================
-- Head expanded 
-- Massless = true, CanCollide = false, Transparency = 0.5

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

local TARGET_HEAD_SIZE   = Vector3.new(10, 10, 10)   -- Adjust size here
local HEAD_DROP_OFFSET   = -3.0                       -- How far down to drop the head (negative = lower). Try -2.5 to -4
local HEAD_TRANS         = 0.5                        -- Semi-visible
local activeNPCs         = {}                         -- For cleanup only
local isUnloaded         = false

local patchOptions = { recoil = true, firemodes = false }

-- ================== HELPER FUNCTIONS ==================
local function hasAIChild(model)
    for _, child in ipairs(model:GetChildren()) do
        if child.Name:sub(1, 3) == "AI_" then return true end
    end
    return false
end

-- ================== HEAD HITBOX FUNCTION (EXPAND + DROP) ==================
local function applyHeadHitbox(head)
    head.Size = TARGET_HEAD_SIZE
    head.Transparency = HEAD_TRANS
    head.CanCollide = false
    head.Massless = true
    head.Material = Enum.Material.ForceField

    -- Drop head down to overlap body
    local neck = head:FindFirstChild("Neck")
    if neck and neck:IsA("Motor6D") then
        neck.C1 = CFrame.new(0, HEAD_DROP_OFFSET, 0) * neck.C1.Rotation
    end
end

local function restoreHead(head, data)
    if head and data.originalHeadSize then
        head.Size = data.originalHeadSize
        head.Transparency = data.originalTrans
        head.CanCollide = data.originalCollide
        head.Massless = data.originalMassless
        head.Material = data.originalMaterial
    end

    local neck = head:FindFirstChild("Neck")
    if neck and data.originalC1 then
        neck.C1 = data.originalC1
    end
end

local function cleanupNPC(model)
    if not activeNPCs[model] then return end
    local data = activeNPCs[model]
   
    restoreHead(data.head, data)
   
    activeNPCs[model] = nil
end

-- ================== ADD NPC (FOR CLEANUP) ==================
local function addNPC(model)
    if activeNPCs[model] or model.Name ~= "Male" or not hasAIChild(model) then return end
   
    local head = model:FindFirstChild("Head")
    local humanoid = model:FindFirstChildOfClass("Humanoid")
   
    if not head or not humanoid then return end
   
    -- Save originals
    local originalHeadSize   = head.Size
    local originalTrans      = head.Transparency
    local originalCollide    = head.CanCollide
    local originalMassless   = head.Massless
    local originalMaterial   = head.Material
   
    local neck = head:FindFirstChild("Neck")
    local originalC1 = neck and neck.C1
   
    activeNPCs[model] = {
        head = head,
        humanoid = humanoid,
        originalHeadSize = originalHeadSize,
        originalTrans = originalTrans,
        originalCollide = originalCollide,
        originalMassless = originalMassless,
        originalMaterial = originalMaterial,
        originalC1 = originalC1
    }
   
    humanoid.Died:Connect(function()
        cleanupNPC(model)
    end)
end

-- ================== NO RECOIL PATCH ==================
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
print("Script Loaded")
patchWeapons(patchOptions)
print("✅ No Recoil: ENABLED")

for _, m in ipairs(Workspace:GetChildren()) do
    if m:IsA("Model") then
        task.spawn(addNPC, m)
    end
end
print("✅ NPC Detection: ENABLED")

Workspace.ChildAdded:Connect(function(m)
    if m:IsA("Model") and m.Name == "Male" then
        task.wait(0.1)
        addNPC(m)
    end
end)

-- ================== SIMPLE WHILE LOOP - HITBOX ==================
spawn(function()
    while not isUnloaded do
        for _, model in ipairs(Workspace:GetChildren()) do
            if model:IsA("Model") and model.Name == "Male" and hasAIChild(model) then
                local head = model:FindFirstChild("Head")
                if head then
                    applyHeadHitbox(head)
                end
            end
        end
        wait(1)
    end
end)

-- ================== UNLOAD ==================
function unloadScript()
    isUnloaded = true
   
    for model, data in pairs(activeNPCs) do
        cleanupNPC(model)
    end
   
    print("❌ Script unloaded")
end

print("✅ Ready!")
