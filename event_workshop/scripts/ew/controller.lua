return function(mod, json, C, S, E, A)
    local T = { selectedRule = 1, selectedAction = 1, status = "配置已保存；新局需手动启用", pendingSave = false }
    function T:load()
        if not mod:HasData() then return end
        local ok, data = pcall(json.decode, mod:LoadData())
        if not ok or type(data) ~= "table" then
            self.status = "存档格式损坏，已载入默认配置"
            A.log(self.status)
            self.corruptSave = true
            return
        end
        if type(data.config) == "table" and type(data.config.schemaVersion) == "number"
            and data.config.schemaVersion > S.VERSION then
            self.readOnly = true
            self.status = "存档版本较新，当前版本停止写入"
            A.log(self.status)
            return
        end
        E.config = S.config(data.config)
        self.savedRun = data.run
    end
    function T:save()
        if self.readOnly then self.status = "存档版本较新，未写入配置"; return false end
        if self.corruptSave then self.status = "存档损坏，默认配置暂未写入；手动编辑后保存"; return false end
        local ok, result = pcall(function()
            mod:SaveData(json.encode({ config = E.config, run = E.run or self.savedRun }))
        end)
        if not ok then self.status = "保存失败，请查看游戏日志"; A.log(result); return false end
        self.pendingSave = false
        return true
    end
    function T:changed(message)
        self.corruptSave = false
        self.status = message or "配置已保存"
        self:save()
    end
    function T:profile() return S.profile(E.config) end
    function T:rule()
        local rules = self:profile().rules
        self.selectedRule = math.max(1, math.min(#rules, self.selectedRule))
        return rules[self.selectedRule]
    end
    function T:action()
        local rule = self:rule()
        if not rule then return nil end
        self.selectedAction = math.max(1, math.min(#rule.actions, self.selectedAction))
        return rule.actions[self.selectedAction]
    end
    function T:newRule(preset)
        local p = self:profile()
        if #p.rules >= S.MAX_RULES then self.status = "每套方案最多 100 条规则"; return false end
        local id = E.config.nextRuleId
        E.config.nextRuleId = id + 1
        p.rules[#p.rules + 1] = preset and S.preset(preset, id) or S.rule({}, id)
        self.selectedRule, self.selectedAction = #p.rules, 1
        self:changed("规则已添加，默认禁用")
        return true
    end
    function T:copyRule()
        local source = self:rule()
        if not source then return end
        if #self:profile().rules >= S.MAX_RULES then self.status = "规则数量达到上限"; return end
        local id = E.config.nextRuleId
        E.config.nextRuleId = id + 1
        local rule = S.rule(S.copy(source), id)
        rule.name, rule.enabled = S.rule({ name = source.name .. " 副本" }, id).name, false
        table.insert(self:profile().rules, rule)
        self.selectedRule, self.selectedAction = #self:profile().rules, 1
        self:changed("已复制规则，副本默认禁用")
    end
    function T:deleteRule()
        local rule = self:rule()
        if not rule then return end
        if E.run then E.run.counters[tostring(rule.id)] = nil end
        table.remove(self:profile().rules, self.selectedRule)
        self.selectedAction = 1
        self:changed("已删除规则")
    end
    function T:addAction()
        local rule = self:rule()
        if not rule then return end
        if #rule.actions >= S.MAX_ACTIONS then self.status = "每条规则最多 20 个动作"; return end
        table.insert(rule.actions, S.action())
        self.selectedAction = #rule.actions
        self:changed("动作已添加")
    end
    function T:deleteAction()
        local rule = self:rule()
        if not rule then return end
        if #rule.actions == 1 then self.status = "至少保留一个动作"; return end
        table.remove(rule.actions, self.selectedAction)
        self:changed("动作已删除")
    end
    function T:moveAction(delta)
        local rule, index = self:rule(), self.selectedAction
        if not rule then return end
        local to = index + delta
        if to < 1 or to > #rule.actions then return end
        rule.actions[index], rule.actions[to] = rule.actions[to], rule.actions[index]
        self.selectedAction = to
        self:changed("动作顺序已调整")
    end
    function T:newProfile(copy)
        if #E.config.profiles >= S.MAX_PROFILES then self.status = "最多 20 套方案"; return end
        local source = self:profile()
        local pid = E.config.nextProfileId
        E.config.nextProfileId = pid + 1
        local profile = { id = pid, name = "方案 " .. pid, rules = {} }
        if copy then
            profile.name = source.name .. " 副本"
            for _, rule in ipairs(source.rules) do
                profile.rules[#profile.rules + 1] = S.rule(rule, E.config.nextRuleId)
                E.config.nextRuleId = E.config.nextRuleId + 1
            end
        end
        table.insert(E.config.profiles, profile)
        self:switchProfile(#E.config.profiles)
        self:changed("方案已添加；总开关已关闭")
    end
    function T:switchProfile(index)
        local profile = E.config.profiles[index]
        if not profile then return end
        E.config.activeProfileId = profile.id
        self.selectedRule, self.selectedAction = 1, 1
        if E.run then E.run.master = false end
        self:changed("方案已切换；请手动打开总开关")
    end
    function T:deleteProfile()
        if #E.config.profiles == 1 then self.status = "至少保留一套方案"; return end
        for i, p in ipairs(E.config.profiles) do
            if p.id == E.config.activeProfileId then
                if E.run then
                    for _, r in ipairs(p.rules) do E.run.counters[tostring(r.id)] = nil end
                end
                table.remove(E.config.profiles, i)
                break
            end
        end
        self:switchProfile(1)
    end
    function T:setMaster(value)
        if not A.isSinglePlayer() then self.status = "第一版仅支持单人游戏"; return end
        local ok, err = E:setMaster(value, A.context())
        if ok then self:changed(value and "本局已启用" or "本局已停用")
        else self.status = err end
    end
    function T:import(raw)
        local valid, errorMessage = S.validateImport(raw)
        if not valid then return false, errorMessage end
        self.readOnly = false
        E.config = S.config(raw)
        -- 导入时重分配 ID，避免新规则复用本局旧规则的计数。
        local nextId = 1
        for _, p in ipairs(E.config.profiles) do
            for _, rule in ipairs(p.rules) do rule.id = nextId; nextId = nextId + 1 end
        end
        E.config.nextRuleId = nextId
        self.selectedRule, self.selectedAction = 1, 1
        if E.run then E.run.master, E.run.counters = false, {} end
        self:changed("配置已导入；总开关已关闭")
        return true
    end
    return T
end
