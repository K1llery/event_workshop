#!/usr/bin/env python3
"""使用系统已有 Lua 动态库检查源码并运行测试，不安装新的运行时。"""

from __future__ import annotations

import ctypes
import ctypes.util
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    library = ctypes.util.find_library("lua5.3") or ctypes.util.find_library("lua5.4")
    if not library:
        print("未找到 Lua 5.3/5.4 动态库；可以在游戏控制台执行 lua EW('selftest')。")
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
        metadata = ET.parse(ROOT / "event_workshop" / "metadata.xml").getroot()
        source = (ROOT / "event_workshop" / "main.lua").read_text(encoding="utf-8")
        registration = re.search(r'RegisterMod\("([^"]+)"', source)
        if not registration or metadata.findtext("name") != registration.group(1):
            raise RuntimeError("metadata.xml 名称必须与 RegisterMod 名称一致")
        if metadata.findtext("directory") != "event_workshop":
            raise RuntimeError("metadata.xml directory 必须与模组安装目录一致")
        if not any(tag.get("id") == "Lua" for tag in metadata.findall("tag")):
            raise RuntimeError("metadata.xml 缺少本项目要求的 Lua 标签")
        if metadata.findtext("version") != "1.0.1":
            raise RuntimeError("metadata.xml 安装版本须保持本机已验证的 1.0.1；发行版本使用 catalog.lua 的 C.version")
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
