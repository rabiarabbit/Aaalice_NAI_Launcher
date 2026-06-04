# Krita Bridge Acceptance Audit

Snapshot: 2026-05-11 10:22 Asia/Shanghai

Objective: implement `docs/superpowers/specs/2026-05-07-krita-integration-design.md`.

This audit treats the design document as the source of truth. Automated tests,
package checks, isolated-profile checks, and diagnostics reports are evidence
only for the requirements they directly cover. Real Krita GUI/end-to-end
requirements remain open until they are observed in the real Windows Krita
application.

## Overall Status

Not complete.

The Launcher code, Krita plugin source, installer, documentation, and automated
test coverage are in place. The current plugin source now removes the legacy
`Inpaint Mask` layer source, uses the active Krita selection for all Inpaint
masks, and exposes `Strength`, `Noise`, `Inpaint Strength`, and `Minimum
Context` as linked slider plus numeric controls, and sends completed images to
the Docker result area first. Single-clicking a result writes the temporary
preview layer; double-clicking adds it as a new layer. The real Krita user
profile has been refreshed from the current source and now reports
`profile_ok=true`. The repo `dist` zip and `/tmp` preflight package both contain
the current source with SHA256
`2a511dba61de59e3a4f552b4b0070a4ed46dbeb9249fb3becc359ffbba120a83`. The
current acceptance report generated to `/tmp` has 6 passing
profile/diagnostics/runtime gates and 19 pending GUI/end-to-end gates.

## Concrete Success Criteria

The objective is complete only when the approved design is implemented as
artifacts and verified against the real Windows Krita target. The concrete
deliverables are:

- Launcher loopback bridge server, protocol, settings lifecycle, request
  orchestration, history/save integration, gallery/generated-image send action,
  and disabled-by-default behavior.
- Krita Python plugin package with the documented `.desktop` plus
  `nai_launcher_bridge/` layout, zero-pip runtime path, discovery-file
  connection, authenticated local-only transport, Docker UI, canvas/mask I/O,
  preview layer, final-result writeback, and cancel handling.
- Installer/package/preflight tooling that can safely check, package, install,
  restore, and report acceptance without silently writing the real profile.
- User/developer documentation covering enablement, install, troubleshooting,
  protocol, local-only credential boundary, packaging/license boundary, and
  release-note safety statements.
- Automated test evidence for protocol parsing, request mapping, provider
  state, server authentication, plugin transport, canvas helpers, diagnostics,
  packaging, installer, preflight, and acceptance hard gates.
- Real Windows Krita evidence that the plugin appears in Python Plugin Manager,
  the Docker loads, Diagnostics pass on an active document, and every manual
  GUI/end-to-end acceptance gate is backed by observed evidence.

Until the final real-profile acceptance report returns `acceptance_ok=true`,
the implementation must be treated as not complete even if automated tests pass.

## Explicit Design Coverage Matrix

