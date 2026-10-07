-- 原生控制台仅输出 ASCII；MCM 与日志保留原始中文和配置数据。
local X = {}
local statuses = {
    ["配置已保存；新局需手动启用"] = "Configuration saved; enable the master switch in each new run.",
    ["配置已保存"] = "Configuration saved.",
    ["本局已启用"] = "Master switch ON for this run.", ["本局已停用"] = "Master switch OFF for this run.",
    ["第一版仅支持单人游戏"] = "Single-player only.", ["请先进入一局单人游戏"] = "Enter a single-player run first.",
    ["规则已添加，默认禁用"] = "Rule added; disabled by default.",
    ["每套方案最多 100 条规则"] = "Each profile supports at most 100 rules.",
    ["规则数量达到上限"] = "Rule limit reached.", ["已复制规则，副本默认禁用"] = "Rule copied; copy is disabled.",
    ["已删除规则"] = "Rule deleted.", ["动作已添加"] = "Action added.",
    ["每条规则最多 20 个动作"] = "Each rule supports at most 20 actions.",
    ["至少保留一个动作"] = "Keep at least one action.", ["动作已删除"] = "Action deleted.",
    ["动作顺序已调整"] = "Action order changed.", ["最多 20 套方案"] = "At most 20 profiles.",
    ["方案已添加；总开关已关闭"] = "Profile added; master switch OFF.",
    ["方案已切换；请手动打开总开关"] = "Profile selected; enable the master switch manually.",
    ["至少保留一套方案"] = "Keep at least one profile.",
    ["配置已导入；总开关已关闭"] = "Configuration imported; master switch OFF.",
    ["存档版本较新，当前版本停止写入"] = "Save format is newer; writes disabled.",
    ["存档版本较新，未写入配置"] = "Save format is newer; configuration was not written.",
    ["保存失败，请查看游戏日志"] = "Save failed; see log.txt.",
    ["存档格式损坏，已载入默认配置"] = "Invalid save; defaults loaded.",
    ["存档损坏，默认配置暂未写入；手动编辑后保存"] = "Invalid save; edit manually before saving defaults.",
    ["已继续本局，恢复总开关状态"] = "Run continued; master switch restored.",
    ["新一局: 请手动打开本局总开关"] = "New run; enable the master switch manually.",
}
local fragments = {
    { "请输入版本 1 或 2 的配置 JSON，包含 1–20 套方案", "Use schema version 1 or 2 JSON with 1-20 profiles" },
    { "每套方案必须包含规则列表，最多 100 条", "Each profile needs a rules array with at most 100 rules" },
    { "规则含未知事件或无效动作列表", "Unknown event or invalid action list" },
    { "条件必须为对象", "Conditions must be an object" },
    { "条件字段或数值无效：", "Invalid condition field or value: " },
    { "最多 20 个扩展条件", "At most 20 filters" },
    { "扩展条件必须为对象", "Filter must be an object" },
    { "扩展条件字段无效：", "Invalid filter field: " },
    { "配置含未知动作", "Configuration contains an unknown action" },
    { "动作字段或数值无效：", "Invalid action field or value: " },
    { "道具 ID 无效或为隐藏道具：", "Collectible ID invalid or hidden: " },
    { "在 64 次抽取内未找到满足品质的道具，跳过此次生成", "No quality match after 64 attempts; spawn skipped" },
    { "掉落物子类型超出原版范围", "Pickup subtype out of range" },
    { "饰品 ID 无效", "Trinket ID invalid" },
    { "生成实体不支持直接创建玩家", "Direct player spawning is unsupported" },
    { "敌人子类型超出原版定义范围", "NPC subtype out of range" },
    { "事件对象已不存在或此事件没有实体对象", "Event entity is missing or no longer exists" },
    { "碰撞对象已不存在", "Collider no longer exists" },
    { "此动作需要指定非零物品 ID", "This action requires a nonzero item ID" },
    { "实体大小必须大于 0", "Entity size must be positive" },
    { "请选择 FLAG_ 开头的实体标记", "Select an EntityFlag starting with FLAG_" },
    { "实体转换需要敌人对象", "Morph requires an NPC" },
    { "需要拾取物对象", "Pickup target required" },
    { "游戏结束 / 退出事件仅支持提示、计数器和规则启停", "Game end / exit supports messages, counters and rule switches only" },
    { "此槽位没有可调整充能的主动道具", "Slot has no chargeable active item" },
    { "障碍索引超出当前房间", "Grid index outside the current room" },
    { "墙和房门请使用现有门操作，不能安全生成", "Use existing door operations; walls / doors cannot be safely spawned" },
    { "障碍生成失败", "Grid spawn failed" },
    { "此处没有可填的坑", "No pit at this position" },
    { "当前房间不满足该入口的生成条件", "Room does not allow this special door" },
    { "红房门必须指定门槽位", "Red room requires a door slot" },
    { "此处无法生成红房门", "Red room door cannot be created here" },
    { "指定规则 ID 不在当前方案", "Rule ID not in current profile" },
    { "目标房间不存在", "Target room does not exist" },
    { "楼层类型 3 已被原版废弃", "Stage type 3 is deprecated" },
    { "支线楼层类型仅适用于 1–8 层", "Alternate stage types require stages 1-8" },
    { "未实现的动作: ", "Unsupported action: " },
    { "玩家对象已不存在", "Player no longer exists" },
    { "事件工坊规则已执行", "Event Workshop rule executed" },
    { "跳过: 同一因果链已经执行", "skipped: already executed in this causal chain" },
    { "未执行: 条件不满足", "skipped: conditions not met" },
    { "因果链达到 32 条规则上限", "Causal chain limit reached (32 rules)" },
    { "当前房间实体达到 512，跳过生成", "Room entity limit reached (512); spawn skipped" },
    { "本帧原版操作 / 生成数量达到限流上限", "Native operation / spawn limit reached this frame" },
    { "事件队列达到上限，跳过: ", "Event queue full; skipped: " },
    { "延迟动作队列已满，跳过", "Delayed action queue full; skipped" },
    { "延迟动作取消: 已离开事件房间", "delayed action cancelled: left the event room" },
    { "限流: 本帧", "Rate limit this frame: " }, { "达到上限", " limit reached" },
    { "动作超出范围", "Action out of range" }, { "原版接口不可用: ", "Native API unavailable: " },
    { "成功", "OK" }, { "失败: ", "failed: " }, { "卡牌 ID 无效", "Card ID invalid" },
    { "药丸颜色 ID 无效", "Pill color ID invalid" }, { "药丸效果 ID 无效", "Pill effect ID invalid" },
    { "物品 ID 无效: ", "Item ID invalid: " },
}
function X.text(value)
    local text = tostring(value)
    text = statuses[text] or text
    text = text:gsub("自检通过：(%d+) 项", "Self-test passed: %1 checks")
    text = text:gsub("自检失败：", "Self-test FAILED: ")
    text = text:gsub("搜索结果：(%d+) 个道具", "Search results: %1 items")
    text = text:gsub("已导出；使用 lua EW%(%[%[import JSON%]%]%) 导入", "Export complete; use lua EW([[import JSON]])")
    for _, pair in ipairs(fragments) do text = text:gsub(pair[1], function() return pair[2] end) end
    return (text:gsub("[\128-\255]+", "[non-ASCII text; see log.txt]"))
