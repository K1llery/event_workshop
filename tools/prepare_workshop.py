#!/usr/bin/env python3
"""生成独立的创意工坊上传目录，保留已有条目 ID 和上传修订号。"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "event_workshop"
ASSETS = ROOT / "workshop"


def prepare(destination: Path) -> None:
    mod_dir = destination / "event_workshop"
    metadata_path = mod_dir / "metadata.xml"
    previous = None
    if mod_dir.exists():
        if not metadata_path.is_file():
            raise ValueError("目标目录已有不属于本项目的内容，停止覆盖")
        previous = ET.parse(metadata_path).getroot()
        if (previous.findtext("directory") != "event_workshop"
                or previous.findtext("name") != "Event Workshop"):
            raise ValueError("目标目录不是 Event Workshop，停止覆盖")
        allowed = {p.relative_to(SOURCE) for p in SOURCE.rglob("*") if p.is_file()}
        unexpected = [
            str(p.relative_to(mod_dir)) for p in mod_dir.rglob("*")
            if p.is_file() and p.relative_to(mod_dir) not in allowed
        ]
        if unexpected:
            raise ValueError("上传目录包含额外文件，请先检查：" + ", ".join(unexpected))

    description = (ASSETS / "description.bbcode.txt").read_text(encoding="utf-8").strip()
    if len(description.encode("utf-8")) >= 8000:
        raise ValueError("创意工坊说明的 UTF-8 编码须少于 8000 字节")
    preview = ASSETS / "preview.jpg"
    if not preview.is_file() or not 0 < preview.stat().st_size < 1_000_000:
        raise ValueError("封面不存在或超过 1 MB")
    registration = re.search(
        r'RegisterMod\("([^"]+)"', (SOURCE / "main.lua").read_text(encoding="utf-8")
    )
    if not registration or registration.group(1) != "Event Workshop":
        raise ValueError("上传名称必须与已验证的 RegisterMod 名称一致")

    metadata = ET.parse(SOURCE / "metadata.xml").getroot()
    metadata.find("description").text = description
    # 官方工具的 version 是递增上传修订号，不是 C.version 功能版本。
    metadata.find("version").text = (
        previous.findtext("version", "1") if previous is not None else "1"
    )
    ET.SubElement(metadata, "visibility").text = "Private"
    ET.SubElement(metadata, "tag", {"id": "Tweaks"})
    if previous is not None and previous.findtext("id"):
        ET.SubElement(metadata, "id").text = previous.findtext("id")

    mod_dir.mkdir(parents=True, exist_ok=True)
    for path in sorted(SOURCE.rglob("*")):
        if path.is_file() and path.name != "metadata.xml":
            target = mod_dir / path.relative_to(SOURCE)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    ET.indent(metadata, space="  ")
    ET.ElementTree(metadata).write(metadata_path, encoding="utf-8", xml_declaration=True)
    for name in ("preview.jpg", "description.bbcode.txt", "change-notes.txt", "上传步骤.md"):
        shutil.copy2(ASSETS / name, destination / name)
    manifest = {
        "visibility": "Private",
        "workshop_id": metadata.findtext("id"),
        "upload_revision": metadata.findtext("version"),
        "description_chars": len(description),
        "files": {
            str(p.relative_to(mod_dir)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(mod_dir.rglob("*")) if p.is_file()
        },
        "preview_sha256": hashlib.sha256(preview.read_bytes()).hexdigest(),
    }
    (destination / "release-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"上传 metadata：{metadata_path}")
    print(f"封面：{destination / 'preview.jpg'}")
    print(
        f"可见性：Private；说明 {len(description)} 字符；"
        f"上传文件 {len(manifest['files'])} 个"
    )
    if manifest["workshop_id"]:
        print(f"已有创意工坊条目 ID：{manifest['workshop_id']}；再次上传会更新此条目")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("/mnt/d/IsaacWorkshop"))
    args = parser.parse_args()
    prepare(args.output_dir)


if __name__ == "__main__":
    main()
