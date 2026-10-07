return function(C, S, E, A, T, json, selftest)
    local M = { installed = nil, query = "", results = {}, resultIndex = 1, charIndex = 1, presetIndex = 1, parameterIndex = 1, filterIndex = 1,
        conditionParameter = 1, contentGroup = "enemies", contentIndex = 1 }
    local category = "事件工坊 Event Workshop"
    local alphabet = "abcdefghijklmnopqrstuvwxyz0123456789 -_'"
    -- MCM 中文字体缺少全角标点；仅转换显示文本，不修改玩家保存的名称。
    local function ui(value)
        if type(value) == "function" then
            return function(...) return ui(value(...)) end
        elseif type(value) == "table" then
            local lines = {}
            for i, line in ipairs(value) do lines[i] = ui(line) end
            return lines
        elseif type(value) ~= "string" then return value end
        for _, pair in ipairs({
            { "：", ": " }, { "（", " (" }, { "）", ")" },
            { "，", ", " }, { "；", "; " }, { "。", "." }, { "？", "?" },
            { "“", '"' }, { "”", '"' }, { "、", " / " }, { "→", " -> " },
        }) do value = value:gsub(pair[1], pair[2]) end
        return value
    end
    local function selectedRule() return T:rule() end
    local function selectedAction() return T:action() end
    function M:search(query)
        self.query = tostring(query or "")
        self.results = A.searchItems(self.query)
        self.resultIndex = 1
        T.status = "搜索结果：" .. #self.results .. " 个道具"
    end
    function M:install()
        local mcm = ModConfigMenu
        if not mcm or type(mcm.AddSetting) ~= "function" or self.installed == mcm then return end
        if mcm.RemoveCategory then mcm.RemoveCategory(category) end
        local types = mcm.OptionType
        if not types then return end
        local function text(tab, value)
            mcm.AddText(category, tab, ui(value))
        end
        local function space(tab)
            if mcm.AddSpace then mcm.AddSpace(category, tab) end
        end
        local function setting(tab, options)
            options.Display, options.Info, options.Popup = ui(options.Display), ui(options.Info), ui(options.Popup)
            mcm.AddSetting(category, tab, options)
        end
        local function button(tab, label, fn, info, confirmation)
            setting(tab, {
                Type = types.TEXT, Display = label, OnSelect = fn, Info = info,
                Popup = confirmation,
            })
        end
        local function boolean(tab, label, get, set, info)
            setting(tab, {
                Type = types.BOOLEAN, CurrentSetting = function() return get() == true end,
                Display = function() return label .. "：" .. (get() and "开启" or "关闭") end,
                OnChange = set, Info = info,
            })
        end
        local function number(tab, label, get, set, min, max, info, display)
            local options = { Type = types.NUMBER, Minimum = min, Maximum = 1, Info = info }
            options.CurrentSetting = function()
                options.Minimum = type(min) == "function" and min() or min
                options.Maximum = math.max(options.Minimum, type(max) == "function" and max() or max)
                return math.max(options.Minimum, math.min(options.Maximum, get() or options.Minimum))
            end
            options.Display = display or function() return label .. "：" .. tostring(get() or min) end
            options.OnChange = set
            setting(tab, options)
            return options
        end
        local function choice(tab, label, list, get, set, info)
            local function rows() return type(list) == "function" and list() or list end
            number(tab, label, function() return C.index(rows(), get()) end,
                function(n) local row = rows()[n]; if row then set(row[1]) end end, 1, function() return #rows() end, info,
                function() return label .. "：" .. C.label(rows(), get()) end)
        end
        local function ruleField(key, value)
            local rule = selectedRule()
            if rule then rule[key] = value; T:changed() end
        end
        local function conditionField(key, value)
            local rule = selectedRule()
            if rule then rule.conditions[key] = value; T:changed() end
        end
        local function actionField(key, value)
            local action = selectedAction()
            if action then action[key] = value; T:changed() end
        end
        local function profileIndex()
            for i, p in ipairs(E.config.profiles) do if p.id == E.config.activeProfileId then return i end end
            return 1
        end
        text("运行", "事件工坊 " .. C.version .. " · 单人")
        space("运行")
        boolean("运行", "本局运行规则", function() return E.ready and E.run and E.run.master end,
            function(value) T:setMaster(value) end,
            { "新局 / R 重开自动关闭；继续游戏保留状态。",
                "首次开启执行一次开局规则；不会重开、切换种子或重置房间。" })
        text("运行", function() return "状态：" .. T.status end)
        text("运行", function()
            if not E.ready or not E.run then return "请进入单人游戏后启用" end
            return "本局种子：" .. Game():GetSeeds():GetStartSeedString()
        end)
        space("运行")
        number("运行", "当前方案", profileIndex, function(i) T:switchProfile(i) end,
            1, function() return #E.config.profiles end,
            { "切换方案会关闭总开关，需要手动启用。", "开局事件每局只补触发一次，切换方案不会重复。" },
            function() return "当前方案：" .. T:profile().name end)
        button("运行", "新建空方案", function() T:newProfile(false) end)
        button("运行", "复制当前方案", function() T:newProfile(true) end)
        button("运行", "删除当前方案", function() T:deleteProfile() end, nil,
            "确定删除当前方案？$newline$按确认键删除，返回键取消。")
        space("运行")
        button("运行", "运行自检（不改变本局）", function()
            local ok, result = pcall(selftest)
            T.status = ok and ("自检通过：" .. tostring(result) .. " 项") or ("自检失败：" .. tostring(result))
            A.writeConsole(ok and ("Self-test passed: " .. tostring(result) .. " checks.") or "Self-test FAILED; see log.txt.")
            A.log(T.status)
        end, "只测试隔离的规则逻辑，不修改当前局、种子、资源或配置。")

        number("规则", "选择规则", function() return T.selectedRule end,
            function(n) T.selectedRule, T.selectedAction = n, 1 end,
            1, function() return #T:profile().rules end, "在条件和动作页面编辑当前选中规则。",
            function()
                local rule = selectedRule()
                return rule and ("规则 " .. T.selectedRule .. "/" .. #T:profile().rules .. "：" .. rule.name) or "暂无规则，请先添加"
            end)
        text("规则", function() local r = selectedRule(); return r and ("规则 ID：" .. r.id) or "" end)
        boolean("规则", "启用此规则", function() local r = selectedRule(); return r and r.enabled end,
            function(v) ruleField("enabled", v) end, "规则已启用且本局总开关开启时才会执行。")
        space("规则")
        button("规则", "添加空规则", function() T:newRule() end)
        button("规则", "复制当前规则", function() T:copyRule() end)
        button("规则", "删除当前规则", function() T:deleteRule() end, nil,
            "确定删除当前规则？$newline$按确认键删除，返回键取消。")
        space("规则")
        text("规则", "重命名：控制台 lua EW('rename ID 名称')")
        text("规则", function()
            local r = selectedRule()
            return r and (C.label(C.events, r.event) .. " -> " .. C.label(C.actions, r.actions[1].kind)
                .. (#r.actions > 1 and (" 等 " .. #r.actions .. " 个动作") or "")) or ""
        end)

        text("条件", function() local r = selectedRule(); return r and ("当前规则：" .. r.name) or "请先添加规则" end)
        choice("条件", "事件分类", C.eventGroups,
            function() local r = selectedRule(); return r and C.eventInfo[r.event].group or "progress" end,
            function(v) local list = C.grouped(C.events, C.eventInfo, v); ruleField("event", list[1][1]) end)
        choice("条件", "触发事件", function()
            local r = selectedRule(); return C.grouped(C.events, C.eventInfo, r and C.eventInfo[r.event].group or "progress")
        end, function() local r = selectedRule(); return r and r.event end,
            function(v) ruleField("event", v) end, "先选择事件，再设置下面的筛选条件。")
        space("条件")
        text("条件", function() local r = selectedRule(); return r and ("检测方式: " .. C.eventInfo[r.event].detection) or "" end)
        choice("条件", "筛选组合", { { 0, "全部满足" }, { 1, "任一满足" } },
            function() local r = selectedRule(); return r and r.conditions.matchMode or 0 end,
            function(v) conditionField("matchMode", v) end,
            "组合房间、角色、持有道具和扩展筛选；概率、间隔、冷却和次数上限始终必须满足。")
        local function conditionNumber(key, label, min, max, info, display)
            number("条件", label, function() local r = selectedRule(); return r and r.conditions[key] or min end,
                function(v) conditionField(key, v) end, min, max, info, display)
        end
        conditionNumber("chance", "执行概率", 0, 100, "0% 不执行，100% 必定执行；仍需满足其他条件。",
            function() local r = selectedRule(); return "执行概率：" .. (r and r.conditions.chance or 0) .. "%" end)
        conditionNumber("every", "执行间隔", 1, 999,
            { "只累计满足房间、角色和持有道具条件的事件。",
                "例如设为 3，在第 3、6、9 次再检查概率和次数上限。" },
            function() local r = selectedRule(); return "每 " .. (r and r.conditions.every or 1) .. " 次符合条件时执行" end)
        space("条件")
        choice("条件", "房间类型", C.rooms, function() local r = selectedRule(); return r and r.conditions.roomType or -1 end,
            function(v) conditionField("roomType", v) end)
        conditionNumber("character", "角色 ID", -1, 1000000,
            "设为 -1 表示不限角色；lua EW('characters') 查看原版角色 ID。",
            function() local r = selectedRule(); local id = r and r.conditions.character or -1
                return "角色 ID：" .. (id == -1 and "不限" or tostring(id)) end)
        conditionNumber("collectible", "持有道具 ID", 0, function() return A.maxItemId end,
            "设为 0 表示不限；道具页面搜索后选择“用于持有条件”。",
            function() local r = selectedRule(); local id = r and r.conditions.collectible or 0
                return "持有道具 ID：" .. (id == 0 and "不限" or tostring(id)) end)
        text("条件", function()
            local r = selectedRule()
            return "持有：" .. A.itemName(r and r.conditions.collectible or 0)
        end)
        space("条件")
        local function limit(key, label, info)
            conditionNumber(key, label, 0, 999, info, function()
                local r = selectedRule(); local n = r and r.conditions[key] or 0
                return label .. "：" .. (n == 0 and "不限" or (n .. " 次"))
            end)
        end
        limit("maxRoom", "每房间上限", "0 表示不限；离开再进入同一个房间不会重置次数。")
        limit("maxFloor", "每层上限", "0 表示不限；进入下一层重新计数。")
        limit("maxRun", "每局上限", "0 表示不限；开关、继续游戏都不会清空次数，新局重新计数。")

        conditionNumber("cooldownFrames", "冷却帧数 (30 帧 = 1 秒)", 0, 108000)
        conditionNumber("intervalFrames", "定时 / 持续条件帧数", 1, 108000, "仅时间分类事件使用，30 帧 = 1 秒。")
        choice("条件", "监听游戏操作", C.buttons, function() local r = selectedRule(); return r and r.conditions.inputAction or 0 end,
            function(v) conditionField("inputAction", v) end, "仅按下 / 松开事件使用。")
        local function filter() local r = selectedRule(); return r and r.filters[math.min(self.filterIndex, #r.filters)] end
        local function changeFilter(key, value) local f = filter(); if f then f[key] = value; T:changed() end end
        space("条件")
        number("条件", "选择扩展筛选", function() return self.filterIndex end, function(v) self.filterIndex = v end,
            1, function() local r = selectedRule(); return r and #r.filters or 1 end, nil,
            function() local r = selectedRule(); return "扩展筛选: " .. self.filterIndex .. "/" .. (r and #r.filters or 0) end)
        choice("条件", "筛选数值", C.filterFields, function() local f = filter(); return f and f.field or "coins" end,
            function(v) changeFilter("field", v) end)
        choice("条件", "比较方式", C.operators, function() local f = filter(); return f and f.op or "ge" end,
            function(v) changeFilter("op", v) end)
        local fv = number("条件", "阈值", function() local f = filter(); return f and f.value or 0 end,
            function(v) changeFilter("value", v) end, -1000000000, 1000000000)
        fv.ModifyBy = 0.1
        number("条件", "筛选参数 ID", function() local f = filter(); return f and f.argument or 1 end,
            function(v) changeFilter("argument", v) end, 0, 1000000,
            "指定道具数量、饰品倍数、变身、自定义计数器筛选使用的 ID；其他筛选忽略。")
        boolean("条件", "此项取反", function() local f = filter(); return f and f.negate end,
            function(v) changeFilter("negate", v) end)
        button("条件", "添加扩展筛选", function()
            local r = selectedRule(); if r and #r.filters < 20 then r.filters[#r.filters + 1] = S.filter(); self.filterIndex = #r.filters; T:changed() end
        end)
        button("条件", "删除扩展筛选", function()
            local r = selectedRule(); if r and #r.filters > 0 then table.remove(r.filters, math.min(self.filterIndex, #r.filters)); self.filterIndex = 1; T:changed() end
        end)

        text("动作", "选中动作后选择参数，界面只提供该动作的字段")
        number("动作", "选择动作", function() return T.selectedAction end,
            function(n) T.selectedAction, self.parameterIndex = n, 1 end,
            1, function() local r = selectedRule(); return r and #r.actions or 1 end, nil,
            function()
                local a, r = selectedAction(), selectedRule()
                return a and ("动作 " .. T.selectedAction .. "/" .. #r.actions .. "：" .. C.label(C.actions, a.kind)) or "请先添加规则"
            end)
        choice("动作", "动作分类", C.actionGroups,
            function() local a = selectedAction(); return a and C.actionInfo[a.kind].group or "spawn" end,
            function(v) local list = C.grouped(C.actions, C.actionInfo, v); actionField("kind", list[1][1]); self.parameterIndex = 1 end)
        choice("动作", "动作类型", function()
            local a = selectedAction(); return C.grouped(C.actions, C.actionInfo, a and C.actionInfo[a.kind].group or "spawn")
        end, function() local a = selectedAction(); return a and a.kind end,
            function(v) actionField("kind", v); self.parameterIndex = 1 end)
        text("动作", function()
            local a = selectedAction()
            return a and C.actionHelp[a.kind] or ""
        end)
        choice("动作", "动作执行方式", { { 0, "依次执行全部" }, { 1, "随机选择一个" } },
            function() local r = selectedRule(); return r and r.conditions.randomAction or 0 end,
            function(v) conditionField("randomAction", v) end)
        local function fields()
            local a, result = selectedAction(), {}
            for _, key in ipairs(a and C.actionInfo[a.kind].fields or {}) do result[#result + 1] = key end
            for _, key in ipairs({ "delayFrames", "repeatCount", "repeatFrames" }) do result[#result + 1] = key end
            return result
        end
        local function fieldKey()
            local list = fields(); self.parameterIndex = math.min(self.parameterIndex, #list); return list[self.parameterIndex]
        end
        space("动作")
        number("动作", "选择参数", function() return self.parameterIndex end, function(v) self.parameterIndex = v end,
            1, function() return #fields() end, nil,
            function() local key = fieldKey(); return "参数 " .. self.parameterIndex .. "/" .. #fields() .. ": " .. C.fields[key].label end)
        local parameterOptions
        parameterOptions = number("动作", "参数值", function()
            local key, a = fieldKey(), selectedAction()
            local f = C.fields[key]
            if parameterOptions then parameterOptions.ModifyBy = (key == "value" or key == "duration" or key == "red" or key == "green" or key == "blue") and 0.1 or 1 end
            if f.list then return C.index(f.list, a and a[key] or f.default) end
            if key == "message" then return 0 end
            return a and a[key] or f.default
        end, function(value)
            local key, f = fieldKey(), C.fields[fieldKey()]
            if f.list then value = f.list[value][1] elseif key == "message" then return end
            actionField(key, value)
        end, function() local f = C.fields[fieldKey()]; return f.list and 1 or f.min or 0 end,
            function() local f = C.fields[fieldKey()]; return f.list and #f.list or f.max or 0 end,
            "选择参数后左右键修改；小数步长 0.1。提示文字使用 lua EW('action ID 序号 message 文字') 编辑。",
            function()
                local key, a = fieldKey(), selectedAction(); local f = C.fields[key]
                local value = a and a[key] or f.default
                return f.label .. ": " .. (f.list and C.label(f.list, value) or tostring(value))
            end)
        text("动作", function()
            local a = selectedAction()
            return a and a.itemId > 0 and ("物品字段 ID: " .. a.itemId) or ""
        end)
        space("动作")
        button("动作", "添加动作", function() T:addAction(); self.parameterIndex = 1 end)
        button("动作", "当前动作上移", function() T:moveAction(-1) end)
        button("动作", "当前动作下移", function() T:moveAction(1) end)
        button("动作", "删除当前动作", function() T:deleteAction(); self.parameterIndex = 1 end, nil,
            "确定删除当前动作？$newline$至少保留一个动作。")

        text("记录", "规则连锁允许；同一链中每条规则最多执行一次")
        text("记录", "每帧最多 128 个事件 / 256 个动作；每链最多 32 条规则")
        for index = 1, 12 do
            local offset = index
            text("记录", function() return E.history[math.max(0, #E.history - 12) + offset] or "" end)
        end
        button("记录", "清空显示记录", function() E.history = {} end)

        choice("目录", "内容分类", C.contentGroups, function() return self.contentGroup end,
            function(v) self.contentGroup, self.contentIndex = v, 1 end)
        number("目录", "浏览内容", function() return self.contentIndex end, function(v) self.contentIndex = v end,
            1, function() return #C.content[self.contentGroup] end, nil,
            function() local row = C.content[self.contentGroup][self.contentIndex]; return row and ("#" .. row[1] .. " " .. row[2]) or "无内容" end)
        button("目录", function() return self.contentGroup == "callbacks" and "用于当前规则的原版通知筛选" or "用于当前动作的对应字段" end, function()
            local row = C.content[self.contentGroup][self.contentIndex]
            if row and self.contentGroup == "callbacks" then
                local r = selectedRule()
                if r and #r.filters < 20 then
                    r.event = "native_callback"
                    r.filters[#r.filters + 1] = S.filter({ field = "callbackId", op = "eq", value = row[1] })
                    T:changed()
                end
            elseif row then actionField(C.contentFields[self.contentGroup], row[1]) end
        end)
        text("目录", "子类型和具体实体变体可在动作参数中填写")

        text("道具", "名称搜索：字符拼写或控制台输入")
        text("道具", "lua EW('search 名称')")
        text("道具", function() return "搜索：" .. self.query end)
        number("道具", "选择字符", function() return self.charIndex end,
            function(n) self.charIndex = n end, 1, #alphabet, nil,
            function() return "选择字符：" .. alphabet:sub(self.charIndex, self.charIndex) end)
        button("道具", "追加字符并搜索", function()
            if #self.query < 120 then self:search(self.query .. alphabet:sub(self.charIndex, self.charIndex)) end
        end)
        button("道具", "删除最后一个字符", function()
            local last = utf8.offset(self.query, -1)
            self:search(last and self.query:sub(1, last - 1) or "")
        end)
        button("道具", "清空搜索", function() self:search("") end)
        space("道具")
        number("道具", "搜索结果", function() return self.resultIndex end,
            function(n) self.resultIndex = n end, 1, function() return #self.results end, nil,
            function()
                local id = self.results[self.resultIndex]
                return id and ("结果 " .. self.resultIndex .. "/" .. #self.results .. "：#" .. id .. " " .. A.itemName(id)) or "没有匹配道具"
            end)
        button("道具", "用于当前动作", function()
            local id = self.results[self.resultIndex]
            if id then actionField("itemId", id) end
        end)
        button("道具", "用于持有条件", function()
            local id = self.results[self.resultIndex]
            if id then conditionField("collectible", id) end
        end)
        button("道具", "当前动作恢复随机道具", function() actionField("itemId", 0) end)

        number("预设", "选择预设", function() return self.presetIndex end,
            function(n) self.presetIndex = n end, 1, #C.presets, nil,
            function() return "预设：" .. C.presets[self.presetIndex][2] end)
        button("预设", "添加此预设（默认禁用）", function() T:newRule(C.presets[self.presetIndex][1]) end)
        space("预设")
        button("预设", "导出配置到控制台 / 日志", function()
            local output = json.encode(E.config)
            Isaac.ConsoleOutput(A.consoleJSON(output) .. "\n")
            A.log("EXPORT " .. output)
            T.status = "已导出；使用 lua EW([[import JSON]]) 导入"
        end)
        text("预设", "导入与重命名：lua EW('help') 查看说明")
        text("预设", "新配置保留到下局，新局总开关仍默认关闭")
        self.installed = mcm
        self:search(self.query)
        A.log("MCM 菜单已注册")
    end
    return M
end
