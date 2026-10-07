local mod = RegisterMod("Event Workshop", 1)
local json = require("json")
local C = include("scripts/ew/catalog")
local S = include("scripts/ew/schema")(C)
local A = include("scripts/ew/adapter")(C, S)
local I = include("scripts/ew/isolation")(A)
include("scripts/ew/actions")(C, S, A, I)
local makeEngine = include("scripts/ew/engine")
local E = makeEngine(S, A)
I.bind(E)
local T = include("scripts/ew/controller")(mod, json, C, S, E, A)
T:load()
local queue, lastClear, collisionFrame, collisionKeys = {}, nil, -1, {}
local O
local function defer(event, context)
    if not E.ready or not E.run or not E.run.master or not context then return end
    if O and not O.wants(event) then return end
    if #queue >= E.MAX_QUEUE then E:record("事件队列达到上限，跳过: " .. event); return end
    queue[#queue + 1] = { event = event, context = I.annotate(context, event), frame = A.frame() }
end
O = include("scripts/ew/observer")(C, S, A, E, I, defer)
local selftest = include("scripts/ew/selftest")(C, S, makeEngine)
local M = include("scripts/ew/menu")(C, S, E, A, T, json, selftest)
local K = include("scripts/ew/console")(C, S, E, A, T, M, json, selftest)
EW = K.execute
local function captureAll()
    for i = 0, Game():GetNumPlayers() - 1 do A.capture(Isaac.GetPlayer(i)) end
end
local function dispatch(event, context)
    if context then A.prepare(context) end
    if E.busy then defer(event, context); return end
    E:dispatch(event, I.annotate(context, event))
    if E.ready and E.run and E.run.master then T.pendingSave = true end
end
local registered = {}
local function hook(name, fn)
    if ModCallbacks[name] == nil then return end
    registered[name] = true
    mod:AddCallback(ModCallbacks[name], function(_, ...)
        fn(mod, ...)
        if E.ready and O.wants("native_callback") and name ~= "MC_PRE_MOD_UNLOAD" then
            local first = select(1, ...)
            local entity = (type(first) == "userdata" or type(first) == "table") and type(first.ToPlayer) == "function" and first or nil
            local ctx = O.context(entity, { callbackId = ModCallbacks[name], after = type(first) == "number" and first or nil })
            if ctx then
                for _, rule in ipairs(S.profile(E.config).rules) do
                    if rule.enabled and rule.event == "native_callback" and E:matches(rule, ctx) then
                        defer("native_callback", ctx); break
                    end
                end
            end
        end
    end)
end
hook("MC_POST_GAME_STARTED", function(_, continued)
    queue, lastClear, A.snapshots = {}, nil, {}
    E:newRun(Game():GetSeeds():GetStartSeed(), continued, E.run or T.savedRun)
    T.savedRun = nil
    A.refreshItems(); captureAll(); O.reset()
    A.expire(E)
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        if p.AddCacheFlags then p:AddCacheFlags(CacheFlag.CACHE_ALL); p:EvaluateItems() end
    end
    M:install(); M:search(M.query)
    T.status = continued and "已继续本局，恢复总开关状态" or "新一局: 请手动打开本局总开关"
    if continued then defer("continue_run", A.context()) end
    T:save()
    A.log("已进入" .. (continued and "继续游戏" or "新局") .. "; master=" .. tostring(E.run.master))
end)
hook("MC_POST_NEW_ROOM", function()
    if A.frame() <= 1 then E.ready, queue = false, {}; return end
    if not E.ready then return end
    lastClear = nil; O.arrive(); A.expire(E)
    dispatch("new_room", O.context(nil, { chain = O.arrivalChain }))
    if O.read(Game():GetRoom(), "IsFirstVisit") then defer("first_visit", O.context(nil, { chain = O.arrivalChain })) end
    captureAll()
end)
hook("MC_POST_NEW_LEVEL", function()
    if E.ready and A.frame() > 1 then dispatch("new_level", O.context(nil, { chain = O.arrivalChain })) end
end)
hook("MC_PRE_SPAWN_CLEAN_AWARD", function()
    local ctx = A.clearContext()
    if not ctx then return end
    local key = ctx.roomKey .. ":" .. tostring(A.frame())
    if key ~= lastClear then
        ctx.chain = I.current() or I.clearChain()
        lastClear = key; defer("room_clear", ctx)
        if ctx.roomType == RoomType.ROOM_BOSS then defer("boss_clear", O.context(nil, { chain = ctx.chain })) end
        if not O.hits[ctx.roomKey] then defer("no_hit_clear", O.context(nil, { chain = ctx.chain })) end
    end
    -- 始终不返回覆盖值，原版奖励和充能照常执行。
end)
hook("MC_ENTITY_TAKE_DMG", function(_, entity, amount, flags, source)
    local ctx = O.context(entity, { amount = amount, after = amount, flags = flags, source = source and source.Entity,
        sourceType = source and source.Type or -1 })
    local player = O.read(entity, "ToPlayer")
    local cause = I.current() or I.origin(source and source.Entity)
    if cause then
        if player then O.inheritDamage(player, cause) else I.mark(entity, cause) end
    end
    if player and (flags & DamageFlag.DAMAGE_FAKE) == 0 then
        O.hits[ctx.roomKey] = true; defer("player_damage", ctx)
    elseif O.read(entity, "ToNPC") then defer("enemy_damage", ctx) end
    defer("entity_damage", O.context(entity, { after = amount, flags = flags, source = source and source.Entity,
        sourceType = source and source.Type or -1 }))
end)
hook("MC_POST_ENTITY_KILL", function(_, entity)
    local ctx, npc = O.context(entity), O.read(entity, "ToNPC")
    defer("entity_kill", ctx)
    if npc and npc:IsActiveEnemy(true) and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        I.clearCause(I.current() or I.origin(entity))
        defer("enemy_kill", O.context(entity))
        if O.read(npc, "IsBoss") then defer("boss_kill", O.context(entity)) end
    end
end)
hook("MC_POST_ENTITY_REMOVE", function(_, entity) defer("entity_remove", O.context(entity)) end)
for _, row in ipairs({ { "MC_USE_ITEM", "use_active" }, { "MC_PRE_USE_ITEM", "pre_use_active" } }) do
    local name, event = row[1], row[2]
    hook(name, function(_, id, _, player, flags, slot)
        defer(event, O.context(player, { itemId = id, flags = flags, slot = slot }))
    end)
end
hook("MC_USE_CARD", function(_, id, player, flags) defer("use_card", O.context(player, { itemId = id, flags = flags })) end)
hook("MC_USE_PILL", function(_, id, player, flags) defer("use_pill", O.context(player, { itemId = id, flags = flags })) end)
for _, row in ipairs({ { "MC_POST_NPC_INIT", "npc" }, { "MC_POST_PICKUP_INIT", "pickup" },
    { "MC_FAMILIAR_INIT", "familiar" }, { "MC_POST_TEAR_INIT", "tear" }, { "MC_POST_PROJECTILE_INIT", "projectile" },
    { "MC_POST_LASER_INIT", "laser" }, { "MC_POST_KNIFE_INIT", "knife" }, { "MC_POST_BOMB_INIT", "bomb" }, { "MC_POST_EFFECT_INIT", "effect" } }) do
    local name, kind = row[1], row[2]
    hook(name, function(_, entity)
        I.mark(entity, I.current() or I.origin(entity))
        defer(kind .. "_spawn", O.context(entity))
    end)
end
hook("MC_POST_FIRE_TEAR", function(_, tear) defer("fire_tear", O.context(tear)) end)
for _, kind in ipairs({ "PLAYER", "NPC", "PICKUP", "TEAR", "PROJECTILE", "KNIFE", "BOMB", "FAMILIAR" }) do
    local event = kind:lower() .. "_collision"
    hook("MC_PRE_" .. kind .. "_COLLISION", function(_, entity, collider)
        if collisionFrame ~= A.frame() then collisionFrame, collisionKeys = A.frame(), {} end
        local key = event .. ":" .. tostring(entity.InitSeed) .. ":" .. tostring(collider.InitSeed)
        if not collisionKeys[key] then
            collisionKeys[key] = true
            defer(event, O.context(entity, { collider = collider }))
            if kind == "PICKUP" and O.trackPickups() then O.contact(entity, collider) end
        end
    end)
end
hook("MC_POST_PICKUP_UPDATE", function(_, entity)
    if O.wants("chest_opened") then O.inspect(entity, "pickup") end
    if O.wants("entity_changed") then O.identity(entity) end
end)
hook("MC_NPC_UPDATE", function(_, entity) if O.wants("entity_changed") then O.identity(entity) end end)
hook("MC_POST_PICKUP_SELECTION", function(_, entity, variant, subtype)
    defer("pickup_selection", O.context(entity, { variant = variant, subtype = subtype, itemId = subtype }))
end)
hook("MC_POST_PLAYER_INIT", function(_, player) defer("player_init", O.context(player)) end)
hook("MC_POST_UPDATE", function()
    M:install()
    if not E.ready then return end
    if Game().IsPaused and Game():IsPaused() then return end
    O.tick(); A.expire(E)
    local incoming, now = queue, A.frame()
    queue = {}
    local current = A.context()
    for _, entry in ipairs(incoming) do
        if entry.frame < now then
            if current and entry.context.roomKey == current.roomKey then dispatch(entry.event, entry.context) end
        elseif #queue < E.MAX_QUEUE then queue[#queue + 1] = entry end
    end
    E:tick(A.context())
    if O.wants("machine_changed") and Isaac.GetRoomEntities then
        for _, entity in ipairs(Isaac.GetRoomEntities()) do if entity.Type == 6 then O.inspect(entity, "machine") end end
    end
    captureAll()
    if E.run and E.run.master then T.pendingSave = true end
    if T.pendingSave and now - (T.lastSaveFrame or 0) >= 30 then T:save() end
end)
hook("MC_POST_RENDER", function()
    M:install()
    if A.notice and A.frame() < A.notice.expires then Isaac.RenderText(A.notice.text, 30, 60, 1, 1, 1, 1) end
end)
hook("MC_POST_GET_COLLECTIBLE", function(_, id, pool) defer("pool_collectible", O.context(nil, { itemId = id, pool = pool })) end)
hook("MC_GET_CARD", function(_, _, id) defer("pool_card", O.context(nil, { itemId = id })) end)
hook("MC_GET_PILL_COLOR", function(_, seed) defer("pool_pill_color", O.context(nil, { after = seed })) end)
hook("MC_GET_PILL_EFFECT", function(_, id, color) defer("pool_pill_effect", O.context(nil, { itemId = id, subtype = color })) end)
hook("MC_GET_TRINKET", function(_, id) defer("pool_trinket", O.context(nil, { itemId = id })) end)
hook("MC_POST_CURSE_EVAL", function(_, curses) defer("curse_evaluated", O.context(nil, { after = curses, flags = curses })) end)
hook("MC_PRE_ENTITY_SPAWN", function(_, t, v, s, pos, _, spawner)
    defer("entity_spawn_request", O.context(nil, { entityType = t, variant = v, subtype = s, position = pos, source = spawner }))
end)
hook("MC_PRE_ROOM_ENTITY_SPAWN", function(_, t, v, s, index)
    defer("room_spawn_request", O.context(nil, { entityType = t, variant = v, subtype = s, gridIndex = index }))
end)
hook("MC_PRE_ENTITY_DEVOLVE", function(_, entity) defer("entity_devolve", O.context(entity)) end)
hook("MC_EVALUATE_CACHE", function(_, player, flag) A.evaluate(player, flag, E) end)
hook("MC_PRE_GAME_EXIT", function(_, shouldSave)
    dispatch("game_exit", O.context(nil, { after = shouldSave and 1 or 0, terminal = true }))
    if not shouldSave then E.run, T.savedRun = nil, nil end
    T:save(); queue, E.ready = {}, false
end)
hook("MC_POST_GAME_END", function(_, gameOver)
    dispatch("game_end", O.context(nil, { after = gameOver and 1 or 0, terminal = true }))
    E.run, T.savedRun, E.ready, queue = nil, nil, false, {}; T:save()
end)
hook("MC_EXECUTE_CMD", K.callback)
hook("MC_PRE_MOD_UNLOAD", function(_, unloaded) if unloaded == mod and EW == K.execute then EW = nil end end)
-- 通用高级通知只观察原版回调，不覆盖返回值；失效的生成器回调不注册。
for name in pairs(ModCallbacks) do
    if not registered[name] and name ~= "MC_LEVEL_GENERATOR" and name ~= "MC_PRE_MOD_UNLOAD" then
        hook(name, function() end)
    end
end
A.log(C.version .. ' 已加载; 使用 MCM 或 lua EW("help"); 无 REPENTOGON 依赖')
