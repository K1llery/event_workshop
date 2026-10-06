#!/usr/bin/env python3
"""复制本项目模组源码并构建安装包，保留游戏生成的文件和存档。"""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "event_workshop"


def build() -> Path:
    archive = ROOT / "dist" / "event_workshop-1.0.0.zip"
    archive.parent.mkdir(exist_ok=True)
    with ZipFile(archive, "w", ZIP_DEFLATED) as output:
        for path in sorted(SOURCE.rglob("*")):
            if path.is_file():
                output.write(path, path.relative_to(ROOT))
        output.write(ROOT / "docs" / "使用说明.md", "使用说明.md")
    return archive


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--game-dir",
        type=Path,
        default=Path("/mnt/d/SteamLibrary/steamapps/common/The Binding of Isaac Rebirth"),
    )
    parser.add_argument("--package-only", action="store_true")
    args = parser.parse_args()
    if not args.package_only:
        if not (args.game_dir / "isaac-ng.exe").is_file():
            parser.error("游戏目录不存在或缺少 isaac-ng.exe")
        target = args.game_dir / "mods" / "event_workshop"
        if target.exists():
            metadata = target / "metadata.xml"
            if not metadata.is_file() or ET.parse(metadata).findtext("directory") != "event_workshop":
                parser.error("目标目录已有其他内容，停止覆盖")
        target.mkdir(parents=True, exist_ok=True)
        count = 0
        for path in sorted(SOURCE.rglob("*")):
            if path.is_file():
                dest = target / path.relative_to(SOURCE)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, dest)
                count += 1
        print(f"已安装 {count} 个源码文件：{target}")
    print(f"安装包：{build()}")


if __name__ == "__main__":
    main()
