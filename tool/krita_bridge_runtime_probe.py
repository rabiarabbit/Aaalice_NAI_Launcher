import json
import os
import time
import traceback
from pathlib import Path


def _report_path() -> Path:
    appdata = os.environ.get("APPDATA")
    if appdata:
        base = Path(appdata)
    else:
        base = Path.home() / "AppData" / "Roaming"
    target = base / "nai-launcher"
    target.mkdir(parents=True, exist_ok=True)
    return target / "krita-bridge-runtime-probe.json"


def _process_events(seconds: float) -> None:
    try:
        from PyQt5.QtWidgets import QApplication

        app = QApplication.instance()
        if app is None:
            return
        deadline = time.time() + seconds
        while time.time() < deadline:
            app.processEvents()
            time.sleep(0.05)
    except Exception:
        return


def _set_selection(doc, x: int, y: int, width: int, height: int) -> None:
    from krita import Selection

    selection = Selection()
    selection.select(x, y, width, height, 255)
    doc.setSelection(selection)
    doc.refreshProjection()


def _layer_exists(doc, name: str) -> bool:
    stack = [doc.rootNode()]
    while stack:
        node = stack.pop()
        try:
            node_name = node.name()
        except Exception:
            node_name = ""
        if node_name == name:
            return True
        if hasattr(node, "childNodes"):
            stack.extend(node.childNodes())
    return False


def _make_probe_document(payload: dict):
    from krita import Krita

    app = Krita.instance()
    doc = app.createDocument(
        128,
        128,
        "NAI Bridge Runtime Probe",
        "RGBA",
        "U8",
        "",
        120.0,
    )
    payload["created_document"] = doc is not None
    window = app.activeWindow()
    payload["active_window"] = window is not None
    if doc is not None and window is not None:
        window.addView(doc)
        _process_events(0.5)
        _set_selection(doc, 16, 16, 64, 64)
        _process_events(0.5)
    return doc


