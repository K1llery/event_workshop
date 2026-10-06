"""验证上传目录隔离、隐藏设置及已有创意工坊条目身份保留。"""

import contextlib
import io
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from tools.prepare_workshop import SOURCE, prepare


class WorkshopPreparationTests(unittest.TestCase):
    def build(self, directory: Path) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            prepare(directory)

    def test_private_package_does_not_modify_source(self) -> None:
        original = (SOURCE / "metadata.xml").read_bytes()
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            self.build(directory)
            mod_dir = directory / "event_workshop"
            metadata = ET.parse(mod_dir / "metadata.xml").getroot()
            self.assertEqual(metadata.findtext("visibility"), "Private")
            self.assertEqual(metadata.findtext("version"), "1")
            self.assertIsNone(metadata.find("id"))
            for path in SOURCE.rglob("*.lua"):
                self.assertEqual(
                    path.read_bytes(), (mod_dir / path.relative_to(SOURCE)).read_bytes()
                )
            self.assertFalse((mod_dir / "preview.jpg").exists())
            self.assertLess((directory / "preview.jpg").stat().st_size, 1_000_000)
        self.assertEqual(original, (SOURCE / "metadata.xml").read_bytes())

    def test_rebuild_preserves_published_item_id_and_revision(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            self.build(directory)
            path = directory / "event_workshop" / "metadata.xml"
            tree = ET.parse(path)
            ET.SubElement(tree.getroot(), "id").text = "1234567890"
            tree.find("version").text = "41"
            tree.write(path, encoding="utf-8", xml_declaration=True)
            self.build(directory)
            metadata = ET.parse(path).getroot()
            self.assertEqual(metadata.findtext("id"), "1234567890")
            self.assertEqual(metadata.findtext("version"), "41")

    def test_rejects_extra_files_before_copying(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            self.build(directory)
            extra = directory / "event_workshop" / "personal-save.dat"
            extra.write_bytes(b"must not upload")
            with self.assertRaisesRegex(ValueError, "额外文件"):
                self.build(directory)
            self.assertEqual(extra.read_bytes(), b"must not upload")


if __name__ == "__main__":
    unittest.main()
