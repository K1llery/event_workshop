local G = {
    frame = 0, seed = 12345, roomIndex = 0, floorSeed = 200, stage = 1,
    entities = {}, clear = true, curses = 0, roomType = 1, stored = "", output = {}, logs = {}, spawned = {}, players = {},
}
BitSet128 = function(lo) return lo end
ItemConfig, Entity, RoomDescriptor = {}, {}, {}
local gameDir = os.getenv("ISAAC_GAME_DIR") or "/mnt/d/SteamLibrary/steamapps/common/The Binding of Isaac Rebirth"
dofile(gameDir .. "/resources/scripts/enums.lua")
package.preload.json = function() return dofile(gameDir .. "/resources/scripts/json.lua") end
G.json = require("json")
local vector = { X = 100, Y = 100 }
local function vec(x, y)
    return { X = x or 0, Y = y or 0, Distance = function(self, other)
        return math.sqrt((self.X - other.X)^2 + (self.Y - other.Y)^2)
    end }
end
Vector = setmetatable({ Zero = vec(0, 0) }, { __call = function(_, x, y) return vec(x, y) end })
vector = vec(100, 100)
Color = function(...) return { ... } end
EntityRef = function(e) return { Entity = e, Type = e and e.Type or 0 } end
local items = {
    [1] = { Name = "Sad Onion", Hidden = false, Quality = 3, MaxCharges = 0, ChargeType = 0 },
    [2] = { Name = "Test Active", Hidden = false, Quality = 1, MaxCharges = 6, ChargeType = 0 },
    [3] = { Name = "Timed Active", Hidden = false, Quality = 2, MaxCharges = 6, ChargeType = 1 },
    [4] = { Name = "Hidden", Hidden = true, Quality = 4, MaxCharges = 0, ChargeType = 0 },
    [5] = { Name = "Other Mod Item", Hidden = false, Quality = 4, MaxCharges = 0, ChargeType = 0 },
}
local itemConfig = {}
function itemConfig:GetCollectibles() return { Size = 6 } end
function itemConfig:GetCollectible(id) return items[id] end
function itemConfig:GetCard(id) return id >= 1 and id <= 98 and {} or nil end
function itemConfig:GetTrinket(id) return id >= 1 and id <= 189 and {} or nil end
local function newPlayer(controller)
    local p = {
        Type = 1, InitSeed = 100 + (controller or 0), ControllerIndex = controller or 0, Position = vector,
        coins = 0, keys = 0, bombs = 0, hearts = 6, maxHearts = 6, counts = {}, card = {}, pill = {}, trinket = {}, effects = {}, active = { [0] = 2 },
        charge = { [0] = 0 }, battery = {}, inventory = {}, alive = true,
        Damage = 3.5, MaxFireDelay = 10, MoveSpeed = 1, TearRange = 260, ShotSpeed = 1, Luck = 0, CanFly = false,
        TearFlags = 0, Velocity = Vector.Zero, forms = {}, special = {}, dead = false,
    }
    function p:Exists() return self.alive end
    function p:ToPlayer() return self end
    function p:GetPlayerType() return self.character or 0 end
    function p:HasCollectible(id) return self.inventory[id] == true end
    function p:GetActiveItem(slot) return self.active[slot] or 0 end
    function p:GetActiveCharge(slot) return self.charge[slot] or 0 end
    function p:GetBatteryCharge(slot) return self.battery[slot] or 0 end
    function p:SetActiveCharge(n, slot)
        self.charge[slot] = math.min(n, 6); self.battery[slot] = math.max(0, n - 6)
    end
    function p:AddCollectible(id, _, _, slot)
        self.inventory[id] = true; self.counts[id] = (self.counts[id] or 0) + 1
        if items[id] and items[id].MaxCharges > 0 then self.active[slot or 0] = id end
    end
    function p:GetCollectibleNum(id) return self.counts[id] or (self.inventory[id] and 1 or 0) end
    function p:GetCollectibleCount() local n = 0; for _, count in pairs(self.counts) do n = n + count end; return n end
    function p:RemoveCollectible(id)
        self.counts[id] = math.max(0, self:GetCollectibleNum(id) - 1)
        self.inventory[id] = self.counts[id] > 0
    end
    function p:IsDead() return self.dead end
    function p:Revive() self.dead = false; self.hearts = 2 end
    function p:ChangePlayerType(id) self.character = id end
    function p:GetHearts() return self.hearts end
    function p:GetMaxHearts() return self.maxHearts end
    function p:GetSoulHearts() return self.soul or 0 end
    function p:GetBlackHearts() return self.black or 0 end
    function p:GetBoneHearts() return self.bone or 0 end
    function p:GetRottenHearts() return self.rotten or 0 end
    function p:GetEternalHearts() return self.eternal or 0 end
    function p:GetGoldenHearts() return self.golden or 0 end
    function p:GetBrokenHearts() return self.broken or 0 end
    for key, method in pairs({ soul = "AddSoulHearts", black = "AddBlackHearts", bone = "AddBoneHearts", rotten = "AddRottenHearts",
        eternal = "AddEternalHearts", golden = "AddGoldenHearts", broken = "AddBrokenHearts" }) do
        local name = key; p[method] = function(self, n) self[name] = (self[name] or 0) + n end
    end
    function p:AddMaxHearts(n) self.maxHearts = self.maxHearts + n end
    function p:SetFullHearts() self.hearts = self.maxHearts end
    function p:GetCard(slot) return self.card[slot] or 0 end
    function p:GetPill(slot) return self.pill[slot] or 0 end
    function p:GetTrinket(slot) return self.trinket[slot] or 0 end
    function p:SetCard(slot, id) self.card[slot] = id end
    function p:SetPill(slot, id) self.pill[slot] = id end
    function p:AddCard(id) self.card[0] = id end
    function p:AddPill(id) self.pill[0] = id end
    function p:AddTrinket(id) self.trinket[0] = id end
    function p:TryRemoveTrinket(id) for slot, value in pairs(self.trinket) do if value == id then self.trinket[slot] = 0 end end end
    function p:GetTrinketMultiplier(id) local n = 0; for _, value in pairs(self.trinket) do if value == id then n = n + 1 end end; return n end
    function p:HasPlayerForm(id) return self.forms[id] == true end
    function p:GetMovementInput() return self.movement or Vector.Zero end
    function p:GetShootingInput() return self.shooting or Vector.Zero end
    function p:AddCacheFlags(flags) self.cache = flags end
    function p:EvaluateItems()
        self.Damage, self.MaxFireDelay, self.MoveSpeed, self.TearRange, self.ShotSpeed, self.Luck, self.CanFly = 3.5, 10, 1, 260, 1, 0, false
        for _, flag in ipairs({ CacheFlag.CACHE_DAMAGE, CacheFlag.CACHE_FIREDELAY, CacheFlag.CACHE_SPEED, CacheFlag.CACHE_RANGE,
            CacheFlag.CACHE_SHOTSPEED, CacheFlag.CACHE_LUCK, CacheFlag.CACHE_FLYING, CacheFlag.CACHE_TEARFLAG }) do
            if G.mod then G.fire(ModCallbacks.MC_EVALUATE_CACHE, self, flag) end
        end
    end
    function p:TakeDamage(amount, flags, source)
        G.fire(ModCallbacks.MC_ENTITY_TAKE_DMG, self, amount, flags, source, 0)
        self.hearts = math.max(0, self.hearts - amount); if self.hearts == 0 then self.dead = true end
    end
    function p:SetMinDamageCooldown(n) self.cooldown = n end
    function p:UseActiveItem(id, flags, slot) G.fire(ModCallbacks.MC_USE_ITEM, id, {}, self, flags, slot, 0) end
    function p:UseCard(id, flags) G.fire(ModCallbacks.MC_USE_CARD, id, self, flags) end
    function p:UsePill(id, color, flags) G.fire(ModCallbacks.MC_USE_PILL, id, self, flags, color) end
    function p:SwapActiveItems() self.active[0], self.active[1] = self.active[1], self.active[0] end
    function p:DropPocketItem(slot, pos)
        local id = self:GetCard(slot); if id > 0 then Isaac.Spawn(5, 300, id, pos, Vector.Zero, self); self.card[slot] = 0 end
    end
    function p:DropTrinket(pos) local id = self:GetTrinket(0); if id > 0 then Isaac.Spawn(5, 350, id, pos, Vector.Zero, self); self.trinket[0] = 0 end end
    function p:AddGoldenKey() self.goldenKey = true end
    function p:RemoveGoldenKey() self.goldenKey = false end
    function p:AddGoldenBomb() self.goldenBomb = true end
    function p:RemoveGoldenBomb() self.goldenBomb = false end
    for key, pair in pairs({ soulCharge = { "GetSoulCharge", "AddSoulCharge" }, bloodCharge = { "GetBloodCharge", "AddBloodCharge" },
        poopMana = { "GetPoopMana", "AddPoopMana" }, jarHearts = { "GetJarHearts", "AddJarHearts" },
        jarFlies = { "GetJarFlies", "AddJarFlies" }, gigaBombs = { "GetNumGigaBombs", "AddGigaBombs" } }) do
        local name = key
        p[pair[1]] = function(self) return self.special[name] or 0 end
        p[pair[2]] = function(self, n) self.special[name] = (self.special[name] or 0) + n end
    end
    function p:GetEffects()
        local effects = self.effects
        return setmetatable({}, { __index = function(_, method)
            return function(_, id, a, count)
                local key = method:match("Collectible") and "c" or method:match("Trinket") and "t" or "n"
                key = key .. id
                effects[key] = (effects[key] or 0) + (method:match("^Add") and (count or 1) or -(a or 1))
            end
        end })
    end
    function p:GetNumCoins() return self.coins end
    function p:GetNumKeys() return self.keys end
    function p:GetNumBombs() return self.bombs end
    function p:AddCoins(n) self.coins = math.min(99, self.coins + n) end
    function p:AddKeys(n) self.keys = math.min(99, self.keys + n) end
    function p:AddBombs(n) self.bombs = math.min(99, self.bombs + n) end
    function p:AddHearts(n) self.hearts = self.hearts + n end
    return p
