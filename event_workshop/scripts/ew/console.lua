return function(C, S, E, A, T, M, json, selftest)
    local K = {}
    local function out(message)
        A.writeConsole(message)
        A.log("CONSOLE " .. tostring(message))
    end
    local function selected(id)
        id = tonumber(id)
        for i, rule in ipairs(T:profile().rules) do
            if rule.id == id then T.selectedRule, T.selectedAction = i, 1; return rule end
        end
        error('Rule ID not found in this profile; use lua EW("list")')
    end
    local function split(input)
        local words = {}
        for word in input:gmatch("%S+") do words[#words + 1] = word end
        return words
    end
    local function integer(value)
        local n = tonumber(value)
        if not n or n ~= math.floor(n) or n == math.huge or n == -math.huge then error("Enter an integer") end
        return n
    end
    local function itemID(value)
        if tonumber(value) then return integer(value) end
        local matches = A.searchItems(value)
        if #matches == 1 then return matches[1] end
        error("Item name matched " .. #matches .. " items; use search and enter an item ID")
    end
    function K.run(args)
        local command, rest = args:match("^%s*(%S+)%s*(.-)%s*$")
        command = command and command:lower() or "help"
        local w = split(rest or "")
        if command == "help" then
            out('Repentance+ console: lua EW("command arguments"); example: lua EW("status")')
            local help = [[ew on | off | status | list
ew new [event] | preset <preset> | select <ruleID>
ew enable <ruleID> on|off | rename <ruleID> <name>
ew event <ruleID> <event> | copy <ruleID> | delete <ruleID>
ew condition <ruleID> <field> <integer>
ew addaction <ruleID> <kind> | delaction <ruleID> <index>
ew action <ruleID> <index> <field> <value>
ew search <item name or ID> | characters
ew profile list|new|copy|delete|select <index>|rename <name>
ew export | import <JSON> | selftest
Events: use events for the complete list
Actions: use actions for the complete list
Conditions: chance every roomType character collectible maxRoom maxFloor maxRun
Presets: 11 examples; see the MCM Presets page or manual
See the bundled manual for parameters and limitations.]]
            for line in help:gmatch("[^\n]+") do
                if line:sub(1, 3) == "ew " then line = "lua EW(" .. string.format("%q", line:sub(4)) .. ")" end
                out(line)
            end
            out('Catalog: events / actions / fields <kind> / contents <category> [query] / trace')
            out('Filters: filter <ruleID> add <field> <operator> <value> [argumentID] [not]; filter ID delete index')
            out('Example: lua EW("preset clear_pedestal"), then list, enable ID on, and on.')
        elseif command == "status" then
            out("Profile: " .. A.consoleName(T:profile().name, "Profile " .. T:profile().id .. " (name in MCM)") .. "; rules: " .. #T:profile().rules)
            out(E.ready and E.run and ("Master: " .. tostring(E.run.master)
                .. "; seed: " .. Game():GetSeeds():GetStartSeedString()
                .. "; run_start fired: " .. tostring(E.run.startedFired)) or "No active run")
            out("Loop protection: each rule once per chain; 32 rules per chain; 128 events / 256 actions per frame")
            out(T.status)
        elseif command == "on" or command == "off" then
            T:setMaster(command == "on"); out(T.status)
        elseif command == "list" then
            for i, r in ipairs(T:profile().rules) do
                out(i .. ". ID=" .. r.id .. " [" .. (r.enabled and "ON" or "OFF") .. "] "
                    .. A.consoleName(r.name, "Rule " .. r.id .. " (name in MCM)") .. " | " .. r.event .. " | actions=" .. #r.actions)
            end
        elseif command == "new" then
            if w[1] and not C.contains(C.events, w[1]) then error('Unknown event; use lua EW("events")') end
            if not T:newRule() then out(T.status); return end
            if w[1] then T:rule().event = w[1]; T:changed() end
            out("Current rule ID=" .. T:rule().id .. "; disabled by default")
        elseif command == "preset" then
            if not C.contains(C.presets, w[1]) then error('Unknown preset; see the MCM Presets page') end
            T:newRule(w[1]); out(T.status)
        elseif command == "select" then
            local r = selected(w[1]); out("Selected: ID=" .. r.id .. " " .. A.consoleName(r.name, "(name in MCM)"))
        elseif command == "enable" then
            if w[2] ~= "on" and w[2] ~= "off" then error("Use on or off") end
            selected(w[1]).enabled = w[2] == "on"; T:changed(); out(T.status)
        elseif command == "rename" then
            local id, name = rest:match("^(%d+)%s+(.+)$")
            if not name then error('lua EW("rename <ruleID> <name>")') end
            local r = selected(id)
            r.name = S.rule({ name = name }, r.id).name
            T:changed(); out(T.status)
        elseif command == "event" then
            if not C.contains(C.events, w[2]) then error("Unknown event") end
            selected(w[1]).event = w[2]; T:changed(); out(T.status)
        elseif command == "copy" then
            selected(w[1]); T:copyRule(); out(T.status)
        elseif command == "delete" then
            selected(w[1]); T:deleteRule(); out(T.status)
        elseif command == "condition" then
            local r = selected(w[1])
            if r.conditions[w[2]] == nil then error("Unknown condition field") end
            local n = integer(w[3])
            local copy = S.copy(r.conditions); copy[w[2]] = n
            local normalized = S.conditions(copy)
            if normalized[w[2]] ~= n then error("Condition value out of range; see the manual") end
            r.conditions = normalized; T:changed(); out(T.status)
        elseif command == "addaction" then
            selected(w[1])
            if not C.contains(C.actions, w[2]) then error("Unknown action kind") end
            local count = #T:rule().actions
            T:addAction()
            if #T:rule().actions > count then T:action().kind = w[2]; T:changed() end
            out(T.status)
        elseif command == "delaction" then
            local r = selected(w[1]); local n = integer(w[2])
            if n < 1 or n > #r.actions then error("Action index not found") end
            T.selectedAction = n; T:deleteAction(); out(T.status)
        elseif command == "action" then
            local r = selected(w[1]); local n = integer(w[2])
            if n < 1 or n > #r.actions then error("Action index not found") end
            local key, value = w[3], rest:match("^%S+%s+%S+%s+%S+%s+(.+)$")
            if not key or r.actions[n][key] == nil or not value then error('lua EW("action <ID> <index> <field> <value>")') end
            if key == "kind" then
                if not C.contains(C.actions, value) then error("Unknown action") end
            elseif C.fields[key].list then
                local list = C.fields[key].list
                value = type(list[1][1]) == "number" and integer(value) or value
                if not C.contains(list, value) then error("Unknown option") end
            elseif key == "message" then
                value = value
            else
                value = key == "itemId" and itemID(value) or tonumber(value)
                if not value then error("Enter a valid number") end
            end
            local action = S.copy(r.actions[n]); action[key] = value
            local normalized = S.action(action)
            if normalized[key] ~= value then error("Action value out of range; see the manual") end
            r.actions[n] = normalized; T.selectedAction = n; T:changed(); out(T.status)
        elseif command == "events" or command == "actions" then
            for _, row in ipairs(command == "events" and C.events or C.actions) do out(row[1] .. " | " .. row[1]:gsub("_", " ")) end
        elseif command == "fields" then
            local info = C.actionInfo[w[1]]
            if not info then error("Unknown action; use actions") end
            out("Parameters for " .. w[1] .. "; native API limitations apply. See MCM / manual for details.")
            local fields = S.copy(info.fields)
            for _, key in ipairs({ "delayFrames", "repeatCount", "repeatFrames" }) do fields[#fields + 1] = key end
            for _, key in ipairs(fields) do
                local field = C.fields[key]
                out(key .. " | " .. key:gsub("(%l)(%u)", "%1 %2"):lower())
                if field.list then for _, row in ipairs(field.list) do out("  " .. tostring(row[1]) .. " " .. A.consoleName(row[2], tostring(row[1]))) end
                elseif field.min then out("  Range " .. field.min .. " - " .. field.max) end
            end
        elseif command == "contents" then
            local list = C.content[w[1]]
            if not list then
                for _, row in ipairs(C.contentGroups) do out(row[1] .. " | " .. row[1]:gsub("_", " ")) end
            else
                local query = rest:match("^%S+%s*(.*)$"):lower()
                local found = 0
                for _, row in ipairs(list) do
                    local label = A.consoleLabel(w[1], row)
                    if query == "" or tostring(row[1]) == query or row[2]:lower():find(query, 1, true) or label:lower():find(query, 1, true) then
                        out(tostring(row[1]) .. " | " .. label); found = found + 1
                    end
                end
                out("Matched " .. found .. " entries")
            end
        elseif command == "trace" then
            for _, entry in ipairs(E.history) do
                for _, r in ipairs(T:profile().rules) do
                    local pattern = r.name:gsub("(%W)", "%%%1")
                    entry = entry:gsub(pattern, function() return "Rule " .. r.id end)
                end
                out(entry)
            end
        elseif command == "filter" then
            local rule = selected(w[1])
            if w[2] == "add" then
                if #rule.filters >= 20 then error("At most 20 filters") end
                if not C.contains(C.filterFields, w[3]) or not C.contains(C.operators, w[4]) then error("Unknown filter field or operator") end
                local value = tonumber(w[5]); if not value then error("Threshold must be a number") end
                rule.filters[#rule.filters + 1] = S.filter({ field = w[3], op = w[4], value = value,
                    argument = w[6] and w[6] ~= "not" and integer(w[6]) or 1, negate = w[6] == "not" or w[7] == "not" })
            elseif w[2] == "delete" then
                local index = integer(w[3]); if not rule.filters[index] then error("Filter not found") end
                table.remove(rule.filters, index)
            elseif w[2] == "list" then
                for index, f in ipairs(rule.filters) do out(index .. " " .. f.field .. " " .. f.op .. " " .. f.value .. (f.negate and " NOT" or "")) end
                return
            else error("Use filter ID add|delete|list") end
            T:changed(); out(T.status)
        elseif command == "search" then
            M:search(rest)
            out("Found " .. #M.results .. " items; see all results in the MCM Items page")
            for i = 1, math.min(30, #M.results) do
                local id = M.results[i]; out("#" .. id .. " " .. A.consoleName((Isaac.GetItemConfig():GetCollectible(id) or {}).Name or "", "(name in MCM)"))
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
                for i, p in ipairs(E.config.profiles) do out(i .. ". ID=" .. p.id .. " " .. A.consoleName(p.name, "(name in MCM)")) end
            elseif sub == "new" or sub == "copy" then T:newProfile(sub == "copy"); out(T.status)
            elseif sub == "delete" then T:deleteProfile(); out(T.status)
            elseif sub == "select" then
                local index = integer(w[2])
                if not E.config.profiles[index] then error("Profile index not found") end
                T:switchProfile(index); out(T.status)
            elseif sub == "rename" and name ~= "" then
                local copy = S.copy(E.config); S.profile(copy).name = name
                T:profile().name = S.profile(S.config(copy)).name
                T:changed(); out(T.status)
            else error('lua EW("profile list|new|copy|delete|select <index>|rename <name>")') end
        elseif command == "export" then
            local output = json.encode(E.config)
            Isaac.ConsoleOutput(A.consoleJSON(output) .. "\n"); A.log("EXPORT " .. output)
        elseif command == "import" then
            local data = A.consoleDecode(rest, json)
            local ok, err = T:import(data)
            if not ok then error(err) end
            out(T.status); M:search(M.query)
        elseif command == "selftest" then
            out("Self-test passed: " .. selftest() .. " checks; run, configuration and seed unchanged")
        else error('Unknown command; use lua EW("help")') end
    end
    function K.execute(args)
        local ok, err = pcall(function()
            if args ~= nil and type(args) ~= "string" then error('Use lua EW("command arguments"); argument must be a string') end
            K.run(args or "")
        end)
        if not ok then out("ERROR: " .. tostring(err)) end
        -- 两种入口均不返回值，避免原版 MC_EXECUTE_CMD 的返回值崩溃问题。
    end
    function K.callback(_, command, args)
        if type(command) ~= "string" or command:lower() ~= "ew" then return end
        K.execute(args)
    end
    return K
end