| Design Area | Explicit Requirement | Artifact / Evidence | Completion Judgment |
|---|---|---|---|
| Overview architecture | Thin Krita plugin handles only canvas I/O and UI; Launcher keeps generation, crop/resize/composite, streaming, credentials, history, and statistics | `krita_bridge_service.dart` routes through existing generation service; plugin files only implement UI/transport/canvas helpers; docs state the boundary | Implemented; real E2E still pending |
| Implementation gate 1 | Krita plugin discovery in Python Plugin Manager using exact `.desktop` plus folder layout | `install_plugin.py --check`, package tests, zip layout, and real profile check verify files are installed and enabled | Source changed after install; profile refresh and real Plugin Manager GUI observation pending |
| Implementation gate 2 | Validate `PyQt5.QtWebSockets`; use bundled fallback or HTTP/SSE if unavailable | Target Krita 5.3.1 lacks QtWebSockets; `fallback_websocket.py` and tests implement loopback-only fallback | Covered by feasibility result and tests |
| Implementation gate 3 | Canvas PNG round trip preserves channels, alpha, and dimensions | CLI spike and `canvas_io.py` tests cover export/writeback helpers; Diagnostics gate exists for real document validation | Partially covered; real Docker Diagnostics pending |
| Implementation gate 4 | Krita-sourced Focused Inpaint parity with in-app crop/composite path | Launcher service maps focused rect and context pixels into existing pipeline; service/protocol tests cover mapping | Automated coverage only; real E2E pending |
| Implementation gate 5 | Krita requests cannot cancel/overwrite Launcher UI generation without explicit arbitration | Service/provider tests cover busy rejection, scoped cancel, and disconnect cancellation | Covered by automated tests; real UI behavior pending |
| Protocol transport | `ws://127.0.0.1:{port}/krita`, single client, JSON frames, versioned `ping`/`pong`, authenticated session | `krita_bridge_server.dart`, `bridge_client.py`, fallback client, protocol/server/client tests | Covered by automated tests |
| Auto-discovery and security | Discovery JSON under `%APPDATA%/nai-launcher/krita-bridge.json` with `port`, `pid`, `version`, `secret`, `started_at`; stale files ignored; loopback plus secret required | Server/notifier/discovery tests and docs; acceptance includes auto-discovery and auth-failure gates | Covered by tests; real auto-connect pending |
| Protocol validation | Required fields, unknown type, forward-compatible unknown fields, frame cap, Base64/image bounds errors | `krita_bridge_protocol.dart`, `krita_bridge_models.dart`, `krita_bridge_protocol_test.dart`, `docs/krita-bridge.md` protocol reference | Covered by automated tests and developer docs |
| Message set | `inpaint`, `img2img`, `get_params`, `cancel`, `ping`, `result`, `progress`, `error`, `params`, `push_image`, `pong`, `cancelled` | Dart protocol/service tests and Python plugin protocol/UI tests | Covered by automated tests |
| Launcher files | Add `lib/core/krita/*` and `lib/presentation/providers/krita/*` modules | Files exist with focused tests under `test/core/krita` and `test/presentation/providers/krita` | Covered by file evidence and tests |
| Launcher required behaviors | Disabled by default, random session secret, atomic discovery file, delete on disable, reject before valid ping, use `generateImageStream`, full-canvas focused previews | Notifier/server/service code and focused Windows tests | Covered by automated tests; manual settings UI pending |
| UI integration | Settings section, status/port/session regeneration, generation/gallery send-to-Krita through existing destination/action flows | Settings section, `krita_send_helper.dart`, gallery destination dialog tests | Covered by tests; real GUI pending |
| Plugin file structure | Ship `.desktop`, `__init__.py`, `nai_launcher_bridge.py`, `bridge_client.py`, `bridge_dock.py`, `canvas_utils.py`, `protocol.py` | Package contains those plus runtime helpers, diagnostics, fallback, LICENSE | Covered by package tests |
| Plugin transport | Reads discovery file, validates PID, connects only to loopback, authenticates before ready, auto-reconnects | `bridge_client.py`, `discovery.py`, `fallback_websocket.py`, related tests | Covered by automated tests; real connect pending |
| Qt thread safety | WebSocket callbacks and layer writes must be marshalled onto Krita's main Qt thread | Fallback socket worker invokes `_fallback_*` Qt signals; `BridgeClient` emits `message_received` and Docker handles UI/canvas work from that signal path; `test_bridge_client` covers fallback handshake/message delivery through signals | Covered by automated tests; real GUI pending |
| Docker UI | Status LED, prompt/negative fields, strength/context controls, Focused Inpaint checkbox, Inpaint/Img2Img buttons, progress/cancel | `ui.py`/`bridge_dock.py`; fake Qt UI tests cover state and messages | Covered by fake UI tests; real Docker pending |
| Canvas/mask I/O | Visible projection PNG, selection rect, active Krita selection mask, same-size mask requirement, new result layer or document fallback | `canvas_io.py`, `protocol.py`, `test_canvas_io.py`, `test_discovery_protocol.py` | Covered by automated tests; real writeback pending |
| Preview and safety | Separate `NAI Preview` layer, throttled preview writes, final result enters the Docker result area, single-click previews, double-click writes a new layer, selected results can be deleted/cleared, and no user content is overwritten without explicit double-click | `ui.py` throttles preview writes to 0.35s, keeps the last progress preview visible on final result, debounces focus-frame layer writes, and provides result-area `Delete`/`Clear`; canvas/UI tests cover preview throttling, result-area click/double-click/delete/clear behavior, final write fallback, and localized writeback failure cleanup; acceptance `preview_throttle` and `result_layer_aligned` gates remain real-GUI gated | Automated coverage only; real performance/GUI pending |
| Workflows 1-6 | Connection, Focused Inpaint, Normal Inpaint, Img2Img, Launcher push to Krita, Cancel generation | Protocol/service/plugin tests and manual checklist gates | Partially covered; real E2E pending |
| Edge cases | Coordinate-space rules, no silent scaling, local validation for no document, small/large canvas, missing mask, missing focus rect, not connected | Protocol/canvas/UI tests and docs | Covered by tests; real GUI messages pending |
| Large canvas | V1 sends <=4096 as-is and rejects larger normal requests instead of silent downscale | `krita_bridge_protocol.dart`, `canvas_io.py`, tests, docs | Covered by tests; real manual gate pending |
| Recovery | Krita restart, Launcher restart/crash, Krita crash mid-generation | Discovery reconnect, disconnect cleanup/cancel tests, docs | Partially covered by tests; real crash/restart drills pending |
| Storage/history/metadata | Final PNG in Krita layer and existing Launcher save/history path; `result.params`; do not store mask/source canvas by default; Anlas/statistics stay Launcher-side | Service tests cover history/result params; docs describe token/statistics boundary | Covered by tests/docs; real history gate pending |
| Error mapping | Stable codes for auth, Anlas, rate limit, timeout, unauthorized client, busy, streaming unsupported, empty mask, unsupported document format | Dart enum/error mapping, service tests for 401/402/429/timeout/busy/streaming/empty-mask cases, and Python UI translations/tests | Covered by automated tests |
| License/compliance | Plugin GPL boundary, local-only bridge, no NovelAI credentials/settings in plugin package | `krita_plugin/nai_launcher_bridge/LICENSE`, docs, package/token scan tests, and current zip sensitive-marker scan | Covered by docs/package tests; release review still needed |
| Validation plan | Launcher unit tests, provider/widget tests, manual Krita tests, end-to-end acceptance checklist | Focused Flutter/Python tests plus `acceptance_report.py`/preflight and manual gate list | Automated coverage in place; manual acceptance pending |
| Out of scope | ControlNet/Vibe Transfer from Krita, concurrent Krita clients, dock persistence, binary frames, non-Windows validation | Design document records these exclusions; implementation avoids these scopes | Covered as exclusions |

