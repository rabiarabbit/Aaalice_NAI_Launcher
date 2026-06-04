# Krita Bridge

The Krita Bridge connects Krita to NAI Launcher on the same Windows user session. Krita handles canvas input/output only; NAI Launcher keeps NovelAI credentials, request construction, generation, history, and statistics.

## Enable In Launcher

1. Open NAI Launcher settings.
2. Enable `Krita Bridge`.
3. Confirm the status shows either `监听中` or `已连接`.
4. If the connection gets stale, use `重生成会话` to restart the local bridge with a new secret.

The bridge is disabled by default and listens only on `127.0.0.1`. Launcher writes the current port and session secret to `%APPDATA%/nai-launcher/krita-bridge.json`.

## Install The Krita Plugin

1. Build or use `dist/nai_launcher_bridge_krita_plugin.zip`.
2. Copy `nai_launcher_bridge.desktop` and the `nai_launcher_bridge/` folder to `%APPDATA%/krita/pykrita/`.
3. Open `Settings > Configure Krita > Python Plugin Manager`.
4. Enable `NAI Launcher Bridge`, restart Krita, then open `Settings > Dockers > NAI Launcher Bridge`.

The plugin reads the discovery file, rejects stale Launcher PIDs, connects to `ws://127.0.0.1:{port}/krita`, and authenticates with the per-session secret. It prefers Krita's bundled `PyQt5.QtWebSockets.QWebSocket`; if that module is unavailable, it falls back to the bundled stdlib WebSocket client. It does not read or store NovelAI tokens.

To build the plugin zip from the current source, run:

```powershell
python krita_plugin/package_plugin.py
```

If `dist` is not writable in the current environment, write the same package
layout to an explicit path:

```bash
python3 krita_plugin/package_plugin.py --output /tmp/nai_launcher_bridge_krita_plugin.zip
```

For a repeatable local install, run a dry-run first:

```powershell
python krita_plugin/install_plugin.py
```

To check whether the current profile already contains the full plugin runtime
file set, required `.desktop` manifest entries, and `kritarc` enable flag
without writing files, run:

```powershell
python krita_plugin/install_plugin.py --check
```

To summarize profile checks plus the latest docker Diagnostics report into the
acceptance gates, run:

```powershell
python krita_plugin/acceptance_report.py
```

For the safe preflight path, which does not install or enable anything in the
real Krita profile, run:

```powershell
python krita_plugin/preflight.py
```

On Windows, the same safe preflight is also available as:

```bat
scripts\krita_bridge_preflight.bat
```

It runs the plugin unit tests, refreshes the plugin zip, applies and verifies an
isolated temporary profile layout, checks the real profile read-only, and
regenerates `build/krita_acceptance/acceptance.json` and
`build/krita_acceptance/acceptance.md` with automation evidence attached. The
isolated install uses a temporary directory only; it does not install or enable
the real Krita profile. Use `--require-acceptance` only after all real GUI
evidence has been recorded.

If the default `dist` or `build/krita_acceptance` paths are not writable, send
the package and report outputs to writable temporary paths:

```bash
python3 krita_plugin/preflight.py --skip-tests --package-output /tmp/krita_preflight_plugin.zip --report-json /tmp/krita_preflight_acceptance.json --report-markdown /tmp/krita_preflight_acceptance.md
```

To save those gates as local artifacts, run:

```powershell
python krita_plugin/acceptance_report.py --output-json build/krita_acceptance/acceptance.json --output-markdown build/krita_acceptance/acceptance.md
```

For a quick local summary after manual checks, you can pass only the manual
evidence flags that were confirmed:

```powershell
python krita_plugin/acceptance_report.py --evidence-plugin-manager-visible --evidence-docker-visible --evidence-launcher-settings-toggle --evidence-auto-discovery-connect --evidence-auth-failure-safe --evidence-img2img-e2e --evidence-inpaint-e2e --evidence-focused-inpaint-e2e --evidence-krita-cancel-e2e --evidence-no-selection-behavior --evidence-large-canvas-rejected --evidence-disconnect-generation-safe --evidence-preview-throttle --evidence-result-layer-aligned --evidence-launcher-history-recorded --evidence-novelai-token-launcher-only --evidence-bridge-rejects-unauthenticated --evidence-gallery-send-e2e --evidence-disabled-bridge-existing-flows --output-json build/krita_acceptance/acceptance.json --output-markdown build/krita_acceptance/acceptance.md
```

