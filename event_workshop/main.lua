local mod = RegisterMod("Event Workshop", 1)
local json = require("json")
local C = include("scripts/ew/catalog")
local S = include("scripts/ew/schema")(C)
local A = include("scripts/ew/adapter")(C, S)
local makeEngine = include("scripts/ew/engine")
local E = makeEngine(S, A)
local T = include("scripts/ew/controller")(mod, json, C, S, E, A)
T:load()
local selftest = include("scripts/ew/selftest")(C, S, makeEngine)
local M = include("scripts/ew/menu")(C, S, E, A, T, json, selftest)
local K = include("scripts/ew/console")(C, S, E, A, T, M, json, selftest)
-- 原生忏悔+ 1.9.7.17 的控制台不转交裸自定义命令，使用内置 lua 命令进入。
EW = K.execute

local queue, lastClear = {}, nil
local function captureAll()
    for i = 0, Game():GetNumPlayers() - 1 do A.capture(Isaac.GetPlayer(i)) end
end
local function dispatch(event, context)
    if context then A.prepare(context) end
    E:dispatch(event, context)
    if E.ready and E.run and E.run.master then T.pendingSave = true end
end
local function defer(event, context)
    if not E.ready or E.busy or not E.run or not E.run.master or not context then return end
    queue[#queue + 1] = { event = event, context = context, frame = Game():GetFrameCount() }
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    queue, lastClear, A.snapshots = {}, nil, {}
    E:newRun(Game():GetSeeds():GetStartSeed(), continued, E.run or T.savedRun)
    T.savedRun = nil
    A.refreshItems()
    captureAll()
    M:install()
    M:search(M.query)
    T.status = continued and "已继续本局，恢复总开关状态" or "新一局：请手动打开本局总开关"
    T:save()
    A.log("已进入" .. (continued and "继续游戏" or "新局") .. "；master=" .. tostring(E.run.master))
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    -- R 重开时进房回调先于开局回调，不能沿用上一局的运行开关。
    if Game():GetFrameCount() <= 1 then E.ready, queue = false, {}; return end
    if not E.ready then return end
    lastClear = nil
    dispatch("new_room", A.context())
    captureAll()
end)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    if E.ready and Game():GetFrameCount() > 1 then dispatch("new_level", A.context()) end
end)
mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, function()
    local context = A.clearContext()
    if not context then return end
    local key = context.roomKey .. ":" .. tostring(Game():GetFrameCount())
    if key ~= lastClear then
        lastClear = key
        defer("room_clear", context)
    end
    -- 不返回值：原版奖励、充能、出口与完成标记照常执行。
end)
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, _, flags)
    if E.busy then return end
    local player = entity:ToPlayer()
    if player and (flags & DamageFlag.DAMAGE_FAKE) == 0 then defer("player_damage", A.context(player)) end
end, EntityType.ENTITY_PLAYER)
mod:AddCallback(ModCallbacks.MC_POST_ENTITY_KILL, function(_, entity)
    if E.busy then return end
    local npc = entity:ToNPC()
    if npc and npc:IsActiveEnemy(true) and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        defer("enemy_kill", A.context())
    end
end)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, function(_, _, _, player)
    if not E.busy then defer("use_active", A.context(player)) end
end)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    M:install()
    if not E.ready then return end
    local waiting = {}
    local now, current = Game():GetFrameCount(), A.context()
    for _, entry in ipairs(queue) do
        if entry.frame < now then
            if current and entry.context.roomKey == current.roomKey then dispatch(entry.event, entry.context) end
        else waiting[#waiting + 1] = entry end
    end
    queue = waiting
    captureAll()
    if T.pendingSave then T:save() end
end)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function() M:install() end)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
    if not shouldSave then E.run, T.savedRun = nil, nil end
    T:save()
    queue, E.ready = {}, false
end)
mod:AddCallback(ModCallbacks.MC_POST_GAME_END, function()
    E.run, T.savedRun, E.ready, queue = nil, nil, false, {}
    T:save()
end)
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, K.callback)
mod:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function(_, unloaded)
    if unloaded == mod and EW == K.execute then EW = nil end
end)
A.log(C.version .. ' 已加载；使用 MCM 或 lua EW("help") 配置；无 REPENTOGON 依赖')