## Prompt-To-Artifact Checklist

| Requirement | Artifact / Evidence | Status |
|---|---|---|
| Launcher loopback WebSocket server, authenticated handshake, discovery file, single-client replacement | `lib/core/krita/krita_bridge_server.dart`; focused Windows `flutter.bat test` suite includes `test\core\krita\krita_bridge_server_test.dart` and passed 48/48 tests | Covered by automated tests |
| Protocol DTOs, JSON validation, versioning, error codes, oversized payload rejection, image bounds validation | `lib/core/krita/krita_bridge_models.dart`, `lib/core/krita/krita_bridge_protocol.dart`; focused Windows suite includes `krita_bridge_protocol_test.dart` | Covered by automated tests |
| `inpaint`, `img2img`, `get_params`, `cancel`, `push_image`, `result`, `progress`, `params`, `pong`, and `cancelled` messages | Dart protocol/service tests plus Python plugin protocol/UI tests; `python3 -m pytest -q krita_plugin/tests` currently reports 139 passed | Covered by automated tests |
| Bridge disabled by default, settings toggle, listening/connected/error state, session regeneration | `lib/presentation/providers/krita/krita_bridge_notifier.dart`, settings UI section, notifier tests | Partially covered; real Launcher settings UI gate pending |
| Krita requests route through existing generation pipeline and history/save path | `lib/presentation/providers/krita/krita_bridge_service.dart`; focused Windows suite covers progress, result, history registration, cancel, busy state, and disconnect handling | Covered by automated tests; real E2E pending |
| Gallery and generated images send to Krita through existing destination/action flows | `lib/presentation/widgets/gallery/image_send_destination_dialog.dart`, `lib/presentation/utils/krita_send_helper.dart`, generation/gallery UI changes | Covered by automated tests; real receive pending |
| Krita plugin package layout with `.desktop` sibling and `nai_launcher_bridge/` folder | `krita_plugin/nai_launcher_bridge.desktop`, `krita_plugin/nai_launcher_bridge/*`, `dist/nai_launcher_bridge_krita_plugin.zip`; `test_package_plugin` currently reports 3 passed | Covered by package tests |
| Krita plugin zero-dependency fallback when `PyQt5.QtWebSockets` is absent | `krita_plugin/nai_launcher_bridge/fallback_websocket.py`, discovery/client tests; implementation gate documents that target Krita 5.3.1 lacks QtWebSockets | Covered by automated tests and feasibility check |
| Krita canvas export, mask handling, selection rect, preview throttling, final layer write/new document fallback | `canvas_io.py`, `ui.py`, plugin Python canvas/UI tests, including localized writeback failure cleanup | Covered by fake-Krita automated tests; real GUI pending |
| Real Krita plugin discovery in Python Plugin Manager and Docker visibility | Real-profile `install_plugin.py --check` now reports `profile_ok=true`, including `plugin_ui=ok`; `plugin_manager_visible=pending` and `docker_visible=pending` still require observed GUI evidence after restart | Profile installed; GUI evidence pending |
| Real Krita Diagnostics report with launcher discovery, active document, PNG round trip, and selection/mask evidence | Current `acceptance.json` gates `diagnostics_report`, `launcher_discovery`, `active_document`, `canvas_png_round_trip`, and `selection_and_masks` are `pass`; Diagnostics file `generated_at` is `2026-05-10T09:48:12Z`, so rerun Diagnostics after restart before final sign-off | Passed by report; rerun recommended |
| Real Img2Img, Inpaint, Focused Inpaint, Cancel, disconnect, preview, large canvas, result alignment, history, token locality, unauthenticated rejection, gallery send, disabled-flow E2E | `acceptance.json` lists these gates as pending; automation evidence is attached but marked supporting-only | Not complete |
| User docs for enablement, plugin install, troubleshooting, protocol examples, error codes, versioning, and release notes | `docs/krita-bridge.md`, `krita_plugin/README.md`, updated design document | Covered |
| Plugin installer apply/check/restore with backups and running-Krita guard | `krita_plugin/install_plugin.py`, `test_install_plugin.py`; current real-profile apply created/used backup directory `/tmp/krita_real_profile_backup_focus_results_preview` and post-check reports `profile_ok=true` | Covered by tests; real profile refreshed |
| Acceptance report generator with JSON/Markdown outputs, manual evidence handling, manual passed-gate note guard, and Diagnostics schema/layout guard | `krita_plugin/acceptance_report.py`, `krita_plugin/nai_launcher_bridge/diagnostics.py`, tests, `build/krita_acceptance/acceptance.json`, `build/krita_acceptance/acceptance.md` | Covered |
| Hard release gate for completed real acceptance evidence | `krita_plugin/acceptance_report.py --require-ok`; tests cover non-zero exit while any gate is open, zero exit when all gates pass with note-bearing evidence, rejection of bare manual `--evidence-*` flags, failed JSON/Markdown artifacts when note-bearing evidence is missing, and explicit `manual_evidence_notes` reporting even when other gates are still open | Covered |
| Safe preflight command for repeatable verification without writing the real profile | `krita_plugin/preflight.py`, `scripts/krita_bridge_preflight.bat`, `krita_plugin/tests/test_preflight.py`; full plugin suite covers skip-tests/default/require-acceptance behavior, isolated temporary profile install verification, and rejects accidental real-profile `--apply` usage | Covered |

