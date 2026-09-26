"""Sprite pipeline checks. Matte round-trip needs Pillow and numpy."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from sprite_pipeline.cast import check, load, prompt  # noqa: E402
from sprite_pipeline.wiring import wiring_errors  # noqa: E402


class Cast(unittest.TestCase):
    def test_cast_is_short_and_editable(self):
        doc = load()
        self.assertEqual(check(doc), [])
        self.assertEqual(doc["base"], "bikini")
        text = prompt(doc, doc["characters"][0])
        self.assertIn("base: bikini", text)
        self.assertNotIn("EXCLUDE", text)

    def test_no_pipeline_markdown(self):
        roots = [ROOT / "ai_agent_docs", ROOT / "characters", ROOT / "tools" / "sprite_pipeline"]
        found = []
        for root in roots:
            if not root.exists():
                continue
            found.extend(p.relative_to(ROOT).as_posix() for p in root.rglob("*.md"))
        self.assertEqual(found, [])


class Wiring(unittest.TestCase):
    def test_dialogue_sprite_tags_resolve(self):
        self.assertEqual(wiring_errors(), [])


class Install(unittest.TestCase):
    def test_refuses_overwrite(self):
        import importlib.util

        spec = importlib.util.spec_from_file_location("install_sprite", ROOT / "tools" / "install_sprite.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            src = tmp / "draft.png"
            src.write_bytes(b"x")
            assets = tmp / "assets"
            assets.mkdir()
            (assets / "ren_neutral.webp").write_bytes(b"old")
            with self.assertRaises(SystemExit):
                module.install(src, "ren", "neutral", assets_dir=assets, sprites_dir=tmp / "sprites")


class Matte(unittest.TestCase):
    def test_partial_alpha_round_trip(self):
        try:
            import numpy as np
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow and numpy are not installed")
        import importlib.util

        spec = importlib.util.spec_from_file_location("triangulate_matte", ROOT / "tools" / "triangulate_matte.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            white = np.ones((8, 8, 3), dtype=np.float32)
            black = np.zeros((8, 8, 3), dtype=np.float32)
            colour = np.array([0.8, 0.2, 0.4], dtype=np.float32)
            white[1, 1] = colour
            black[1, 1] = colour
            white[2, 2] = colour * 0.5 + 0.5
            black[2, 2] = colour * 0.5
            Image.fromarray((white * 255 + 0.5).astype("uint8"), "RGB").save(tmp / "w.png")
            Image.fromarray((black * 255 + 0.5).astype("uint8"), "RGB").save(tmp / "b.png")
            module.triangulate(tmp / "w.png", tmp / "b.png", tmp / "out.png", tmp / "a.png")
            rgba = np.asarray(Image.open(tmp / "out.png").convert("RGBA"), dtype=np.float32) / 255.0
            self.assertAlmostEqual(float(rgba[1, 1, 3]), 1.0, delta=0.02)
            self.assertAlmostEqual(float(rgba[2, 2, 3]), 0.5, delta=0.02)
            self.assertAlmostEqual(float(rgba[0, 0, 3]), 0.0, delta=0.02)
