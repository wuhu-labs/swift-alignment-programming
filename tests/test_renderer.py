from __future__ import annotations

import pathlib
import subprocess
import unittest

from swift_alignment_programming.renderer import render_from_symbol_graph_directory


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
BIRD_SHAPE_FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "bird-shape-symbolgraphs"
BIRD_SHAPE_EXPECTED_OUTPUT = (REPO_ROOT / "tests" / "fixtures" / "BirdShapeKit.public.swift").read_text()
EXTENSION_NESTING_FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "extension-nesting-symbolgraphs"
EXTENSION_NESTING_EXPECTED_OUTPUT = (REPO_ROOT / "tests" / "fixtures" / "ExtensionNesting.public.swift").read_text()


class RendererTests(unittest.TestCase):
    def test_renderer_matches_fixture_output(self) -> None:
        rendered = render_from_symbol_graph_directory(BIRD_SHAPE_FIXTURE_DIR, "BirdShapeKit")
        self.assertEqual(rendered, BIRD_SHAPE_EXPECTED_OUTPUT)

    def test_renderer_nests_types_declared_in_public_extensions(self) -> None:
        rendered = render_from_symbol_graph_directory(EXTENSION_NESTING_FIXTURE_DIR, "ExtensionNesting")
        self.assertEqual(rendered, EXTENSION_NESTING_EXPECTED_OUTPUT)
        self.assertNotIn("public struct Input\n", rendered)
        self.assertNotIn("public func execute(input: Input) -> Result\n\npublic struct Outer", rendered)

    def test_cli_can_render_from_fixture_directory(self) -> None:
        command = [
            str(REPO_ROOT / "generate_public_interface"),
            "--target",
            "BirdShapeKit",
            "--symbol-graph-dir",
            str(BIRD_SHAPE_FIXTURE_DIR),
        ]
        result = subprocess.run(command, check=True, text=True, capture_output=True)
        self.assertEqual(result.stdout, BIRD_SHAPE_EXPECTED_OUTPUT)
        self.assertEqual(result.stderr, "")

    def test_cli_nests_types_declared_in_public_extensions(self) -> None:
        command = [
            str(REPO_ROOT / "generate_public_interface"),
            "--target",
            "ExtensionNesting",
            "--symbol-graph-dir",
            str(EXTENSION_NESTING_FIXTURE_DIR),
        ]
        result = subprocess.run(command, check=True, text=True, capture_output=True)
        self.assertEqual(result.stdout, EXTENSION_NESTING_EXPECTED_OUTPUT)
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