end
G.newPlayer = newPlayer
G.players[1] = newPlayer()
local room = {}
function room:IsClear() return G.clear end
function room:IsFirstVisit() return G.firstVisit == true end
function room:GetRoomShape() return 1 end
function room:GetAliveEnemiesCount() local n = 0; for _, e in ipairs(G.entities) do if e:Exists() and e.Type >= 10 and e.Type < 1000 then n = n + 1 end end; return n end
function room:GetAliveBossesCount() return G.bossCount or 0 end
function room:GetFrameCount() return G.frame end
function room:GetRandomPosition() return vector end
function room:GetGridSize() return 16 end
function room:GetGridEntity(index) return G.grids and G.grids[index] end
function room:GetGridPosition(index) return Vector(index * 10, 100) end
function room:GetGridIndex() return 0 end
function room:GetDoor(slot) return G.doors and G.doors[slot] end
function room:GetBrokenWatchState() return G.watch or 0 end
function room:SetBrokenWatchState(n) G.watch = n end
function room:SpawnClearAward() G.fire(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD) end
function room:GetType() return G.roomType end
function room:GetCenterPos() return vector end
function room:FindFreePickupSpawnPosition(pos) return pos end
function room:FindFreeTilePosition(pos) return pos end
local level = {}
function level:GetCurses() return G.curses end
function level:AddCurse(flags) G.curses = G.curses | flags end
function level:RemoveCurses(flags) G.curses = G.curses & ~flags end
function level:GetCurrentRoomIndex() return G.roomIndex end
function level:GetRoomByIdx(index) return { Data = index >= 0 and {} or nil } end
function level:GetStage() return G.stage end
function level:GetStageType() return 0 end
function level:GetDungeonPlacementSeed() return G.floorSeed end
function level:GetCurrentRoomDesc() return { ListIndex = G.roomIndex, SpawnSeed = 300 + G.roomIndex } end
local seeds = {}
function seeds:GetStartSeed() return G.seed end
function seeds:GetStartSeedString() return "SEED TEST" end
local pool = {}
function pool:GetCollectible(_, decrease, seed)
    assert(decrease == false and type(seed) == "number", "抽取必须使用私有种子且不消耗道具池")
    return 5
