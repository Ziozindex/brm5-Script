local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local TARGET_HITBOX_SIZE = Vector3.new(15, 15, 15)
local currentHitboxSize = 15 -- Default size

local activeNPCs = {}
local originalSizes = {}
local isUnloaded = false

local patchOptions = { recoil = true, firemodes = false }

-- Load Orion UI Library
local OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/jensonhirst/Orion/main/source"))()

-- Create the main window
local Window = OrionLib:MakeWindow({
    Name = "Hitbox + No Recoil",
    HidePremium = false,
    SaveConfig = true,
    ConfigFolder = "OrionConfig"
})

print("🎯 Initializing: Hitbox Expander + No Recoil")

-- Helper Functions
local function getRootPart(model)
    return model:FindFirstChild("Root") or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso")
end

local function hasAIChild(model)
    for _, c in ipairs(model:GetChildren()) do
        if type(c.Name) == "string" and c.Name:sub(1, 3) == "AI_" then return true end
    end
    return false
end

local function applySilentHitbox(model, root)
    if not root then return end
    
    if not originalSizes[model] then 
        originalSizes[model] = root.Size 
    end
    
    local newSize = Vector3.new(currentHitboxSize, currentHitboxSize, currentHitboxSize)
    root.Size = newSize
    root.Transparency = 1
    root.CanCollide = true
    
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") and part ~= root then
            part.Size = newSize
            part.CanCollide = true
        end
    end
end

local function restoreOriginalSize(model)
    local root = getRootPart(model)
    if root and originalSizes[model] then
        root.Size = originalSizes[model]
        root.Transparency = 1
        root.CanCollide = false
    end
    
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
    
    originalSizes[model] = nil
end

local function addNPC(model)
    if activeNPCs[model] or model.Name ~= "Male" or not hasAIChild(model) then return end
    local head = model:FindFirstChild("Head")
    local root = getRootPart(model)
    if not head or not root then return end
    activeNPCs[model] = { head = head, root = root }
    
    applySilentHitbox(model, root)
    
    print("✅ NPC Added - Hitbox Expanded")
end

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

-- Create COMBAT Tab
local CombatTab = Window:MakeTab({
    Name = "Combat",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

-- Hitbox Section
local HitboxSection = CombatTab:AddSection({
    Name = "Hitbox Settings"
})

HitboxSection:AddParagraph("Hitbox Expander","Automatically enlarges NPC hitboxes to make them easier to hit")

HitboxSection:AddToggle({
    Name = "Enable Hitbox Expander",
    Default = true,
    Callback = function(Value)
        if Value then
            print("✅ Hitbox Expander: ENABLED")
            for m, d in pairs(activeNPCs) do
                if d.root then
                    applySilentHitbox(m, d.root)
                end
            end
        else
            print("❌ Hitbox Expander: DISABLED")
            for m, _ in pairs(activeNPCs) do
                restoreOriginalSize(m)
            end
        end
    end
})

HitboxSection:AddSlider({
    Name = "Hitbox Size",
    Min = 1,
    Max = 50,
    Default = 15,
    Color = Color3.fromRGB(0, 255, 0),
    Increment = 1,
    ValueName = "Size",
    Callback = function(Value)
        currentHitboxSize = Value
        print("📏 Hitbox Size: " .. Value)
        -- Update all active NPCs with new size
        for m, d in pairs(activeNPCs) do
            if d.root then
                applySilentHitbox(m, d.root)
            end
        end
    end
})

-- Create WEAPONS Tab
local WeaponsTab = Window:MakeTab({
    Name = "Weapons",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

-- Recoil Section
local RecoilSection = WeaponsTab:AddSection({
    Name = "Weapon Modifications"
})

RecoilSection:AddParagraph("No Recoil","Removes all weapon recoil for perfect accuracy")

RecoilSection:AddToggle({
    Name = "Enable No Recoil",
    Default = true,
    Callback = function(Value)
        patchOptions.recoil = Value
        if Value then
            patchWeapons(patchOptions)
            print("✅ No Recoil: ENABLED")
        else
            print("❌ No Recoil: DISABLED")
        end
    end
})

-- Create MISC Tab
local MiscTab = Window:MakeTab({
    Name = "Misc",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

local MiscSection = MiscTab:AddSection({
    Name = "Script Controls"
})

MiscSection:AddButton({
    Name = "Unload Script",
    Callback = function()
        isUnloaded = true
        for m, _ in pairs(activeNPCs) do 
            restoreOriginalSize(m) 
        end
        activeNPCs = {}
        originalSizes = {}
        OrionLib:MakeNotification({
            Name = "Script Unloaded",
            Content = "Hitboxes restored to normal size",
            Image = "rbxassetid://4483345998",
            Time = 5
        })
        wait(1)
        OrionLib:Destroy()
    end
})

-- Initialization
patchWeapons(patchOptions)
print("✅ No Recoil: ENABLED")
print("✅ Hitbox Expander: ENABLED")

for _, m in ipairs(Workspace:GetChildren()) do
    if m:IsA("Model") and m.Name == "Male" then 
        if hasAIChild(m) then addNPC(m) end 
    end
end

Workspace.ChildAdded:Connect(function(m)
    if m:IsA("Model") and m.Name == "Male" then 
        task.delay(0.2, function() 
            if hasAIChild(m) then addNPC(m) end 
        end) 
    end
end)

-- Main Loop
RunService.RenderStepped:Connect(function()
    if isUnloaded then return end

    for m, d in pairs(activeNPCs) do
        if d.root then
            applySilentHitbox(m, d.root)
        end
    end
end)

OrionLib:Init()
