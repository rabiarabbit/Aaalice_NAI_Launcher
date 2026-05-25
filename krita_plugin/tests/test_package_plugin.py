import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from zipfile import ZipFile

PLUGIN_ROOT = Path(__file__).resolve().parents[1]


def _load_package_plugin():
    spec = importlib.util.spec_from_file_location(
        "krita_bridge_package_plugin_test",
        PLUGIN_ROOT / "package_plugin.py",
    )
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class PackagePluginTests(unittest.TestCase):
    def test_desktop_manifest_points_to_plugin_package(self):
        desktop = (PLUGIN_ROOT / "nai_launcher_bridge.desktop").read_text(
            encoding="utf-8",
        )

        self.assertIn("ServiceTypes=Krita/PythonPlugin", desktop)
        self.assertIn("X-KDE-Library=nai_launcher_bridge", desktop)
        self.assertIn("Name=NAI Launcher Bridge", desktop)
        self.assertTrue((PLUGIN_ROOT / "nai_launcher_bridge" / "__init__.py").exists())
        self.assertTrue(
            (PLUGIN_ROOT / "nai_launcher_bridge" / "nai_launcher_bridge.py").exists()
        )

    def test_package_contains_krita_importer_layout_and_required_files(self):
        module = _load_package_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            module.DIST = Path(temp_dir)
            module.OUTPUT = module.DIST / "plugin.zip"

            with redirect_stdout(io.StringIO()):
                module.main()

            with ZipFile(module.OUTPUT) as archive:
                entries = set(archive.namelist())
                package_data = {
                    entry: archive.read(entry)
                    for entry in entries
                }

        required = {
            "nai_launcher_bridge.desktop",
            "nai_launcher_bridge/LICENSE",
            "nai_launcher_bridge/__init__.py",
            "nai_launcher_bridge/bridge_client.py",
            "nai_launcher_bridge/bridge_dock.py",
            "nai_launcher_bridge/canvas_io.py",
            "nai_launcher_bridge/canvas_utils.py",
            "nai_launcher_bridge/diagnostics.py",
            "nai_launcher_bridge/discovery.py",
            "nai_launcher_bridge/fallback_websocket.py",
            "nai_launcher_bridge/nai_launcher_bridge.py",
            "nai_launcher_bridge/plugin.py",
            "nai_launcher_bridge/protocol.py",
            "nai_launcher_bridge/ui.py",
        }

        self.assertTrue(required.issubset(entries))
        self.assertFalse(any("__pycache__" in entry for entry in entries))
        self.assertFalse(any(entry.endswith(".pyc") for entry in entries))
        self.assertFalse(any(entry.startswith("tests/") for entry in entries))
        self.assertFalse(any(entry.startswith("build/") for entry in entries))
        self.assertFalse(any(entry.startswith("dist/") for entry in entries))
        self.assertFalse(any(entry.startswith("settings/") for entry in entries))
        self.assertFalse(any(entry.startswith("user/") for entry in entries))

        for data in package_data.values():
            self.assertNotIn(b"pst-", data)
            self.assertNotIn(b"Bearer ", data)

    def test_output_argument_writes_requested_zip(self):
        module = _load_package_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "custom" / "bridge.zip"

            with redirect_stdout(io.StringIO()) as stdout:
                module.main(["--output", str(output)])

            self.assertEqual(stdout.getvalue().strip(), str(output))
            with ZipFile(output) as archive:
                entries = set(archive.namelist())
                ui_source = archive.read("nai_launcher_bridge/ui.py").decode("utf-8")

        self.assertIn("nai_launcher_bridge.desktop", entries)
        self.assertIn("nai_launcher_bridge/ui.py", entries)
        self.assertIn("_export_clean_canvas", ui_source)
        self.assertNotIn("Preview Focus Frame", ui_source)

    def test_package_excludes_generated_images_endpoint_presets_and_user_settings(self):
        module = _load_package_plugin()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "krita_plugin"
            plugin_dir = root / "nai_launcher_bridge"
            plugin_dir.mkdir(parents=True)
            (root / "nai_launcher_bridge.desktop").write_text(
                "ServiceTypes=Krita/PythonPlugin\n"
                "X-KDE-Library=nai_launcher_bridge\n",
                encoding="utf-8",
            )
            (plugin_dir / "__init__.py").write_text("", encoding="utf-8")
            (plugin_dir / "plugin.py").write_text("", encoding="utf-8")
            (plugin_dir / "generated_result.png").write_bytes(b"generated image")
            (plugin_dir / "endpoint_presets.json").write_text(
                '{"endpoint_override":"https://nai.local"}',
                encoding="utf-8",
            )
            (plugin_dir / "user_settings.json").write_text(
                '{"persistentApiToken":"pst-secret"}',
                encoding="utf-8",
            )
            module.ROOT = root
            module.DIST = Path(temp_dir) / "dist"
            module.OUTPUT = module.DIST / "plugin.zip"

            with redirect_stdout(io.StringIO()):
                module.main()

            with ZipFile(module.OUTPUT) as archive:
                entries = set(archive.namelist())
                package_data = b"\n".join(archive.read(entry) for entry in entries)

        self.assertIn("nai_launcher_bridge/__init__.py", entries)
        self.assertIn("nai_launcher_bridge/plugin.py", entries)
        self.assertNotIn("nai_launcher_bridge/generated_result.png", entries)
        self.assertNotIn("nai_launcher_bridge/endpoint_presets.json", entries)
        self.assertNotIn("nai_launcher_bridge/user_settings.json", entries)
        self.assertNotIn(b"endpoint_override", package_data)
        self.assertNotIn(b"persistentApiToken", package_data)


if __name__ == "__main__":
    unittest.main()