end
function X.name(value, fallback)
    value = tostring(value)
    return value:find("[\128-\255]") and fallback or value
end
function X.json(value)
    local output = {}
    for _, code in utf8.codes(value) do
        if code <= 127 then output[#output + 1] = string.char(code)
        elseif code <= 65535 then output[#output + 1] = string.format("\\u%04x", code)
        else
            local n = code - 65536
            output[#output + 1] = string.format("\\u%04x\\u%04x", 55296 + math.floor(n / 1024), 56320 + n % 1024)
        end
    end
    return table.concat(output)
end
function X.decode(value, json)
    -- 原版 JSON 解码器将代理对分别编码为 CESU-8，修复导出的补充平面字符。
    local function repair(node)
        if type(node) == "string" then
            return (node:gsub("\237([\160-\175])([\128-\191])\237([\176-\191])([\128-\191])", function(a, b, c, d)
                local high = (a:byte() - 160) * 64 + b:byte() - 128
                local low = (c:byte() - 176) * 64 + d:byte() - 128
                return utf8.char(65536 + high * 1024 + low)
            end))
        elseif type(node) == "table" then
            local result = {}
            for key, item in pairs(node) do result[repair(key)] = repair(item) end
            return result
        end
        return node
    end
    return repair(json.decode(value))
end
X.machines = { "Slot Machine", "Blood Donation Machine", "Fortune Telling Machine", "Beggar", "Devil Beggar",
    "Shell Game", "Key Master", "Donation Machine", "Bomb Bum", "Shop Restock Machine", "Greed Donation Machine",
    "Mom's Dressing Table", "Battery Bum", "Isaac's Secret", "Hell Game", "Crane Game", "Confessional", "Rotten Beggar" }
return X
