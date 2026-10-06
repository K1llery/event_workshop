return function(C, S, E, A, T, M, json, selftest)
    local K = {}
    local function out(message) Isaac.ConsoleOutput("[事件工坊] " .. tostring(message) .. "\n") end
    local function selected(id)
        id = tonumber(id)
        for i, rule in ipairs(T:profile().rules) do
            if rule.id == id then T.selectedRule, T.selectedAction = i, 1; return rule end
        end
        error("当前方案没有此规则 ID；ew list 查看列表")
    end
    local function split(input)
        local words = {}
        for word in input:gmatch("%S+") do words[#words + 1] = word end
        return words
    end
    local function integer(value)
        local n = tonumber(value)
        if not n or n ~= math.floor(n) or n == math.huge or n == -math.huge then error("请输入整数") end
        return n
    end
    local function itemID(value)
        if tonumber(value) then return integer(value) end
        local matches = A.searchItems(value)
        if #matches == 1 then return matches[1] end
        error("道具名称匹配 " .. #matches .. " 项；使用 ew search 后填写道具 ID")
    end
    function K.run(args)
        local command, rest = args:match("^%s*(%S+)%s*(.-)%s*$")
        command = command and command:lower() or "help"
        local w = split(rest or "")
        if command == "help" then
            out([[ew on | off | status | list
ew new [事件名称] | preset <预设名称> | select <规则ID>
ew enable <规则ID> on|off | rename <规则ID> <名称>
ew event <规则ID> <事件> | copy <规则ID> | delete <规则ID>
ew condition <规则ID> <字段> <整数>
ew addaction <规则ID> <动作类型> | delaction <规则ID> <序号>
ew action <规则ID> <序号> <字段> <值>
ew search <道具名称或ID> | characters
ew profile list|new|copy|delete|select <序号>|rename <名称>
ew export | import <JSON> | selftest
事件：room_clear new_room new_level run_start player_damage enemy_kill use_active
动作：spawn_collectible spawn_pickup give_collectible coins keys bombs hearts charge spawn_enemy undo_clear_charge
条件：chance every roomType character collectible maxRoom maxFloor maxRun
预设：clear_pedestal no_clear_charge start_coins damage_coin
示例：ew preset clear_pedestal → ew list → ew enable 3 on → ew on
详细字段和限制见项目 docs/使用说明.md。]])
        elseif command == "status" then
            out("方案：" .. T:profile().name .. "；规则数：" .. #T:profile().rules)
            out(E.ready and E.run and ("总开关：" .. tostring(E.run.master)
                .. "；种子：" .. Game():GetSeeds():GetStartSeedString()
                .. "；本局开局事件已补触发：" .. tostring(E.run.startedFired)) or "尚未进入游戏")
            out(T.status)
        elseif command == "on" or command == "off" then
            T:setMaster(command == "on"); out(T.status)
        elseif command == "list" then
            for i, r in ipairs(T:profile().rules) do
                out(i .. ". ID=" .. r.id .. " [" .. (r.enabled and "开启" or "关闭") .. "] "
                    .. r.name .. " | " .. r.event .. " | 动作数=" .. #r.actions)
            end
        elseif command == "new" then
            if w[1] and not C.contains(C.events, w[1]) then error("未知事件，ew help 查看列表") end
            if not T:newRule() then out(T.status); return end
            if w[1] then T:rule().event = w[1]; T:changed() end
            out("当前规则 ID=" .. T:rule().id .. "；默认禁用")
        elseif command == "preset" then
            if not C.contains(C.presets, w[1]) then error("未知预设，ew help 查看列表") end
            T:newRule(w[1]); out(T.status)
        elseif command == "select" then
            out("已选择：" .. selected(w[1]).name)
        elseif command == "enable" then
            if w[2] ~= "on" and w[2] ~= "off" then error("使用 on 或 off") end
            selected(w[1]).enabled = w[2] == "on"; T:changed(); out(T.status)
        elseif command == "rename" then
            local id, name = rest:match("^(%d+)%s+(.+)$")
            if not name then error("ew rename <规则ID> <名称>") end
            local r = selected(id)
            r.name = S.rule({ name = name }, r.id).name
            T:changed(); out(T.status)
        elseif command == "event" then
            if not C.contains(C.events, w[2]) then error("未知事件") end
            selected(w[1]).event = w[2]; T:changed(); out(T.status)
        elseif command == "copy" then
            selected(w[1]); T:copyRule(); out(T.status)
        elseif command == "delete" then
            selected(w[1]); T:deleteRule(); out(T.status)
        elseif command == "condition" then
            local r = selected(w[1])
            if r.conditions[w[2]] == nil then error("未知条件字段") end
            local n = integer(w[3])
            local copy = S.copy(r.conditions); copy[w[2]] = n
            local normalized = S.conditions(copy)
            if normalized[w[2]] ~= n then error("条件值超出范围，见使用说明") end
            r.conditions = normalized; T:changed(); out(T.status)
        elseif command == "addaction" then
            selected(w[1])
            if not C.contains(C.actions, w[2]) then error("未知动作类型") end
            local count = #T:rule().actions
            T:addAction()
            if #T:rule().actions > count then T:action().kind = w[2]; T:changed() end
            out(T.status)
        elseif command == "delaction" then
            local r = selected(w[1]); local n = integer(w[2])
            if n < 1 or n > #r.actions then error("动作序号不存在") end
            T.selectedAction = n; T:deleteAction(); out(T.status)
        elseif command == "action" then
            local r = selected(w[1]); local n = integer(w[2])
            if n < 1 or n > #r.actions then error("动作序号不存在") end
            local key, value = w[3], rest:match("^%S+%s+%S+%s+%S+%s+(.+)$")
            if not key or r.actions[n][key] == nil or not value then error("ew action <ID> <序号> <字段> <值>") end
            if key == "kind" or key == "heartType" then
                if not C.contains(key == "kind" and C.actions or C.hearts, value) then error("未知选项") end
            else value = key == "itemId" and itemID(value) or integer(value) end
            local action = S.copy(r.actions[n]); action[key] = value
            local normalized = S.action(action)
            if normalized[key] ~= value then error("动作值超出范围，见使用说明") end
            r.actions[n] = normalized; T.selectedAction = n; T:changed(); out(T.status)
        elseif command == "search" then
            M:search(rest)
            out("找到 " .. #M.results .. " 项；全部结果可在 MCM 道具页面浏览")
            for i = 1, math.min(30, #M.results) do
                local id = M.results[i]; out("#" .. id .. " " .. A.itemName(id))
            end
        elseif command == "characters" then
            local entries = {}
            for name, id in pairs(PlayerType) do
                if type(id) == "number" and name:find("^PLAYER_") then entries[#entries + 1] = { id, name } end
            end
            table.sort(entries, function(a, b) return a[1] < b[1] end)
            for _, entry in ipairs(entries) do out(entry[1] .. " " .. entry[2]) end
        elseif command == "profile" then
            local sub, name = rest:match("^(%S+)%s*(.-)$")
            if sub == "list" then
                for i, p in ipairs(E.config.profiles) do out(i .. ". " .. p.name) end
            elseif sub == "new" or sub == "copy" then T:newProfile(sub == "copy"); out(T.status)
            elseif sub == "delete" then T:deleteProfile(); out(T.status)
            elseif sub == "select" then
                local index = integer(w[2])
                if not E.config.profiles[index] then error("方案序号不存在") end
                T:switchProfile(index); out(T.status)
            elseif sub == "rename" and name ~= "" then
                local copy = S.copy(E.config); S.profile(copy).name = name
                T:profile().name = S.profile(S.config(copy)).name
                T:changed(); out(T.status)
            else error("ew profile list|new|copy|delete|select <序号>|rename <名称>") end
        elseif command == "export" then
            local output = json.encode(E.config)
            Isaac.ConsoleOutput(output .. "\n"); A.log("EXPORT " .. output)
        elseif command == "import" then
            local data = json.decode(rest)
            local ok, err = T:import(data)
            if not ok then error(err) end
            out(T.status); M:search(M.query)
        elseif command == "selftest" then
            out("纯逻辑自检通过：" .. selftest() .. " 项；未修改当前局、配置或种子")
        else error("未知命令；ew help 查看帮助") end
    end
    function K.callback(_, command, args)
        if command:lower() ~= "ew" then return end
        local ok, err = pcall(K.run, args or "")
        if not ok then out("错误：" .. tostring(err)) end
    end
    return K
end
