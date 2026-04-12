from __future__ import annotations

import argparse
import pathlib
import shutil
import subprocess
import sys

from .renderer import render_from_symbol_graph_directory


def build_symbol_graph(package_path: pathlib.Path, target: str, verbose_build: bool) -> pathlib.Path:
    artifact_dir = package_path / ".build" / "public-interface-artifacts" / "symbolgraphs"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    for stale in artifact_dir.glob(f"{target}*.json"):
        stale.unlink()

    command = [
        "swift",
        "build",
        "--package-path",
        str(package_path),
        "--target",
        target,
        "-Xswiftc",
        "-emit-symbol-graph",
        "-Xswiftc",
        "-emit-symbol-graph-dir",
        "-Xswiftc",
        str(artifact_dir),
        "-Xswiftc",
        "-symbol-graph-minimum-access-level",
        "-Xswiftc",
        "public",
    ]

    result = subprocess.run(command, text=True, capture_output=True)
    if verbose_build:
        if result.stdout:
            print(result.stdout, end="", file=sys.stderr)
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        if not verbose_build:
            if result.stdout:
                print(result.stdout, end="", file=sys.stderr)
            if result.stderr:
                print(result.stderr, end="", file=sys.stderr)
        raise subprocess.CalledProcessError(result.returncode, command)

    if not list(artifact_dir.glob(f"{target}*.json")):
        raise FileNotFoundError(f"No symbol graph JSON files were generated for target {target} in {artifact_dir}")
    return artifact_dir


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a readable pseudo-Swift public interface for a SwiftPM target from symbol graphs."
    )
    parser.add_argument("--target", required=True, help="SwiftPM target name")
    parser.add_argument(
        "--package-path",
        default=".",
        help="Path to the Swift package root (defaults to current directory)",
    )
    parser.add_argument(
        "--symbol-graph-dir",
        help="Use an existing symbol graph directory instead of building the target",
    )
    parser.add_argument(
        "--output",
        help="Write the rendered pseudo-Swift interface to this file instead of stdout",
    )
    parser.add_argument(
        "--verbose-build",
        action="store_true",
        help="Print underlying swift build output to stderr",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    package_path = pathlib.Path(args.package_path).resolve()
    if args.symbol_graph_dir:
        symbol_graph_dir = pathlib.Path(args.symbol_graph_dir).resolve()
    else:
        symbol_graph_dir = build_symbol_graph(package_path, args.target, args.verbose_build)

    rendered = render_from_symbol_graph_directory(symbol_graph_dir, args.target)

    if args.output:
        output_path = pathlib.Path(args.output)
        if not output_path.is_absolute():
            output_path = package_path / output_path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(rendered)
    else:
        sys.stdout.write(rendered)
    return 0
