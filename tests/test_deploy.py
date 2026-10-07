"""验证部署前备份、失败中止和安装身份保留。"""

import contextlib
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools import deploy


class DeploymentTests(unittest.TestCase):
    def fixture(self, root: Path) -> tuple[Path, Path]:
        game = root / "game"
        mod = game / "mods/event_workshop"
        mod.mkdir(parents=True)
        (game / "isaac-ng.exe").touch()
        (mod / "main.lua").write_text("old source", encoding="utf-8")
        (mod / "metadata.xml").write_text(
            "<metadata><directory>event_workshop</directory><id>3814693280</id></metadata>",
            encoding="utf-8",
        )
        data = game / "data/event_workshop"
        data.mkdir(parents=True)
        (data / "save2.dat").write_bytes(b"old save")
        return game, mod

    def run_install(self, game: Path) -> None:
        with patch("sys.argv", ["deploy.py", "--game-dir", str(game)]), \
                patch.object(deploy, "build", return_value=game / "package.zip"), \
                contextlib.redirect_stdout(io.StringIO()):
            deploy.main()

    def test_backup_preserves_source_data_and_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            game, mod = self.fixture(root)
            original = (mod / "metadata.xml").read_bytes()
            with patch.object(deploy, "ROOT", root):
                self.run_install(game)
            backup = next((root / "dist/backups").iterdir())
            self.assertEqual((backup / "mods/event_workshop/main.lua").read_text(), "old source")
            self.assertEqual((backup / "data/event_workshop/save2.dat").read_bytes(), b"old save")
            self.assertEqual((game / "data/event_workshop/save2.dat").read_bytes(), b"old save")
            self.assertEqual((mod / "metadata.xml").read_bytes(), original)
            self.assertEqual((mod / "main.lua").read_bytes(), (deploy.SOURCE / "main.lua").read_bytes())
            manifest = json.loads((backup / "manifest.json").read_text())
            for relative, digest in manifest.items():
                self.assertEqual(hashlib.sha256((backup / relative).read_bytes()).hexdigest(), digest)

    def test_backup_failure_stops_before_overwriting(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            game, mod = self.fixture(Path(folder))
            with patch.object(deploy, "backup_install", side_effect=OSError("backup failed")):
                with self.assertRaisesRegex(OSError, "backup failed"):
                    self.run_install(game)
            self.assertEqual((mod / "main.lua").read_text(), "old source")


if __name__ == "__main__":
    unittest.main()
