import json
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

from PyQt5.QtCore import QByteArray
from PyQt5.QtGui import QImage

from . import canvas_io
from .discovery import discovery_file_path, load_discovery


Check = Dict[str, Any]
SCHEMA_VERSION = 1
PLUGIN_NAME = "nai_launcher_bridge"


def run_diagnostics(*, write_report: bool = True) -> Dict[str, Any]:
    checks: List[Check] = []
    _check_plugin_layout(checks)
    _check_qt_websockets(checks)
    _check_discovery(checks)
    _check_active_document(checks)
    _check_canvas_round_trip(checks)
    _check_selection_and_masks(checks)

    report: Dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "plugin": PLUGIN_NAME,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "python": sys.version,
        "checks": checks,
        "summary": _summary(checks),
    }
    if write_report:
        report_path = _write_report(report)
        report["report_path"] = str(report_path)
    return report


def format_summary(report: Dict[str, Any]) -> str:
    summary = report.get("summary") or {}
    report_path = report.get("report_path")
    parts = [
        f"pass={summary.get('pass', 0)}",
        f"fail={summary.get('fail', 0)}",
        f"warning={summary.get('warning', 0)}",
        f"skip={summary.get('skip', 0)}",
    ]
    if report_path:
        parts.append(str(report_path))
    return "Diagnostics: " + ", ".join(parts)


def _check_plugin_layout(checks: List[Check]) -> None:
    plugin_dir = Path(__file__).resolve().parent
    pykrita_dir = plugin_dir.parent
    desktop = pykrita_dir / "nai_launcher_bridge.desktop"
    if desktop.exists() and plugin_dir.name == "nai_launcher_bridge":
        _add_check(
            checks,
            "plugin_layout",
            "pass",
            "Plugin folder and .desktop file are in the expected layout.",
            desktop=str(desktop),
            plugin_dir=str(plugin_dir),
        )
        return
    _add_check(
        checks,
        "plugin_layout",
        "fail",
        "Expected nai_launcher_bridge.desktop next to the nai_launcher_bridge folder.",
        desktop=str(desktop),
        plugin_dir=str(plugin_dir),
    )


def _check_qt_websockets(checks: List[Check]) -> None:
    try:
        from PyQt5.QtWebSockets import QWebSocket  # noqa: F401
    except Exception as error:
        _add_check(
            checks,
            "qt_websockets",
            "warning",
            "PyQt5.QtWebSockets is unavailable; plugin will use bundled fallback.",
            error=str(error),
        )
        return
    _add_check(
        checks,
        "qt_websockets",
        "pass",
        "PyQt5.QtWebSockets.QWebSocket is importable.",
    )


def _check_discovery(checks: List[Check]) -> None:
    path = discovery_file_path()
    if not path.exists():
        _add_check(
            checks,
            "launcher_discovery",
            "fail",
            "Launcher discovery file is missing. Enable Krita Bridge in Launcher.",
            path=str(path),
        )
        return

    try:
        discovery = load_discovery(path)
    except Exception as error:
        _add_check(
            checks,
            "launcher_discovery",
            "fail",
            "Launcher discovery file exists but is not usable.",
            path=str(path),
            error=str(error),
        )
        return

    _add_check(
        checks,
        "launcher_discovery",
        "pass",
        "Launcher discovery file is usable.",
        path=str(path),
        url=discovery.url,
        pid=discovery.pid,
        version=discovery.version,
        started_at=discovery.started_at,
        secret_length=len(discovery.secret),
    )


def _check_active_document(checks: List[Check]) -> None:
    doc = canvas_io.active_document()
    if doc is None:
        _add_check(
            checks,
            "active_document",
            "skip",
            "No active Krita document; canvas checks were skipped.",
        )
        return
    _add_check(
        checks,
        "active_document",
        "pass",
        "Active Krita document is available.",
        width=doc.width(),
        height=doc.height(),
    )


