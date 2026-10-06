local C = {}
C.events = {
    { "room_clear", "清理房间" }, { "new_room", "进入房间" },
    { "new_level", "进入新楼层" }, { "run_start", "开局（首次启用时）" },
    { "player_damage", "玩家受伤回调" }, { "enemy_kill", "击杀敌人" },
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
return C
