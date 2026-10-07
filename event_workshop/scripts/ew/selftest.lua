return function(C, S, makeEngine)
    return function()
        local passed = 0
        local function test(name, fn)
            local ok, err = pcall(fn)
            if not ok then error(name .. "：" .. tostring(err)) end
            passed = passed + 1
        end
        local ctx = { roomType = 1, roomKey = "floor1:room1", floorKey = "floor1" }
        local records, logs, single = {}, {}, true
        local E
        local A = {
            isSinglePlayer = function() return single end,
            character = function() return 0 end,
            hasCollectible = function(_, id) return id == 1 end,
            log = function(err) logs[#logs + 1] = err end,
            execute = function(action)
                if action.amount == 99 then error("预期的测试错误") end
                records[#records + 1] = action.amount
                if action.amount == 88 then E:dispatch("room_clear", ctx) end
            end,
        }
        local function reset(event)
            records, logs, single = {}, {}, true
            E = makeEngine(S, A)
            E:newRun(12345, false)
            local rule = S.rule({ enabled = true, event = event or "room_clear" }, 1)
            E.config.profiles[1].rules = { rule }
            return rule
        end
        test("新局关闭总开关", function()
            reset(); E:dispatch("room_clear", ctx); assert(#records == 0 and not E.run.master)
        end)
        test("首次启用补触发且不更改种子", function()
            reset("run_start"); E:setMaster(true, ctx)
            assert(#records == 1 and E.run.seed == 12345 and E.run.startedFired)
        end)
        test("重复开关不补触发", function()
            reset("run_start"); E:setMaster(true, ctx); E:setMaster(false, ctx); E:setMaster(true, ctx)
            assert(#records == 1)
        end)
        test("继续游戏恢复状态", function()
            reset("run_start"); E:setMaster(true, ctx)
            local saved = S.copy(E.run); E:newRun(12345, true, saved); E:setMaster(true, ctx)
            assert(E.run.master and E.run.startedFired and #records == 1)
        end)
        test("相同种子新局也停用", function()
            reset(); E:setMaster(true, ctx); E:newRun(12345, false, S.copy(E.run)); assert(not E.run.master)
        end)
        test("种子不匹配不恢复", function()
            reset(); E:setMaster(true, ctx); E:newRun(54321, true, S.copy(E.run)); assert(not E.run.master)
        end)
        test("规则禁用", function()
            local r = reset(); r.enabled = false; E:setMaster(true, ctx); E:dispatch("room_clear", ctx); assert(#records == 0)
        end)
        test("多条件取且", function()
            local r = reset(); r.conditions.collectible = 1; r.conditions.character = 0; r.conditions.roomType = 5
            E:setMaster(true, ctx); E:dispatch("room_clear", ctx); assert(#records == 0)
            r.conditions.roomType = 1; E:dispatch("room_clear", ctx); assert(#records == 1)
        end)
        test("每 N 次计数", function()
            local r = reset(); r.conditions.every = 2; E:setMaster(true, ctx)
            E:dispatch("room_clear", ctx); E:dispatch("room_clear", ctx); E:dispatch("room_clear", ctx)
            assert(#records == 1)
        end)
        test("0% 概率", function()
            local r = reset(); r.conditions.chance = 0; E:setMaster(true, ctx); E:dispatch("room_clear", ctx); assert(#records == 0)
        end)
        test("每房间上限及重复进入", function()
            local r = reset(); r.conditions.maxRoom = 1; E:setMaster(true, ctx)
            E:dispatch("room_clear", ctx); E:dispatch("room_clear", ctx)
            E:dispatch("room_clear", { roomType = 1, roomKey = "floor1:room2", floorKey = "floor1" })
            E:dispatch("room_clear", ctx); assert(#records == 2)
        end)
        test("每层上限", function()
            local r = reset(); r.conditions.maxFloor = 1; E:setMaster(true, ctx)
            E:dispatch("room_clear", ctx)
            E:dispatch("room_clear", { roomType = 1, roomKey = "floor1:room2", floorKey = "floor1" })
            E:dispatch("room_clear", { roomType = 1, roomKey = "floor2:room1", floorKey = "floor2" })
            assert(#records == 2)
        end)
        test("每局上限保持到继续游戏", function()
            local r = reset(); r.conditions.maxRun = 1; E:setMaster(true, ctx); E:dispatch("room_clear", ctx)
            E:newRun(12345, true, S.copy(E.run)); E:dispatch("room_clear", ctx); assert(#records == 1)
        end)
        test("动作顺序与错误隔离", function()
            local r = reset(); r.actions = { S.action({ amount = 1 }), S.action({ amount = 99 }), S.action({ amount = 2 }) }
            E:setMaster(true, ctx); E:dispatch("room_clear", ctx)
            assert(#records == 2 and records[1] == 1 and records[2] == 2 and #logs == 1 and not E.busy)
        end)
        test("禁止递归触发", function()
            local r = reset(); r.actions = { S.action({ amount = 88 }) }
            E:setMaster(true, ctx); E:dispatch("room_clear", ctx); assert(#records == 1)
        end)
        test("本地合作不执行", function()
            reset(); single = false; E:setMaster(true, ctx); E:dispatch("room_clear", ctx); assert(#records == 0)
        end)
        test("私有随机状态可恢复", function()
            reset(); E:nextSeed(); local saved = S.copy(E.run); local nextSeed = E:nextSeed()
            E:newRun(12345, true, saved); assert(E:nextSeed() == nextSeed and E.run.seed == 12345)
        end)
        test("配置去除重复 ID 且保留中文", function()
            local cfg = S.config({ profiles = { { id = 1, name = "测试方案", rules = {
                { id = 1, name = "清理房间" }, { id = 1, name = "开局奖励" },
            } } } })
            assert(cfg.profiles[1].rules[1].id ~= cfg.profiles[1].rules[2].id and cfg.profiles[1].name == "测试方案")
        end)
        test("损坏配置规范化", function()
            local cfg = S.config({ profiles = { false, { rules = { false, { conditions = { every = 0, chance = 200 } } } } } })
            local r = cfg.profiles[1].rules[1]; assert(r.conditions.every == 1 and r.conditions.chance == 100)
        end)
        local function causal(rules)
            local frame, pending, calls = 10, {}, {}
            local engine
            local adapter = {
                frame = function() return frame end, isSinglePlayer = function() return true end,
                character = function() return 0 end, hasCollectible = function() return true end,
                metric = function(context, field) return context[field] end,
                log = function() end,
                execute = function(action, context)
                    calls[#calls + 1] = action.kind
                    if action.kind == "keys" or action.kind == "coins" then
                        pending[#pending + 1] = { event = action.kind .. "_changed", context = {
                            roomType = 1, roomKey = "r", floorKey = "f", chain = S.copy(context.chain) } }
                    end
                end,
            }
            engine = makeEngine(S, adapter)
            engine:newRun(12345, false)
            engine.config.profiles[1].rules = {}
            for index, raw in ipairs(rules) do engine.config.profiles[1].rules[index] = S.rule(raw, index) end
            engine:setMaster(true, { roomType = 1, roomKey = "r", floorKey = "f" })
            local function advance()
                frame = frame + 1
                local entries = pending; pending = {}
                for _, entry in ipairs(entries) do engine:dispatch(entry.event, entry.context) end
                engine:tick({ roomType = 1, roomKey = "r", floorKey = "f" })
            end
            return engine, advance, calls
        end
        test("同链自循环停止且新事件仍执行", function()
            local engine, advance, calls = causal({ { enabled = true, event = "coins_changed", actions = { { kind = "coins" } } } })
            engine:dispatch("coins_changed", { roomType = 1, roomKey = "r", floorKey = "f" })
            advance(); advance(); assert(#calls == 1)
            engine:dispatch("coins_changed", { roomType = 1, roomKey = "r", floorKey = "f" }); advance(); assert(#calls == 2)
        end)
        test("双规则互为因果停止", function()
            local engine, advance, calls = causal({
                { enabled = true, event = "coins_changed", actions = { { kind = "keys" } } },
                { enabled = true, event = "keys_changed", actions = { { kind = "coins" } } },
            })
            engine:dispatch("coins_changed", { roomType = 1, roomKey = "r", floorKey = "f" })
            for _ = 1, 8 do advance() end
            assert(#calls == 2 and calls[1] == "keys" and calls[2] == "coins")
        end)
        test("延迟动作保留因果链", function()
            local engine, advance, calls = causal({ { enabled = true, event = "coins_changed",
                actions = { { kind = "coins", delayFrames = 2 } } } })
            engine:dispatch("coins_changed", { roomType = 1, roomKey = "r", floorKey = "f" })
            for _ = 1, 8 do advance() end; assert(#calls == 1)
        end)
        test("事件爆发受限流保护", function()
            local engine, _, calls = causal({ { enabled = true, event = "room_clear", actions = { { kind = "message" } } } })
            for _ = 1, 1000 do engine:dispatch("room_clear", { roomType = 1, roomKey = "r", floorKey = "f" }) end
            assert(#calls <= engine.MAX_EVENTS)
        end)
        test("旧版导入兼容", function()
            local raw = S.default(); raw.schemaVersion = 1
            assert(S.validateImport(raw)); assert(S.config(raw).schemaVersion == S.VERSION)
        end)
        test("扩展条件支持任一满足与取反", function()
            local engine, _, calls = causal({ { enabled = true, event = "room_clear", conditions = { roomType = 5, matchMode = 1 },
                filters = { { field = "coins", op = "eq", value = 0 } }, actions = { { kind = "message" } } } })
            engine:dispatch("room_clear", { roomType = 1, roomKey = "r", floorKey = "f", coins = 0 }); assert(#calls == 1)
            engine.config.profiles[1].rules[1].filters[1].negate = true
            engine:dispatch("room_clear", { roomType = 1, roomKey = "r", floorKey = "f", coins = 0 }); assert(#calls == 1)
        end)
        test("数值跨越筛选", function()
            local engine, _, calls = causal({ { enabled = true, event = "coins_changed",
                filters = { { field = "after", op = "cross_up", value = 5 } }, actions = { { kind = "message" } } } })
            engine:dispatch("coins_changed", { roomType = 1, roomKey = "r", floorKey = "f", before = 3, after = 6 })
            engine:dispatch("coins_changed", { roomType = 1, roomKey = "r", floorKey = "f", before = 6, after = 7 })
            assert(#calls == 1)
        end)
        test("小数参数规范化", function()
            local action = S.action({ kind = "stat", value = 1.5 })
            assert(action.value == 1.5 and action.stat == "damage")
        end)
        return passed
    end
end
