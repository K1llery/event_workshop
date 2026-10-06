return function(C, S)
    local A = { items = {}, snapshots = {}, maxItemId = 0 }
    function A.log(message)
        Isaac.DebugString("[EventWorkshop] " .. tostring(message))
    end
    function A.isSinglePlayer()
        -- 雅各与以扫、遗骸等可以有多个实体，以控制器区分本地合作。
        local controller
        for i = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if controller == nil then controller = player.ControllerIndex end
            if player.ControllerIndex ~= controller then return false end
        end
        return controller ~= nil
    end
    function A.context(player)
        if not player then
            if Game():GetNumPlayers() == 0 then return nil end
            player = Isaac.GetPlayer(0)
        end
        local level = Game():GetLevel()
        local room = Game():GetRoom()
        local desc = level:GetCurrentRoomDesc()
        local floor = tostring(level:GetStage()) .. ":" .. tostring(level:GetStageType())
            .. ":" .. tostring(level:GetDungeonPlacementSeed())
        -- 描述符的种子与索引可区分镜面及红房间，无需忏悔龙维度接口。
        return {
            player = player, roomType = room:GetType(), floorKey = floor,
            roomKey = floor .. ":" .. tostring(desc.ListIndex) .. ":" .. tostring(desc.SpawnSeed),
            position = room:GetCenterPos(),
        }
    end
    function A.character(ctx) return ctx.player:GetPlayerType() end
    function A.hasCollectible(ctx, id) return ctx.player:HasCollectible(id) end
    function A.refreshItems()
        A.items = {}
        local config = Isaac.GetItemConfig()
        A.maxItemId = math.max(0, config:GetCollectibles().Size - 1)
        for id = 1, A.maxItemId do
            local item = config:GetCollectible(id)
            if item and not item.Hidden then
                A.items[#A.items + 1] = { id = id, name = item.Name or tostring(id), quality = item.Quality or 0 }
            end
        end
    end
    function A.itemName(id)
        if id == 0 then return "随机 / 不限" end
        local item = Isaac.GetItemConfig():GetCollectible(id)
        if not item then return "不存在的道具 #" .. id end
        -- EID 仅用于可选名称翻译；模组运行不依赖 EID。
        if EID and type(EID.getObjectName) == "function" then
            local ok, name = pcall(EID.getObjectName, EID, 5, 100, id)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        return item.Name or tostring(id)
    end
    function A.searchItems(query)
        query = tostring(query or ""):lower()
        local found = {}
        for _, item in ipairs(A.items) do
            if query == "" or tostring(item.id) == query or item.name:lower():find(query, 1, true)
                or A.itemName(item.id):lower():find(query, 1, true) then
                found[#found + 1] = item.id
            end
        end
        return found
    end
    local function snapshot(player)
        local slots = {}
        for slot = 0, 3 do
            slots[tostring(slot)] = {
                item = player:GetActiveItem(slot),
                total = player:GetActiveCharge(slot) + player:GetBatteryCharge(slot),
            }
        end
        return slots
    end
    function A.capture(player)
        A.snapshots[player.InitSeed] = snapshot(player)
    end
    function A.clearContext()
        local ctx = A.context()
        if not ctx then return nil end
        ctx.beforeCharge = S.copy(A.snapshots[ctx.player.InitSeed] or snapshot(ctx.player))
        ctx.chargeUndone = false
        return ctx
    end
    function A.prepare(ctx)
        if not ctx.beforeCharge then return end
        ctx.clearChargeGain = {}
        for slot = 0, 3 do
            local before = ctx.beforeCharge[tostring(slot)]
            local id = ctx.player:GetActiveItem(slot)
            if before and before.item == id then
                local total = ctx.player:GetActiveCharge(slot) + ctx.player:GetBatteryCharge(slot)
                ctx.clearChargeGain[tostring(slot)] = math.max(0, total - before.total)
            end
        end
    end
    local function validItem(id)
        local item = Isaac.GetItemConfig():GetCollectible(id)
        if not item or item.Hidden then error("道具 ID 无效或为隐藏道具：" .. id) end
        return item
    end
    local function selectItem(action, engine)
        if action.itemId > 0 then validItem(action.itemId); return action.itemId end
        local minQuality, maxQuality = math.min(action.qualityMin, action.qualityMax),
            math.max(action.qualityMin, action.qualityMax)
        for _ = 1, 64 do
            local id = Game():GetItemPool():GetCollectible(action.pool, false, engine:nextSeed())
            local item = Isaac.GetItemConfig():GetCollectible(id)
            if item and not item.Hidden and item.Quality >= minQuality and item.Quality <= maxQuality then
                return id
            end
        end
        error("在 64 次抽取内未找到满足品质的道具，跳过此次生成")
    end
    local function position(ctx, enemy)
        local room = Game():GetRoom()
        if enemy then return room:FindFreeTilePosition(ctx.position, 40) end
        return room:FindFreePickupSpawnPosition(ctx.position, 40, true)
    end
    function A.execute(action, ctx, engine)
        local player = ctx.player
        if not player or not player:Exists() then return end
        local kind = action.kind
        if kind == "spawn_collectible" or kind == "give_collectible" then
            for _ = 1, math.max(1, math.min(32, action.amount)) do
                local id = selectItem(action, engine)
                if kind == "spawn_collectible" then
                    Isaac.Spawn(5, 100, id, position(ctx), Vector.Zero, player)
                else
                    player:AddCollectible(id, 0, true)
                end
            end
        elseif kind == "spawn_pickup" then
            local config = Isaac.GetItemConfig()
            local maxSubtypes = { [10] = 12, [20] = 7, [30] = 4, [40] = 7, [90] = 4 }
            if maxSubtypes[action.pickupVariant] and action.subtype > maxSubtypes[action.pickupVariant] then
                error("掉落物子类型超出原版范围")
            end
            if action.pickupVariant == 70 then
                local color = action.subtype & ~PillColor.PILL_GIANT_FLAG
                if color < 0 or color > 14 then error("药丸颜色 ID 无效") end
            end
            if action.pickupVariant == 300 and action.subtype > 0 and not config:GetCard(action.subtype) then
                error("卡牌 ID 无效")
            end
            if action.pickupVariant == 350 and action.subtype > 0 and not config:GetTrinket(action.subtype) then
                error("饰品 ID 无效")
            end
            for _ = 1, math.max(1, math.min(32, action.amount)) do
                Isaac.Spawn(5, action.pickupVariant, action.subtype, position(ctx), Vector.Zero, player)
            end
        elseif kind == "coins" then
            player:AddCoins(math.max(-player:GetNumCoins(), action.amount))
        elseif kind == "keys" then
            player:AddKeys(math.max(-player:GetNumKeys(), action.amount))
        elseif kind == "bombs" then
            player:AddBombs(math.max(-player:GetNumBombs(), action.amount))
        elseif kind == "hearts" then
            local funcs = { red = "AddHearts", soul = "AddSoulHearts", black = "AddBlackHearts",
                max = "AddMaxHearts", bone = "AddBoneHearts", rotten = "AddRottenHearts" }
            local amount = math.max(-48, math.min(48, action.amount))
            if action.heartType == "max" then player:AddMaxHearts(amount, true)
            else player[funcs[action.heartType]](player, amount) end
        elseif kind == "charge" then
            local item = Isaac.GetItemConfig():GetCollectible(player:GetActiveItem(action.slot))
            if item and item.MaxCharges > 0 then
                local total = player:GetActiveCharge(action.slot) + player:GetBatteryCharge(action.slot)
                local cap = item.MaxCharges * (player:HasCollectible(CollectibleType.COLLECTIBLE_BATTERY) and 2 or 1)
                player:SetActiveCharge(math.max(0, math.min(cap, total + action.amount)), action.slot)
            end
        elseif kind == "undo_clear_charge" then
            if not ctx.beforeCharge or not ctx.clearChargeGain or ctx.chargeUndone then return end
            ctx.chargeUndone = true
            for slot = 0, 3 do
                local before = ctx.beforeCharge[tostring(slot)]
                local id = player:GetActiveItem(slot)
                local item = Isaac.GetItemConfig():GetCollectible(id)
                if before and before.item == id and item and item.ChargeType == ItemConfig.CHARGE_NORMAL then
                    local gain = ctx.clearChargeGain[tostring(slot)] or 0
                    local total = player:GetActiveCharge(slot) + player:GetBatteryCharge(slot)
                    if gain > 0 then player:SetActiveCharge(math.max(0, total - gain), slot) end
                end
            end
        elseif kind == "spawn_enemy" then
            for _ = 1, math.max(1, math.min(32, action.amount)) do
                Isaac.Spawn(action.enemyType, 0, 0, position(ctx, true), Vector.Zero, nil)
            end
        end
    end
    return A
end