## Earlier Verification Evidence

The following rows are retained from the previous audit snapshot for traceability.
They are superseded by the current verification table below, especially for
real-profile install state, package hash, and open-gate counts.

| Command | Result |
|---|---|
| `python3 -m py_compile krita_plugin/acceptance_report.py krita_plugin/tests/test_acceptance_report.py` | Exit code 0 |
| `python3 -m unittest krita_plugin.tests.test_acceptance_report` | Ran 19 tests in 2.457s, OK |
| `python3 -m unittest krita_plugin.tests.test_ui_state` | Ran 19 tests in 0.824s, OK |
| `python3 -m unittest discover -s krita_plugin/tests` | Ran 98 tests in 3.711s, OK |
| `cmd.exe /c "cd /d G:\AIdarw\Aaalice_NAI_Launcher && C:\dev\flutter\bin\flutter.bat test test\presentation\providers\krita\krita_bridge_service_test.dart"` | Service test file passed, including explicit 402 Anlas, 429 rate-limit, and timeout bridge error-code mappings |
| `cmd.exe /c "cd /d G:\AIdarw\Aaalice_NAI_Launcher && C:\dev\flutter\bin\flutter.bat test test\core\krita\krita_bridge_protocol_test.dart test\core\krita\krita_bridge_server_test.dart test\presentation\providers\krita\krita_bridge_notifier_test.dart test\presentation\providers\krita\krita_bridge_service_test.dart test\presentation\widgets\gallery\image_send_destination_dialog_test.dart"` | 48/48 tests passed |
| `cmd.exe /c "cd /d G:\AIdarw\Aaalice_NAI_Launcher && C:\dev\flutter\bin\flutter.bat analyze lib\core\krita lib\presentation\providers\krita lib\presentation\screens\settings\sections\krita_bridge_settings_section.dart lib\presentation\utils\krita_send_helper.dart test\core\krita test\presentation\providers\krita test\presentation\widgets\gallery\image_send_destination_dialog_test.dart"` | `Analyzing 7 items... No issues found!` |
| `cmd.exe /c "cd /d G:\AIdarw\Aaalice_NAI_Launcher && C:\dev\flutter\bin\flutter.bat analyze"` | Exit code 1 with existing repo-wide lint/info/warning backlog (`2169 issues found`); not used as a Krita-specific completion signal |
| `python3 krita_plugin/package_plugin.py` | Wrote `dist/nai_launcher_bridge_krita_plugin.zip` |
| `python3 -m unittest krita_plugin.tests.test_package_plugin` | Ran 2 tests, OK |
| `sha256sum dist/nai_launcher_bridge_krita_plugin.zip` | `8d0a1f363c6ea1a31e8e369a8c45d9a7c200a65f9facf569ee594cb05b2f2918` |
| `python3 krita_plugin/install_plugin.py --pykrita-dir /tmp/krita-bridge-preflight-5en9xdr9/pykrita --kritarc /tmp/krita-bridge-preflight-5en9xdr9/kritarc --apply` | Applied isolated profile layout |
| `python3 krita_plugin/install_plugin.py --pykrita-dir /tmp/krita-bridge-preflight-5en9xdr9/pykrita --kritarc /tmp/krita-bridge-preflight-5en9xdr9/kritarc --check` | `profile_ok=true` |
| `python3 krita_plugin/install_plugin.py --check` | Historical real profile `profile_ok=false`; superseded by the current real-profile install/check evidence reporting `profile_ok=true` |
| `python3 krita_plugin/acceptance_report.py --output-json /tmp/krita-acceptance-open-bare.json --output-markdown /tmp/krita-acceptance-open-bare.md --evidence-plugin-manager-visible --require-ok` | Returned exit code 1 and appended `manual_evidence_notes=fail` while other real gates remain open |
| `python3 krita_plugin/acceptance_report.py --automation-evidence-file krita_plugin/automation_evidence.example.json --require-ok` | Returned exit code 1 with current real profile because acceptance gates are still open |
| `python3 krita_plugin/preflight.py` | Ran 97 plugin tests in 4.320s, refreshed package, verified isolated temporary profile install, checked real profile read-only, regenerated acceptance report, and reported `acceptance_ok=false` with 25 open gates |
| `cmd.exe /c "cd /d G:\AIdarw\Aaalice_NAI_Launcher && scripts\krita_bridge_preflight.bat --skip-tests"` | Windows wrapper ran successfully, refreshed package, verified isolated temporary profile `/tmp/krita-bridge-preflight-k0po5de_`, checked real profile read-only, regenerated acceptance report, and reported `acceptance_ok=false` with 25 open gates |
| `zipgrep -n "api\.novelai\|Authorization\|endpoint_override\|endpointOverride\|accessToken\|refreshToken\|persistentApiToken\|accountId\|sessionToken" dist/nai_launcher_bridge_krita_plugin.zip` | Exit code 1 with no matches, confirming the current plugin zip does not contain those sensitive NovelAI endpoint/account/token markers |
| `rg -n 'Example .*get_params\|Example Focused Inpaint\|unsupported_document_format\|supported_versions\|Unknown fields' docs/krita-bridge.md` | Finds protocol examples, version mismatch response, forward-compatibility rule, and full error-code coverage in the developer protocol reference |

