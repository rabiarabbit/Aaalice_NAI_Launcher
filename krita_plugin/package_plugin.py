import argparse
import sys
from pathlib import Path
from typing import Sequence
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parent
DIST = ROOT.parent / "dist"
OUTPUT = DIST / "nai_launcher_bridge_krita_plugin.zip"
ALLOWED_PLUGIN_SUFFIXES = {".py", ".md", ".txt"}
ALLOWED_PLUGIN_NAMES = {"LICENSE"}


def main(argv: Sequence[str] = ()) -> None:
    args = _parse_args(argv)
    output = Path(args.output) if args.output else OUTPUT
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w", ZIP_DEFLATED) as archive:
        archive.write(
            ROOT / "nai_launcher_bridge.desktop",
            "nai_launcher_bridge.desktop",
        )
        for path in sorted((ROOT / "nai_launcher_bridge").rglob("*")):
            if (
                path.is_file()
                and "__pycache__" not in path.parts
                and path.suffix != ".pyc"
                and _is_allowed_plugin_file(path)
            ):
                archive.write(path, path.relative_to(ROOT).as_posix())
    print(output)


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Package the Krita NAI Launcher Bridge plugin.",
    )
    parser.add_argument(
        "--output",
        help=(
            "Path to write the zip package. Defaults to "
            "dist/nai_launcher_bridge_krita_plugin.zip."
        ),
    )
    return parser.parse_args(argv)


def _is_allowed_plugin_file(path: Path) -> bool:
    return path.name in ALLOWED_PLUGIN_NAMES or path.suffix in ALLOWED_PLUGIN_SUFFIXES


if __name__ == "__main__":
    main(sys.argv[1:])
