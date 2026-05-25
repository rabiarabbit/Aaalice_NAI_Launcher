import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLUGIN_ROOT = ROOT / "krita_plugin"
DEFAULT_REPORT_JSON = ROOT / "build" / "krita_acceptance" / "acceptance.json"
DEFAULT_REPORT_MARKDOWN = ROOT / "build" / "krita_acceptance" / "acceptance.md"
DEFAULT_AUTOMATION_EVIDENCE = PLUGIN_ROOT / "automation_evidence.example.json"
PLUGIN_ZIP = ROOT / "dist" / "nai_launcher_bridge_krita_plugin.zip"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run safe Krita Bridge preflight checks without writing the real "
            "Krita profile."
        ),
    )
    parser.add_argument(
        "--skip-tests",
        action="store_true",
        help="Skip Python plugin unit tests.",
    )
    parser.add_argument(
        "--require-acceptance",
        action="store_true",
        help="Return a non-zero exit code when the acceptance report is false.",
    )
    parser.add_argument(
        "--skip-isolated-install",
        action="store_true",
        help="Skip the temporary isolated profile install/apply check.",
    )
    parser.add_argument(
        "--report-json",
        type=Path,
        default=DEFAULT_REPORT_JSON,
        help="Path for the generated acceptance JSON report.",
    )
    parser.add_argument(
        "--report-markdown",
        type=Path,
        default=DEFAULT_REPORT_MARKDOWN,
        help="Path for the generated acceptance Markdown report.",
    )
    parser.add_argument(
        "--package-output",
        type=Path,
        default=PLUGIN_ZIP,
        help=(
            "Path for the generated plugin zip. Defaults to "
            "dist/nai_launcher_bridge_krita_plugin.zip."
        ),
    )
    args = parser.parse_args()

    if not args.skip_tests:
        _run(
            "Python plugin tests",
            [
                sys.executable,
                "-m",
                "unittest",
                "discover",
                "-s",
                "krita_plugin/tests",
            ],
        )

    _run(
        "Package Krita plugin",
        [
            sys.executable,
            "krita_plugin/package_plugin.py",
            "--output",
            str(args.package_output),
        ],
    )
    _print_zip_hash(args.package_output)

    if not args.skip_isolated_install:
        _run_isolated_profile_check()

    _run_capture_allow_failure(
        "Read-only real profile check",
        [sys.executable, "krita_plugin/install_plugin.py", "--check"],
    )

    _run(
        "Acceptance report",
        [
            sys.executable,
            "krita_plugin/acceptance_report.py",
            "--automation-evidence-file",
            str(DEFAULT_AUTOMATION_EVIDENCE),
            "--output-json",
            str(args.report_json),
            "--output-markdown",
            str(args.report_markdown),
        ],
    )

    acceptance_ok = _print_acceptance_summary(args.report_json)
    if args.require_acceptance and not acceptance_ok:
        return 1
    return 0


def _run(label: str, command: list[str]) -> None:
    print(f"\n== {label} ==", flush=True)
    print(" ".join(command), flush=True)
    completed = subprocess.run(command, cwd=ROOT)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)


def _run_capture(label: str, command: list[str]) -> str:
    print(f"\n== {label} ==", flush=True)
    print(" ".join(command), flush=True)
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if completed.stdout:
        print(completed.stdout, end="", flush=True)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)
    return completed.stdout


def _run_capture_allow_failure(label: str, command: list[str]) -> str:
    print(f"\n== {label} ==", flush=True)
    print(" ".join(command), flush=True)
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if completed.stdout:
        print(completed.stdout, end="", flush=True)
    if completed.returncode != 0:
        print(
            f"{label.replace(' ', '_').lower()}_exit={completed.returncode}",
            flush=True,
        )
    return completed.stdout


def _run_isolated_profile_check() -> None:
    with tempfile.TemporaryDirectory(prefix="krita-bridge-preflight-") as temp_dir:
        temp_root = Path(temp_dir)
        pykrita_dir = temp_root / "pykrita"
        kritarc_path = temp_root / "kritarc"
        backup_dir = temp_root / "backup"
        _run(
            "Isolated profile install check",
            [
                sys.executable,
                "krita_plugin/install_plugin.py",
                "--pykrita-dir",
                str(pykrita_dir),
                "--kritarc",
                str(kritarc_path),
                "--backup-dir",
                str(backup_dir),
                "--apply",
            ],
        )
        output = _run_capture(
            "Isolated profile verification",
            [
                sys.executable,
                "krita_plugin/install_plugin.py",
                "--pykrita-dir",
                str(pykrita_dir),
                "--kritarc",
                str(kritarc_path),
                "--check",
            ],
        )
        if "profile_ok=true" not in output:
            raise SystemExit(1)


def _print_zip_hash(path: Path = PLUGIN_ZIP) -> None:
    if not path.exists():
        print(f"plugin_zip=missing path={path}", flush=True)
        return
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"plugin_zip={path}", flush=True)
    print(f"plugin_zip_size={path.stat().st_size}", flush=True)
    print(f"plugin_zip_sha256={digest}", flush=True)


def _print_acceptance_summary(path: Path) -> bool:
    data = json.loads(path.read_text(encoding="utf-8"))
    gates = data.get("gates", [])
    failed = [gate for gate in gates if gate.get("status") != "pass"]
    acceptance_ok = bool(data.get("acceptance_ok"))
    print("\n== Acceptance Summary ==", flush=True)
    print(f"acceptance_ok={str(acceptance_ok).lower()}", flush=True)
    print(f"open_gates={len(failed)}", flush=True)
    for gate in failed:
        print(
            f"- {gate.get('name')}: {gate.get('status')} - {gate.get('detail')}",
            flush=True,
        )
    return acceptance_ok


if __name__ == "__main__":
    raise SystemExit(main())