## Current Verification Evidence

| Command | Result |
|---|---|
| `python3 -m pytest -q krita_plugin/tests/test_ui_state.py -k 'mask_layer_source_is_not_exposed or numeric_parameters_have_linked_sliders_and_spin_boxes or minimum_context_controls_are_enabled_only_for_focused_inpaint or inpaint_always_uses_selection_mask_source or non_focused_inpaint_uses_selection_mask_source'` | `5 passed`, 32 deselected; cache warning only |
| `python3 -m pytest -q krita_plugin/tests/test_ui_state.py -k 'focused_inpaint_live_preview_starts_and_syncs_selection or minimum_context_change_updates_live_focus_outer_frame or deleting_selected_result_removes_item_and_payload or clearing_results_removes_all_items_and_payloads or result_keeps_last_progress_preview_visible or preview_throttle_writes_first_frame_immediately'` | `6 passed`, 37 deselected; cache warning only |
| `python3 -m pytest -q krita_plugin/tests/test_canvas_io.py -k write_png_preview_waits_for_krita_after_replacing_existing_layer` | `1 passed`, 21 deselected; cache warning only |
| `python3 -m pytest -q krita_plugin/tests` | `139 passed`, `4 subtests passed`; cache warning only |
| `cmd.exe /c "cd /d G:\AIdarw\Aaalice_NAI_Launcher && python -m pytest -q krita_plugin\tests"` | Prior Windows run before the clean-canvas export fix: `127 passed` |
| `python3 -m py_compile krita_plugin/nai_launcher_bridge/ui.py krita_plugin/nai_launcher_bridge/canvas_io.py krita_plugin/nai_launcher_bridge/diagnostics.py tool/krita_bridge_runtime_probe.py` | Exit code 0 |
| `cmd.exe /c "cd /d G:\AIdarw\Aaalice_NAI_Launcher && C:\dev\flutter\bin\flutter.bat test test\core\utils\inpaint_mask_utils_test.dart test\presentation\providers\krita\krita_bridge_service_test.dart"` | `27/27` tests passed, including source-preserved inpaint composite, transparent out-of-mask patch extraction, masked preview/writeback, and focused inpaint masked-patch writeback |
| `python3 -m json.tool krita_plugin/automation_evidence.example.json` and `python3 -m json.tool krita_plugin/acceptance_evidence.example.json` | Both JSON files validate |
| `python3 krita_plugin/package_plugin.py` | Refreshed `dist/nai_launcher_bridge_krita_plugin.zip` after non-sandbox retry; SHA256 `2a511dba61de59e3a4f552b4b0070a4ed46dbeb9249fb3becc359ffbba120a83` |
| `python3 -m pytest -q krita_plugin/tests/test_package_plugin.py` | `4 passed`; cache warning only |
| `python3 krita_plugin/package_plugin.py --output /tmp/nai_launcher_bridge_krita_plugin-current.zip` | SHA256 `2a511dba61de59e3a4f552b4b0070a4ed46dbeb9249fb3becc359ffbba120a83`; packaged `ui.py` contains `_export_clean_canvas`, linked slider controls, debounced focus-frame writes, result-area click/double-click/delete/clear handlers, keeps the last progress preview on result, and does not contain `Preview Focus Frame` or `Inpaint Mask Layer` |
| `python3 krita_plugin/install_plugin.py --pykrita-dir /tmp/.../pykrita --kritarc /tmp/.../kritarc --backup-dir /tmp/.../backup --apply` then `--check` | Isolated current-source profile install succeeds with `profile_ok=true`, including `plugin_ui=ok`, `plugin_canvas_io=ok`, `plugin_canvas_utils=ok`, `plugin_diagnostics=ok`, and `kritarc_enabled=ok` |
| `python3 krita_plugin/preflight.py --skip-tests --package-output /tmp/krita_preflight_plugin.zip --report-json /tmp/krita_preflight_acceptance.json --report-markdown /tmp/krita_preflight_acceptance.md` | Preflight succeeds with temp outputs, package SHA256 `2a511dba61de59e3a4f552b4b0070a4ed46dbeb9249fb3becc359ffbba120a83`, isolated profile install verifies `profile_ok=true`, real profile check reports `profile_ok=true`, and acceptance remains false with real GUI/E2E gates pending |
| `unzip -p dist/nai_launcher_bridge_krita_plugin.zip nai_launcher_bridge/ui.py \| rg ...` | Packaged `ui.py` contains `_focus_preview_write_timer`, `_delete_selected_results`, `_clear_results`, `clear_preview=False`, and `_preview_throttle_seconds = 0.35`; no `Preview Focus Frame` or `Inpaint Mask Layer` match was reported |
| `sha256sum dist/nai_launcher_bridge_krita_plugin.zip` | `2a511dba61de59e3a4f552b4b0070a4ed46dbeb9249fb3becc359ffbba120a83` |
| `zipgrep -n "api\.novelai\|Authorization\|endpoint_override\|endpointOverride\|accessToken\|refreshToken\|persistentApiToken\|accountId\|sessionToken" dist/nai_launcher_bridge_krita_plugin.zip` | Exit code 1 with no matches, confirming the plugin zip does not contain those sensitive NovelAI endpoint/account/token markers |
| `python3` zip inspection for packaged `ui.py` | `Preview Focus Frame` absent, while `自动推导同心外框` and `预览层写入失败` are present |
| `cmd.exe /c "cd /d G:\AIdarw\Aaalice_NAI_Launcher && scripts\update_krita_bridge_plugin.bat"` | Earlier run before the clean-canvas export fix installed the then-latest plugin into real profile, enabled `kritarc`, created backup `build\krita_real_profile_backup\20260510-204454`, and post-check reported `profile_ok=true` |
| `python3 krita_plugin/install_plugin.py --apply --backup-dir /tmp/krita_real_profile_backup_focus_results_preview` | Applied current source to the real Krita profile, enabled `kritarc`, and reported `profile_ok=true`, including `plugin_ui=ok` |
| `python3 krita_plugin/install_plugin.py --check` | Current read-only check reports `profile_ok=true`; `plugin_ui=ok`, `plugin_canvas_io=ok`, `plugin_canvas_utils=ok`, `plugin_diagnostics=ok`, and `kritarc_enabled=ok` |
| `python3 krita_plugin/acceptance_report.py --automation-evidence-file krita_plugin/automation_evidence.example.json --output-json /tmp/krita_preflight_acceptance.json --output-markdown /tmp/krita_preflight_acceptance.md` | Current temp report reports `profile_installed_enabled=pass`; acceptance still remains false because real GUI/E2E gates are pending |
| `python3 -m json.tool /mnt/c/Users/10562/AppData/Roaming/nai-launcher/krita-bridge-diagnostics.json` | Existing Diagnostics report validates; generated at `2026-05-10T09:48:12.647363+00:00`, with active document `832x1216`, selection rect `371,701 215x166`, PNG round trip pass, and no failed diagnostics checks |
| `powershell.exe -NoProfile -Command "Start-Process -FilePath 'D:\Krita (x64)\bin\krita.exe'"` | Launched real Krita GUI after profile update |
| `powershell.exe -NoProfile -Command "Start-Sleep -Seconds 2; Get-Process krita -ErrorAction SilentlyContinue \| Select-Object Id,MainWindowTitle,Path"` | Krita is running as PID `35592` with title `Krita` at `D:\Krita (x64)\bin\krita.exe` |

