return function(S, adapter)
    local E = { config = S.default(), run = nil, ready = false, busy = false, history = {},
        MAX_EVENTS = 128, MAX_ACTIONS = 256, MAX_QUEUE = 2048, MAX_CHAIN_RULES = 32 }
    local function now() return adapter.frame and adapter.frame() or 0 end
    function E:record(message)
        self.history[#self.history + 1] = tostring(message)
        if #self.history > 40 then table.remove(self.history, 1) end
    end
    function E:newRun(seed, continued, saved)
        local restore = continued and type(saved) == "table" and saved.seed == seed
        local function tableValue(key, default)
            return restore and type(saved[key]) == "table" and S.copy(saved[key]) or (default or {})
        end
        self.run = {
            seed = seed, master = restore and saved.master == true or false,
            startedFired = restore and saved.startedFired == true or false,
            counters = restore and type(saved.counters) == "table" and S.copy(saved.counters) or {},
            randomState = restore and S.number(saved.randomState, 1, 1, 2147483646)
                or (math.abs(seed) % 2147483646 + 1),
            modifiers = tableValue("modifiers"),
            variables = tableValue("variables"),
            scheduled = tableValue("scheduled"),
            origins = tableValue("origins", { rooms = {}, entities = {} }),
            chainSerial = restore and S.number(saved.chainSerial, 0, 0, 1000000000) or 0,
            chains = tableValue("chains"),
            roomWatch = restore and type(saved.roomWatch) == "table" and S.copy(saved.roomWatch) or nil,
            timers = restore and type(saved.timers) == "table" and S.copy(saved.timers) or {},
            roomHits = restore and type(saved.roomHits) == "table" and S.copy(saved.roomHits) or {},
        }
        local modifiers, tasks = {}, {}
        for _, entry in ipairs(self.run.modifiers) do
            if type(entry) == "table" and (entry.kind == "stat" or entry.kind == "tear_flag") then
                entry.scope = S.number(entry.scope, 0, 0, 3)
                entry.expires = S.number(entry.expires, now(), 0, 1000000000)
                entry.value = S.scalar(entry.value, 0, -100000, 100000)
                modifiers[#modifiers + 1] = entry
            end
        end
        for _, task in ipairs(self.run.scheduled) do
            if #tasks < self.MAX_QUEUE and type(task) == "table" and type(task.action) == "table"
                and type(task.roomKey) == "string" and type(task.floorKey) == "string" and type(task.chain) == "table" then
                task.action, task.due, task.ruleName = S.action(task.action), S.number(task.due, now(), 0, 1000000000), tostring(task.ruleName or "延迟动作")
                tasks[#tasks + 1] = task
            end
        end
        self.run.modifiers, self.run.scheduled = modifiers, tasks
        self.run.origins.rooms = type(self.run.origins.rooms) == "table" and self.run.origins.rooms or {}
        self.run.origins.entities = type(self.run.origins.entities) == "table" and self.run.origins.entities or {}
        self.ready, self.busy, self.activeChain = true, false, nil
        self.budgetFrame, self.eventBudget, self.actionBudget, self.operationBudget, self.spawnBudget = nil, 0, 0, 0, 0
    end
    function E:nextSeed()
        -- 独立 PRNG：不推进游戏全局随机数，也不更改局内种子。
        self.run.randomState = (self.run.randomState * 48271) % 2147483647
        return self.run.randomState
    end
    function E:setMaster(enabled, context)
        if not self.ready or not self.run then return false, "请先进入一局单人游戏" end
        self.run.master = enabled == true
        if not self.run.master then self.run.scheduled = {} end
        if self.run.master and not self.run.startedFired then
            self.run.startedFired = true
            self:dispatch("run_start", context)
        end
        return true
    end
    function E:budget(kind)
        if self.budgetFrame ~= now() then self.budgetFrame, self.eventBudget, self.actionBudget, self.operationBudget, self.spawnBudget = now(), 0, 0, 0, 0 end
        local fields = { event = "eventBudget", action = "actionBudget", operation = "operationBudget", spawn = "spawnBudget" }
        local field, cap = fields[kind], kind == "event" and self.MAX_EVENTS or kind == "spawn" and 64 or self.MAX_ACTIONS
        if self[field] >= cap then self:record("限流: 本帧" .. kind .. "达到上限"); return false end
        self[field] = self[field] + 1
        return true
    end
    function E:chain(context)
        local chain = context.chain
        if type(chain) ~= "table" or not tonumber(chain.id) then
            self.run.chainSerial = self.run.chainSerial + 1
            chain = { id = self.run.chainSerial, visited = {} }
            context.chain = chain
        end
        local key = tostring(chain.id)
        local existing = self.run.chains[key]
        if type(existing) ~= "table" then
            existing = { id = chain.id, visited = {}, frame = now() }
            self.run.chains[key] = existing
        end
        existing.visited = type(existing.visited) == "table" and existing.visited or {}
        for id in pairs(type(chain.visited) == "table" and chain.visited or {}) do existing.visited[id] = true end
        existing.frame = now()
        context.chain = existing
        -- 保留近期链；实体持有的已访问集合可在链记录淘汰后恢复循环防护。
        local count = 0
        for _ in pairs(self.run.chains) do count = count + 1 end
        if count > 256 then
            local oldest, frame
            for id, entry in pairs(self.run.chains) do
                if id ~= key and (type(entry) ~= "table" or not frame or (tonumber(entry.frame) or 0) < frame) then oldest, frame = id, type(entry) == "table" and (tonumber(entry.frame) or 0) or 0 end
            end
            if oldest then self.run.chains[oldest] = nil end
        end
        return existing
    end
    function E:matches(rule, context)
        local c, checks = rule.conditions, {}
        if c.roomType ~= -1 then checks[#checks + 1] = c.roomType == context.roomType end
        if c.character ~= -1 then checks[#checks + 1] = c.character == adapter.character(context) end
        if c.collectible ~= 0 then checks[#checks + 1] = adapter.hasCollectible(context, c.collectible) end
        for _, filter in ipairs(rule.filters or {}) do
            local value = adapter.metric and adapter.metric(context, filter.field, filter.argument, self) or nil
            local target, result = filter.value, false
            if value ~= nil then
                if filter.op == "eq" then result = value == target elseif filter.op == "ne" then result = value ~= target
                elseif filter.op == "ge" then result = value >= target elseif filter.op == "le" then result = value <= target
                elseif filter.op == "gt" then result = value > target elseif filter.op == "lt" then result = value < target
                elseif filter.op == "bits" then result = (math.floor(value) & math.floor(target)) == math.floor(target)
                elseif filter.op == "cross_up" then result = context.before ~= nil and context.before < target and value >= target
                elseif filter.op == "cross_down" then result = context.before ~= nil and context.before > target and value <= target end
            end
            if filter.negate then result = not result end
            checks[#checks + 1] = result
        end
        if #checks == 0 then return true end
        if c.matchMode == 1 then for _, value in ipairs(checks) do if value then return true end end; return false end
        for _, value in ipairs(checks) do if not value then return false end end
        return true
    end
    function E:perform(action, context, ruleName)
        if not self:budget("action") then return end
        local oldBusy, oldChain = self.busy, self.activeChain
        self.busy, self.activeChain = true, context.chain
        local ok, err = pcall(adapter.execute, action, context, self)
        self.busy, self.activeChain = oldBusy, oldChain
        if not ok then
            adapter.log("规则 " .. ruleName .. ": " .. tostring(err)); self:record(ruleName .. " 失败: " .. tostring(err))
        else self:record(ruleName .. " -> " .. action.kind .. " 成功") end
    end
    function E:actions(rule, context)
        local list = rule.actions
        if rule.conditions.randomAction == 1 then list = { list[self:nextSeed() % #list + 1] } end
        for _, action in ipairs(list) do
            for repetition = 1, action.repeatCount or 1 do
                local delay = (action.delayFrames or 0) + (repetition - 1) * (action.repeatFrames or 30)
                if delay == 0 then self:perform(action, context, rule.name)
                elseif #self.run.scheduled < self.MAX_QUEUE then
                    self.run.scheduled[#self.run.scheduled + 1] = {
                        action = S.copy(action), due = now() + delay, roomKey = context.roomKey, floorKey = context.floorKey,
                        chain = S.copy(context.chain), ruleName = rule.name, playerSeed = context.player and context.player.InitSeed,
                        entitySeed = context.entity and context.entity.InitSeed,
                        colliderSeed = context.collider and context.collider.InitSeed,
                        position = context.position and { X = context.position.X, Y = context.position.Y },
                    }
                else self:record("延迟动作队列已满，跳过") end
            end
        end
    end
    function E:dispatch(event, context)
        if not self.ready or not self.run or not self.run.master or self.busy or not context then return end
        if not adapter.isSinglePlayer() or not self:budget("event") then return end
        local original = context
        context = {}
        for key, value in pairs(original) do context[key] = value end
        local chain = self:chain(context)
        self.busy = true
        local ok, err = pcall(function()
            local rules = S.copy(S.profile(self.config).rules)
            for _, rule in ipairs(rules) do
                if rule.enabled and rule.event == event and (not context.ruleId or context.ruleId == rule.id) then
                    local c, id = rule.conditions, tostring(rule.id)
                    local length = 0; for _ in pairs(chain.visited) do length = length + 1 end
                    if chain.visited[id] then self:record(rule.name .. " 跳过: 同一因果链已经执行")
                    elseif length >= self.MAX_CHAIN_RULES then self:record("因果链达到 32 条规则上限")
                    elseif self:matches(rule, context) then
                        local counter = self.run.counters[id] or {}
                        counter.seen = S.number(counter.seen, 0, 0, 1000000000) + 1
                        counter.total = S.number(counter.total, 0, 0, 1000000000)
                        counter.rooms, counter.floors = counter.rooms or {}, counter.floors or {}
                        local rk, fk = context.roomKey, context.floorKey
                        local roomCount, floorCount = counter.rooms[rk] or 0, counter.floors[fk] or 0
                        self.run.counters[id] = counter
                        local allowed = counter.seen % c.every == 0
                            and (c.maxRoom == 0 or roomCount < c.maxRoom)
                            and (c.maxFloor == 0 or floorCount < c.maxFloor)
                            and (c.maxRun == 0 or counter.total < c.maxRun)
                            and (c.cooldownFrames == 0 or not counter.lastFrame or now() - counter.lastFrame >= c.cooldownFrames)
                        if allowed and c.chance > 0 and (c.chance == 100 or self:nextSeed() % 100 < c.chance) then
                            chain.visited[id] = true
                            counter.total, counter.lastFrame = counter.total + 1, now()
                            counter.rooms[rk], counter.floors[fk] = roomCount + 1, floorCount + 1
                            self:actions(rule, context)
                        end
                    else self:record(rule.name .. " 未执行: 条件不满足") end
                end
            end
        end)
        self.busy, self.activeChain = false, nil
        if not ok then adapter.log("事件执行失败: " .. tostring(err)); self:record(err) end
    end
    function E:tick(context)
        if not self.run or not self.run.master or not context or not adapter.isSinglePlayer() then return end
        local tasks = self.run.scheduled
        self.run.scheduled = {}
        local executed = 0
        for _, task in ipairs(tasks) do
            if task.roomKey == context.roomKey and task.floorKey == context.floorKey then
                if task.due <= now() and executed < self.MAX_ACTIONS then
                    local ctx = adapter.restoreTask and adapter.restoreTask(task) or context
                    if ctx then
                        ctx.chain = self:chain({ chain = task.chain })
                        self:perform(task.action, ctx, task.ruleName)
                        executed = executed + 1
                    end
                else self.run.scheduled[#self.run.scheduled + 1] = task end
            else self:record(task.ruleName .. " 延迟动作取消: 已离开事件房间") end
        end
    end
    return E
end
