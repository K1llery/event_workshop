local G = dofile("tests/mock_game.lua")
local passed = 0
local function test(name, fn)
    fn(); passed = passed + 1; print("通过：" .. name)
end
test("真实游戏 JSON 和枚举可加载", function()
    assert(RoomType.ROOM_PLANETARIUM == 24 and EntityType.ENTITY_SPIDER == 85)
end)
test("原生 lua 控制台入口可执行、捕获错误且不改存档", function()
    local stored, seed = G.stored, G.seed
    local before = #G.output
    G.consoleInput("ew help")
    assert(#G.output == before + 1 and G.output[#G.output]:find("Unknown command", 1, true))
    assert(G.command("help"):find('lua EW("status")', 1, true))
    assert(G.command("  STATUS  "):find("No active run", 1, true))
    assert(G.stored == stored and G.seed == seed)
    assert(EW({}) == nil and G.output[#G.output]:find("argument must be a string", 1, true))
    assert(EW("unknown") == nil and G.output[#G.output]:find("Unknown command", 1, true))
    assert(G.stored == stored and G.seed == seed)
end)
test("原生 lua 控制台可重命名并保存含空格的名称", function()
    G.command("rename 1 clear reward")
    assert(G.saved().config.profiles[1].rules[1].name == "clear reward")
end)
test("支持转交命令的控制台保留 EW 回调且无返回值", function()
    local before = #G.output
    assert(G.fire(ModCallbacks.MC_EXECUTE_CMD, "EW", "help") == nil)
    assert(#G.output > before)
    before = #G.output
    assert(G.fire(ModCallbacks.MC_EXECUTE_CMD, "other", "help") == nil and #G.output == before)
end)
test("首次进入不补执行开局、进房、进层", function()
    G.start(); assert(G.saved().run.master == false and #G.spawned == 0)
end)
test("首次启用在原局给予奖励且只一次", function()
    G.command("preset start_coins"); G.command("enable 3 on")
    local seed, room, stage = G.seed, G.roomIndex, G.stage
    G.command("on"); assert(G.players[1].coins == 5)
    G.command("off"); G.command("on")
    assert(G.players[1].coins == 5 and G.seed == seed and G.roomIndex == room and G.stage == stage)
end)
test("清房追加底座且不阻断原版回调", function()
    G.command("enable 1 on")
    assert(G.fire(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD) == nil)
    assert(#G.spawned == 0)
    G.players[1].charge[0] = 1; G.tick()
    assert(#G.spawned == 1 and G.spawned[1][1] == 5 and G.spawned[1][2] == 100 and G.spawned[1][3] == 5)
    assert(G.players[1].charge[0] == 1)
end)
test("清房预设抵消增量且不误扣满充能", function()
    G.command("enable 2 on")
    G.fire(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD); G.players[1].charge[0] = 2; G.tick()
    assert(G.players[1].charge[0] == 1)
    G.players[1].charge[0] = 6; G.tick()
    G.fire(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD); G.tick()
    assert(G.players[1].charge[0] == 6)
end)
test("清房抵消保留其他规则追加的充能", function()
    G.command("enable 1 off"); G.command("enable 2 off")
    G.command("new room_clear"); G.command("action 4 1 kind charge"); G.command("enable 4 on")
    G.command("preset no_clear_charge"); G.command("enable 5 on")
    G.players[1].charge[0] = 1; G.tick()
    G.fire(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD); G.players[1].charge[0] = 2; G.tick()
    assert(G.players[1].charge[0] == 2)
end)
test("退出后重新加载和继续恢复总开关与开局标记", function()
    G.fire(ModCallbacks.MC_PRE_GAME_EXIT, true)
    G.reload(); G.start(true)
    assert(G.saved().run.master and G.saved().run.startedFired)
    local coins = G.players[1].coins
    G.command("on"); assert(G.players[1].coins == coins)
end)
test("R 重开同种子也停用，配置保留", function()
    G.command("new new_room"); G.command("action 6 1 kind coins"); G.command("enable 6 on")
    local coins, spawned = G.players[1].coins, #G.spawned
    G.start(false)
    assert(not G.saved().run.master and not G.saved().run.startedFired)
    assert(G.saved().config.profiles[1].rules[3].enabled)
    assert(G.players[1].coins == coins and #G.spawned == spawned, "R 重开的早期回调不能运行上一局的规则")
    G.command("delete 6")
end)
test("新局首次启用重新执行开局规则", function()
    local coins = G.players[1].coins
    G.command("on"); assert(G.players[1].coins == coins + 5)
end)
test("多个动作按顺序编辑及执行", function()
    G.command("new new_room"); G.command("action 7 1 kind coins"); G.command("action 7 1 amount 3")
    G.command("addaction 7 keys"); G.command("action 7 2 amount 2"); G.command("enable 7 on")
    local coins, keys = G.players[1].coins, G.players[1].keys
    G.tick()
    G.roomIndex = 1; G.fire(ModCallbacks.MC_POST_NEW_ROOM); G.tick()
    assert(G.players[1].coins == coins + 3 and G.players[1].keys == keys + 2)
end)
test("受伤回调延后一帧，忽略假伤害", function()
    G.command("preset damage_coin"); G.command("enable 8 on")
    local coins = G.players[1].coins
    G.fire(ModCallbacks.MC_ENTITY_TAKE_DMG, G.players[1], 1, DamageFlag.DAMAGE_FAKE)
    G.tick(); assert(G.players[1].coins == coins)
    G.fire(ModCallbacks.MC_ENTITY_TAKE_DMG, G.players[1], 1, 0)
    assert(G.players[1].coins == coins); G.tick(); assert(G.players[1].coins == coins + 1)
end)
test("使用主动回调追加行为且无返回值", function()
    G.command("new use_active"); G.command("action 9 1 kind bombs"); G.command("enable 9 on")
    assert(G.fire(ModCallbacks.MC_USE_ITEM, 2, {}, G.players[1], 0, 0, 0) == nil)
    G.tick(); assert(G.players[1].bombs == 1)
end)
test("敌人死亡回调排除友军", function()
    G.command("new enemy_kill"); G.command("action 10 1 kind bombs"); G.command("enable 10 on")
    local friendly = false
    local npc = {
        ToNPC = function(self) return self end, IsActiveEnemy = function() return true end,
        HasEntityFlags = function() return friendly end,
    }
    friendly = true; G.fire(ModCallbacks.MC_POST_ENTITY_KILL, npc); G.tick()
    assert(G.players[1].bombs == 1)
    friendly = false; G.fire(ModCallbacks.MC_POST_ENTITY_KILL, npc); G.tick()
    assert(G.players[1].bombs == 2)
end)
test("MCM 页面显示、动态范围和参数编辑", function()
    local count = 0
    for _, rows in pairs(G.rows) do
        for _, row in ipairs(rows) do
            local value = type(row.Display) == "function" and row.Display() or row.Display
            assert(row.Type == 2 or type(value) == "string")
            if value then
                assert(not value:find("：", 1, true) and not value:find("（", 1, true),
                    "本机 MCM 字体缺少全角冒号和括号")
            end
            if row.CurrentSetting then
                local setting = row.CurrentSetting()
                assert(type(setting) == "number" or type(setting) == "boolean")
                if row.Type == 5 then assert(type(row.Maximum) == "number" and row.Maximum >= row.Minimum) end
            end
            count = count + 1
        end
    end
    for _, tab in ipairs({ "运行", "规则", "条件", "动作", "道具", "预设" }) do
        assert(G.rows[tab] and #G.rows[tab] > 0, "缺少菜单页面：" .. tab)
    end
    local ruleOn
    for _, row in ipairs(G.rows["规则"]) do
        if row.Type == 4 then ruleOn = row end
        local label = type(row.Display) == "function" and row.Display() or row.Display or ""
        assert(not label:find("触发事件", 1, true), "事件设置应在条件页")
    end
    local eventFound, cadenceFound = false, false
    for _, row in ipairs(G.rows["条件"]) do
        local label = type(row.Display) == "function" and row.Display() or row.Display or ""
        if label:find("触发事件: ", 1, true) then eventFound = true end
        if label:find("每 1 次符合条件时执行", 1, true) then cadenceFound = true end
    end
    assert(eventFound and cadenceFound)
    assert(ruleOn.Type == 4); ruleOn.OnChange(false)
    assert(G.saved().config.profiles[1].rules[9].enabled == false)
end)
test("道具名称搜索包含其他模组道具", function()
    local output = G.command("search Other Mod")
    assert(output:find("#5 Other Mod Item", 1, true))
end)
test("导入导出只改配置，不换种子，并停用总开关", function()
    local export = G.command("export")
    local seed = G.seed
    G.command("import " .. export)
    assert(G.seed == seed and not G.saved().run.master)
end)
test("切换方案不重复开局事件", function()
    G.command("profile new")
    assert(not G.saved().run.master and #G.saved().config.profiles == 2)
    G.command("preset start_coins")
    local id = G.saved().config.profiles[2].rules[1].id
    G.command("enable " .. id .. " on")
    local coins = G.players[1].coins
    G.command("on"); assert(G.players[1].coins == coins)
end)
test("合作玩家出现后规则不执行", function()
    G.command("new new_room")
    local id = G.saved().config.profiles[2].rules[2].id
    G.command("action " .. id .. " 1 kind coins"); G.command("enable " .. id .. " on")
    G.players[2] = G.newPlayer(1)
    local coins = G.players[1].coins
    G.roomIndex = 2; G.fire(ModCallbacks.MC_POST_NEW_ROOM); G.tick()
    assert(G.players[1].coins == coins)
    G.players[2] = nil
end)
test("游戏内自检不修改实际局内状态与配置", function()
    local config, seed, coins = G.stored, G.seed, G.players[1].coins
    assert(G.command("selftest"):find("27 checks", 1, true))
    assert(G.stored == config and G.seed == seed and G.players[1].coins == coins)
end)
test("给予物品不依赖底座，资源扣除不为负数", function()
    G.command("new new_room")
    local id = G.saved().config.profiles[2].rules[3].id
    G.command("action " .. id .. " 1 kind give_collectible"); G.command("action " .. id .. " 1 itemId 1")
    G.command("addaction " .. id .. " coins"); G.command("action " .. id .. " 2 amount -999")
    G.command("enable " .. id .. " on")
    G.roomIndex = 3; G.fire(ModCallbacks.MC_POST_NEW_ROOM); G.tick()
    assert(G.players[1].inventory[1] and G.players[1].coins == 0)
end)
test("已离开房间时丢弃延迟事件", function()
    local before = G.players[1].bombs
    G.fire(ModCallbacks.MC_USE_ITEM, 2, {}, G.players[1])
    G.roomIndex = 4; G.tick()
    assert(G.players[1].bombs == before)
end)
test("错误导入拒绝未知动作且保留当前配置", function()
    local before = G.stored
    local raw = G.json.decode(G.command("export"))
    raw.profiles[1].rules[1].actions[1].kind = "not_supported"
    local outputCount = #G.output
    G.consoleInput("lua EW(" .. string.format("%q", "import " .. G.json.encode(raw)) .. ")")
    assert(G.output[outputCount + 1]:find("ERROR: ", 1, true) and G.stored == before)
end)
test("无 MCM 时仍可加载和操作控制台", function()
    ModConfigMenu = nil
    G.reload(); G.start(true)
    assert(G.command("status"):find("Master:", 1, true))
    G.command("off")
end)
test("带合法 JSON 的损坏存档不会阻止模组加载", function()
    G.stored = '{"config":3,"run":false}'
    G.reload(); G.start(false)
    assert(G.saved().config.profiles[1].rules[1].enabled == false)
end)
test("卸载时只清理本模组拥有的控制台入口", function()
    local entry = EW
    G.fire(ModCallbacks.MC_PRE_MOD_UNLOAD, {})
    assert(EW == entry)
    local other = function() end
    EW = other
    G.fire(ModCallbacks.MC_PRE_MOD_UNLOAD, G.mod)
    assert(EW == other)
    EW = entry
    G.fire(ModCallbacks.MC_PRE_MOD_UNLOAD, G.mod)
    assert(EW == nil)
end)
print("回调、MCM、控制台、存档模拟集成测试通过：" .. passed .. " 项")