## Remaining Gates From The Real Acceptance Report

The latest current-state real-profile report was generated to
`/tmp/krita_preflight_acceptance.json` and
`/tmp/krita_preflight_acceptance.md`.

Currently passing:

- `profile_installed_enabled`
- `diagnostics_report`
- `launcher_discovery`
- `active_document`
- `canvas_png_round_trip`
- `selection_and_masks`

Currently failing:

- None.

Still pending:

- `plugin_manager_visible`: pending
- `docker_visible`: pending
- `launcher_settings_toggle`: pending
- `auto_discovery_connect`: pending
- `auth_failure_safe`: pending
- `img2img_e2e`: pending
- `inpaint_e2e`: pending
- `focused_inpaint_e2e`: pending
- `krita_cancel_e2e`: pending
- `no_selection_behavior`: pending
- `large_canvas_rejected`: pending
- `disconnect_generation_safe`: pending
- `preview_throttle`: pending
- `result_layer_aligned`: pending
- `launcher_history_recorded`: pending
- `novelai_token_launcher_only`: pending
- `bridge_rejects_unauthenticated`: pending
- `gallery_send_e2e`: pending
- `disabled_bridge_existing_flows`: pending

## Next Required Action

### 2026-05-11 Current Real-Profile State

The current source includes live Focused Inpaint frame updates, clean canvas
export before sending requests, preview-layer failure throttling, selection-only
inpaint masks, linked slider plus numeric controls for `Strength`, `Noise`,
`Inpaint Strength`, and `Minimum Context`, a bottom result area where
single-click previews a generated image, double-click adds it as a new
layer, and `Delete`/`Clear` manage stored results. The current package and
isolated profile install are refreshed from current source. The latest real
profile apply and read-only check report that the installed plugin matches the
current source:

