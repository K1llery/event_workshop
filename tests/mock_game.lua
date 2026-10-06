local G = {
    frame = 0, seed = 12345, roomIndex = 0, floorSeed = 200, stage = 1,
    roomType = 1, stored = "", output = {}, logs = {}, spawned = {}, players = {},
}
BitSet128 = function(lo) return lo end
ItemConfig, Entity, RoomDescriptor = {}, {}, {}
local gameDir = os.getenv("ISAAC_GAME_DIR") or "/mnt/d/SteamLibrary/steamapps/common/The Binding of Isaac Rebirth"
dofile(gameDir .. "/resources/scripts/enums.lua")
package.preload.json = function() return dofile(gameDir .. "/resources/scripts/json.lua") end
G.json = require("json")
local vector = { X = 100, Y = 100 }
Vector = { Zero = { X = 0, Y = 0 } }
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
        InitSeed = 100 + (controller or 0), ControllerIndex = controller or 0, Position = vector,
        coins = 0, keys = 0, bombs = 0, hearts = 6, active = { [0] = 2 },
        charge = { [0] = 0 }, battery = {}, inventory = {}, alive = true,
    }
    function p:Exists() return self.alive end
    function p:ToPlayer() return self end
    function p:GetPlayerType() return 0 end
    function p:HasCollectible(id) return self.inventory[id] == true end
    function p:GetActiveItem(slot) return self.active[slot] or 0 end
    function p:GetActiveCharge(slot) return self.charge[slot] or 0 end
    function p:GetBatteryCharge(slot) return self.battery[slot] or 0 end
    function p:SetActiveCharge(n, slot)
        self.charge[slot] = math.min(n, 6); self.battery[slot] = math.max(0, n - 6)
    end
    function p:AddCollectible(id) self.inventory[id] = true end
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
function room:GetType() return G.roomType end
function room:GetCenterPos() return vector end
function room:FindFreePickupSpawnPosition(pos) return pos end
function room:FindFreeTilePosition(pos) return pos end
local level = {}
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
function game:GetNumPlayers() return #G.players end
function game:GetLevel() return level end
function game:GetRoom() return room end
function game:GetSeeds() return seeds end
function game:GetItemPool() return pool end
function game:GetFrameCount() return G.frame end
Game = function() return game end
Isaac = {
    GetItemConfig = function() return itemConfig end,
    GetPlayer = function(index) return G.players[index + 1] end,
    DebugString = function(msg) G.logs[#G.logs + 1] = msg end,
    ConsoleOutput = function(msg) G.output[#G.output + 1] = msg end,
    Spawn = function(t, v, s, pos, velocity, spawner)
        G.spawned[#G.spawned + 1] = { t, v, s, pos, velocity, spawner }
        return {}
    end,
}
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
function G.command(cmd)
    local before = #G.output
    G.fire(ModCallbacks.MC_EXECUTE_CMD, "ew", cmd)
    local result = table.concat(G.output, "", before + 1)
    assert(not result:find("错误：", 1, true), result)
    return result
end
function G.saved() return G.json.decode(G.stored) end
function G.reload()
    for key in pairs(rows) do rows[key] = nil end
    dofile("event_workshop/main.lua")
end
G.reload()
return G
