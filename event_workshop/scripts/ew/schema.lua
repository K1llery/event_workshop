return function(C)
    local S = { VERSION = 1, MAX_RULES = 100, MAX_ACTIONS = 20, MAX_PROFILES = 20 }
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
    function S.action(raw)
        raw = type(raw) == "table" and raw or {}
        return {
            kind = C.contains(C.actions, raw.kind) and raw.kind or "spawn_collectible",
            amount = number(raw.amount, 1, -999, 999),
            itemId = number(raw.itemId, 0, 0, 1000000),
            pool = C.contains(C.pools, raw.pool) and raw.pool or 0,
            qualityMin = number(raw.qualityMin, 0, 0, 4),
            qualityMax = number(raw.qualityMax, 4, 0, 4),
            pickupVariant = C.contains(C.pickups, raw.pickupVariant) and raw.pickupVariant or 20,
            subtype = number(raw.subtype, 1, 0, 1000000),
            heartType = C.contains(C.hearts, raw.heartType) and raw.heartType or "red",
            slot = number(raw.slot, 0, 0, 3),
            enemyType = C.contains(C.enemies, raw.enemyType) and raw.enemyType or 10,
        }
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
        }
    end
    function S.rule(raw, id)
        raw = type(raw) == "table" and raw or {}
        local result = {
            id = id, name = text(raw.name, "规则 " .. id), enabled = raw.enabled == true,
            event = C.contains(C.events, raw.event) and raw.event or "room_clear",
            conditions = S.conditions(raw.conditions), actions = {},
        }
        if type(raw.actions) == "table" then
            for _, action in ipairs(raw.actions) do
                if #result.actions >= S.MAX_ACTIONS then break end
                result.actions[#result.actions + 1] = S.action(action)
            end
        end
        if #result.actions == 0 then result.actions[1] = S.action() end
        return result
    end
    function S.preset(key, id)
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
        if type(raw) ~= "table" or raw.schemaVersion ~= S.VERSION or type(raw.profiles) ~= "table"
            or #raw.profiles == 0 or #raw.profiles > S.MAX_PROFILES then
            return false, "请输入版本 1 的配置 JSON，包含 1–20 套方案"
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