- `profile_ok=true`
- `plugin_ui=ok`
- `plugin_canvas_io=ok`
- `plugin_canvas_utils=ok`
- `plugin_diagnostics=ok`
- `kritarc_enabled=ok`

The plugin source now removes bridge-owned preview layers before exporting a
new Img2Img/Inpaint request so temporary `NAI Preview` or `NAI Focus Preview`
overlays cannot be sent back into Launcher as source pixels. Focused Inpaint
restores the live focus frame after that clean canvas export. All Inpaint
requests now use the current Krita selection as the mask; the legacy `Inpaint
Mask Layer` source and Mask Source dropdown have been removed. Disabling
Focused Inpaint removes the double-frame layer. Final result and pushed images
now enter the Docker result area first. Single-click writes the temporary
`NAI Preview` layer; double-click calls result writeback and still reports
`已作为新文档打开 ...` when Krita falls back to a new document. `Delete` removes
selected result items and `Clear` empties the result area. The last progress
preview is kept visible when the final result arrives. Preview writes are
throttled to 0.35 seconds, focus-frame layer writes are debounced, and repeated
preview-layer failures are localized and not reported every frame.
The repo `dist` package and the explicit `/tmp` package are refreshed from the
same current source:

```text
/mnt/g/aidarw/aaalice_nai_launcher/dist/nai_launcher_bridge_krita_plugin.zip
/tmp/nai_launcher_bridge_krita_plugin-current.zip
SHA256: 2a511dba61de59e3a4f552b4b0070a4ed46dbeb9249fb3becc359ffbba120a83
```

