return function(C, S, A, I)
    local function call(object, method, ...)
        if not object or type(object[method]) ~= "function" then error("原版接口不可用: " .. method) end
        return object[method](object, ...)
    end
    A.call = call
    function A.consumeOperation() I.operation(false) end
    function A.frame() return Game():GetFrameCount() end
    function A.position(action, ctx, enemy)
        local room, pos = Game():GetRoom(), ctx.position
        if action.position == 0 then pos = room:GetCenterPos()
        elseif action.position == 1 then pos = ctx.player.Position
        elseif action.position == 3 then
            pos = room:GetGridPosition(I.engine:nextSeed() % room:GetGridSize())
            pos = room:FindFreeTilePosition(pos, 40)
        end
        if enemy then return room:FindFreeTilePosition(pos, 40) end
        return room:FindFreePickupSpawnPosition(pos, 40, true)
    end
    function A.spawn(t, v, s, pos, velocity, spawner)
        if t == 1 then error("生成实体不支持直接创建玩家") end
        I.operation(true)
        if t >= 10 and t < 1000 and s > 255 then error("敌人子类型超出原版定义范围") end
        local engine = I.engine
        local entity = Game().Spawn and Game():Spawn(t, v, pos, velocity, spawner, s, engine:nextSeed())
            or Isaac.Spawn(t, v, s, pos, velocity, spawner)
        I.mark(entity)
        return entity
    end
    local function direction(angle, speed)
        local radians = angle * math.pi / 180
        return Vector(math.cos(radians) * (speed or 1), math.sin(radians) * (speed or 1))
    end
    local function color(action) return Color(action.red, action.green, action.blue, 1, 0, 0, 0) end
    function A.targets(action, ctx)
        if action.target == 0 then
            if not ctx.entity or not ctx.entity:Exists() then error("事件对象已不存在或此事件没有实体对象") end
            return { ctx.entity }
        elseif action.target == 1 then return { ctx.player }
        elseif action.target == 6 then
            if not ctx.collider or not ctx.collider:Exists() then error("碰撞对象已不存在") end
            return { ctx.collider }
        end
        local found, nearest, distance = {}, nil, math.huge
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local valid = ((action.target == 2 or action.target == 3) and entity:IsActiveEnemy(false)
                and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY))
                or (action.target == 4 and entity.Type == 5) or (action.target == 5 and entity.Type == 3)
            local d = entity.Position:Distance(ctx.player.Position)
            if valid and (action.radius == 0 or d <= action.radius) then
                if action.target == 2 then if d < distance then nearest, distance = entity, d end
                else found[#found + 1] = entity end
            end
        end
        if nearest then found[1] = nearest end
        return found
    end
    local resources = {
        coins = { "GetNumCoins", "AddCoins" }, keys = { "GetNumKeys", "AddKeys" }, bombs = { "GetNumBombs", "AddBombs" },
        soulCharge = { "GetSoulCharge", "AddSoulCharge" }, bloodCharge = { "GetBloodCharge", "AddBloodCharge" },
        poopMana = { "GetPoopMana", "AddPoopMana" }, jarHearts = { "GetJarHearts", "AddJarHearts" },
        jarFlies = { "GetJarFlies", "AddJarFlies" }, gigaBombs = { "GetNumGigaBombs", "AddGigaBombs" },
    }
    A.resourceMethods = resources
    function A.resource(player, name)
        local pair = resources[name]; return pair and call(player, pair[1]) or 0
    end
    local function item(action, method)
        local id = action.itemId
        if id <= 0 then error("此动作需要指定非零物品 ID") end
        if method and not Isaac.GetItemConfig()[method](Isaac.GetItemConfig(), id) then error("物品 ID 无效: " .. id) end
        return id
    end
    local function frames(seconds) return math.max(1, math.floor(seconds * 30)) end
    local function pillColor(id)
        local value = id & ~PillColor.PILL_GIANT_FLAG
        if value < 0 or value > 14 then error("药丸颜色 ID 无效") end
        return id
    end
    local base = { spawn_collectible = true, give_collectible = true, spawn_pickup = true, coins = true,
        keys = true, bombs = true, hearts = true, charge = true, undo_clear_charge = true, spawn_enemy = true }
    local perEntity = {
        entity_heal = function(e, a) e.HitPoints = math.min(e.MaxHitPoints, e.HitPoints + a.value) end,
        entity_kill_action = function(e) e:Kill() end,
        entity_remove_action = function(e) e:Remove() end,
        entity_move = function(e, a, ctx) e.Position = A.position(a, ctx, true) end,
        entity_velocity = function(e, a) e.Velocity = direction(a.angle, a.value) end,
        entity_size = function(e, a) if a.value <= 0 then error("实体大小必须大于 0") end; e.SpriteScale = Vector(a.value, a.value) end,
        entity_color = function(e, a) e:SetColor(color(a), frames(a.duration), 100, false, false) end,
        entity_damage_action = function(e, a, ctx) e:TakeDamage(math.max(0, a.value), a.flags, EntityRef(ctx.player), 0) end,
        clear_status = function(e) e:RemoveStatusEffects() end,
        entity_flags = function(e, a)
            local flag = EntityFlag[a.flag]; if not flag then error("请选择 FLAG_ 开头的实体标记") end
            call(e, a.mode == 0 and "AddEntityFlags" or "ClearEntityFlags", flag)
        end,
        entity_morph = function(e, a)
            local npc = e:ToNPC(); if not npc then error("实体转换需要敌人对象") end
            npc:Morph(a.entityType, a.variant, a.subtype, -1)
        end,
        pickup_morph = function(e, a)
            local pickup = e:ToPickup(); if not pickup then error("需要拾取物对象") end
            pickup:Morph(5, a.pickupVariant, a.subtype, true, true, false)
        end,
        pickup_price = function(e, a)
            local pickup = e:ToPickup(); if not pickup then error("需要拾取物对象") end
            pickup.AutoUpdatePrice, pickup.Price = false, a.amount
        end,
        pickup_options = function(e, a)
            local pickup = e:ToPickup(); if not pickup then error("需要拾取物对象") end
            pickup.OptionsPickupIndex = math.max(0, a.amount)
        end,
        open_chest = function(e) local pickup = e:ToPickup(); if pickup then pickup:TryOpenChest() end end,
        reroll_collectible = function(e, a, _, engine)
            local pickup = e:ToPickup()
            if pickup and pickup.Variant == 100 then pickup:Morph(5, 100, A.selectItem(a, engine), true, true, false) end
        end,
        reroll_enemy = function(e) if e:ToNPC() then Game():RerollEnemy(e) end end,
        entity_status = function(e, a, ctx)
            local source, duration = EntityRef(ctx.player), frames(a.duration)
            if a.status == "poison" then e:AddPoison(source, duration, math.max(0, a.value))
            elseif a.status == "burn" then e:AddBurn(source, duration, math.max(0, a.value))
            elseif a.status == "slow" then e:AddSlowing(source, duration, math.max(0, math.min(1, a.value)), color(a))
            elseif a.status == "confusion" then e:AddConfusion(source, duration, false)
            else
                local names = { freeze = "AddFreeze", midas = "AddMidasFreeze", fear = "AddFear",
                    charm = "AddCharmed", shrink = "AddShrink" }
                call(e, names[a.status], source, duration)
            end
        end,
    }
    local function perform(a, ctx, engine)
        local p, room, level, kind = ctx.player, Game():GetRoom(), Game():GetLevel(), a.kind
        if ctx.terminal and kind ~= "message" and kind ~= "counter" and kind ~= "rule_switch" then
            error("游戏结束 / 退出事件仅支持提示、计数器和规则启停")
        end
        if base[kind] then return A.executeBase(a, ctx, engine) end
        if perEntity[kind] then
            for _, entity in ipairs(A.targets(a, ctx)) do
                I.operation(false)
                I.mark(entity)
                perEntity[kind](entity, a, ctx, engine)
            end
            return
        end
        local n, pos = math.max(1, math.min(32, a.amount)), A.position(a, ctx)
        if kind == "spawn_entity" or kind == "spawn_effect" or kind == "spawn_familiar" or kind == "spawn_machine" then
            local t = ({ spawn_effect = 1000, spawn_familiar = 3, spawn_machine = 6 })[kind] or a.entityType
            for _ = 1, n do A.spawn(t, a.variant, a.subtype, pos, Vector.Zero, p) end
        elseif kind == "remove_collectible" then
            local id = item(a, "GetCollectible")
            for _ = 1, n do I.operation(false); if p:HasCollectible(id) then p:RemoveCollectible(id) end end
        elseif kind == "give_trinket" then
            local id = item(a, "GetTrinket"); for _ = 1, n do I.operation(false); p:AddTrinket(id, false) end
        elseif kind == "remove_trinket" then p:TryRemoveTrinket(item(a, "GetTrinket"))
        elseif kind == "smelt_trinket" then
            local id = item(a, "GetTrinket")
            p:AddTrinket(id, false); p:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM, -1)
        elseif kind == "give_card" then p:AddCard(item(a, "GetCard"))
        elseif kind == "give_pill" then p:AddPill(pillColor(a.itemId))
        elseif kind == "set_card" then p:SetCard(a.slot, a.itemId == 0 and 0 or item(a, "GetCard"))
        elseif kind == "set_pill" then p:SetPill(a.slot, pillColor(a.itemId))
        elseif kind == "drop_pocket" then call(p, "DropPocketItem", a.slot, pos)
        elseif kind == "drop_trinket" then p:DropTrinket(pos, true)
        elseif kind == "swap_active" then p:SwapActiveItems()
        elseif kind == "set_resource" or kind == "special_resource" then
            local pair = resources[a.resource]
            local current = call(p, pair[1])
            local delta = kind == "set_resource" and (math.max(0, a.amount) - current) or math.max(-current, a.amount)
            call(p, pair[2], delta)
        elseif kind == "heal" then p:SetFullHearts()
        elseif kind == "golden_key" then call(p, a.mode == 0 and "AddGoldenKey" or "RemoveGoldenKey")
        elseif kind == "golden_bomb" then call(p, a.mode == 0 and "AddGoldenBomb" or "RemoveGoldenBomb")
        elseif kind == "set_charge" or kind == "empty_charge" or kind == "full_charge" then
            local config = Isaac.GetItemConfig():GetCollectible(p:GetActiveItem(a.slot))
            if not config or config.MaxCharges <= 0 then error("此槽位没有可调整充能的主动道具") end
            local cap = config.MaxCharges * (p:HasCollectible(CollectibleType.COLLECTIBLE_BATTERY) and 2 or 1)
            p:SetActiveCharge(kind == "full_charge" and cap or kind == "empty_charge" and 0 or math.max(0, math.min(cap, a.amount)), a.slot)
        elseif kind == "player_damage_action" then p:TakeDamage(math.max(0, a.value), a.flags, EntityRef(p), 0)
        elseif kind == "invulnerability" then p:SetMinDamageCooldown(frames(a.duration))
        elseif kind == "revive" then if p:IsDead() then p:Revive() end
        elseif kind == "use_item" then
            p:UseActiveItem(item(a, "GetCollectible"), UseFlag.USE_NOANIM, a.slot)
            if a.consume == 1 then p:SetActiveCharge(0, a.slot) end
        elseif kind == "use_card_action" then
            p:UseCard(item(a, "GetCard"), UseFlag.USE_NOANIM)
            if a.consume == 1 then p:SetCard(a.slot, 0) end
        elseif kind == "use_pill_action" then
            if not C.contains(C.content.pills, a.itemId) then error("药丸效果 ID 无效") end
            p:UsePill(a.itemId, pillColor(a.subtype), UseFlag.USE_NOANIM)
            if a.consume == 1 then p:SetPill(a.slot, 0) end
        elseif kind:find("^temporary_") then
            local names = { temporary_collectible = "Collectible", temporary_trinket = "Trinket", temporary_null = "Null" }
            local suffix = names[kind]
            if a.amount >= 0 then call(p:GetEffects(), "Add" .. suffix .. "Effect", a.itemId, false, math.abs(a.amount))
            else call(p:GetEffects(), "Remove" .. suffix .. "Effect", a.itemId, math.abs(a.amount)) end
        elseif kind == "stat" or kind == "tear_flag" then
            engine.run.modifiers[#engine.run.modifiers + 1] = { player = p.InitSeed, kind = kind,
                stat = a.stat, flag = a.flag, value = a.value, scope = a.scope, roomKey = ctx.roomKey,
                floorKey = ctx.floorKey, expires = A.frame() + frames(a.duration) }
            p:AddCacheFlags(CacheFlag.CACHE_ALL); p:EvaluateItems()
        elseif kind == "fire_tear_action" or kind == "fire_bomb" then
            for _ = 1, n do I.operation(true); I.mark(call(p, kind == "fire_bomb" and "FireBomb" or "FireTear", pos, direction(a.angle, a.value))) end
        elseif kind == "fire_brimstone" then I.mark(p:FireBrimstone(direction(a.angle)))
        elseif kind == "fire_tech" then I.mark(p:FireTechLaser(pos, LaserOffset.LASER_TECH1_OFFSET, direction(a.angle), false, true))
        elseif kind == "fire_tech_x" then I.mark(p:FireTechXLaser(pos, direction(a.angle, a.value), math.max(1, a.radius)))
        elseif kind == "fire_knife" then I.mark(p:FireKnife(p, a.angle, false, a.subtype))
        elseif kind == "blue_flies" then I.mark(p:AddBlueFlies(n, pos, nil))
        elseif kind == "blue_spiders" then for _ = 1, n do I.operation(true); I.mark(p:AddBlueSpider(pos)) end
        elseif kind == "wisp" or kind == "item_wisp" then
            for _ = 1, n do I.operation(true); I.mark(call(p, kind == "wisp" and "AddWisp" or "AddItemWisp", item(a, "GetCollectible"), pos, true)) end
        elseif kind == "minisaac" then for _ = 1, n do I.operation(true); I.mark(p:AddMinisaac(pos)) end
        elseif kind == "explosion" then Game():BombExplosionEffects(pos, math.max(0, a.value), 0, color(a), p, math.max(0.1, a.radius / 100), true, false)
        elseif kind == "fart" then
            if a.effectKind == 1 then Game():ButterBeanFart(pos, a.radius, p, true)
            elseif a.effectKind == 2 then Game():CharmFart(pos, a.radius, p)
            else Game():Fart(pos, a.radius, p) end
        elseif kind == "restock_shop" then call(room, a.mode == 0 and "ShopRestockFull" or "ShopRestockPartial")
        elseif kind == "respawn_enemies" then room:RespawnEnemies()
        elseif kind == "clear_award" then room:SpawnClearAward()
        elseif kind:find("^grid_") or kind == "bridge" then
            local index = a.gridIndex >= 0 and a.gridIndex or ctx.gridIndex or room:GetGridIndex(pos)
            if index >= room:GetGridSize() then error("障碍索引超出当前房间") end
            if kind == "grid_spawn" then
                if a.gridType == 16 or a.gridType == 15 then error("墙和房门请使用现有门操作，不能安全生成") end
                if not room:SpawnGridEntity(index, a.gridType, a.variant, engine:nextSeed(), a.subtype) then error("障碍生成失败") end
            elseif kind == "grid_destroy" then room:DestroyGrid(index, true)
            elseif kind == "grid_remove" then room:RemoveGridEntity(index, 0, false)
            elseif kind == "grid_damage" then room:DamageGrid(index, math.max(0, a.amount))
            else
                local grid = room:GetGridEntity(index)
                local pit = grid and grid:ToPit()
                if not pit then error("此处没有可填的坑") end
                pit:MakeBridge(nil); pit:UpdateCollision()
            end
        elseif kind == "door" then
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and (a.doorSlot == -1 or a.doorSlot == slot) then
                    if a.mode == 0 then door:Open() elseif a.mode == 1 then door:Close(true)
                    elseif a.mode == 2 then door:TryUnlock(p, true) elseif a.mode == 3 then door:SetLocked(true)
                    else room:RemoveDoor(slot) end
                end
            end
        elseif kind == "special_door" then
            local method = ({ "TrySpawnDevilRoomDoor", "TrySpawnBossRushDoor", "TrySpawnBlueWombDoor",
                "TrySpawnMegaSatanRoomDoor", "TrySpawnSecretExit", "TrySpawnTheVoidDoor" })[a.doorKind + 1]
            if not call(room, method) then error("当前房间不满足该入口的生成条件") end
        elseif kind == "red_room" then
            if a.doorSlot < 0 then error("红房门必须指定门槽位") end
            if not level:MakeRedRoomDoor(level:GetCurrentRoomIndex(), a.doorSlot) then error("此处无法生成红房门") end
        elseif kind == "map" then
            call(level, ({ "ShowMap", "ApplyMapEffect", "ApplyCompassEffect", "ApplyBlueMapEffect", "SetCanSeeEverything" })[a.mode + 1], true)
            level:UpdateVisibility()
        elseif kind == "curse" then
            if a.mode == 0 then level:AddCurse(a.flags, false) else level:RemoveCurses(a.flags) end
        elseif kind == "angel_chance" then level:AddAngelRoomChance(a.value)
        elseif kind == "room_color" then call(room, a.mode == 0 and "SetFloorColor" or "SetWallColor", color(a))
        elseif kind == "room_slow" then
            local previous = engine.run.roomWatch and engine.run.roomWatch.previous or room:GetBrokenWatchState()
            room:SetBrokenWatchState(a.mode == 0 and 1 or 2)
            engine.run.roomWatch = { roomKey = ctx.roomKey, expires = A.frame() + frames(a.duration),
                previous = previous }
        elseif kind == "sound" then SFXManager():Play(a.itemId, math.max(0, math.min(1, a.value)), 0, false, 1)
        elseif kind == "message" then
            A.writeConsole(a.message)
            A.log("MESSAGE " .. a.message)
            A.notice = { text = A.consoleText(a.message), expires = A.frame() + 150 }
        elseif kind == "shake" then Game():ShakeScreen(frames(a.duration))
        elseif kind == "darken" then Game():Darken(math.max(0, math.min(1, a.value)), frames(a.duration))
        elseif kind == "animation" then call(p, ({ "AnimateHappy", "AnimateSad", "AnimateTeleport", "AnimateAppear", "AnimateLightTravel" })[a.mode + 1], true)
        elseif kind == "particles" then Game():SpawnParticles(pos, a.variant, n, a.value, color(a), 0)
        elseif kind == "rule_switch" then
            for _, rule in ipairs(S.profile(engine.config).rules) do
                if rule.id == a.ruleId then
                    rule.enabled = a.mode == 0
                    if A.invalidateListeners then A.invalidateListeners() end
                    return
                end
            end
            error("指定规则 ID 不在当前方案")
        elseif kind == "counter" then
            local key = tostring(a.counterId); local old = engine.run.variables[key] or 0
            engine.run.variables[key] = math.max(-1000000000, math.min(1000000000, a.mode == 0 and old + a.amount or a.amount))
        elseif kind == "teleport" then
            local desc = level:GetRoomByIdx(a.roomIndex)
            if not desc or not desc.Data then error("目标房间不存在") end
            Game():StartRoomTransition(a.roomIndex, Direction.NO_DIRECTION, RoomTransitionAnim.TELEPORT, p)
        elseif kind == "stage_transition" then
            local suffix = ({ [0] = "", [1] = "a", [2] = "b", [4] = "c", [5] = "d" })[a.stageType]
            if suffix == nil then error("楼层类型 3 已被原版废弃") end
            if a.stageType >= 4 and a.stage > 8 then error("支线楼层类型仅适用于 1–8 层") end
            Isaac.ExecuteCommand("stage " .. a.stage .. suffix)
        elseif kind == "change_character" then p:ChangePlayerType(a.character)
        else error("未实现的动作: " .. tostring(kind)) end
    end
    function A.execute(action, ctx, engine)
        if not ctx.player or not ctx.player:Exists() then error("玩家对象已不存在") end
        I.operation(false)
        I.before(action, ctx)
        local ok, err = pcall(perform, action, ctx, engine)
        -- 动作结束立即检测变化并传递当前因果链，避免下一帧被误认作独立的玩家事件。
        if A.rebase and not ctx.terminal then A.rebase() end
        for i = 0, Game():GetNumPlayers() - 1 do A.capture(Isaac.GetPlayer(i)) end
        if not ok then error(err) end
    end
    function A.evaluate(player, flag, engine)
        if not engine.run then return end
        local names = { damage = { CacheFlag.CACHE_DAMAGE, "Damage" }, speed = { CacheFlag.CACHE_SPEED, "MoveSpeed" },
            range = { CacheFlag.CACHE_RANGE, "TearRange" }, shotSpeed = { CacheFlag.CACHE_SHOTSPEED, "ShotSpeed" },
            luck = { CacheFlag.CACHE_LUCK, "Luck" } }
        for _, modifier in ipairs(engine.run.modifiers or {}) do
            if modifier.player == player.InitSeed then
                if modifier.kind == "tear_flag" and flag == CacheFlag.CACHE_TEARFLAG then
                    local tearFlag = TearFlags[modifier.flag]
                    if tearFlag then player.TearFlags = player.TearFlags | tearFlag end
                elseif modifier.stat == "flight" and flag == CacheFlag.CACHE_FLYING then player.CanFly = modifier.value > 0
                elseif modifier.stat == "tears" and flag == CacheFlag.CACHE_FIREDELAY then
                    local rate = math.max(0.1, 30 / (player.MaxFireDelay + 1) + modifier.value)
                    player.MaxFireDelay = math.max(-0.99, 30 / rate - 1)
                elseif names[modifier.stat] and flag == names[modifier.stat][1] then
                    local name = names[modifier.stat][2]
                    player[name] = player[name] + modifier.value
                    if modifier.stat == "damage" or modifier.stat == "speed" or modifier.stat == "range" then
                        player[name] = math.max(0.01, player[name])
                    end
                end
            end
        end
    end
    function A.expire(engine)
        if not engine.run then return end
        local ctx, now, retained, changed = A.context(), A.frame(), {}, false
        for _, m in ipairs(engine.run.modifiers) do
            local expired = (m.scope == 0 and m.roomKey ~= ctx.roomKey) or (m.scope == 1 and m.floorKey ~= ctx.floorKey)
                or (m.scope == 3 and now >= m.expires)
            if expired then changed = true else retained[#retained + 1] = m end
        end
        engine.run.modifiers = retained
        if changed then
            for i = 0, Game():GetNumPlayers() - 1 do local p = Isaac.GetPlayer(i); p:AddCacheFlags(CacheFlag.CACHE_ALL); p:EvaluateItems() end
        end
        local watch = engine.run.roomWatch
        if watch and (watch.roomKey ~= ctx.roomKey or now >= watch.expires) then
            if watch.roomKey == ctx.roomKey then Game():GetRoom():SetBrokenWatchState(watch.previous or 0) end
            engine.run.roomWatch = nil
        end
    end
    return A
end
