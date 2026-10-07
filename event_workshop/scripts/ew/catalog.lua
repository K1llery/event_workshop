local C = {}
C.version = "1.1.1"
C.events = {
    { "room_clear", "清理房间" }, { "new_room", "进入房间" },
    { "new_level", "进入新楼层" }, { "run_start", "开局（首次启用时）" },
    { "player_damage", "玩家受伤回调" }, { "enemy_kill", "敌人死亡" },
    { "use_active", "使用主动道具" },
}
C.actions = {
    { "spawn_collectible", "生成底座道具" }, { "spawn_pickup", "生成掉落物" },
    { "give_collectible", "直接给予道具" }, { "coins", "增减金币" },
    { "keys", "增减钥匙" }, { "bombs", "增减炸弹" },
    { "hearts", "增减生命" }, { "charge", "调整主动充能" },
    { "spawn_enemy", "生成敌人" }, { "undo_clear_charge", "抵消本次清房充能" },
}
C.rooms = {
    { -1, "不限" }, { 1, "普通房" }, { 2, "商店" }, { 3, "错误房" },
    { 4, "宝箱房" }, { 5, "Boss 房" }, { 6, "小 Boss 房" }, { 7, "隐藏房" },
    { 8, "超级隐藏房" }, { 9, "街机房" }, { 10, "诅咒房" }, { 11, "挑战房" },
    { 12, "图书馆" }, { 13, "献祭房" }, { 14, "恶魔房" }, { 15, "天使房" }, { 16, "夹层" },
    { 17, "Boss Rush" }, { 20, "箱子房" }, { 21, "骰子房" },
    { 22, "黑市" }, { 23, "贪婪出口" }, { 24, "星象房" }, { 29, "究极隐藏房" },
}
C.pools = {
    { 0, "宝箱房" }, { 1, "商店" }, { 2, "Boss" }, { 3, "恶魔房" },
    { 4, "天使房" }, { 5, "隐藏房" }, { 6, "图书馆" }, { 7, "贝壳游戏" },
    { 8, "黄金箱子" }, { 9, "红箱子" }, { 10, "乞丐" },
    { 12, "诅咒房" }, { 26, "星象房" },
}
C.pickups = {
    { 20, "金币" }, { 30, "钥匙" }, { 40, "炸弹" }, { 10, "心" },
    { 90, "电池" }, { 300, "卡牌 / 符文" }, { 70, "药丸" }, { 350, "饰品" },
}
C.hearts = {
    { "red", "红心" }, { "soul", "魂心" }, { "black", "黑心" },
    { "max", "红心容器" }, { "bone", "骨心" }, { "rotten", "腐心" },
}
C.slots = { { 0, "主主动" }, { 1, "书包主动" }, { 2, "口袋主动" }, { 3, "第二口袋主动" } }
C.enemies = {
    { 10, "呆头" }, { 13, "苍蝇" }, { 14, "吐弹苍蝇" }, { 18, "攻击苍蝇" },
    { 21, "蛆虫" }, { 22, "苍蝇巢" }, { 25, "爆炸苍蝇" }, { 26, "血口" },
    { 27, "宿主" }, { 85, "蜘蛛" }, { 38, "婴儿" },
}
C.presets = {
    { "clear_pedestal", "清房生成随机底座" },
    { "no_clear_charge", "清房不充能" },
    { "start_coins", "首次启用给予 5 金币" },
    { "damage_coin", "受伤获得 1 金币" },
}
function C.index(list, value)
    for i, entry in ipairs(list) do
        if entry[1] == value then return i end
    end
    return 1
end
function C.label(list, value)
    for _, entry in ipairs(list) do
        if entry[1] == value then return entry[2] end
    end
    return tostring(value)
end
function C.contains(list, value)
    for _, entry in ipairs(list) do
        if entry[1] == value then return true end
    end
    return false
end

-- 分类和参数描述同时用于 MCM、控制台、配置规范化与覆盖文档。
C.eventGroups = { { "progress", "游戏与房间" }, { "combat", "战斗" }, { "use", "使用物品" },
    { "entity", "实体" }, { "collision", "碰撞尝试" }, { "state", "玩家状态变化" },
    { "environment", "环境与交互" }, { "time", "时间与输入" }, { "advanced", "高级通知" } }
C.actionGroups = { { "spawn", "生成" }, { "inventory", "持有物" }, { "resource", "资源与生命" },
    { "effect", "使用与临时效果" }, { "combat", "攻击与实体" }, { "world", "房间与楼层" },
    { "visual", "表现反馈" }, { "control", "规则与高级动作" } }