Current automated evidence:

- latest local rerun after the focus/result/preview fix:
  `python3 -m pytest -q krita_plugin/tests`: `139 passed`, `4 subtests passed`
- prior Windows-side plugin suite before the clean-canvas export fix:
  `cmd.exe /c "python -m pytest -q krita_plugin\tests"`: `127 passed`
- targeted selection-only mask and linked slider/numeric UI tests: `5 passed`
  in `test_ui_state.py`
- targeted focus/result/preview UI tests: `6 passed` in `test_ui_state.py`
- targeted live Focused Inpaint / clean canvas export UI tests remain covered in
  `test_ui_state.py`
- targeted preview-layer failure resilience tests:
  `focused_inpaint_send_continues_when_restoring_live_frame_fails` and
  `repeated_preview_layer_failure_is_not_reported_every_frame` pass in
  `test_ui_state.py`
- targeted preview-layer wait test: `1 passed` in `test_canvas_io.py`
- current-source package from the official `--output` path:
  `python3 krita_plugin/package_plugin.py --output
  /tmp/nai_launcher_bridge_krita_plugin-current.zip`, SHA256
  `2a511dba61de59e3a4f552b4b0070a4ed46dbeb9249fb3becc359ffbba120a83`;
  packaged `ui.py` includes `_export_clean_canvas`, linked slider controls,
  debounced focus-frame writes, result-area click/double-click/delete/clear
  handlers, keeps the last progress preview on final result, and has no
  `Preview Focus Frame` or `Inpaint Mask Layer` button/control text
- runtime probe source now records
  `focus_layer_visible_during_clean_export=false` and
  `focus_layer_restored_after_clean_export=true` when executed inside real
  Krita, so manual runtime evidence can confirm the focus frame is not baked
  into the source PNG export
- isolated current-source profile install to `/tmp/.../pykrita` with explicit
  `/tmp/.../backup`: `profile_ok=true`, including `plugin_ui=ok` and
  `kritarc_enabled=ok`
- preflight with temp outputs:
  `python3 krita_plugin/preflight.py --skip-tests --package-output
  /tmp/krita_preflight_plugin.zip --report-json
  /tmp/krita_preflight_acceptance.json --report-markdown
  /tmp/krita_preflight_acceptance.md` succeeds, verifies an isolated
  current-source profile install with `profile_ok=true`, reports the real
  profile as `profile_ok=true`, and leaves acceptance false because the real
  GUI/E2E gates remain pending
- `flutter.bat test test\core\utils\inpaint_mask_utils_test.dart
  test\presentation\providers\krita\krita_bridge_service_test.dart`: `27/27`
  tests passed for masked compositing and Krita bridge inpaint writeback
- `python3 -m json.tool` validates both
  `krita_plugin/automation_evidence.example.json` and
  `krita_plugin/acceptance_evidence.example.json`
- `python3 krita_plugin/install_plugin.py --apply --backup-dir
  /tmp/krita_real_profile_backup_focus_results_preview` updated the real Krita
  profile from current source and reported `profile_ok=true`
- `python3 krita_plugin/install_plugin.py --check` reports `profile_ok=true`
  for the real Krita profile, including `plugin_ui=ok`
- `python krita_plugin\acceptance_report.py --automation-evidence-file ...`
  still reports `acceptance_ok=false` because the real GUI/E2E gates remain
  pending.

Current next action for full bridge acceptance: relaunch Krita, confirm the
Python Plugin Manager entry and `Settings > Dockers > NAI Launcher Bridge`,
rerun Diagnostics from the current Docker, optionally run
`tool/krita_bridge_runtime_probe.py` from Krita's Scripter to capture
`focused_inpaint_probe.ok`, then test the real live Focused Inpaint frame,
result-area single-click preview, result-area double-click layer insertion,
masked writeback, cancellation, history recording, and gallery send path. The
full bridge acceptance goal can be marked complete only when the real-profile
report returns `acceptance_ok=true` for those real GUI/E2E requirements.
