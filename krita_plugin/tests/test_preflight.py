import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


PLUGIN_ROOT = Path(__file__).resolve().parents[1]


def _load_preflight():
    spec = importlib.util.spec_from_file_location(
        "krita_bridge_preflight_test",
        PLUGIN_ROOT / "preflight.py",
    )
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _call_silently(callback, *args):
    with redirect_stdout(io.StringIO()):
        return callback(*args)


class PreflightTests(unittest.TestCase):
    def test_skip_tests_and_isolated_install_runs_without_profile_apply(self):
        module = _load_preflight()
        calls = []

        def fake_run(label, command):
            calls.append((label, command))

        def fake_capture(label, command):
            calls.append((label, command))
            return "profile_ok=false\n"

        with (
            patch.object(
                sys,
                "argv",
                ["preflight.py", "--skip-tests", "--skip-isolated-install"],
            ),
            patch.object(module, "_run", side_effect=fake_run),
            patch.object(module, "_run_capture_allow_failure", side_effect=fake_capture),
            patch.object(module, "_print_zip_hash"),
            patch.object(module, "_print_acceptance_summary", return_value=False),
        ):
            result = module.main()

        self.assertEqual(0, result)
        self.assertEqual(
            ["Package Krita plugin", "Read-only real profile check", "Acceptance report"],
            [label for label, _command in calls],
        )
        flattened = [part for _label, command in calls for part in command]
        self.assertIn("--check", flattened)
        self.assertIn("--output", flattened)
        self.assertIn("--automation-evidence-file", flattened)
        self.assertNotIn("--apply", flattened)
        self.assertNotIn("--restore", flattened)
        self.assertNotIn("--allow-running-krita", flattened)

    def test_default_preflight_runs_plugin_tests_before_packaging(self):
        module = _load_preflight()
        calls = []

        def fake_run(label, command):
            calls.append((label, command))

        with (
            patch.object(sys, "argv", ["preflight.py"]),
            patch.object(module, "_run", side_effect=fake_run),
            patch.object(
                module,
                "_run_capture_allow_failure",
                return_value="profile_ok=false\n",
            ),
            patch.object(module, "_run_isolated_profile_check") as isolated_check,
            patch.object(module, "_print_zip_hash"),
            patch.object(module, "_print_acceptance_summary", return_value=False),
        ):
            result = module.main()

        self.assertEqual(0, result)
        isolated_check.assert_called_once_with()
        self.assertEqual("Python plugin tests", calls[0][0])
        self.assertEqual(
            [
                sys.executable,
                "-m",
                "unittest",
                "discover",
                "-s",
                "krita_plugin/tests",
            ],
            calls[0][1],
        )

    def test_package_output_argument_is_passed_to_packager_and_hash(self):
        module = _load_preflight()
        calls = []
        hash_paths = []

        def fake_run(label, command):
            calls.append((label, command))

        with (
            patch.object(
                sys,
                "argv",
                [
                    "preflight.py",
                    "--skip-tests",
                    "--skip-isolated-install",
                    "--package-output",
                    "/tmp/current.zip",
                ],
            ),
            patch.object(module, "_run", side_effect=fake_run),
            patch.object(
                module,
                "_run_capture_allow_failure",
                return_value="profile_ok=false\n",
            ),
            patch.object(module, "_print_zip_hash", side_effect=hash_paths.append),
            patch.object(module, "_print_acceptance_summary", return_value=False),
        ):
            result = module.main()

        self.assertEqual(0, result)
        package_command = calls[0][1]
        self.assertEqual("Package Krita plugin", calls[0][0])
        self.assertIn("--output", package_command)
        self.assertIn("/tmp/current.zip", package_command)
        self.assertEqual([Path("/tmp/current.zip")], hash_paths)

    def test_require_acceptance_returns_failure_when_gates_are_open(self):
        module = _load_preflight()

        with (
            patch.object(
                sys,
                "argv",
                [
                    "preflight.py",
                    "--skip-tests",
                    "--skip-isolated-install",
                    "--require-acceptance",
                ],
            ),
            patch.object(module, "_run"),
            patch.object(
                module,
                "_run_capture_allow_failure",
                return_value="profile_ok=false\n",
            ),
            patch.object(module, "_print_zip_hash"),
            patch.object(module, "_print_acceptance_summary", return_value=False),
        ):
            result = module.main()

        self.assertEqual(1, result)

    def test_stale_real_profile_check_does_not_abort_preflight_report(self):
        module = _load_preflight()
        calls = []

        def fake_run(label, command):
            calls.append((label, command))

        def fake_capture(label, command):
            calls.append((label, command))
            self.assertEqual("Read-only real profile check", label)
            return "profile_ok=false\n"

        with (
            patch.object(
                sys,
                "argv",
                ["preflight.py", "--skip-tests", "--skip-isolated-install"],
            ),
            patch.object(module, "_run", side_effect=fake_run),
            patch.object(module, "_run_capture_allow_failure", side_effect=fake_capture),
            patch.object(module, "_print_zip_hash"),
            patch.object(module, "_print_acceptance_summary", return_value=False),
        ):
            result = module.main()

        self.assertEqual(0, result)
        self.assertEqual(
            [
                "Package Krita plugin",
                "Read-only real profile check",
                "Acceptance report",
            ],
            [label for label, _command in calls],
        )

    def test_isolated_profile_check_applies_only_to_temp_profile(self):
        module = _load_preflight()
        runs = []
        captures = []

        def fake_run(label, command):
            runs.append((label, command))

        def fake_capture(label, command):
            captures.append((label, command))
            return "profile_ok=true\n"

        with (
            patch.object(module, "_run", side_effect=fake_run),
            patch.object(module, "_run_capture", side_effect=fake_capture),
        ):
            module._run_isolated_profile_check()

        self.assertEqual(1, len(runs))
        self.assertEqual("Isolated profile install check", runs[0][0])
        self.assertIn("--apply", runs[0][1])
        self.assertIn("--backup-dir", runs[0][1])
        self.assertNotIn("--allow-running-krita", runs[0][1])
        self.assertEqual(1, len(captures))
        self.assertEqual("Isolated profile verification", captures[0][0])
        self.assertIn("--check", captures[0][1])
        for _label, command in runs + captures:
            command_text = " ".join(command)
            self.assertIn("krita-bridge-preflight-", command_text)
            self.assertNotIn("/mnt/c/Users", command_text)

    def test_isolated_profile_check_fails_when_profile_check_does_not_pass(self):
        module = _load_preflight()

        with (
            patch.object(module, "_run"),
            patch.object(module, "_run_capture", return_value="profile_ok=false\n"),
        ):
            with self.assertRaises(SystemExit):
                module._run_isolated_profile_check()

    def test_acceptance_summary_reports_false_until_all_gates_pass(self):
        module = _load_preflight()

        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "acceptance.json"
            path.write_text(
                json.dumps(
                    {
                        "acceptance_ok": False,
                        "gates": [
                            {
                                "name": "profile_installed_enabled",
                                "status": "pass",
                                "detail": "ok",
                            },
                            {
                                "name": "docker_visible",
                                "status": "pending",
                                "detail": "manual evidence required",
                            },
                        ],
                    },
                ),
                encoding="utf-8",
            )

            self.assertFalse(_call_silently(module._print_acceptance_summary, path))

            path.write_text(
                json.dumps(
                    {
                        "acceptance_ok": True,
                        "gates": [
                            {
                                "name": "profile_installed_enabled",
                                "status": "pass",
                                "detail": "ok",
                            },
                        ],
                    },
                ),
                encoding="utf-8",
            )

            self.assertTrue(_call_silently(module._print_acceptance_summary, path))


if __name__ == "__main__":
    unittest.main()