C.eventInfo, C.actionInfo = {}, {}
local function event(id, label, group, detection)
    if not C.contains(C.events, id) then C.events[#C.events + 1] = { id, label } end
    C.eventInfo[id] = { group = group, detection = detection or "原版回调" }
end
local function action(id, label, group, fields, isolation)
    if not C.contains(C.actions, id) then C.actions[#C.actions + 1] = { id, label } end
    C.actionInfo[id] = { group = group, fields = fields, isolation = isolation }
end
event("room_clear", "清理房间", "progress", "原版回调")
event("new_room", "进入房间", "progress", "原版回调")
event("new_level", "进入新楼层", "progress", "原版回调")
event("run_start", "开局 (首次启用时)", "progress", "原版回调")
event("continue_run", "继续游戏", "progress", "原版回调")
event("game_end", "游戏结束", "progress", "原版回调")
event("game_exit", "退出游戏", "progress", "原版回调")
event("player_damage", "玩家伤害回调", "combat", "原版回调")
event("enemy_damage", "敌人伤害回调", "combat", "原版回调")
event("entity_damage", "任意实体伤害回调", "combat", "原版回调")
event("enemy_kill", "敌人死亡", "combat", "原版回调")
event("boss_kill", "首领死亡", "combat", "原版回调")
event("fire_tear", "玩家发射眼泪", "combat", "原版回调")
event("use_active", "使用主动道具", "use", "原版回调")
event("pre_use_active", "主动道具使用前", "use", "原版回调")
event("use_card", "使用卡牌或符文", "use", "原版回调")
event("use_pill", "使用药丸", "use", "原版回调")
event("npc_spawn", "敌人生成", "entity", "原版回调")
event("pickup_spawn", "拾取物生成", "entity", "原版回调")
event("familiar_spawn", "跟班生成", "entity", "原版回调")
event("tear_spawn", "眼泪生成", "entity", "原版回调")
event("projectile_spawn", "敌方弹幕生成", "entity", "原版回调")
event("laser_spawn", "激光生成", "entity", "原版回调")
event("knife_spawn", "刀生成", "entity", "原版回调")
event("bomb_spawn", "炸弹生成", "entity", "原版回调")
event("effect_spawn", "特效生成", "entity", "原版回调")
event("entity_remove", "实体移除", "entity", "原版回调")
event("entity_kill", "实体死亡", "entity", "原版回调")
event("player_collision", "玩家碰撞尝试", "collision", "原版回调")
event("npc_collision", "敌人碰撞尝试", "collision", "原版回调")
event("pickup_collision", "拾取物碰撞尝试", "collision", "原版回调")
event("tear_collision", "眼泪碰撞尝试", "collision", "原版回调")
event("projectile_collision", "弹幕碰撞尝试", "collision", "原版回调")
event("knife_collision", "刀碰撞尝试", "collision", "原版回调")
event("bomb_collision", "炸弹碰撞尝试", "collision", "原版回调")
event("familiar_collision", "跟班碰撞尝试", "collision", "原版回调")
event("coins_changed", "金币变化", "state", "状态比较")
event("keys_changed", "钥匙变化", "state", "状态比较")
event("bombs_changed", "炸弹数量变化", "state", "状态比较")
event("health_changed", "生命变化", "state", "状态比较")
event("charge_changed", "主动充能变化", "state", "状态比较")
event("charge_full", "主动充满", "state", "状态比较")
event("charge_empty", "主动耗尽", "state", "状态比较")
event("collectible_gain", "道具数量增加", "state", "状态比较")
event("collectible_loss", "道具数量减少", "state", "状态比较")
event("active_changed", "主动槽位变化", "state", "状态比较")
event("trinket_changed", "饰品槽位变化", "state", "状态比较")
event("card_changed", "卡牌槽位变化", "state", "状态比较")
event("pill_changed", "药丸槽位变化", "state", "状态比较")
event("player_death", "玩家死亡状态", "state", "状态比较")
event("player_revive", "玩家复活", "state", "状态比较")
event("character_changed", "角色变化", "state", "状态比较")
event("form_changed", "变身变化", "state", "状态比较")
event("move_start", "开始移动", "state", "状态比较")
event("move_stop", "停止移动", "state", "状态比较")
event("shoot_start", "开始射击", "state", "状态比较")
event("shoot_stop", "停止射击", "state", "状态比较")
event("resource_changed", "特殊资源变化", "state", "状态比较")
event("first_visit", "首次进入房间", "environment", "状态比较")
event("no_hit_clear", "无伤清房 (按伤害回调)", "environment", "状态比较")
event("boss_clear", "清理首领房", "environment", "状态比较")
event("combat_start", "房间重新进入战斗", "environment", "状态比较")
event("greed_wave", "贪婪波次变化", "environment", "状态比较")
event("ambush_changed", "挑战战斗状态变化", "environment", "状态比较")
event("curse_changed", "诅咒变化", "environment", "状态比较")
event("door_changed", "门开关变化", "environment", "状态比较")
event("grid_changed", "障碍状态变化", "environment", "状态比较")
event("grid_destroyed", "障碍被破坏或移除 (推断)", "environment", "推断检测")
event("pickup_collected", "拾取成功 (推断)", "environment", "推断检测")
event("purchase", "购买完成 (推断)", "environment", "推断检测")
event("chest_opened", "箱子开启 (推断)", "environment", "推断检测")
event("machine_changed", "机器状态变化 (推断)", "environment", "推断检测")
event("pool_collectible", "道具池抽取", "advanced", "原版回调")
event("pool_card", "卡牌抽取请求", "advanced", "原版回调")
event("pool_pill_color", "药丸颜色选择请求", "advanced", "原版回调")
event("pool_pill_effect", "药丸效果选择请求", "advanced", "原版回调")
event("pool_trinket", "饰品抽取请求", "advanced", "原版回调")
event("curse_evaluated", "楼层诅咒计算", "advanced", "原版回调")
event("entity_spawn_request", "实体生成请求", "advanced", "原版回调")
event("room_spawn_request", "房间布局生成请求", "advanced", "原版回调")
event("entity_devolve", "敌人退化请求", "advanced", "原版回调")
event("timer", "周期定时", "time", "状态比较")
event("room_timer", "进房后定时", "time", "状态比较")
event("hold_condition", "条件持续满足", "time", "状态比较")
event("input_pressed", "游戏操作按下", "time", "状态比较")
event("input_released", "游戏操作松开", "time", "状态比较")
action("spawn_collectible", "生成底座道具", "spawn", { "amount", "itemId", "pool", "qualityMin", "qualityMax", "position" })
action("spawn_pickup", "生成掉落物", "spawn", { "amount", "pickupVariant", "subtype", "position" })
action("spawn_enemy", "生成敌人", "spawn", { "amount", "enemyType", "variant", "subtype", "position" })
action("spawn_entity", "生成指定实体", "spawn", { "amount", "entityType", "variant", "subtype", "position" }, "room")
action("spawn_effect", "生成特效", "spawn", { "amount", "variant", "subtype", "position" }, "room")
action("spawn_familiar", "生成跟班", "spawn", { "amount", "variant", "subtype", "position" }, "room")
action("spawn_machine", "生成机器", "spawn", { "amount", "variant", "subtype", "position" }, "room")
action("give_collectible", "给予道具", "inventory", { "amount", "itemId", "pool", "qualityMin", "qualityMax", "slot" })
action("remove_collectible", "移除道具", "inventory", { "amount", "itemId" })
action("give_trinket", "给予饰品", "inventory", { "amount", "itemId" })
action("remove_trinket", "移除饰品", "inventory", { "itemId" })
action("smelt_trinket", "熔炼饰品", "inventory", { "itemId" })
action("give_card", "给予卡牌或符文", "inventory", { "itemId" })
action("give_pill", "给予药丸", "inventory", { "itemId" })
action("set_card", "设置卡牌槽位", "inventory", { "itemId", "slot" })
action("set_pill", "设置药丸槽位", "inventory", { "itemId", "slot" })
action("drop_pocket", "掉落口袋物品", "inventory", { "slot", "position" })
action("drop_trinket", "掉落饰品", "inventory", { "position" })
action("swap_active", "交换主动道具", "inventory", {  })
action("coins", "增减金币", "resource", { "amount" })
action("keys", "增减钥匙", "resource", { "amount" })
action("bombs", "增减炸弹", "resource", { "amount" })
action("set_resource", "设置资源数量", "resource", { "resource", "amount" })
action("hearts", "增减生命", "resource", { "heartType", "amount" })
action("heal", "补满红心", "resource", {  })
action("golden_key", "给予或移除金钥匙", "resource", { "mode" })
action("golden_bomb", "给予或移除金炸弹", "resource", { "mode" })
action("special_resource", "调整特殊资源", "resource", { "resource", "amount" })
action("charge", "增减主动充能", "resource", { "amount", "slot" })
action("set_charge", "设置主动充能", "resource", { "amount", "slot" })
action("full_charge", "充满主动", "resource", { "slot" })
action("empty_charge", "清空主动充能", "resource", { "slot" })
action("undo_clear_charge", "抵消清房充能", "resource", {  })
action("player_damage_action", "使玩家受到伤害", "resource", { "value", "flags" })
action("invulnerability", "短时伤害保护", "resource", { "duration" })
action("revive", "复活玩家", "resource", {  }, "room")
action("use_item", "执行主动道具效果", "effect", { "itemId", "slot", "consume" }, "room")
action("use_card_action", "执行卡牌或符文效果", "effect", { "itemId", "slot", "consume" }, "room")
action("use_pill_action", "执行药丸效果", "effect", { "itemId", "subtype", "slot", "consume" }, "room")
action("temporary_collectible", "调整临时道具效果", "effect", { "itemId", "amount" }, "room")
action("temporary_trinket", "调整临时饰品效果", "effect", { "itemId", "amount" }, "room")
action("temporary_null", "调整原版临时效果", "effect", { "itemId", "amount" }, "room")
action("stat", "调整属性", "effect", { "stat", "value", "scope", "duration" })
action("tear_flag", "增加眼泪特性", "effect", { "flag", "scope", "duration" })
action("fire_tear_action", "发射眼泪", "combat", { "amount", "value", "angle", "position" }, "room")
action("fire_bomb", "发射炸弹", "combat", { "amount", "value", "angle", "position" }, "room")
action("fire_brimstone", "发射硫磺火", "combat", { "angle" }, "room")
action("fire_tech", "发射科技激光", "combat", { "angle", "position" }, "room")
action("fire_tech_x", "发射科技 X 激光", "combat", { "angle", "value", "radius", "position" }, "room")
action("fire_knife", "发射刀", "combat", { "angle", "subtype" }, "room")
action("blue_flies", "生成蓝苍蝇", "combat", { "amount", "position" }, "room")
action("blue_spiders", "生成蓝蜘蛛", "combat", { "amount", "position" }, "room")
action("wisp", "生成魂火", "combat", { "amount", "itemId", "position" }, "room")
action("item_wisp", "生成道具魂火", "combat", { "amount", "itemId", "position" }, "room")
action("minisaac", "生成小以撒", "combat", { "amount", "position" }, "room")
action("explosion", "范围爆炸", "combat", { "value", "radius", "position" }, "room")
action("fart", "范围放屁", "combat", { "effectKind", "radius", "position" }, "room")
action("entity_damage_action", "伤害实体", "combat", { "target", "value", "radius", "flags" }, "room")
action("entity_heal", "治疗实体", "combat", { "target", "value", "radius" })
action("entity_kill_action", "杀死实体", "combat", { "target", "radius" }, "room")
action("entity_remove_action", "移除实体", "combat", { "target", "radius" }, "room")
action("entity_morph", "转换实体", "combat", { "target", "entityType", "variant", "subtype", "radius" }, "room")
action("entity_move", "移动实体", "combat", { "target", "position", "radius" }, "room")
action("entity_velocity", "调整实体速度", "combat", { "target", "angle", "value", "radius" }, "room")
action("entity_size", "调整实体大小", "combat", { "target", "value", "radius" })
action("entity_color", "染色实体", "combat", { "target", "red", "green", "blue", "duration", "radius" })
action("entity_status", "施加状态效果", "combat", { "target", "status", "duration", "value", "radius" }, "room")
action("clear_status", "清除状态效果", "combat", { "target", "radius" })
action("entity_flags", "设置实体标记", "combat", { "target", "flag", "mode", "radius" }, "room")
action("pickup_morph", "转换拾取物", "world", { "target", "pickupVariant", "subtype", "radius" }, "room")
action("pickup_price", "设置拾取物价格", "world", { "target", "amount", "radius" })
action("pickup_options", "设置拾取物选择组", "world", { "target", "amount", "radius" })
action("open_chest", "尝试打开箱子", "world", { "target", "radius" }, "room")
action("reroll_collectible", "重掷底座", "world", { "target", "pool", "qualityMin", "qualityMax", "radius" }, "room")
action("reroll_enemy", "重掷敌人", "world", { "target", "radius" }, "room")
action("restock_shop", "商店补货", "world", { "mode" }, "room")
action("respawn_enemies", "重新生成房间敌人", "world", {  }, "room")
action("clear_award", "额外生成清房奖励", "world", {  }, "room")
action("grid_spawn", "生成障碍", "world", { "gridType", "variant", "gridIndex", "subtype" }, "room")
action("grid_destroy", "破坏障碍", "world", { "gridIndex" }, "room")
action("grid_remove", "移除障碍", "world", { "gridIndex" }, "room")
action("grid_damage", "伤害障碍", "world", { "gridIndex", "amount" }, "room")
action("bridge", "尝试填坑搭桥", "world", { "gridIndex" }, "room")
action("door", "操作现有门", "world", { "doorSlot", "mode" }, "room")
action("special_door", "尝试生成特殊入口", "world", { "doorKind" }, "room")
action("red_room", "尝试生成红房门", "world", { "doorSlot" }, "room")
action("map", "揭示地图", "world", { "mode" })
action("curse", "添加或移除诅咒", "world", { "flags", "mode" }, "room")
action("angel_chance", "增加天使房权重", "world", { "value" })
action("room_color", "房间地板或墙壁染色", "world", { "mode", "red", "green", "blue" })
action("room_slow", "设置房间快慢效果", "world", { "mode", "duration" }, "room")
action("sound", "播放音效", "visual", { "itemId", "value" })
action("message", "显示配置提示", "visual", { "message" })
action("shake", "震屏", "visual", { "duration" })
action("darken", "暂时变暗", "visual", { "value", "duration" })
action("animation", "玩家动画", "visual", { "mode" })
action("particles", "生成粒子", "visual", { "variant", "amount", "value", "red", "green", "blue", "position" })
action("rule_switch", "启停指定规则", "control", { "ruleId", "mode" })
action("counter", "调整自定义计数器", "control", { "counterId", "amount", "mode" })
action("teleport", "传送到本层房间", "control", { "roomIndex" }, "room")
action("stage_transition", "进入指定楼层", "control", { "stage", "stageType" }, "room")
action("change_character", "改变角色", "control", { "character" }, "room")

event("entity_changed", "实体类型 / 变体变化", "entity", "状态比较")
event("pickup_selection", "拾取物选择通知", "advanced", "原版回调")
event("player_init", "玩家实体初始化", "entity", "原版回调")
event("native_callback", "原版回调通知 (高级)", "advanced", "原版回调")
C.targets = { { 0, "事件对象" }, { 1, "玩家" }, { 2, "最近敌人" }, { 3, "所有敌人" },
    { 4, "所有拾取物" }, { 5, "所有跟班" }, { 6, "事件碰撞对象" } }
C.positions = { { 0, "房间中心" }, { 1, "玩家位置" }, { 2, "事件位置" }, { 3, "随机空地" } }
C.scopes = { { 0, "当前房间" }, { 1, "当前楼层" }, { 2, "当前局" }, { 3, "指定秒数" } }
C.stats = { { "damage", "伤害" }, { "tears", "每秒眼泪数" }, { "speed", "移速" },
    { "range", "射程" }, { "shotSpeed", "弹速" }, { "luck", "幸运" }, { "flight", "飞行" } }
C.statuses = { { "poison", "中毒" }, { "burn", "燃烧" }, { "slow", "减速" }, { "freeze", "冻结" },
    { "midas", "金化" }, { "fear", "恐惧" }, { "confusion", "混乱" }, { "charm", "魅惑" }, { "shrink", "缩小" } }
C.resources = { { "coins", "金币" }, { "keys", "钥匙" }, { "bombs", "炸弹" },
    { "soulCharge", "魂充能" }, { "bloodCharge", "血充能" }, { "poopMana", "便便魔力" },
    { "jarHearts", "罐中红心" }, { "jarFlies", "罐中苍蝇" }, { "gigaBombs", "巨型炸弹" } }
C.hearts[#C.hearts + 1] = { "eternal", "永恒心" }
C.hearts[#C.hearts + 1] = { "golden", "金心" }
C.hearts[#C.hearts + 1] = { "broken", "碎心" }
local function enumList(source, min, max)
    local result, seen = {}, {}
    for name, id in pairs(source or {}) do
        if type(id) == "number" and id >= min and id <= max and not seen[id]
            and not name:find("^NUM_") then
            seen[id] = true; result[#result + 1] = { id, name }
        end
    end
    table.sort(result, function(a, b) return a[1] < b[1] end)
    return result
end
local function complete(list, source, min, max)
    for _, row in ipairs(enumList(source, min, max)) do
        if not C.contains(list, row[1]) then list[#list + 1] = row end
    end
end
complete(C.rooms, RoomType, 1, 99)
complete(C.pools, ItemPoolType, 0, 30)
complete(C.pickups, PickupVariant, 1, 999)
complete(C.enemies, EntityType, 10, 999)
C.entities = enumList(EntityType, 2, 1000)
C.grids = enumList(GridEntityType, 1, 27)
C.buttons = enumList(ButtonAction, 0, 31)
C.forms = enumList(PlayerForm, 0, 100)
C.chests = {}
for name, id in pairs(PickupVariant or {}) do if name:find("CHEST") then C.chests[id] = true end end
C.flags = {}
for name in pairs(TearFlags or {}) do C.flags[#C.flags + 1] = { name, name } end
for name in pairs(EntityFlag or {}) do C.flags[#C.flags + 1] = { name, name } end
if #C.flags == 0 then C.flags = { { "TEAR_HOMING", "追踪" } } end
table.sort(C.flags, function(a, b) return a[1] < b[1] end)
C.fields = {}
local function field(key, label, default, min, max, list)
    C.fields[key] = { label = label, default = default, min = min, max = max, list = list }
end
field("amount", "数量 / 增减值", 1, -999, 999)
field("value", "数值", 1, -100000, 100000)
field("itemId", "物品 / 效果 ID", 0, 0, 1000000)
field("pool", "随机道具池", 0, nil, nil, C.pools)
field("qualityMin", "最低品质", 0, 0, 4)
field("qualityMax", "最高品质", 4, 0, 4)
field("pickupVariant", "拾取物类型", 20, nil, nil, C.pickups)
field("subtype", "子类型 / 药丸颜色", 1, 0, 1000000)
field("variant", "实体变体 ID", 0, 0, 4095)
field("heartType", "生命类型", "red", nil, nil, C.hearts)
field("slot", "槽位", 0, nil, nil, C.slots)
field("enemyType", "敌人类型", 10, nil, nil, C.enemies)
field("entityType", "实体类型", 10, nil, nil, C.entities)
field("position", "执行位置", 0, nil, nil, C.positions)
field("target", "执行目标", 0, nil, nil, C.targets)
field("scope", "作用范围", 0, nil, nil, C.scopes)
field("stat", "属性", "damage", nil, nil, C.stats)
field("status", "状态效果", "poison", nil, nil, C.statuses)
field("resource", "资源类型", "coins", nil, nil, C.resources)
field("flag", "标记名称", "TEAR_HOMING", nil, nil, C.flags)
field("duration", "持续时间 (秒)", 5, 0.1, 3600)
field("angle", "方向角度", 0, -360, 360)
field("radius", "作用半径 (0 表示不限)", 0, 0, 2000)
field("flags", "原版标记位组合", 0, 0, 2147483647)
field("mode", "模式 (含义见说明)", 0, 0, 4)
field("consume", "消耗持有物 / 充能", 0, 0, 1)
field("effectKind", "放屁类型 (0 普通 / 1 推开 / 2 魅惑)", 0, 0, 2)
field("gridType", "障碍类型", 2, nil, nil, C.grids)
field("gridIndex", "障碍索引 (-1 为事件 / 执行位置)", -1, -1, 1000)
field("doorSlot", "门槽位 (-1 为全部现有门)", -1, -1, 7)
field("doorKind", "入口 (0 恶魔 / 1 Boss Rush / 2 蓝子宫 / 3 撒旦 / 4 支线 / 5 虚空)", 0, 0, 5)
field("red", "红色分量", 1, 0, 4)
field("green", "绿色分量", 1, 0, 4)
field("blue", "蓝色分量", 1, 0, 4)
field("ruleId", "目标规则 ID", 1, 1, 1000000000)
field("counterId", "自定义计数器编号", 1, 1, 100)
field("roomIndex", "目标房间索引", 0, -13, 168)
field("stage", "目标楼层编号", 1, 1, 13)
field("stageType", "目标楼层类型", 0, 0, 5)
field("character", "目标角色 ID", 0, 0, 40)
field("delayFrames", "延迟帧数 (30 帧 = 1 秒)", 0, 0, 108000)
field("repeatCount", "执行次数", 1, 1, 32)
field("repeatFrames", "重复间隔帧数", 30, 1, 108000)
field("message", "提示文字 (控制台可编辑)", "Event Workshop rule executed")
C.filterFields = {
    { "callbackId", "原版回调 ID" }, { "itemId", "事件物品 ID" }, { "entityType", "事件实体类型" }, { "variant", "事件实体变体" },
    { "subtype", "事件实体子类型" }, { "sourceType", "事件来源实体类型" }, { "slot", "事件槽位" },
    { "before", "变化前数值" }, { "after", "变化后数值" }, { "delta", "变化量" },
    { "flags", "事件标记位" }, { "gridType", "障碍类型" }, { "gridIndex", "障碍索引" },
    { "coins", "金币" }, { "keys", "钥匙" }, { "bombs", "炸弹" }, { "red", "红心 (半颗)" },
    { "soul", "魂 / 黑心 (半颗)" }, { "max", "心之容器 (半颗)" }, { "bone", "骨心" },
    { "rotten", "腐心" }, { "eternal", "永恒心" }, { "golden", "金心" }, { "broken", "碎心" },
    { "charge", "主主动总充能" }, { "stage", "楼层编号" }, { "stageType", "楼层类型" },
    { "roomType", "房间类型" }, { "roomShape", "房间形状" }, { "firstVisit", "首次进入 (1 是)" },
    { "clear", "房间已清理 (1 是)" }, { "enemies", "存活敌人数" }, { "bosses", "存活首领数" },
    { "curses", "楼层诅咒位组合" }, { "difficulty", "难度" }, { "greed", "贪婪模式 (1 是)" },
    { "damage", "玩家伤害" }, { "tears", "每秒眼泪数" }, { "speed", "移速" },
    { "range", "射程" }, { "shotSpeed", "弹速" }, { "luck", "幸运" }, { "flight", "飞行 (1 是)" },
    { "collectibleCount", "持有道具总数" }, { "heldCollectible", "指定道具数量" },
    { "heldTrinket", "指定饰品倍数" }, { "form", "指定变身 (1 是)" },
    { "elapsed", "本局时间 (秒)" }, { "roomElapsed", "本房间时间 (秒)" }, { "counter", "自定义计数器值" },
}
C.operators = { { "eq", "等于" }, { "ne", "不等于" }, { "ge", "大于等于" }, { "le", "小于等于" },
    { "gt", "大于" }, { "lt", "小于" }, { "bits", "包含全部标记位" }, { "cross_up", "向上跨过阈值" },
    { "cross_down", "向下跨过阈值" } }
function C.grouped(list, info, group)
    local result = {}
    for _, row in ipairs(list) do if info[row[1]].group == group then result[#result + 1] = row end end
    return result
end
C.presetRules = {
    no_hit_key = { event = "no_hit_clear", actions = { { kind = "keys" } } },
    boss_soul = { event = "boss_kill", actions = { { kind = "hearts", heartType = "soul", amount = 2 } } },
    five_enemies = { event = "enemy_kill", conditions = { every = 5 }, actions = { { kind = "spawn_collectible" } } },
    card_luck = { event = "use_card", actions = { { kind = "stat", stat = "luck", value = 1, scope = 0 } } },
    timed_coin = { event = "timer", conditions = { intervalFrames = 900 }, actions = { { kind = "coins" } } },
    gain_item_bonus = { event = "collectible_gain", actions = { { kind = "give_collectible", itemId = 1 } } },
    hit_slow = { event = "enemy_damage", actions = { { kind = "entity_status", target = 0, status = "slow", value = 0.5, duration = 2 } } },
}
for _, row in ipairs({ { "no_hit_key", "无伤清房给予钥匙" }, { "boss_soul", "首领死亡给予魂心" },
    { "five_enemies", "每 5 个敌人死亡生成底座" }, { "card_luck", "用卡后本房间幸运增加" },
    { "timed_coin", "每 30 秒给予金币" }, { "gain_item_bonus", "获得道具追加伤心洋葱 (防循环示例)" },
    { "hit_slow", "敌人伤害回调后减速" } }) do C.presets[#C.presets + 1] = row end
C.actionHelp = {}
for _, row in ipairs(C.actions) do
    C.actionHelp[row[1]] = "参数范围见当前字段；原版不支持的目标会跳过并记录原因。"
end
local help = {
    door = "模式: 0 打开 / 1 关闭 / 2 尝试解锁 / 3 上锁 / 4 移除现有门。",
    golden_key = "模式: 0 给予 / 其他 移除。", golden_bomb = "模式: 0 给予 / 其他 移除。",
    map = "模式: 0 显示地图 / 1 地图效果 / 2 指南针 / 3 蓝地图 / 4 显示所有。",
    curse = "模式: 0 添加 / 其他 移除；仅原版支持的楼层诅咒。",
    room_color = "模式: 0 地板 / 其他 墙壁；颜色分量 1 为原色。",
    room_slow = "模式: 0 减速 / 其他 加速；到期恢复原来的钟表状态。",
    restock_shop = "模式: 0 全部补货并重掷 / 其他 部分补货。",
    counter = "模式: 0 增减 / 其他 设置；不会另发计数器变化事件。",
    rule_switch = "模式: 0 启用 / 其他 禁用；在下一次事件生效。",
    animation = "模式: 0 开心 / 1 悲伤 / 2 传送动画 / 3 出现 / 4 光束旅行。",
    hearts = "红 / 魂 / 黑 / 容器按半颗；骨 / 腐 / 永恒 / 金 / 碎按各自原版单位。",
    stage_transition = "高级动作: 原生 stage 命令进入指定层，重新生成目标楼层；总开关不执行此动作。",
    change_character = "高级动作: 仅改变角色类型，不自动给予该角色开局资源。",
    temporary_collectible = "只调整原版临时效果，不等于实际持有所有道具功能。",
    use_item = "执行指定效果；原版不可追踪的持续效果在本房间继承因果链。",
    smelt_trinket = "给予指定饰品后执行熔炉；也会熔炼玩家其他当前持有饰品。",
    stat = "数值为加法；飞行正值为开启，非正值为关闭；射速数值为每秒眼泪数增量。",
    spawn_enemy = "敌人类型、变体和子类型需组成有效原版实体；部分首领要求特定房间。",
}
for key, value in pairs(help) do C.actionHelp[key] = value end
C.callbacks = enumList(ModCallbacks, 0, 73)
C.contentGroups = { { "enemies", "敌人类型" }, { "entities", "实体类型" }, { "pickups", "拾取物" },
    { "pools", "道具池" }, { "cards", "卡牌 / 符文" }, { "trinkets", "饰品" }, { "pills", "药丸效果" },
    { "effects", "特效变体" }, { "familiars", "跟班变体" }, { "machines", "机器变体" },
    { "grids", "障碍" }, { "sounds", "音效" }, { "characters", "角色" }, { "flags", "眼泪 / 实体标记" }, { "callbacks", "原版回调编号" } }
C.content = { enemies = C.enemies, entities = C.entities, pickups = C.pickups, pools = C.pools,
    cards = enumList(Card, 1, 100000), trinkets = enumList(TrinketType, 1, 100000),
    pills = enumList(PillEffect, 0, 1000), effects = enumList(EffectVariant, 0, 10000),
    familiars = enumList(FamiliarVariant, 0, 10000), machines = enumList(SlotVariant, 0, 10000),
    grids = C.grids, sounds = enumList(SoundEffect, 0, 10000), characters = enumList(PlayerType, 0, 100000), flags = C.flags, callbacks = C.callbacks }
-- 原版未定义 SlotVariant 枚举，按已核对的原版机器目录补齐数值。
C.content.machines = { { 1, "老虎机" }, { 2, "献血机" }, { 3, "占卜机" }, { 4, "乞丐" },
    { 5, "恶魔乞丐" }, { 6, "贝壳游戏" }, { 7, "钥匙乞丐" }, { 8, "捐款机" }, { 9, "炸弹乞丐" },
    { 10, "补货机" }, { 11, "贪婪捐款机" }, { 12, "梳妆台" }, { 13, "电池乞丐" },
    { 14, "以撒秘密" }, { 15, "地狱游戏" }, { 16, "抓娃娃机" }, { 17, "忏悔室" }, { 18, "腐烂乞丐" } }
C.contentFields = { enemies = "enemyType", entities = "entityType", pickups = "pickupVariant", pools = "pool",
    cards = "itemId", trinkets = "itemId", pills = "itemId", effects = "variant", familiars = "variant",
    machines = "variant", grids = "gridType", sounds = "itemId", characters = "character", flags = "flag", callbacks = "flags" }
return C