end
local game = {}
function game:IsPaused() return G.paused == true end
function game:IsGreedMode() return false end
function game:StartRoomTransition(index) G.roomIndex = index; G.fire(ModCallbacks.MC_POST_NEW_ROOM) end
function game:GetNumPlayers() return #G.players end
function game:GetLevel() return level end
function game:GetRoom() return room end
function game:GetSeeds() return seeds end
function game:GetItemPool() return pool end
function game:GetFrameCount() return G.frame end
Game = function() return game end
Isaac = {
    GetRoomEntities = function() local entities = {}; for _, e in ipairs(G.entities) do if e:Exists() then entities[#entities + 1] = e end end; return entities end,
    ExecuteCommand = function(command) G.lastNativeCommand = command end,
    GetItemConfig = function() return itemConfig end,
    GetPlayer = function(index) return G.players[index + 1] end,
    DebugString = function(msg) G.logs[#G.logs + 1] = msg end,
    ConsoleOutput = function(msg) G.output[#G.output + 1] = msg end,
    Spawn = function(t, v, s, pos, velocity, spawner)
        G.spawned[#G.spawned + 1] = { t, v, s, pos, velocity, spawner }
        local entity = G.newEntity(t, v, s, pos, spawner)
        local name = ({ [2] = "MC_POST_TEAR_INIT", [3] = "MC_FAMILIAR_INIT", [4] = "MC_POST_BOMB_INIT", [5] = "MC_POST_PICKUP_INIT",
            [7] = "MC_POST_LASER_INIT", [8] = "MC_POST_KNIFE_INIT", [9] = "MC_POST_PROJECTILE_INIT", [1000] = "MC_POST_EFFECT_INIT" })[t] or "MC_POST_NPC_INIT"
        G.fire(ModCallbacks[name], entity)
        return entity
    end,
}
function G.newEntity(t, v, s, pos, spawner)
    local e = { Type = t, Variant = v, SubType = s, InitSeed = 10000 + #G.entities,
        Position = pos or vector, Velocity = Vector.Zero, SpawnerEntity = spawner, HitPoints = 10, MaxHitPoints = 10,
        State = 0, data = {}, removed = false, dead = false, flags = 0 }
    function e:Exists() return not self.removed end
    function e:GetData() return self.data end
    function e:ToPlayer() return nil end
    function e:ToNPC() return self.Type >= 10 and self.Type < 1000 and self or nil end
    function e:ToPickup() return self.Type == 5 and self or nil end
    function e:IsActiveEnemy() return self:ToNPC() ~= nil and not self.removed end
    function e:IsBoss() return self.boss == true end
    function e:HasEntityFlags(flags) return (self.flags & flags) ~= 0 end
    function e:AddEntityFlags(flags) self.flags = self.flags | flags end
    function e:ClearEntityFlags(flags) self.flags = self.flags & ~flags end
    function e:Kill() self.dead = true; G.fire(ModCallbacks.MC_POST_ENTITY_KILL, self) end
    function e:Remove() self.removed = true; G.fire(ModCallbacks.MC_POST_ENTITY_REMOVE, self) end
    function e:TakeDamage(n, flags, source)
        G.fire(ModCallbacks.MC_ENTITY_TAKE_DMG, self, n, flags, source, 0)
        self.HitPoints = self.HitPoints - n; if self.HitPoints <= 0 then self:Kill() end
    end
    function e:Morph(t2, v2, s2) self.Type, self.Variant, self.SubType = t2, v2, s2 end
    function e:SetColor(c) self.color = c end
    function e:IsShopItem() return self.shop == true end
    function e:GetSprite()
        local entity = self
        return { IsPlaying = function(_, name) return entity.animation == name end,
            GetAnimation = function() return entity.animation or "Idle" end, IsFinished = function() return entity.finished == true end }
    end
    G.entities[#G.entities + 1] = e
    return e
end
local rows = {}
ModConfigMenu = {
    OptionType = { TEXT = 1, SPACE = 2, SCROLL = 3, BOOLEAN = 4, NUMBER = 5 },
    AddSetting = function(category, tab, row)
        rows[tab] = rows[tab] or {}; rows[tab][#rows[tab] + 1] = row
        assert(category == "事件工坊 Event Workshop")
        return row
    end,
    AddText = function(category, tab, label)
        return ModConfigMenu.AddSetting(category, tab, { Type = 1, Display = label, NoCursorHere = true })
    end,
    AddSpace = function(category, tab)
        return ModConfigMenu.AddSetting(category, tab, { Type = 2 })
    end,
}
G.rows = rows
function RegisterMod(name)
    assert(name == "Event Workshop")
    local mod = { callbacks = {} }
    function mod:HasData() return G.stored ~= "" end
    function mod:LoadData() return G.stored end
    function mod:SaveData(value) G.stored = value end
    function mod:AddCallback(event, fn)
        self.callbacks[event] = self.callbacks[event] or {}
        table.insert(self.callbacks[event], fn)
    end
    G.mod = mod
    return mod
end
include = function(path) return dofile("event_workshop/" .. path .. ".lua") end
function G.fire(event, ...)
    local last
    for _, fn in ipairs(G.mod.callbacks[event] or {}) do
        last = fn(G.mod, ...)
    end
    return last
end
function G.start(continued)
    if not continued then G.frame = 1 end
    G.fire(ModCallbacks.MC_POST_NEW_ROOM)
    G.fire(ModCallbacks.MC_POST_NEW_LEVEL)
    G.fire(ModCallbacks.MC_POST_GAME_STARTED, continued or false)
end
function G.tick()
    G.frame = G.frame + 1
    G.fire(ModCallbacks.MC_POST_UPDATE)
end
function G.consoleInput(input)
    local command, args = input:match("^(%S+)%s*(.*)$")
    if command == "lua" then
        assert(load(args))()
    else
        -- 模拟本机忏悔+ 原生控制台：未知命令不会转交 MC_EXECUTE_CMD。
        G.output[#G.output + 1] = "Unknown command: " .. tostring(command) .. "\n"
    end
end
function G.command(cmd)
    local before = #G.output
    G.consoleInput("lua EW(" .. string.format("%q", cmd) .. ")")
    local result = table.concat(G.output, "", before + 1)
    assert(not result:find("ERROR: ", 1, true), result)
    return result
end
function G.saved() return G.json.decode(G.stored) end
function G.reload()
    for key in pairs(rows) do rows[key] = nil end
    dofile("event_workshop/main.lua")
end
G.reload()
return G
