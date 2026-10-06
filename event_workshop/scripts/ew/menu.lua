return function(C, S, E, A, T, json, selftest)
    local M = { installed = nil, query = "", results = {}, resultIndex = 1, charIndex = 1, presetIndex = 1 }
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
                options.Maximum = math.max(min, type(max) == "function" and max() or max)
                return math.max(min, math.min(options.Maximum, get() or min))
            end
            options.Display = display or function() return label .. "：" .. tostring(get() or min) end
            options.OnChange = set
            setting(tab, options)
        end
        local function choice(tab, label, list, get, set, info)
            number(tab, label, function() return C.index(list, get()) end,
                function(n) set(list[n][1]) end, 1, #list, info,
                function() return label .. "：" .. C.label(list, get()) end)
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
            Isaac.ConsoleOutput("[事件工坊] " .. T.status .. "\n")
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

        text("条件", function() local r = selectedRule(); return r and ("当前规则：" .. r.name) or "请先添加规则" end)
        choice("条件", "触发事件", C.events, function() local r = selectedRule(); return r and r.event end,
            function(v) ruleField("event", v) end, "先选择事件，再设置下面的筛选条件。")
        space("条件")
        text("条件", "以下条件须同时满足")
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

        text("动作", "多个动作依次执行；选中动作后修改参数")
        number("动作", "选择动作", function() return T.selectedAction end,
            function(n) T.selectedAction = n end,
            1, function() local r = selectedRule(); return r and #r.actions or 1 end, nil,
            function()
                local a, r = selectedAction(), selectedRule()
                return a and ("动作 " .. T.selectedAction .. "/" .. #r.actions .. "：" .. C.label(C.actions, a.kind)) or "请先添加规则"
            end)
        choice("动作", "动作类型", C.actions, function() local a = selectedAction(); return a and a.kind end,
            function(v) actionField("kind", v) end)
        space("动作")
        local function actionNumber(key, label, min, max, info, display)
            number("动作", label, function() local a = selectedAction(); return a and a[key] or min end,
                function(v) actionField(key, v) end, min, max, info, display)
        end
        actionNumber("amount", "数量 / 增减值", -999, 999,
            { "生成 / 给予类：1–32 个；生命调整：-48–48。",
                "红心、魂心、黑心及容器以半颗为单位；骨心、腐心以整颗为单位。" })
        space("动作")
        actionNumber("itemId", "道具 ID", 0, function() return A.maxItemId end,
            "设为 0 表示随机；仅底座和直接给予动作使用，道具页面可按名称搜索。",
            function() local a = selectedAction(); local id = a and a.itemId or 0
                return "道具 ID：" .. (id == 0 and "随机" or tostring(id)) end)
        text("动作", function() local a = selectedAction(); return "道具：" .. A.itemName(a and a.itemId or 0) end)
        choice("动作", "随机道具池", C.pools, function() local a = selectedAction(); return a and a.pool or 0 end,
            function(v) actionField("pool", v) end, "仅随机道具使用；受游戏原有角色及道具池机制影响。")
        actionNumber("qualityMin", "最低品质", 0, 4)
        actionNumber("qualityMax", "最高品质", 0, 4, "反向设置时自动按较小值到较大值筛选。")
        space("动作")
        choice("动作", "掉落物类型", C.pickups, function() local a = selectedAction(); return a and a.pickupVariant or 20 end,
            function(v) actionField("pickupVariant", v) end, "仅生成掉落物动作使用。")
        actionNumber("subtype", "掉落物子类型 / ID", 0, 1000000,
            "普通金币、钥匙、炸弹、红心使用 1；0 表示随机。卡牌、饰品填写对应 ID。")
        space("动作")
        choice("动作", "生命类型", C.hearts, function() local a = selectedAction(); return a and a.heartType or "red" end,
            function(v) actionField("heartType", v) end)
        choice("动作", "充能槽位", C.slots, function() local a = selectedAction(); return a and a.slot or 0 end,
            function(v) actionField("slot", v) end, "普通调整充能使用；抵消清房充能自动检查所有普通主动槽位。")
        choice("动作", "敌人类型", C.enemies, function() local a = selectedAction(); return a and a.enemyType or 10 end,
            function(v) actionField("enemyType", v) end, "仅生成敌人动作使用；第一版提供已知原版敌人。")
        space("动作")
        button("动作", "添加动作", function() T:addAction() end)
        button("动作", "当前动作上移", function() T:moveAction(-1) end)
        button("动作", "当前动作下移", function() T:moveAction(1) end)
        button("动作", "删除当前动作", function() T:deleteAction() end, nil,
            "确定删除当前动作？$newline$至少保留一个动作。")

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
            Isaac.ConsoleOutput(output .. "\n")
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