def _run_focused_inpaint_probe(docker, doc) -> dict:
    from PyQt5.QtWidgets import QPushButton
    from nai_launcher_bridge import canvas_io

    result = {
        "ok": False,
        "manual_preview_button_present": None,
        "focused_enabled": False,
        "mask_source_control_removed": False,
        "minimum_context_enabled_when_focused": False,
        "minimum_context_slider_enabled_when_focused": False,
        "first_focus_layer_exists": False,
        "first_label": "",
        "minimum_context_label": "",
        "selection_change_label": "",
        "selection_change_label_updated": False,
        "focus_layer_visible_during_clean_export": None,
        "focus_layer_restored_after_clean_export": False,
        "disabled_label": "",
        "focus_layer_removed_when_disabled": False,
        "minimum_context_slider_disabled_when_focus_disabled": False,
    }
    if doc is None:
        result["error"] = "No probe document"
        return result

    buttons = [button.text() for button in docker.findChildren(QPushButton)]
    result["manual_preview_button_present"] = "Preview Focus Frame" in buttons

    docker._focused_inpaint.setChecked(True)
    _process_events(0.4)
    docker._sync_focus_preview(force=True, quiet=True)
    _process_events(0.2)

    first_rects = canvas_io.active_focus_preview_rects(docker._minimum_context.value())
    result["focused_enabled"] = docker._focused_inpaint.isChecked()
    result["mask_source_control_removed"] = not hasattr(docker, "_mask_source")
    result["minimum_context_enabled_when_focused"] = docker._minimum_context.isEnabled()
    result["minimum_context_slider_enabled_when_focused"] = (
        docker._minimum_context_slider.isEnabled()
    )
    result["first_focus_rects"] = first_rects
    result["first_label"] = docker._focus_rect_label.text()
    result["first_focus_layer_exists"] = _layer_exists(
        doc,
        canvas_io.FOCUS_PREVIEW_LAYER_NAME,
    )

    docker._minimum_context.setValue(24)
    _process_events(0.4)
    context_rects = canvas_io.active_focus_preview_rects(24)
    result["minimum_context_rects"] = context_rects
    result["minimum_context_label"] = docker._focus_rect_label.text()

    _set_selection(doc, 40, 44, 20, 20)
    _process_events(0.6)
    selection_rects = canvas_io.active_focus_preview_rects(24)
    result["selection_change_rects"] = selection_rects
    result["selection_change_label"] = docker._focus_rect_label.text()
    result["selection_change_label_updated"] = (
        "inner 40,44 20x20" in result["selection_change_label"]
    )

    original_export = canvas_io.export_active_document_png

    def traced_export():
        result["focus_layer_visible_during_clean_export"] = _layer_exists(
            doc,
            canvas_io.FOCUS_PREVIEW_LAYER_NAME,
        )
        return original_export()

    try:
        canvas_io.export_active_document_png = traced_export
        docker._export_clean_canvas()
    finally:
        canvas_io.export_active_document_png = original_export
    result["focus_layer_restored_after_clean_export"] = _layer_exists(
        doc,
        canvas_io.FOCUS_PREVIEW_LAYER_NAME,
    )

    docker._focused_inpaint.setChecked(False)
    _process_events(0.3)
    result["disabled_label"] = docker._focus_rect_label.text()
    result["focus_layer_removed_when_disabled"] = not _layer_exists(
        doc,
        canvas_io.FOCUS_PREVIEW_LAYER_NAME,
    )
    result["minimum_context_slider_disabled_when_focus_disabled"] = (
        not docker._minimum_context_slider.isEnabled()
    )

    result["ok"] = (
        result["manual_preview_button_present"] is False
        and result["focused_enabled"]
        and result["mask_source_control_removed"]
        and result["minimum_context_enabled_when_focused"]
        and result["minimum_context_slider_enabled_when_focused"]
        and result["first_focus_layer_exists"]
        and first_rects is not None
        and context_rects is not None
        and selection_rects is not None
        and context_rects[1]["w"] != first_rects[1]["w"]
        and selection_rects[0]["x"] == 40
        and selection_rects[0]["y"] == 44
        and result["selection_change_label_updated"]
        and result["focus_layer_visible_during_clean_export"] is False
        and result["focus_layer_restored_after_clean_export"]
        and result["focus_layer_removed_when_disabled"]
        and result["minimum_context_slider_disabled_when_focus_disabled"]
    )
    return result


def __main__(*args) -> None:
    payload = {
        "ok": False,
        "checks": [],
    }
    try:
        from krita import Krita
        from nai_launcher_bridge import diagnostics
        from nai_launcher_bridge.ui import NAILauncherBridgeDocker

        app = Krita.instance()
        payload["krita_instance"] = app is not None

        probe_doc = _make_probe_document(payload)
        docker = NAILauncherBridgeDocker()
        try:
            payload["docker_title"] = docker.windowTitle()
            payload["connect_button"] = docker._connect_button.text()
            payload["diagnostics_button"] = docker._diagnostics_button.text()
            payload["initial_status"] = docker._status.text()
            _process_events(3.0)
            payload["connected"] = docker._client.is_connected
            payload["status_after_events"] = docker._status.text()
            payload["focused_inpaint_probe"] = _run_focused_inpaint_probe(
                docker,
                probe_doc,
            )
        finally:
            try:
                docker._client.stop()
            except Exception:
                pass
            try:
                docker.deleteLater()
            except Exception:
                pass

        report = diagnostics.run_diagnostics(write_report=True)
        payload["diagnostics_summary"] = report.get("summary")
        payload["diagnostics_report_path"] = report.get("report_path")
        payload["checks"] = report.get("checks", [])
        payload["ok"] = True
    except Exception:
        payload["error"] = traceback.format_exc()

    _report_path().write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


if __name__ == "__main__":
    __main__()
