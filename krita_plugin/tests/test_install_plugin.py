import importlib.util
import io
import tempfile
import unittest
import json
import sys
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

PLUGIN_ROOT = Path(__file__).resolve().parents[1]


def _load_install_plugin():
    spec = importlib.util.spec_from_file_location(
        "krita_bridge_install_plugin_test",
        PLUGIN_ROOT / "install_plugin.py",
    )
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class InstallPluginTests(unittest.TestCase):
    def test_windows_profile_path_converts_to_wsl_mount_path(self):
        module = _load_install_plugin()

        self.assertEqual(
            Path("/mnt/c/Users/10562/AppData/Roaming"),
            module._windows_path_to_wsl_path(
                r"C:\Users\10562\AppData\Roaming",
            ),
        )

    def test_dry_run_reports_plan_without_writing_profile(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pykrita_dir = root / "pykrita"
            kritarc_path = root / "kritarc"
            backup_dir = root / "backup"

            result = module.install_plugin(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
                backup_dir=backup_dir,
                apply=False,
            )

            self.assertFalse(result.applied)
            self.assertIn("copy_plugin", result.actions)
            self.assertIn("enable_kritarc", result.actions)
            self.assertFalse(pykrita_dir.exists())
            self.assertFalse(kritarc_path.exists())
            self.assertFalse(backup_dir.exists())

    def test_profile_check_reports_missing_profile_requirements(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)

            result = module.check_profile(
                pykrita_dir=root / "pykrita",
                kritarc_path=root / "kritarc",
            )

            self.assertFalse(result.ok)
            self.assertEqual(
                {
                    "desktop_file": False,
                    "desktop_manifest": False,
                    "plugin_dir": False,
                    "plugin_init": False,
                    "plugin_entrypoint": False,
                    "plugin_bootstrap": False,
                    "plugin_runtime": False,
                    "plugin_ui": False,
                    "plugin_bridge_client": False,
                    "plugin_canvas_io": False,
                    "plugin_protocol": False,
                    "plugin_canvas_utils": False,
                    "plugin_diagnostics": False,
                    "plugin_discovery": False,
                    "plugin_fallback_websocket": False,
                    "kritarc_file": False,
                    "kritarc_enabled": False,
                },
                {check.name: check.ok for check in result.checks},
            )

    def test_profile_check_accepts_installed_and_enabled_profile(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pykrita_dir = root / "pykrita"
            kritarc_path = root / "kritarc"
            module.install_plugin(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
                backup_dir=root / "backup",
                apply=True,
                krita_running=False,
            )

            result = module.check_profile(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
            )

            self.assertTrue(result.ok)
            self.assertTrue(all(check.ok for check in result.checks))

    def test_profile_check_rejects_stale_installed_plugin_file(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pykrita_dir = root / "pykrita"
            kritarc_path = root / "kritarc"
            module.install_plugin(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
                backup_dir=root / "backup",
                apply=True,
                krita_running=False,
            )
            (pykrita_dir / "nai_launcher_bridge" / "ui.py").write_text(
                "# stale plugin file\n",
                encoding="utf-8",
            )

            result = module.check_profile(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
            )

            by_name = {check.name: check for check in result.checks}
            self.assertFalse(result.ok)
            self.assertFalse(by_name["plugin_ui"].ok)
            self.assertIn("stale", by_name["plugin_ui"].message)

    def test_check_cli_returns_nonzero_when_profile_check_fails(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stdout = io.StringIO()

            with (
                patch.object(
                    sys,
                    "argv",
                    [
                        "install_plugin.py",
                        "--check",
                        "--pykrita-dir",
                        str(root / "pykrita"),
                        "--kritarc",
                        str(root / "kritarc"),
                    ],
                ),
                redirect_stdout(stdout),
            ):
                exit_code = module.main()

            self.assertEqual(1, exit_code)
            self.assertIn("profile_ok=false", stdout.getvalue())

    def test_apply_cli_verifies_installed_profile_before_success(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stdout = io.StringIO()

            with (
                patch.object(
                    sys,
                    "argv",
                    [
                        "install_plugin.py",
                        "--apply",
                        "--pykrita-dir",
                        str(root / "pykrita"),
                        "--kritarc",
                        str(root / "kritarc"),
                        "--backup-dir",
                        str(root / "backup"),
                    ],
                ),
                patch.object(module, "is_krita_running", return_value=False),
                redirect_stdout(stdout),
            ):
                exit_code = module.main()

            self.assertEqual(0, exit_code)
            self.assertIn("mode=applied", stdout.getvalue())
            self.assertIn("profile_ok=true", stdout.getvalue())

    def test_profile_check_requires_plugin_support_files(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pykrita_dir = root / "pykrita"
            plugin_dir = pykrita_dir / "nai_launcher_bridge"
            plugin_dir.mkdir(parents=True)
            (pykrita_dir / "nai_launcher_bridge.desktop").write_text(
                "ServiceTypes=Krita/PythonPlugin\n"
                "X-KDE-Library=nai_launcher_bridge\n"
                "Name=NAI Launcher Bridge\n",
                encoding="utf-8",
            )
            (plugin_dir / "nai_launcher_bridge.py").write_text("", encoding="utf-8")
            kritarc_path = root / "kritarc"
            kritarc_path.write_text(
                "[python]\nenable_nai_launcher_bridge=true\n",
                encoding="utf-8",
            )

            result = module.check_profile(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
            )

            by_name = {check.name: check.ok for check in result.checks}
            self.assertFalse(result.ok)
            self.assertFalse(by_name["plugin_init"])
            self.assertFalse(by_name["plugin_bootstrap"])
            self.assertFalse(by_name["plugin_runtime"])
            self.assertFalse(by_name["plugin_ui"])
            self.assertFalse(by_name["plugin_bridge_client"])
            self.assertFalse(by_name["plugin_canvas_io"])
            self.assertFalse(by_name["plugin_protocol"])
            self.assertFalse(by_name["plugin_canvas_utils"])
            self.assertFalse(by_name["plugin_diagnostics"])
            self.assertFalse(by_name["plugin_discovery"])
            self.assertFalse(by_name["plugin_fallback_websocket"])

    def test_profile_check_rejects_wrong_desktop_manifest(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pykrita_dir = root / "pykrita"
            plugin_dir = pykrita_dir / "nai_launcher_bridge"
            plugin_dir.mkdir(parents=True)
            (pykrita_dir / "nai_launcher_bridge.desktop").write_text(
                "ServiceTypes=Krita/PythonPlugin\n"
                "X-KDE-Library=wrong_bridge\n"
                "Name=Wrong Bridge\n",
                encoding="utf-8",
            )
            (plugin_dir / "nai_launcher_bridge.py").write_text("", encoding="utf-8")
            kritarc_path = root / "kritarc"
            kritarc_path.write_text(
                "[python]\nenable_nai_launcher_bridge=true\n",
                encoding="utf-8",
            )

            result = module.check_profile(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
            )

            self.assertFalse(result.ok)
            by_name = {check.name: check for check in result.checks}
            self.assertFalse(by_name["desktop_manifest"].ok)
            self.assertIn("X-KDE-Library=nai_launcher_bridge", by_name["desktop_manifest"].message)

    def test_apply_installs_layout_enables_plugin_and_backs_up_existing_profile(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pykrita_dir = root / "pykrita"
            plugin_dir = pykrita_dir / "nai_launcher_bridge"
            kritarc_path = root / "kritarc"
            backup_dir = root / "backup"

            plugin_dir.mkdir(parents=True)
            (pykrita_dir / "nai_launcher_bridge.desktop").write_text(
                "old desktop",
                encoding="utf-8",
            )
            (plugin_dir / "old.py").write_text("old plugin", encoding="utf-8")
            kritarc_path.write_text(
                "[python]\n"
                "enable_ai_diffusion=true\n"
                "enable_nai_launcher_bridge=false\n"
                "[other]\n"
                "value=1\n",
                encoding="utf-8",
            )

            result = module.install_plugin(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
                backup_dir=backup_dir,
                apply=True,
            )

            self.assertTrue(result.applied)
            self.assertTrue((pykrita_dir / "nai_launcher_bridge.desktop").exists())
            self.assertTrue((plugin_dir / "__init__.py").exists())
            self.assertFalse(any(plugin_dir.rglob("*.pyc")))
            self.assertFalse(any("__pycache__" in path.parts for path in plugin_dir.rglob("*")))

            kritarc = kritarc_path.read_text(encoding="utf-8")
            self.assertIn("[python]\n", kritarc)
            self.assertIn("enable_ai_diffusion=true\n", kritarc)
            self.assertIn("enable_nai_launcher_bridge=true\n", kritarc)
            self.assertNotIn("enable_nai_launcher_bridge=false", kritarc)
            self.assertIn("[other]\n", kritarc)

            self.assertEqual(
                "old desktop",
                (backup_dir / "nai_launcher_bridge.desktop").read_text(
                    encoding="utf-8",
                ),
            )
            self.assertEqual(
                "old plugin",
                (backup_dir / "nai_launcher_bridge" / "old.py").read_text(
                    encoding="utf-8",
                ),
            )
            self.assertIn(
                "enable_nai_launcher_bridge=false",
                result.kritarc_backup.read_text(encoding="utf-8"),
            )

    def test_apply_writes_manifest_and_restore_recovers_existing_profile(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pykrita_dir = root / "pykrita"
            plugin_dir = pykrita_dir / "nai_launcher_bridge"
            kritarc_path = root / "kritarc"
            backup_dir = root / "backup"

            plugin_dir.mkdir(parents=True)
            (pykrita_dir / "nai_launcher_bridge.desktop").write_text(
                "old desktop",
                encoding="utf-8",
            )
            (plugin_dir / "old.py").write_text("old plugin", encoding="utf-8")
            kritarc_path.write_text(
                "[python]\nenable_nai_launcher_bridge=false\n",
                encoding="utf-8",
            )

            module.install_plugin(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
                backup_dir=backup_dir,
                apply=True,
            )

            manifest = json.loads((backup_dir / "install_manifest.json").read_text(encoding="utf-8"))
            self.assertTrue(manifest["had_desktop"])
            self.assertTrue(manifest["had_plugin_dir"])
            self.assertTrue(manifest["had_kritarc"])

            result = module.restore_profile(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
                backup_dir=backup_dir,
                apply=True,
            )

            self.assertTrue(result.applied)
            self.assertEqual(
                "old desktop",
                (pykrita_dir / "nai_launcher_bridge.desktop").read_text(
                    encoding="utf-8",
                ),
            )
            self.assertTrue((plugin_dir / "old.py").exists())
            self.assertEqual(
                "[python]\nenable_nai_launcher_bridge=false\n",
                kritarc_path.read_text(encoding="utf-8"),
            )

    def test_restore_removes_plugin_files_when_profile_was_empty_before_install(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pykrita_dir = root / "pykrita"
            kritarc_path = root / "kritarc"
            backup_dir = root / "backup"

            module.install_plugin(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
                backup_dir=backup_dir,
                apply=True,
            )

            self.assertTrue((pykrita_dir / "nai_launcher_bridge.desktop").exists())
            self.assertTrue((pykrita_dir / "nai_launcher_bridge").exists())
            self.assertTrue(kritarc_path.exists())

            module.restore_profile(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
                backup_dir=backup_dir,
                apply=True,
            )

            self.assertFalse((pykrita_dir / "nai_launcher_bridge.desktop").exists())
            self.assertFalse((pykrita_dir / "nai_launcher_bridge").exists())
            self.assertFalse(kritarc_path.exists())

    def test_apply_refuses_to_write_when_krita_is_running_by_default(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)

            with self.assertRaisesRegex(RuntimeError, "Krita is running"):
                module.install_plugin(
                    pykrita_dir=root / "pykrita",
                    kritarc_path=root / "kritarc",
                    backup_dir=root / "backup",
                    apply=True,
                    krita_running=True,
                )

            self.assertFalse((root / "pykrita").exists())
            self.assertFalse((root / "kritarc").exists())

    def test_allow_running_krita_override_keeps_apply_available(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)

            result = module.install_plugin(
                pykrita_dir=root / "pykrita",
                kritarc_path=root / "kritarc",
                backup_dir=root / "backup",
                apply=True,
                krita_running=True,
                allow_running_krita=True,
            )

            self.assertTrue(result.applied)
            self.assertTrue((root / "pykrita" / "nai_launcher_bridge").exists())

    def test_restore_refuses_to_write_when_krita_is_running_by_default(self):
        module = _load_install_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pykrita_dir = root / "pykrita"
            kritarc_path = root / "kritarc"
            backup_dir = root / "backup"

            module.install_plugin(
                pykrita_dir=pykrita_dir,
                kritarc_path=kritarc_path,
                backup_dir=backup_dir,
                apply=True,
                krita_running=False,
            )

            with self.assertRaisesRegex(RuntimeError, "Krita is running"):
                module.restore_profile(
                    pykrita_dir=pykrita_dir,
                    kritarc_path=kritarc_path,
                    backup_dir=backup_dir,
                    apply=True,
                    krita_running=True,
                )


if __name__ == "__main__":
    unittest.main()