When using the report as a hard release gate, copy
`krita_plugin/acceptance_evidence.example.json` to a work file, set only
confirmed gates to `"passed": true`, add a non-empty `"note"` to each passed
gate, and run with `--require-ok`:

```powershell
python krita_plugin/acceptance_report.py --evidence-file build/krita_acceptance/evidence.json --output-json build/krita_acceptance/acceptance.json --output-markdown build/krita_acceptance/acceptance.md --require-ok
```

Evidence files are strict: unknown gate names are rejected instead of ignored,
and passed manual gates require notes. `--require-ok` also rejects bare
`--evidence-*` flags when the report would otherwise pass, so typoed or
context-free entries cannot silently become release evidence.

Automation evidence can be attached separately for supporting test commands,
but it does not close manual GUI gates. Copy
`krita_plugin/automation_evidence.example.json`, update the command output
notes, and pass it with:

```powershell
python krita_plugin/acceptance_report.py --automation-evidence-file build/krita_acceptance/automation_evidence.json --output-json build/krita_acceptance/acceptance.json --output-markdown build/krita_acceptance/acceptance.md
```

After closing Krita and confirming the profile change, run:

```powershell
python krita_plugin/install_plugin.py --apply
```

The installer writes the same `%APPDATA%/krita/pykrita/` layout, enables
`enable_nai_launcher_bridge=true` in `%LOCALAPPDATA%/kritarc`, and backs up any
existing plugin files or `kritarc` under
`build/krita_real_profile_backup/<timestamp>/`.
The read-only check and acceptance-report profile gate verify the installed
runtime modules plus the `.desktop` file still declare the Krita plugin service
type, `X-KDE-Library=nai_launcher_bridge`, and `Name=NAI Launcher Bridge`.
Use `scripts\update_krita_bridge_plugin.bat` from the Windows repository root
for a checked install path; it runs pre/post profile checks and only succeeds
when the final output includes `profile_ok=true`.
It refuses `--apply` or `--restore --apply` while `krita.exe` is running unless
`--allow-running-krita` is provided after manual confirmation.

The same backup directory contains `install_manifest.json` for rollback. To
restore, preview first and then apply after confirming the backup:

```powershell
python krita_plugin/install_plugin.py --restore --backup-dir build/krita_real_profile_backup/<timestamp>
python krita_plugin/install_plugin.py --restore --apply --backup-dir build/krita_real_profile_backup/<timestamp>
```

## Use The Bridge

Use `Get Params` to copy the active Launcher generation settings into the Krita docker. `Img2Img` sends the visible Krita document projection to Launcher. `Inpaint` sends the visible projection plus the active Krita selection as the repaint mask; no manual mask layer is required. `Focused Inpaint` uses that same selection as the inner repaint area and derives the outer focus/context frame from `Minimum Context`. While Focused Inpaint is enabled, the docker updates the frame text immediately as the active selection or `Minimum Context` changes, then debounces the temporary `NAI Focus Preview` layer write so Krita selection dragging stays responsive; disabling Focused Inpaint removes that double-frame preview.

Before a new request is exported, the plugin removes bridge-owned preview
layers from the visible Krita projection so temporary `NAI Preview` or
`NAI Focus Preview` overlays are not sent back into Launcher as source pixels.
Focused Inpaint restores the live focus frame immediately after the clean
canvas export. During generation, preview images update the `NAI Preview` layer
at a throttled cadence, and the last progress preview stays visible when the
final result arrives. Final images are added to the Docker result area at the
bottom: single-click a result to preview it on the temporary `NAI Preview`
layer, double-click it to add it as a new layer when dimensions match the
active document size, use `Delete` to remove selected results, or use `Clear`
to empty the result area; mismatched sizes open as a new Krita document.