def _check_canvas_round_trip(checks: List[Check]) -> None:
    doc = canvas_io.active_document()
    if doc is None:
        _add_check(
            checks,
            "canvas_png_round_trip",
            "skip",
            "Open a Krita document to verify PNG export and layer writeback.",
        )
        return

    layer_name = "NAI Bridge Diagnostic Round Trip"
    try:
        image_png = canvas_io.export_active_document_png()
        decoded = QImage()
        if not decoded.loadFromData(QByteArray(image_png), "PNG"):
            raise RuntimeError("Exported canvas PNG could not be decoded")
        if decoded.width() != doc.width() or decoded.height() != doc.height():
            raise RuntimeError(
                "Exported PNG dimensions do not match the active document"
            )
        if not canvas_io._write_png_as_layer(
            image_png,
            layer_name,
            replace_existing=True,
        ):
            raise RuntimeError("Krita rejected PNG layer writeback")
        _add_check(
            checks,
            "canvas_png_round_trip",
            "pass",
            "Visible projection exported as PNG and wrote back as a layer.",
            width=decoded.width(),
            height=decoded.height(),
            bytes=len(image_png),
        )
    except Exception as error:
        _add_check(
            checks,
            "canvas_png_round_trip",
            "fail",
            "Canvas PNG round trip failed.",
            error=str(error),
        )
    finally:
        try:
            canvas_io._remove_layers_named(doc, layer_name)
            doc.refreshProjection()
        except Exception:
            pass


def _check_selection_and_masks(checks: List[Check]) -> None:
    doc = canvas_io.active_document()
    if doc is None:
        _add_check(
            checks,
            "selection_and_masks",
            "skip",
            "Open a Krita document to inspect the selection inpaint mask source.",
        )
        return

    rect = canvas_io.active_selection_bounds()
    if rect is None:
        selection_status = "skip"
        selection_detail = "No active selection bounds were found."
    else:
        selection_status = "pass"
        selection_detail = "Active selection bounds are available."

    mask_sources: Dict[str, Dict[str, Any]] = {}
    try:
        mask_png = canvas_io.export_inpaint_mask_png()
        image = QImage()
        if not image.loadFromData(QByteArray(mask_png), "PNG"):
            raise RuntimeError("Mask PNG could not be decoded")
        mask_sources["selection"] = {
            "status": "pass",
            "width": image.width(),
            "height": image.height(),
            "bytes": len(mask_png),
        }
    except Exception as error:
        mask_sources["selection"] = {
            "status": "skip",
            "detail": str(error),
        }

    status = "pass" if rect is not None or _has_passed_mask(mask_sources) else "skip"
    _add_check(
        checks,
        "selection_and_masks",
        status,
        selection_detail,
        selection_rect=rect,
        selection_status=selection_status,
        mask_sources=mask_sources,
        document_width=doc.width(),
        document_height=doc.height(),
    )


def _has_passed_mask(mask_sources: Dict[str, Dict[str, Any]]) -> bool:
    return any(value.get("status") == "pass" for value in mask_sources.values())


def _write_report(report: Dict[str, Any]) -> Path:
    target_dir = discovery_file_path().parent
    try:
        target_dir.mkdir(parents=True, exist_ok=True)
    except Exception:
        target_dir = Path(tempfile.gettempdir())
    path = target_dir / "krita-bridge-diagnostics.json"
    path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return path


def _summary(checks: List[Check]) -> Dict[str, int]:
    values = {"pass": 0, "fail": 0, "warning": 0, "skip": 0}
    for check in checks:
        status = str(check.get("status"))
        if status in values:
            values[status] += 1
    return values


def _add_check(
    checks: List[Check],
    name: str,
    status: str,
    detail: str,
    **extra: Any,
) -> None:
    item: Check = {
        "name": name,
        "status": status,
        "detail": detail,
    }
    item.update(extra)
    checks.append(item)
