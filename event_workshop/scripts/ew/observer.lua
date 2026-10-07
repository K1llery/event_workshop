return function(C, S, A, E, I, emit)
    local O = { players = {}, room = nil, timers = {}, hits = {}, contacts = {}, entityStates = {}, damageOrigins = {}, pickupOrigins = {} }
    local function read(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil end
        return object[method](object, ...)
    end
    O.read = read
    local function exists(entity) return entity and (not entity.Exists or entity:Exists()) end
    local function bool(value) return value and 1 or 0 end
    function O.wants(event)
        if not E.run or (not E.run.master and not O.baselining) then return false end
        if O.listenFrame ~= A.frame() or O.listenRevision ~= A.listenerRevision then
            O.listenFrame, O.listenRevision, O.listeners = A.frame(), A.listenerRevision, {}
            for _, rule in ipairs(S.profile(E.config).rules) do
                if rule.enabled then O.listeners[rule.event] = true end
            end
        end
        return O.listeners[event] == true
    end
    function A.invalidateListeners() A.listenerRevision = (A.listenerRevision or 0) + 1 end
    local health = { red = "GetHearts", soul = "GetSoulHearts", black = "GetBlackHearts", max = "GetMaxHearts",
        bone = "GetBoneHearts", rotten = "GetRottenHearts", eternal = "GetEternalHearts", golden = "GetGoldenHearts", broken = "GetBrokenHearts" }
    local specials = { soulCharge = "GetSoulCharge", bloodCharge = "GetBloodCharge", poopMana = "GetPoopMana",
        jarHearts = "GetJarHearts", jarFlies = "GetJarFlies", gigaBombs = "GetNumGigaBombs" }
    local function playerSnapshot(p)
        local result = { coins = p:GetNumCoins(), keys = p:GetNumKeys(), bombs = p:GetNumBombs(),
            character = p:GetPlayerType(), dead = bool(read(p, "IsDead")),
            slots = {}, health = {}, inventory = {}, forms = {}, special = {}, inputs = {} }
        for name, method in pairs(health) do result.health[name] = read(p, method) end
        for name, method in pairs(specials) do result.special[name] = read(p, method) end
        for slot = 0, 3 do
            result.slots[slot] = { active = p:GetActiveItem(slot), charge = p:GetActiveCharge(slot) + p:GetBatteryCharge(slot),
                card = read(p, "GetCard", slot), pill = read(p, "GetPill", slot), trinket = slot < 2 and read(p, "GetTrinket", slot) or nil }
        end
        if O.wants("collectible_gain") or O.wants("collectible_loss") or O.wants("pickup_collected") or O.wants("purchase") then
            for _, item in ipairs(A.observedItems or A.items) do result.inventory[item.id] = read(p, "GetCollectibleNum", item.id, true) or bool(p:HasCollectible(item.id)) end
        end
        if O.wants("form_changed") then
            for _, form in ipairs(C.forms or {}) do result.forms[form[1]] = bool(read(p, "HasPlayerForm", form[1])) end
        end
        local movement, shooting = read(p, "GetMovementInput"), read(p, "GetShootingInput")
        result.moving = movement and bool(movement.X ~= 0 or movement.Y ~= 0) or 0
        result.shooting = shooting and bool(shooting.X ~= 0 or shooting.Y ~= 0) or 0
        if Input then
            for _, row in ipairs(C.buttons) do result.inputs[row[1]] = bool(Input.IsActionPressed(row[1], p.ControllerIndex)) end
        end
        return result
    end
    local function snapshotRoom()
        local room, level, ctx = Game():GetRoom(), Game():GetLevel(), A.context()
        local result = { key = ctx.roomKey, clear = bool(read(room, "IsClear")), curses = read(level, "GetCurses"),
            wave = level.GreedModeWave, ambush = bool(read(room, "IsAmbushActive")), doors = {}, grids = {} }
        if O.wants("door_changed") then
            for slot = 0, 7 do
                local door = read(room, "GetDoor", slot)
                if door then result.doors[slot] = bool(door:IsOpen()) + 2 * bool(door:IsLocked()) end
            end
        end
        if O.wants("grid_changed") or O.wants("grid_destroyed") then
            for index = 0, (read(room, "GetGridSize") or 0) - 1 do
                local grid = room:GetGridEntity(index)
                if grid then result.grids[index] = { type = grid:GetType(), state = grid.State, variant = grid:GetVariant() } end
            end
        end
        return result
    end
    local function changed(event, p, before, after, extra, chain)
        if before == nil or after == nil or before == after then return end
        local ctx = A.context(p)
        ctx.before, ctx.after, ctx.delta, ctx.chain = before, after, after - before, chain
        for key, value in pairs(extra or {}) do ctx[key] = value end
        emit(event, ctx)
    end
    function O.comparePlayer(p, before, after, chain)
        if not before then return end
        for _, resource in ipairs({ "coins", "keys", "bombs" }) do changed(resource .. "_changed", p, before[resource], after[resource], { resource = resource }, chain) end
        for name, value in pairs(after.health) do changed("health_changed", p, before.health[name], value, { heartType = name }, chain) end
        for name, value in pairs(after.special) do changed("resource_changed", p, before.special[name], value, { resource = name }, chain) end
        changed("character_changed", p, before.character, after.character, nil, chain)
        if before.dead ~= after.dead then changed(after.dead == 1 and "player_death" or "player_revive", p, before.dead, after.dead, nil, chain) end
        for id, value in pairs(after.inventory) do
            local old = before.inventory[id]
            if old ~= nil and old ~= value then changed(value > old and "collectible_gain" or "collectible_loss", p, old, value, { itemId = id }, chain) end
        end
        for id, value in pairs(after.forms) do changed("form_changed", p, before.forms[id], value, { itemId = id }, chain) end
        for slot = 0, 3 do
            local old, current = before.slots[slot], after.slots[slot]
            for key, event in pairs({ active = "active_changed", card = "card_changed", pill = "pill_changed", trinket = "trinket_changed" }) do
                changed(event, p, old[key], current[key], { slot = slot, itemId = current[key] }, chain)
            end
            changed("charge_changed", p, old.charge, current.charge, { slot = slot, itemId = current.active }, chain)
            if old.active == current.active and old.charge ~= current.charge then
                local config = Isaac.GetItemConfig():GetCollectible(current.active)
                if current.charge == 0 then changed("charge_empty", p, old.charge, 0, { slot = slot, itemId = current.active }, chain)
                elseif config and config.MaxCharges > 0 and old.charge < config.MaxCharges and current.charge >= config.MaxCharges then
                    changed("charge_full", p, old.charge, current.charge, { slot = slot, itemId = current.active }, chain)
                end
            end
        end
        if before.moving ~= after.moving then changed(after.moving == 1 and "move_start" or "move_stop", p, before.moving, after.moving, nil, chain) end
        if before.shooting ~= after.shooting then changed(after.shooting == 1 and "shoot_start" or "shoot_stop", p, before.shooting, after.shooting, nil, chain) end
        if not ModConfigMenu or not ModConfigMenu.IsVisible then
            for input, value in pairs(after.inputs) do
                if before.inputs[input] ~= value then
                    for _, rule in ipairs(S.profile(E.config).rules) do
                        if rule.enabled and rule.conditions.inputAction == input then
                            changed(value == 1 and "input_pressed" or "input_released", p, before.inputs[input], value,
                                { inputAction = input, ruleId = rule.id }, chain)
                        end
                    end
                end
            end
        end
    end
    function O.compareRoom(before, after, chain)
        if not before or before.key ~= after.key then return end
        local p = Isaac.GetPlayer(0)
        changed("curse_changed", p, before.curses, after.curses, nil, chain)
        changed("greed_wave", p, before.wave, after.wave, nil, chain)
        changed("ambush_changed", p, before.ambush, after.ambush, nil, chain)
        if before.clear == 1 and after.clear == 0 then changed("combat_start", p, 1, 0, nil, chain) end
        for slot = 0, 7 do changed("door_changed", p, before.doors[slot] or -1, after.doors[slot] or -1, { slot = slot }, chain) end
        for index, grid in pairs(before.grids) do
            local current = after.grids[index]
            local ctx = A.context(); ctx.gridIndex, ctx.gridType, ctx.variant, ctx.chain = index, grid.type, grid.variant, chain
            ctx.position = Game():GetRoom():GetGridPosition(index)
            ctx.before, ctx.after = grid.state, current and current.state or -1
            if not current or current.type ~= grid.type or current.state ~= grid.state then
                emit("grid_changed", ctx)
                local rock = grid.type >= 2 and grid.type <= 6 or grid.type == 22 or grid.type >= 25
                local destroyed = current and ((rock and current.state == 2 and grid.state ~= 2)
                    or ((grid.type == 14 or grid.type == 12) and current.state >= 1000 and grid.state < 1000))
                if not current or destroyed then emit("grid_destroyed", ctx) end
            end
        end
    end
    function O.capture(notify, chain)
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            local current = playerSnapshot(p)
            local origin = chain
            if not origin then
                local damage = O.damageOrigins[p.InitSeed]
                if damage and A.frame() <= damage.expires then origin = damage.chain end
                local pending = O.pickupOrigins[p.InitSeed]
                if pending and A.frame() <= pending.expires then origin = origin or pending.chain end
                for _, contact in pairs(O.contacts) do
                    if contact.player == p and contact.chain then origin = origin or contact.chain end
                end
            end
            if notify then O.comparePlayer(p, O.players[p.InitSeed], current, origin) end
            O.players[p.InitSeed] = current
        end
        local room = snapshotRoom()
        if notify then O.compareRoom(O.room, room, chain) end
        O.room = room
    end
    function A.rebase() O.capture(true, I.current()) end
    function A.baseline()
        O.baselining = true
        O.capture(false)
        O.baselining = false
    end
    function O.reset()
        O.players, O.room, O.timers, O.hits, O.contacts, O.entityStates, O.damageOrigins, O.pickupOrigins = {}, nil, {}, {}, {}, {}, {}, {}
        O.timers, O.hits = E.run.timers, E.run.roomHits
        I.arrive()
        O.capture(false); A.invalidateListeners()
    end
    function O.arrive()
        O.arrivalChain = I.arrive(); O.contacts, O.entityStates = {}, {}
        for _, rule in ipairs(S.profile(E.config).rules) do
            if rule.event == "room_timer" then O.timers[tostring(rule.id)] = nil end
        end
        O.capture(false)
    end
    function O.context(entity, extra)
        local player = entity and read(entity, "ToPlayer") or nil
        local ctx = A.context(player)
        if not ctx then return nil end
        ctx.entity = entity
        if entity then ctx.entityType, ctx.variant, ctx.subtype = entity.Type, entity.Variant, entity.SubType; ctx.position = entity.Position or ctx.position end
        for key, value in pairs(extra or {}) do ctx[key] = value end
        return ctx
    end
    function O.trackPickups()
        O.wants("pickup_collected")
        if not E.run or not E.run.master then return false end
        for event in pairs(O.listeners or {}) do
            if event == "pickup_collected" or event == "purchase" or C.eventInfo[event].group == "state" then return true end
        end
        return false
    end
    function O.inheritDamage(player, chain)
        if player and chain then O.damageOrigins[player.InitSeed] = { chain = chain, expires = A.frame() + 2 } end
    end
    function O.contact(pickup, collider)
        local player = read(collider, "ToPlayer")
        if not player then return end
        local snap = playerSnapshot(player)
        O.contacts[tostring(pickup.InitSeed)] = { pickup = pickup, player = player, frame = A.frame(),
            snapshot = snap, variant = pickup.Variant, subtype = pickup.SubType, price = pickup.Price or 0, shop = read(pickup, "IsShopItem"), chain = I.origin(pickup) }
    end
    function O.identity(entity)
        local id = "identity:" .. tostring(entity.InitSeed)
        local identity = tostring(entity.Type) .. ":" .. tostring(entity.Variant) .. ":" .. tostring(entity.SubType)
        if O.entityStates[id] and O.entityStates[id] ~= identity then emit("entity_changed", O.context(entity)) end
        O.entityStates[id] = identity
    end
    function O.inspect(entity, kind)
        if not entity.InitSeed then return end
        local id = tostring(entity.InitSeed)
        local old = O.entityStates[id]
        local state
        if kind == "machine" and entity.GetSprite then
            local sprite = entity:GetSprite()
            local animation = sprite:GetAnimation()
            state = animation .. ":" .. tostring(sprite:IsFinished(animation))
        elseif kind == "pickup" then state = entity.State end
        if old ~= nil and state ~= old then
            if kind == "pickup" and C.chests[entity.Variant] and old == 0 and state ~= 0 then emit("chest_opened", O.context(entity)) end
            if kind == "machine" then emit("machine_changed", O.context(entity)) end
        end
        O.entityStates[id] = state
    end
    function O.tick()
        O.capture(true)
        for id, contact in pairs(O.contacts) do
            if A.frame() > contact.frame then
                local consumed = not exists(contact.pickup) or (contact.pickup.GetSprite and contact.pickup:GetSprite():IsPlaying("Collect"))
                if consumed and exists(contact.player) then
                    if contact.chain then O.pickupOrigins[contact.player.InitSeed] = {
                        chain = contact.chain, expires = A.frame() + (contact.variant == 100 and 120 or 2) } end
                    local after, before = playerSnapshot(contact.player), contact.snapshot
                    local delta = after.coins ~= before.coins or after.keys ~= before.keys or after.bombs ~= before.bombs
                    for key, value in pairs(after.health) do if before.health[key] ~= value then delta = true end end
                    for key, value in pairs(after.inventory) do if before.inventory[key] ~= value then delta = true end end
                    for slot = 0, 3 do for key, value in pairs(after.slots[slot]) do if before.slots[slot][key] ~= value then delta = true end end end
                    if delta then
                        local ctx = O.context(nil, { entityType = 5, variant = contact.variant, subtype = contact.subtype,
                            itemId = contact.subtype, chain = contact.chain, position = contact.player.Position })
                        ctx.player = contact.player
                        emit("pickup_collected", ctx)
                        if contact.shop and contact.price ~= 0 then emit("purchase", ctx) end
                    end
                end
                O.contacts[id] = nil
            end
        end
        local ctx, frame = A.context(), A.frame()
        for _, rule in ipairs(S.profile(E.config).rules) do
            if rule.enabled and E.run and E.run.master then
                local c, key = rule.conditions, tostring(rule.id)
                if rule.event == "timer" or rule.event == "room_timer" or rule.event == "hold_condition" then
                    local timer = O.timers[key] or { start = frame, next = frame + c.intervalFrames, fired = false }
                    O.timers[key] = timer
                    if rule.event == "hold_condition" and not E:matches(rule, ctx) then timer.start, timer.next = frame, frame + c.intervalFrames end
                    if frame >= timer.next and (rule.event ~= "room_timer" or not timer.fired) then
                        local context = O.context(nil, { ruleId = rule.id })
                        emit(rule.event, context); timer.next, timer.fired = frame + c.intervalFrames, true
                    end
                end
            end
        end
    end
    function A.metric(ctx, field, argument, engine)
        if ctx[field] ~= nil then return ctx[field] end
        local p, room, level = ctx.player, Game():GetRoom(), Game():GetLevel()
        if health[field] then return read(p, health[field]) end
        if field == "coins" or field == "keys" or field == "bombs" then return A.resource(p, field) end
        if field == "charge" then return p:GetActiveCharge(0) + p:GetBatteryCharge(0) end
        if field == "stage" then return level:GetStage() elseif field == "stageType" then return level:GetStageType()
        elseif field == "roomShape" then return read(room, "GetRoomShape") elseif field == "firstVisit" then return bool(read(room, "IsFirstVisit"))
        elseif field == "clear" then return bool(read(room, "IsClear")) elseif field == "enemies" then return read(room, "GetAliveEnemiesCount")
        elseif field == "bosses" then return read(room, "GetAliveBossesCount") elseif field == "curses" then return read(level, "GetCurses")
        elseif field == "difficulty" then return Game().Difficulty elseif field == "greed" then return bool(read(Game(), "IsGreedMode"))
        elseif field == "damage" then return p.Damage elseif field == "tears" then return p.MaxFireDelay and 30 / (p.MaxFireDelay + 1)
        elseif field == "speed" then return p.MoveSpeed elseif field == "range" then return p.TearRange
        elseif field == "shotSpeed" then return p.ShotSpeed elseif field == "luck" then return p.Luck
        elseif field == "flight" then return bool(p.CanFly) elseif field == "collectibleCount" then return read(p, "GetCollectibleCount")
        elseif field == "heldCollectible" then return read(p, "GetCollectibleNum", argument, true)
        elseif field == "heldTrinket" then return read(p, "GetTrinketMultiplier", argument)
        elseif field == "form" then return bool(read(p, "HasPlayerForm", argument))
        elseif field == "elapsed" then return (Game().TimeCounter or A.frame()) / 30
        elseif field == "roomElapsed" then return (read(room, "GetFrameCount") or 0) / 30
        elseif field == "counter" then return engine.run.variables[tostring(argument)] or 0 end
        return nil
    end
    function A.restoreTask(task)
        local ctx = A.context()
        if task.playerSeed then
            for i = 0, Game():GetNumPlayers() - 1 do if Isaac.GetPlayer(i).InitSeed == task.playerSeed then ctx.player = Isaac.GetPlayer(i) end end
        end
        if task.entitySeed or task.colliderSeed then
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.InitSeed == task.entitySeed then ctx.entity = entity end
                if entity.InitSeed == task.colliderSeed then ctx.collider = entity end
            end
        end
        if task.position then ctx.position = Vector(task.position.X, task.position.Y) end
        return ctx
    end
    return O
end
