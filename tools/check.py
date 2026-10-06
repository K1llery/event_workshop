#!/usr/bin/env python3
"""使用系统已有 Lua 动态库检查源码并运行测试，不安装新的运行时。"""

from __future__ import annotations

import ctypes
import ctypes.util
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    library = ctypes.util.find_library("lua5.3") or ctypes.util.find_library("lua5.4")
    if not library:
        print("未找到 Lua 5.3/5.4 动态库；可以在游戏控制台执行 ew selftest。")
        return 2
    lua = ctypes.CDLL(library)
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lua.luaL_loadfilex.restype = ctypes.c_int
    lua.lua_pcallk.argtypes = [
        ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
        ctypes.c_longlong, ctypes.c_void_p,
    ]
    lua.lua_pcallk.restype = ctypes.c_int
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    lua.luaL_openlibs(state)
    try:
        files = sorted((ROOT / "event_workshop").rglob("*.lua"))
        files += sorted((ROOT / "tests").rglob("*.lua"))
        for path in files:
            if lua.luaL_loadfilex(state, str(path).encode(), None):
                raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
            lua.lua_settop(state, 0)
        ET.parse(ROOT / "event_workshop" / "metadata.xml")
        print(f"Lua 语法检查通过：{len(files)} 个文件（{library}）；metadata.xml 解析通过", flush=True)
        import os
        os.chdir(ROOT)
        test_path = ROOT / "tests" / "run.lua"
        if lua.luaL_loadfilex(state, str(test_path).encode(), None):
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
        if lua.lua_pcallk(state, 0, 0, 0, 0, None):
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
        return 0
    except (RuntimeError, ET.ParseError) as error:
        print(error, file=sys.stderr)
        return 1
    finally:
        lua.lua_close(state)


if __name__ == "__main__":
    raise SystemExit(main())
