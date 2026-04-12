from __future__ import annotations

import pathlib
import subprocess
import sys
import unittest

from swift_alignment_programming.renderer import render_from_symbol_graph_directory


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "bird-shape-symbolgraphs"
EXPECTED_OUTPUT = (REPO_ROOT / "tests" / "fixtures" / "BirdShapeKit.public.swift").read_text()


class RendererTests(unittest.TestCase):
    def test_renderer_matches_fixture_output(self) -> None:
        rendered = render_from_symbol_graph_directory(FIXTURE_DIR, "BirdShapeKit")
        self.assertEqual(rendered, EXPECTED_OUTPUT)

    def test_cli_can_render_from_fixture_directory(self) -> None:
        command = [
            sys.executable,
            str(REPO_ROOT / "generate_public_interface"),
            "--target",
            "BirdShapeKit",
            "--symbol-graph-dir",
            str(FIXTURE_DIR),
        ]
        result = subprocess.run(command, check=True, text=True, capture_output=True)
        self.assertEqual(result.stdout, EXPECTED_OUTPUT)
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
