local root = "event_workshop/"
local C = dofile(root .. "scripts/ew/catalog.lua")
local S = dofile(root .. "scripts/ew/schema.lua")(C)
local makeEngine = dofile(root .. "scripts/ew/engine.lua")
local test = dofile(root .. "scripts/ew/selftest.lua")(C, S, makeEngine)
print("规则引擎自检通过：" .. test() .. " 项")
dofile("tests/integration.lua")
