-- 为同步、延迟、状态比较和实体后续行为传递因果链，不一概屏蔽正常联动。
return function(A)
    local I = { engine = nil }
    local function state()
        local run = I.engine and I.engine.run
        if not run then return nil end
        run.origins = run.origins or { rooms = {}, entities = {} }
        return run.origins
    end
    local function key(entity, roomKey)
        return roomKey .. ":" .. tostring(entity.InitSeed) .. ":" .. tostring(entity.Type) .. ":" .. tostring(entity.Variant)
    end
    local function copy(chain)
        if type(chain) ~= "table" then return nil end
        local result = { id = chain.id, visited = {} }
        for id, value in pairs(type(chain.visited) == "table" and chain.visited or {}) do result.visited[id] = value end
        return result
    end
    function I.bind(engine) I.engine = engine end
    function I.current() return I.engine and I.engine.activeChain end
    function I.operation(spawn)
        if spawn and Isaac.GetRoomEntities and #Isaac.GetRoomEntities() >= 512 then error("当前房间实体达到 512，跳过生成") end
        if not I.engine:budget("operation") or (spawn and not I.engine:budget("spawn")) then
            error("本帧原版操作 / 生成数量达到限流上限")
        end
    end
    function I.mark(entity, chain)
        chain = chain or I.current()
        if not entity or entity.Type == 1 or not chain then return end
        local ctx, s = A.context(), state()
        if ctx and s and entity.InitSeed then s.entities[key(entity, ctx.roomKey)] = copy(chain) end
        if entity.GetData then entity:GetData().EventWorkshopOrigin = copy(chain) end
    end
    function I.origin(entity, depth, visited)
        if not entity then return nil end
        depth, visited = depth or 0, visited or {}
        if depth > 8 or visited[entity] then return nil end
        visited[entity] = true
        if entity.GetData and entity:GetData().EventWorkshopOrigin then return copy(entity:GetData().EventWorkshopOrigin) end
        local ctx, s = A.context(), state()
        if ctx and s and entity.InitSeed and s.entities[key(entity, ctx.roomKey)] then return s.entities[key(entity, ctx.roomKey)] end
        local chain = I.origin(entity.SpawnerEntity, depth + 1, visited) or I.origin(entity.Parent, depth + 1, visited)
        if chain then I.mark(entity, chain) end
        return chain
    end
    function I.annotate(ctx, event)
        if not ctx then return nil end
        local s = state()
        local natural = event == "timer" or event == "room_timer" or event == "hold_condition"
            or event == "input_pressed" or event == "input_released" or event == "new_room"
            or event == "new_level" or event == "first_visit" or event == "run_start" or event == "continue_run"
            or event == "use_card" or event == "use_pill" or event == "use_active" or event == "pre_use_active"
            or event == "move_start" or event == "move_stop" or event == "shoot_start" or event == "shoot_stop"
            or (event == "native_callback" and (ctx.callbackId == ModCallbacks.MC_POST_UPDATE
                or ctx.callbackId == ModCallbacks.MC_POST_RENDER or ctx.callbackId == ModCallbacks.MC_INPUT_ACTION
                or ctx.callbackId == ModCallbacks.MC_USE_ITEM or ctx.callbackId == ModCallbacks.MC_PRE_USE_ITEM
                or ctx.callbackId == ModCallbacks.MC_USE_CARD or ctx.callbackId == ModCallbacks.MC_USE_PILL))
        ctx.chain = ctx.chain or I.current() or I.origin(ctx.source) or I.origin(ctx.entity) or I.origin(ctx.collider)
            or (not natural and s and s.rooms[ctx.roomKey])
        return ctx
    end
    function I.before(action, ctx)
        local s, chain = state(), I.current()
        local info = A.catalog.actionInfo[action.kind]
        -- 道具效果和持续伤害缺少完整来源；房间内保守继承已执行规则集合。
        if s and chain and info and info.isolation == "room" then
            local old = s.rooms[ctx.roomKey]
            local merged = copy(chain)
            for id in pairs(old and old.visited or {}) do merged.visited[id] = true end
            s.rooms[ctx.roomKey] = merged
        end
        if s and chain and (action.kind == "teleport" or action.kind == "stage_transition"
            or action.kind == "use_item" or action.kind == "use_card_action" or action.kind == "use_pill_action") then
            s.transition = copy(chain); s.transition.expires = A.frame() + 90
        end
    end
    function I.clearCause(chain)
        local s, ctx = state(), A.context()
        if s and ctx and chain then
            s.clearCauses = s.clearCauses or {}
            s.clearCauses[ctx.roomKey] = copy(chain)
        end
    end
    function I.clearChain()
        local s, ctx = state(), A.context()
        return s and ctx and s.clearCauses and s.clearCauses[ctx.roomKey] or nil
    end
    function I.arrive()
        local s, ctx = state(), A.context()
        if s and ctx and s.floorKey ~= ctx.floorKey then
            s.floorKey, s.rooms, s.entities, s.clearCauses = ctx.floorKey, {}, {}, {}
        end
        local arrival = I.current() or (s and s.transition and (not s.transition.expires or A.frame() <= s.transition.expires) and s.transition)
        if s and ctx and arrival then s.rooms[ctx.roomKey] = copy(arrival) end
        if s then s.transition = nil end
        return copy(arrival)
    end
    function I.reason()
        local ctx, s = A.context(), state()
        return ctx and s and s.rooms[ctx.roomKey] and "本房间持续效果继承因果链" or nil
    end
    return I
end
