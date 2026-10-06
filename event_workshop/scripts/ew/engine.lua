return function(S, adapter)
    local E = { config = S.default(), run = nil, ready = false, busy = false }
    function E:newRun(seed, continued, saved)
        local restore = continued and type(saved) == "table" and saved.seed == seed
        self.run = {
            seed = seed, master = restore and saved.master == true or false,
            startedFired = restore and saved.startedFired == true or false,
            counters = restore and type(saved.counters) == "table" and S.copy(saved.counters) or {},
            randomState = restore and S.number(saved.randomState, 1, 1, 2147483646)
                or (math.abs(seed) % 2147483646 + 1),
        }
        self.ready = true
        self.busy = false
    end
    function E:nextSeed()
        -- 独立 PRNG：不推进游戏全局随机数，也不更改局内种子。
        self.run.randomState = (self.run.randomState * 48271) % 2147483647
        return self.run.randomState
    end
    function E:setMaster(enabled, context)
        if not self.ready or not self.run then return false, "请先进入一局单人游戏" end
        self.run.master = enabled == true
        if self.run.master and not self.run.startedFired then
            self.run.startedFired = true
            self:dispatch("run_start", context)
        end
        return true
    end
    function E:dispatch(event, context)
        if not self.ready or not self.run or not self.run.master or self.busy or not context then return end
        if not adapter.isSinglePlayer() then return end
        self.busy = true
        local ok, err = pcall(function()
            local rules = S.copy(S.profile(self.config).rules)
            for _, rule in ipairs(rules) do
                if rule.enabled and rule.event == event then
                    local c = rule.conditions
                    local matches = (c.roomType == -1 or c.roomType == context.roomType)
                        and (c.character == -1 or c.character == adapter.character(context))
                        and (c.collectible == 0 or adapter.hasCollectible(context, c.collectible))
                    if matches then
                        local key = tostring(rule.id)
                        local old = self.run.counters[key]
                        local counter = type(old) == "table" and old or {}
                        counter.seen = S.number(counter.seen, 0, 0, 1000000000) + 1
                        counter.total = S.number(counter.total, 0, 0, 1000000000)
                        counter.rooms = type(counter.rooms) == "table" and counter.rooms or {}
                        counter.floors = type(counter.floors) == "table" and counter.floors or {}
                        local rk, fk = context.roomKey, context.floorKey
                        local roomCount = S.number(counter.rooms[rk], 0, 0, 1000000000)
                        local floorCount = S.number(counter.floors[fk], 0, 0, 1000000000)
                        self.run.counters[key] = counter
                        local allowed = counter.seen % c.every == 0
                            and (c.maxRoom == 0 or roomCount < c.maxRoom)
                            and (c.maxFloor == 0 or floorCount < c.maxFloor)
                            and (c.maxRun == 0 or counter.total < c.maxRun)
                        if allowed and c.chance > 0 and (c.chance == 100 or self:nextSeed() % 100 < c.chance) then
                            -- 先记录次数，动作引发的新回调不会递归执行规则。
                            counter.total = counter.total + 1
                            counter.rooms[rk], counter.floors[fk] = roomCount + 1, floorCount + 1
                            for _, action in ipairs(rule.actions) do
                                local actionOK, actionErr = pcall(adapter.execute, action, context, self)
                                if not actionOK then adapter.log("规则 " .. rule.name .. "：" .. tostring(actionErr)) end
                            end
                        end
                    end
                end
            end
        end)
        self.busy = false
        if not ok then adapter.log("事件执行失败：" .. tostring(err)) end
    end
    return E
end
