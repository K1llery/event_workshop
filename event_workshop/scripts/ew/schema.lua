return function(C)
    local S = { VERSION = 2, MAX_RULES = 100, MAX_ACTIONS = 20, MAX_PROFILES = 20 }
    function S.copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, entry in pairs(value) do result[key] = S.copy(entry) end
        return result
    end
    local function number(value, default, min, max)
        local n = tonumber(value)
        if not n or n ~= n or n == math.huge or n == -math.huge then n = default end
        return math.max(min, math.min(max, math.floor(n)))
    end
    S.number = number
    local function text(value, fallback)
        if type(value) ~= "string" or value == "" then return fallback end
        -- 按字符截断，避免切断中文 UTF-8 编码。
        local ok, length = pcall(utf8.len, value)
        if not ok or not length then return fallback end
        if length > 48 then return value:sub(1, utf8.offset(value, 49) - 1) end
        return value:gsub("[%c]", " ")
    end
    function S.scalar(value, default, min, max)
        local n = tonumber(value)
        if not n or n ~= n or n == math.huge or n == -math.huge then n = default end
        return math.max(min, math.min(max, n))
    end
    function S.action(raw)
        raw = type(raw) == "table" and raw or {}
        local result = { kind = C.contains(C.actions, raw.kind) and raw.kind or "spawn_collectible" }
        for key, field in pairs(C.fields) do
            if field.list then
                result[key] = C.contains(field.list, raw[key]) and raw[key] or field.default
            elseif key == "message" then result[key] = text(raw[key], field.default)
            else
                local normalize = (key == "value" or key == "duration" or key == "angle"
                    or key == "radius" or key == "red" or key == "green" or key == "blue") and S.scalar or number
                local default = key == "subtype" and (raw.kind == "spawn_enemy" or raw.kind == "spawn_entity"
                    or raw.kind == "spawn_familiar" or raw.kind == "spawn_machine" or raw.kind == "spawn_effect") and 0 or field.default
                result[key] = normalize(raw[key], default, field.min, field.max)
            end
        end
        return result
    end
    function S.filter(raw)
        raw = type(raw) == "table" and raw or {}
        return { field = C.contains(C.filterFields, raw.field) and raw.field or "coins",
            op = C.contains(C.operators, raw.op) and raw.op or "ge",
            value = S.scalar(raw.value, 0, -1000000000, 1000000000),
            argument = number(raw.argument, 1, 0, 1000000), negate = raw.negate == true }
    end
    function S.conditions(raw)
        raw = type(raw) == "table" and raw or {}
        return {
            chance = number(raw.chance, 100, 0, 100), every = number(raw.every, 1, 1, 999),
            roomType = C.contains(C.rooms, raw.roomType) and raw.roomType or -1,
            character = number(raw.character, -1, -1, 1000000),
            collectible = number(raw.collectible, 0, 0, 1000000),
            maxRoom = number(raw.maxRoom, 0, 0, 999), maxFloor = number(raw.maxFloor, 0, 0, 999),
            maxRun = number(raw.maxRun, 0, 0, 999),
            matchMode = number(raw.matchMode, 0, 0, 1),
            cooldownFrames = number(raw.cooldownFrames, 0, 0, 108000),
            intervalFrames = number(raw.intervalFrames, 30, 1, 108000),
            inputAction = number(raw.inputAction, 0, 0, 31),
            randomAction = number(raw.randomAction, 0, 0, 1),
        }
    end
    function S.rule(raw, id)
        raw = type(raw) == "table" and raw or {}
        local result = {
            id = id, name = text(raw.name, "规则 " .. id), enabled = raw.enabled == true,
            event = C.contains(C.events, raw.event) and raw.event or "room_clear",
            conditions = S.conditions(raw.conditions), actions = {}, filters = {},
        }
        if type(raw.actions) == "table" then
            for _, action in ipairs(raw.actions) do
                if #result.actions >= S.MAX_ACTIONS then break end
                result.actions[#result.actions + 1] = S.action(action)
            end
        end
        for _, filter in ipairs(type(raw.filters) == "table" and raw.filters or {}) do
            if #result.filters >= 20 then break end
            result.filters[#result.filters + 1] = S.filter(filter)
        end
        if #result.actions == 0 then result.actions[1] = S.action() end
        return result
    end
    function S.preset(key, id)
        if C.presetRules and C.presetRules[key] then
            local template = S.copy(C.presetRules[key]); template.name = C.label(C.presets, key)
            return S.rule(template, id)
        end
        local rule = S.rule({}, id)
        rule.name = C.label(C.presets, key)
        if key == "no_clear_charge" then
            rule.actions[1].kind = "undo_clear_charge"
        elseif key == "start_coins" then
            rule.event = "run_start"
            rule.actions[1].kind, rule.actions[1].amount = "coins", 5
        elseif key == "damage_coin" then
            rule.event = "player_damage"
            rule.actions[1].kind = "coins"
        end
        return rule
    end
    function S.default()
        return {
            schemaVersion = S.VERSION, activeProfileId = 1,
            nextRuleId = 3, nextProfileId = 2,
            profiles = { { id = 1, name = "默认方案", rules = {
                S.preset("clear_pedestal", 1), S.preset("no_clear_charge", 2),
            } } },
        }
    end
    function S.config(raw)
        if type(raw) ~= "table" or type(raw.profiles) ~= "table" then return S.default() end
        local result = { schemaVersion = S.VERSION, profiles = {}, nextRuleId = 1, nextProfileId = 1 }
        local ruleIDs, profileIDs = {}, {}
        for _, profile in ipairs(raw.profiles) do
            if #result.profiles >= S.MAX_PROFILES then break end
            if type(profile) == "table" then
                local pid = number(profile.id, result.nextProfileId, 1, 1000000000)
                while profileIDs[pid] do pid = pid + 1 end
                profileIDs[pid] = true
                result.nextProfileId = math.max(result.nextProfileId, pid + 1)
                local p = { id = pid, name = text(profile.name, "方案 " .. pid), rules = {} }
                for _, rule in ipairs(type(profile.rules) == "table" and profile.rules or {}) do
                    if #p.rules >= S.MAX_RULES then break end
                    if type(rule) == "table" then
                        local rid = number(rule.id, result.nextRuleId, 1, 1000000000)
                        while ruleIDs[rid] do rid = rid + 1 end
                        ruleIDs[rid] = true
                        result.nextRuleId = math.max(result.nextRuleId, rid + 1)
                        if raw.schemaVersion == 1 then
                            rule = S.copy(rule)
                            for _, a in ipairs(rule.actions or {}) do if a.kind == "spawn_enemy" then a.subtype, a.variant = 0, 0 end end
                        end
                        p.rules[#p.rules + 1] = S.rule(rule, rid)
                    end
                end
                result.profiles[#result.profiles + 1] = p
            end
        end
        if #result.profiles == 0 then return S.default() end
        result.nextRuleId = math.max(result.nextRuleId, number(raw.nextRuleId, 1, 1, 1000000000))
        result.nextProfileId = math.max(result.nextProfileId, number(raw.nextProfileId, 1, 1, 1000000000))
        result.activeProfileId = profileIDs[raw.activeProfileId] and raw.activeProfileId or result.profiles[1].id
        return result
    end
    function S.profile(config)
        for _, p in ipairs(config.profiles) do
            if p.id == config.activeProfileId then return p end
        end
        return config.profiles[1]
    end
    function S.validateImport(raw)
        if type(raw) ~= "table" or (raw.schemaVersion ~= 1 and raw.schemaVersion ~= S.VERSION) or type(raw.profiles) ~= "table"
            or #raw.profiles == 0 or #raw.profiles > S.MAX_PROFILES then
            return false, "请输入版本 1 或 2 的配置 JSON，包含 1–20 套方案"
        end
        for _, profile in ipairs(raw.profiles) do
            if type(profile) ~= "table" or type(profile.rules) ~= "table" or #profile.rules > S.MAX_RULES then
                return false, "每套方案必须包含规则列表，最多 100 条"
            end
            for _, rule in ipairs(profile.rules) do
                if type(rule) ~= "table" or not C.contains(C.events, rule.event)
                    or type(rule.actions) ~= "table" or #rule.actions < 1 or #rule.actions > S.MAX_ACTIONS then
                    return false, "规则含未知事件或无效动作列表"
                end
                if rule.conditions ~= nil and type(rule.conditions) ~= "table" then
                    return false, "条件必须为对象"
                end
                local conditions = S.conditions(rule.conditions)
                for key, value in pairs(rule.conditions or {}) do
                    if conditions[key] == nil or type(value) ~= "number" or conditions[key] ~= value then
                        return false, "条件字段或数值无效：" .. tostring(key)
                    end
                end
                if rule.filters ~= nil then
                    if type(rule.filters) ~= "table" or #rule.filters > 20 then return false, "最多 20 个扩展条件" end
                    for _, filter in ipairs(rule.filters) do
                        if type(filter) ~= "table" then return false, "扩展条件必须为对象" end
                        local normalized = S.filter(filter)
                        for key, value in pairs(filter) do
                            if normalized[key] == nil or normalized[key] ~= value then
                                return false, "扩展条件字段无效：" .. tostring(key)
                            end
                        end
                    end
                end
                for _, action in ipairs(rule.actions) do
                    if type(action) ~= "table" or not C.contains(C.actions, action.kind) then
                        return false, "配置含未知动作"
                    end
                    local normalized = S.action(action)
                    for key, value in pairs(action) do
                        if normalized[key] == nil or normalized[key] ~= value then
                            return false, "动作字段或数值无效：" .. tostring(key)
                        end
                    end
                end
            end
        end
        return true
    end
    return S
end