Launcher records Krita-generated final images in the normal generation history. When the existing Launcher auto-save setting is enabled and the image is saved to the local gallery, `result.saved_path` contains that saved PNG path; otherwise `saved_path` is omitted and the result still includes `result.params`.

Click `Diagnostics` in the Krita docker after installation to write a local report to `%APPDATA%/nai-launcher/krita-bridge-diagnostics.json`. The report checks plugin layout, QtWebSockets availability, Launcher discovery, active-document status, canvas PNG export/writeback, and the active Krita selection mask source. Open a Krita document before running diagnostics if you need the canvas round-trip checks.

Acceptance reports only trust Diagnostics files that contain
`schema_version: 1`, `plugin: "nai_launcher_bridge"`, and a passing
`plugin_layout` check, so stale or hand-written JSON files cannot accidentally
close the real Krita Diagnostics gates.

For a deeper real-Krita runtime probe, open Krita's Scripter, run
`tool/krita_bridge_runtime_probe.py`, and inspect
`%APPDATA%/nai-launcher/krita-bridge-runtime-probe.json`. The probe creates a
small document, toggles Focused Inpaint in the real Docker object, verifies that
the manual focus-preview button is absent, checks that `Minimum Context` and
selection changes update the live focus frame, confirms that clean canvas export
temporarily removes `NAI Focus Preview` before source PNG capture, and confirms
that disabling Focused Inpaint removes the double-frame preview layer. Treat
this as runtime supporting evidence; the final acceptance report still requires
observed real GUI/E2E gates.

## Manual Acceptance Checklist

Use this checklist after installing the plugin into the real Krita profile. Only mark a gate as passed in `acceptance_evidence.json` after directly observing it in the real Launcher + Krita UI.

For the current prompt-to-artifact completion audit and the list of still-open
real GUI gates, see `docs/krita-bridge-acceptance-audit.md`.

1. Confirm `NAI Launcher Bridge` appears in `Settings > Configure Krita > Python Plugin Manager`, enable it, restart Krita, and confirm `Settings > Dockers > NAI Launcher Bridge` is visible.
2. Toggle `Krita Bridge` off and on from Launcher settings, confirming the status changes and `%APPDATA%/nai-launcher/krita-bridge.json` is recreated with a new session.
3. Connect from the Krita docker without manually copying a token or port. Then edit the discovery secret to a wrong value and confirm authentication fails without a crash or leaked token/account text.
4. Open a `1024x1024` RGBA document, create a non-empty Krita selection, run `Diagnostics`, and confirm `launcher_discovery`, `active_document`, `canvas_png_round_trip`, and `selection_and_masks` pass.
5. Optionally run `tool/krita_bridge_runtime_probe.py` from Krita's Scripter and confirm `focused_inpaint_probe.ok` is `true` in `%APPDATA%/nai-launcher/krita-bridge-runtime-probe.json`.
6. Run `Img2Img`, normal `Inpaint`, and `Focused Inpaint`. Confirm each result appears in the Docker result area, single-click previews it, double-click adds it as a new aligned layer, `Delete` removes selected results, `Clear` empties the result area, and Launcher history records the final image and key params.
7. During a bridge generation, test `Cancel`, disconnect/reconnect, preview throttling, empty/no-selection behavior, and a canvas above `4096x4096`. Confirm no partial preview is written as a final result.
8. Send a generated or gallery image from Launcher to Krita through the authenticated connection. Then disable the bridge and confirm existing generation, gallery, and Vibe flows still work.
9. Record only the observed passes in `krita_plugin/acceptance_evidence.example.json` copied to `build/krita_acceptance/evidence.json`, rerun `acceptance_report.py`, and keep `acceptance_ok=false` until every gate is backed by evidence.

## Protocol Reference

Krita sends JSON text frames to `ws://127.0.0.1:{port}/krita`. The first message must be:

```json
{"type":"ping","version":1,"secret":"<discovery secret>"}
```

Launcher replies:

```json
{"type":"pong","version":1}
```

If the session secret is valid but the plugin protocol version is not
supported, Launcher still replies with `pong` and includes the compatible
versions without authenticating the socket:

```json
{"type":"pong","version":1,"supported_versions":[1]}
```

Supported Krita-to-Launcher messages are `get_params`, `img2img`, `inpaint`, and `cancel`. Supported Launcher-to-Krita messages are `params`, `progress`, `result`, `push_image`, `error`, `pong`, and `cancelled`.

Request/response messages use `id` for correlation. Unknown fields are ignored
for forward compatibility, but missing required fields return `invalid_request`.
V1 rejects scaled payload metadata and requires canvas PNG dimensions from
`64x64` through `4096x4096`.

Example `get_params` request:

```json
{"type":"get_params","id":"req-params"}
```

Example `params` response:

```json
{
  "type": "params",
  "id": "req-params",
  "model": "nai-diffusion-4-5-full-inpainting",
  "sampler": "k_euler",
  "steps": 28,
  "cfg_scale": 5.0,
  "seed": 12345,
  "width": 1024,
  "height": 1024,
  "strength": 0.7,
  "noise": 0.0,
  "inpaint_strength": 1.0,
  "minimum_context_pixels": 88
}
```

Example `img2img` request:

```json
{
  "type": "img2img",
  "id": "req-img2img",
  "image": "<base64 PNG>",
  "prompt": "1girl, painterly",
  "negative_prompt": "lowres",
  "strength": 0.5,
  "noise": 0.0
}
```

Example Focused Inpaint request:

```json
{
  "type": "inpaint",
  "id": "req-inpaint",
  "image": "<base64 PNG>",
  "mask": "<base64 PNG, white=repaint>",
  "selection_rect": {"x": 200, "y": 150, "w": 400, "h": 300},
  "prompt": "paint stars",
  "negative_prompt": "bad anatomy",
  "strength": 0.7,
  "noise": 0.0,
  "inpaint_strength": 1.0,
  "minimum_context_pixels": 88,
  "mask_closing_iterations": 0,
  "mask_expansion_iterations": 0,
  "focused_inpaint": true
}
```

Example progress, result, and cancel flow:

```json
{"type":"progress","id":"req-inpaint","step":14,"total_steps":28,"preview_image":"<base64 preview>"}
{"type":"result","id":"req-inpaint","image":"<base64 PNG>","name":"NAI Inpaint 10:30:05","saved_path":"G:/.../image.png","params":{"seed":12345,"prompt":"paint stars"}}
{"type":"cancel","id":"req-inpaint"}
{"type":"cancelled","id":"req-inpaint"}
```

Launcher-to-Krita `push_image` does not require an active Krita document; the
plugin inserts it into the active document when compatible or opens it as a new
Krita document:

```json
{"type":"push_image","image":"<base64 PNG>","name":"gen_20260507_103005"}
```

Error frames are stable protocol objects:

```json
{"type":"error","id":"req-inpaint","code":"busy","message":"Previous request still processing"}
```

Common error codes include `auth_failed`, `unauthorized_bridge_client`,
`payload_too_large`, `invalid_request`, `unsupported_message`, `busy`,
`empty_mask`, `insufficient_anlas`, `rate_limited`, `timeout`,
`stream_interrupted`, `streaming_unsupported`, `server_error`, and
`unsupported_document_format`.

## Troubleshooting

- Plugin does not appear: confirm the `.desktop` file and plugin folder are direct children of `%APPDATA%/krita/pykrita/`.
- Cannot connect: enable the bridge in Launcher settings and confirm the discovery file exists.
- Wrong secret: click `重生成会话` in Launcher settings, then reconnect from Krita.
- Large canvas rejected: V1 supports canvases from `64x64` through `4096x4096`.
- Immediate retry rejected: after a failed Krita request, wait a moment before retrying.
- Empty mask: create a non-empty Krita selection before using `Inpaint`.
- QtWebSockets import error: the plugin automatically falls back to the bundled stdlib WebSocket client. If connection still fails, click `重生成会话` in Launcher and reconnect.

## Release Notes

The Krita Bridge is a local-only integration. NovelAI credentials remain inside Launcher, and the Krita plugin only sends canvas PNGs, prompts, and control values over the authenticated loopback bridge.
