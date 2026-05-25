# NAI Launcher - Krita Integration Design

**Date:** 2026-05-07
**Status:** Approved with Feasibility Gates
**Approach:** Thin Plugin + Smart Launcher (Plan B)

## Overview

Enable bidirectional image workflow between NAI Launcher and Krita:

- **Krita → Launcher**: Inpaint (including Focused Inpaint), Img2Img with prompt input and streaming preview
- **Launcher → Krita**: Push generated/gallery images to Krita for editing
- **Architecture**: Launcher runs WebSocket server; Krita Python plugin connects as lightweight client

The plugin handles only canvas I/O and UI. All generation logic (crop/resize/composite for Focused Inpaint, API calls, streaming) stays in the Launcher.

## Implementation Gates

Before implementation starts, validate the following assumptions with small throwaway prototypes:

1. **Krita plugin discovery**: confirm the plugin appears in Krita's Python Plugin Manager with the exact `.desktop` + folder layout described in Section 3.
2. **WebSocket client availability**: confirm the target Windows Krita build can import `PyQt5.QtWebSockets.QWebSocket`. If not, switch the plugin transport to a bundled pure-Python WebSocket client or an HTTP polling/SSE fallback.
3. **Canvas PNG round trip**: confirm export of the visible projection to PNG and insertion of a PNG into a new paint layer preserve color channels, alpha, and dimensions.
4. **Focused Inpaint parity**: confirm Krita-sourced `image + mask + focus rect + minimum context` produces the same request crop and final composite as the in-app editor path.
5. **Generation arbitration**: confirm Krita requests cannot cancel or overwrite an active generation started from the Launcher UI unless the user explicitly chooses to cancel it.

If any gate fails, update this document before writing the production implementation.

### Implementation Gate Results (2026-05-10)

- **Krita plugin discovery:** Package layout is implemented and verified by zip/package tests, and `krita_plugin/install_plugin.py` provides a dry-run/check/apply/restore installer with backups and `install_manifest.json` for the real profile layout, required `.desktop` manifest entries, and `kritarc` enable flag. Apply/restore writes refuse to run while `krita.exe` is detected unless `--allow-running-krita` is provided after manual confirmation. `krita_plugin/acceptance_report.py` summarizes profile checks plus the latest docker Diagnostics report into acceptance-gate statuses, records manual GUI/E2E evidence flags or a note-bearing evidence JSON for the full manual-test checklist, and can save JSON/Markdown artifacts under `build/krita_acceptance/`. A read-only real-profile check currently reports the `.desktop` file and plugin folder missing from `%APPDATA%/krita/pykrita/`, with `%LOCALAPPDATA%/kritarc` present but `enable_nai_launcher_bridge=true` not enabled. The real Krita Python Plugin Manager/Docker appearance gate is still not fully closed yet because applying it to the real profile is a user-profile configuration change that needs explicit confirmation.
- **WebSocket client availability:** Target Krita is `Krita (x64) 5.3.1 (git 9069dbc)` installed at `D:\Krita (x64)`. Its bundled `PyQt5` does not include `QtWebSockets.pyd`, so V1 uses the bundled stdlib WebSocket fallback client. Fallback callbacks are marshalled back through Qt signals before touching Docker UI or canvas state.
- **Canvas PNG round trip:** Real Krita command-line PNG import/export preserved `RGBA`, dimensions, and alpha on a simple document. Plugin-side export now prefers `doc.projection(...).save(..., "PNG")` and falls back to Krita `exportImage`. Plugin layer writeback is implemented with `setPixelData` plus a file-open fallback, but real GUI writeback still needs the enabled-plugin gate above.
- **Focused Inpaint parity:** Launcher-side mapping uses existing `ImageParams`, focused selection rect, and `minimum_context_pixels` through the existing generation stream path. Unit tests cover request mapping and stream/result relay; real Krita-sourced end-to-end crop/composite remains part of the manual acceptance pass.
- **Generation arbitration:** Service/provider tests cover busy rejection, scoped cancel by request id, client-disconnect cancellation, and Launcher UI busy guards while a Krita request is active.

## Section 1: WebSocket Communication Protocol

### Transport

- Launcher listens on `ws://127.0.0.1:{port}/krita` (loopback only)
- Single client model: one Krita connection at a time; new connection replaces old
- JSON text frames for all messages; binary frames reserved for future optimization
- Protocol versioned via `ping`/`pong` handshake

### Auto-Discovery

Launcher writes port file on server start:

```
%APPDATA%/nai-launcher/krita-bridge.json
```

```json
{
  "port": 52381,
  "pid": 12345,
  "version": 1,
  "secret": "base64url-random-32-bytes",
  "started_at": "2026-05-07T10:30:00Z"
}
```

Krita plugin reads this file to discover the port. PID field enables stale-file detection (check if process is alive). File is deleted on Launcher clean exit.

Security requirements for the port file:

- `secret` is generated per Launcher process start and must be included in the first `ping`.
- The file should be written under the current user's app-data directory with normal user-only permissions where possible.
- Stale files are ignored when the PID is dead, when the secret is missing, or when the process start time does not match the current Launcher process.
- Loopback binding is necessary but not sufficient; any local process can connect to `127.0.0.1`, so every message after handshake must be tied to the authenticated WebSocket session.

### Protocol Envelope

All JSON messages use a common envelope:

```json
{
  "type": "inpaint",
  "id": "req-001",
  "version": 1,
  "payload": {}
}
```

For readability, examples below show fields inline. The implementation should still parse through the typed envelope model so future protocol versions can coexist.

Common rules:

- `id` is required for request/response correlation except unsolicited `push_image`.
- Unknown `type` values return `error` with code `unsupported_message`.
- Unknown fields are ignored for forward compatibility.
- Required-field failures return `error` with code `invalid_request`.
- Maximum accepted text-frame size is configurable; V1 should start with `64 MB` and return `payload_too_large` before decoding image bytes.

### Message Types: Krita → Launcher

#### `inpaint`

```json
{
  "type": "inpaint",
  "id": "req-001",
  "image": "<base64 PNG, full canvas>",
  "mask": "<base64 PNG, white=repaint>",
  "selection_rect": {"x": 200, "y": 150, "w": 400, "h": 300},
  "prompt": "1girl, sitting",
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

- `selection_rect`: null when `focused_inpaint` is false
- `selection_rect` is always in original canvas coordinates.
- `minimum_context_pixels` maps to the existing `minimumContextMegaPixels` argument despite the older internal name. Current implementation treats the value as a `0..192` pixel padding, not as a normalized `0.0..1.0` ratio and not as true megapixels.
- `strength` maps to img2img/infill `ImageParams.strength`.
- `inpaint_strength` maps to `ImageParams.inpaintStrength` and therefore to `inpaintImg2ImgStrength` in the NovelAI request.
- `mask_closing_iterations` and `mask_expansion_iterations` map to `ImageParams.inpaintMaskClosingIterations` and `ImageParams.inpaintMaskExpansionIterations`.

#### `img2img`

```json
{
  "type": "img2img",
  "id": "req-002",
  "image": "<base64 PNG>",
  "prompt": "...",
  "negative_prompt": "...",
  "strength": 0.5,
  "noise": 0.0
}
```

#### `get_params`

```json
{"type": "get_params", "id": "req-003"}
```

Requests current generation parameter snapshot from Launcher.

#### `cancel`

```json
{"type": "cancel", "id": "req-001"}
```

#### `ping`

```json
{"type": "ping", "version": 1, "secret": "base64url-random-32-bytes"}
```

### Message Types: Launcher → Krita

#### `result`

```json
{
  "type": "result",
  "id": "req-001",
  "image": "<base64 PNG, full composited image>"
}
```

For Focused Inpaint, the image is already composited back to full canvas size.

#### `progress`

```json
{
  "type": "progress",
  "id": "req-001",
  "step": 14,
  "total_steps": 28,
  "preview_image": "<base64 JPEG, current denoising preview>"
}
```

`preview_image` is included when available from NAI's MessagePack streaming API (not guaranteed on every step). When using the current `NAIImageGenerationApiService.generateImageStream()` path with Focused Inpaint enabled, previews are already composited back onto the full canvas by the Launcher. The plugin should therefore write previews at full canvas size. If a future bridge bypasses that service-level composite and sends crop-only previews, it must add `preview_rect` and `preview_space` fields instead of silently stretching.

#### `error`

```json
{
  "type": "error",
  "id": "req-001",
  "code": "auth_failed",
  "message": "Human-readable error description"
}
```

#### `params`

```json
{
  "type": "params",
  "id": "req-003",
  "model": "nai-diffusion-4-curated-preview",
  "sampler": "k_euler",
  "steps": 28,
  "cfg_scale": 5.0,
  "seed": 12345,
  "width": 832,
  "height": 1216,
  "strength": 0.7,
  "noise": 0.0,
  "inpaint_strength": 1.0,
  "minimum_context_pixels": 88
}
```

#### `push_image`

```json
{
  "type": "push_image",
  "image": "<base64 PNG>",
  "name": "gen_20260507_103005"
}
```

Launcher pushes an image to Krita (from generation page or gallery).

#### `pong`

```json
{"type": "pong", "version": 1}
```

#### `cancelled`

```json
{"type": "cancelled", "id": "req-001"}
```

## Section 2: Launcher Side Architecture

### New Module

```
lib/core/krita/
  krita_bridge_server.dart    -- dart:io HttpServer + WebSocket upgrade
  krita_bridge_models.dart    -- Message type definitions
  krita_bridge_protocol.dart  -- JSON validation, versioning, and error mapping

lib/presentation/providers/krita/
  krita_bridge_notifier.dart  -- Riverpod lifecycle and settings integration
  krita_bridge_service.dart   -- Orchestrates generation requests from Krita
```

`lib/core/krita` must stay transport/protocol-only. It should not read Riverpod providers or generation UI state directly. Request orchestration belongs in the provider/application layer because it depends on `GenerationParamsNotifier`, `ImageWorkflowController`, `NAIImageGenerationApiService`, auth state, and UI settings.

### WebSocket Server (`krita_bridge_server.dart`)

Uses `dart:io` `HttpServer` + `WebSocketTransformer` (no new pub dependencies):

- `start({int preferredPort = 0})` — bind loopback, OS assigns port
- Single client model: `WebSocket? _client`
- `send(Map<String, dynamic>)` for JSON, `sendBinary(Uint8List)` reserved
- Exposes `Stream<Map<String, dynamic>> messages` for incoming messages
- Rejects unauthenticated sockets until a valid `ping` with `secret` is received
- Closes the old authenticated socket when a new authenticated Krita session connects

### Bridge Service (`krita_bridge_service.dart`)

Translates Krita messages into existing generation pipeline calls:

| Krita Request | Launcher Call Chain |
|---|---|
| `inpaint` (focused) | Build `ImageParams(action: infill)` → `NAIImageGenerationApiService.generateImageStream(... focusedInpaintEnabled: true, minimumContextMegaPixels: minimum_context_pixels, focusedSelectionRect: selection_rect)` |
| `inpaint` (normal) | Build `ImageParams(action: infill)` → `InpaintMaskUtils.prepareRequestMaskBytes()` through request builder → `NAIImageGenerationApiService` |
| `img2img` | Build `ImageParams(action: img2img)` → `NAIImageGenerationApiService` |
| `get_params` | Read `GenerationParamsNotifier.state` snapshot |
| Push image | Launcher UI triggers `server.send()` |

Streaming preview relay: listens to `Stream<ImageStreamChunk>` from API service, forwards each `previewImage` as a `progress` WebSocket message.

The bridge must not bypass the existing request builder. It should create an `ImageParams` snapshot from current Launcher parameters, override only Krita-supplied image/mask/prompt/control fields, and then use the same API service path as the rest of the app.

### Riverpod Integration

```dart
// lib/presentation/providers/krita/krita_bridge_notifier.dart
@Riverpod(keepAlive: true)
class KritaBridgeNotifier extends _$KritaBridgeNotifier {
  // States: disabled / starting / listening / connected / error
  // Manages KritaBridgeServer + KritaBridgeService lifecycle
}
```

- `keepAlive: true` — server must persist across navigation
- Initialized via `AppBootstrapEffects` pattern (if bridge is enabled in settings)
- Watches `GenerationParamsNotifier` for `get_params` responses

### UI Integration

- **Settings page**: Krita Integration toggle + port display + connection status indicator
- **Generation image actions**: "Send to Krita" action on generated/history images, reusing the existing image action menu pattern.
- **Gallery page**: add Krita as a destination in the existing `ImageSendDestinationDialog` instead of creating a separate parallel menu path.
- **Connection state**: show disabled/listening/connected/error, connected client label, current port, and a "regenerate session" action that restarts the server and writes a new secret.

### Dependency Changes

Launcher side: none. `dart:io` provides `HttpServer` + `WebSocketTransformer` natively. Existing `web_socket_channel` package remains for ComfyUI client only.

Krita plugin side: zero-dependency is a goal, not yet a guarantee. Validate `PyQt5.QtWebSockets` in the target Krita build. If unavailable, vendor a small pure-Python WebSocket client into the plugin package or switch V1 to HTTP request/response plus polling/SSE.

## Section 3: Krita Plugin Architecture

### File Structure

```
%APPDATA%/krita/pykrita/
  nai_launcher_bridge.desktop    -- Plugin manifest, sibling of plugin folder
  nai_launcher_bridge/
    __init__.py                  -- Imports plugin module
    nai_launcher_bridge.py       -- Registers Extension + DockWidgetFactory
    bridge_client.py             -- WebSocket client connecting to Launcher
    bridge_dock.py               -- DockWidget panel (prompt input, controls, buttons)
    canvas_utils.py              -- Canvas read/write helpers
    protocol.py                  -- JSON message helpers
```

Manual install location: place both `nai_launcher_bridge.desktop` and the `nai_launcher_bridge/` folder directly under `%APPDATA%/krita/pykrita/`, then enable it in Krita's Python Plugin Manager and restart Krita.

Optional package install: ship a zip whose root contains `nai_launcher_bridge.desktop` and `nai_launcher_bridge/` so Krita's Python plugin importer can install the same layout.

### Zero-Dependency Strategy

Only uses Krita's bundled PyQt5 and Python stdlib:

| Capability | Implementation |
|---|---|
| WebSocket client | Preferred: `PyQt5.QtWebSockets.QWebSocket`; fallback: vendored pure-Python WebSocket client if QtWebSockets is unavailable |
| JSON | `json` (stdlib) |
| Base64 | `base64` (stdlib) |
| Port file | `os` + `json` (stdlib) |
| PID detection | `os` / `ctypes` (Windows) |
| UI widgets | `PyQt5.QtWidgets` |

No `pip install` should be required for V1. However, `QtWebSockets` availability must be validated before committing to the zero-dependency path.

### WebSocket Client (`bridge_client.py`)

```python
class BridgeClient(QObject):
    connected = pyqtSignal()
    disconnected = pyqtSignal()
    message_received = pyqtSignal(dict)
```

- Reads `%APPDATA%/nai-launcher/krita-bridge.json` for port
- Validates PID is alive before connecting
- Sends `ping` with `version` and `secret`; refuses to enter connected state until `pong` confirms a supported version
- Auto-reconnect timer: 5-second interval on disconnect

### Dock Panel (`bridge_dock.py`)

```
+-- NAI Launcher Bridge ------------------+
| [Status LED] Connected                  |
|                                         |
| Prompt:                                 |
| [multi-line text input               ]  |
| Negative:                               |
| [multi-line text input               ]  |
|                                         |
| Strength:     [=====o=====] 0.70       |
| Context px:   [=======o===] 88         |
| [x] Focused Inpaint                    |
|                                         |
| [ Inpaint ]  [ Img2Img ]               |
|                                         |
| ||||||||............ Step 14/28         |
+-----------------------------------------+
```

- Status LED: green (connected), yellow (reconnecting), red (not found)
- Prompt / Negative: `QPlainTextEdit`, sent with each request
- Strength / Noise / Inpaint Strength: linked `QSlider` + numeric input, 0.0-1.0
- Context pixels: linked `QSlider` + numeric input, 0-192, only enabled when Focused Inpaint is checked
- Focused Inpaint checkbox: when enabled, reads Krita rectangular selection as `focusAreaRect`
- Inpaint / Img2Img buttons: trigger generation
- Progress bar: visible during generation, shows step count

### Canvas Interaction (`canvas_utils.py`)

**Read canvas image:**

```python
def export_visible_as_png(doc) -> bytes:
    qimage = doc.projection(0, 0, doc.width(), doc.height())
    buffer = QBuffer()
    buffer.open(QBuffer.WriteOnly)
    qimage.save(buffer, "PNG")
    return bytes(buffer.data())
```

Do not construct `QImage` directly from `doc.pixelData(...)` unless the document is verified as `RGBA/U8` and the channel order is handled. Krita raw pixel data is not PNG data and common integer RGBA data is ordered BGRA at the byte level. `doc.projection(...).save(..., "PNG")` is the safer V1 path.

**Read selection (Focused Inpaint focus rect):**

```python
def get_selection_rect(doc) -> dict | None:
    sel = doc.selection()
    if sel is None:
        return None
    return {"x": sel.x(), "y": sel.y(), "w": sel.width(), "h": sel.height()}
```

**Read mask — selection mode:**

- **Selection mode**: Krita selection = mask (intuitive, uses native tools)
- The dock panel no longer exposes a mask-source dropdown. Normal Inpaint and Focused Inpaint both use the active Krita selection as the repaint mask.

Mask requirements:

- Mask PNG sent to Launcher must match the exported canvas dimensions unless the message includes explicit `image_scale` metadata.
- White means repaint, black means preserve.
- Non-rectangular Krita selections are allowed for mask generation, but Focused Inpaint still needs a rectangular `selection_rect` as the focus area. If no rectangular focus area exists, reject locally with a clear message.

**Write generation result:**

```python
def insert_result_layer(doc, image_bytes: bytes, name: str):
    layer = doc.createNode(name, "paintLayer")
    # decode image_bytes → QImage → write pixel data to layer
    doc.rootNode().addChildNode(layer, None)
    doc.refreshProjection()
```

The implementation must validate the write path separately from the design:

- Preferred V1 path: decode PNG to `QImage`, convert to the writable byte order expected by Krita paint layers, call `setPixelData`, then `refreshProjection()`.
- Fallback path: write PNG to a temporary file and use a Krita-supported import/file-layer path if direct raw pixel writes are unreliable for a user's color space.
- If the active document is not `RGBA/U8`, either convert the incoming result to the document color model/depth or show a clear unsupported-document warning for V1.

Each generation creates a new layer (e.g., `NAI Inpaint 10:30:05`) for easy comparison and undo.

### Streaming Preview Display

1. Generation starts → create temporary layer `"NAI Preview"`
2. Each `progress` message → decode Base64 → update `"NAI Preview"` layer → `doc.refreshProjection()`
3. `result` received → delete `"NAI Preview"` → create final result layer

Users see the real-time denoising process (blurry → sharp) on the Krita canvas. With the current Launcher stream path, Focused Inpaint previews are full-canvas composites. Throttling (skip every N frames or update at most every 150-250 ms) should be implemented from the start because `doc.refreshProjection()` is synchronous and can stall painting on large documents.

## Section 4: End-to-End Workflows

### Workflow 1: Connection Establishment

1. Launcher starts with bridge enabled → `KritaBridgeServer.start(port: 0)` → writes port file
2. Krita plugin activated → reads port file → checks PID → `QWebSocket.open()`
3. Handshake: `ping` (version 1 + secret) → `pong` (version 1) → status LED green

Startup order does not matter. Krita retries every 5 seconds if Launcher is not yet running.

### Workflow 2: Focused Inpaint

```
Krita                                    Launcher
-----                                   --------
1. User paints mask (repaint area)
2. User draws rect selection (focus)
3. Checks Focused Inpaint, enters
   prompt, clicks [Inpaint]
4. Plugin reads canvas + mask +
   selection rect
5. Sends `inpaint` message ----------->  6. Decodes image + mask
                                          7. FocusedInpaintUtils.prepareRequest()
                                             → crop, resize to target dimensions
                                          8. NAIImageGenerationApiService
                                             .generateImageStream()
                                          9. Stream<ImageStreamChunk> starts
                                             |
10. Receives `progress` <-----------     10. For each step: send progress
    Updates "NAI Preview" layer              with full-canvas preview_image
    Shows progress bar 14/28
    (repeats for each step)
                                         11. Stream ends, got finalImage
                                         12. compositeGeneratedImage()
                                             → paste result back to full canvas
13. Receives `result` <-------------     13. Sends composited full image
    Deletes "NAI Preview" layer
    Creates "NAI Inpaint 10:30:05"
    layer with final result
```

The plugin sends the full canvas and receives full-canvas preview/result images. All crop/resize/composite logic is hidden inside the Launcher.

### Workflow 3: Normal Inpaint

Same as Workflow 2 but `focused_inpaint: false`, `selection_rect: null`. Launcher skips `FocusedInpaintUtils`, sends full image + mask directly to API.

### Workflow 4: Img2Img

1. User completes sketch on canvas
2. Enters prompt, adjusts strength, clicks [Img2Img]
3. Plugin reads canvas → sends `img2img` message
4. Launcher calls API directly (no mask/crop involved)
5. Streaming preview → progress messages → final result as new layer

### Workflow 5: Launcher Pushes Image to Krita

1. User clicks "Send to Krita" in Launcher (generation page or gallery)
2. Launcher sends `push_image` via WebSocket
3. Plugin creates new layer with the image
4. User can immediately paint mask on it and run Inpaint

This closes the loop: generate → send to Krita → edit → inpaint → edit → inpaint...

### Workflow 6: Cancel Generation

1. Krita sends `cancel` message
2. Launcher cancels API stream, sends `cancelled`
3. Krita deletes "NAI Preview" layer, resets progress bar

## Section 5: Error Handling and Edge Cases

### Coordinate Spaces and Scaling

V1 uses one coordinate system by default: original Krita canvas pixels.

| Field | Coordinate Space |
|---|---|
| `image` | Original canvas dimensions unless `image_scale` is present |
| `mask` | Same dimensions as `image` |
| `selection_rect` | Original canvas coordinates |
| `preview_image` | Full canvas coordinates when produced by current Launcher stream path |
| `result.image` | Full canvas coordinates |

If the plugin ever downscales before sending, it must include:

```json
{
  "original_width": 6000,
  "original_height": 4000,
  "sent_width": 4096,
  "sent_height": 2731,
  "scale_x": 0.6826667,
  "scale_y": 0.68275
}
```

The Launcher should reject scaled payloads in V1 unless both image and mask dimensions match and `selection_rect` can be transformed losslessly enough for the requested operation.

### Security Model

The bridge exposes NovelAI generation through the user's logged-in Launcher session, so local-only transport still needs authorization.

| Risk | Mitigation |
|---|---|
| Another local process connects to the port | Per-session `secret` in port file and required authenticated `ping` |
| Large payload memory pressure | Max JSON frame size, max decoded image bytes, and early `payload_too_large` errors |
| Silent Anlas consumption | Settings toggle, connection status, per-request toast/log in Launcher, optional first-connection confirmation |
| Request spam | One active request at a time plus short cooldown after failures |
| Token leakage | Never send NovelAI tokens to Krita; plugin only sends canvas/prompt data to Launcher |
| Port-file reuse after crash | PID + secret + start-time validation; stale files ignored |

The bridge should be disabled by default until the user enables it in Settings.

### Connection Errors

| Scenario | Krita Behavior | Launcher Behavior |
|---|---|---|
| Launcher not running | Red LED, "NAI Launcher not detected", retry every 5s | — |
| Port file exists but PID dead | Ignore stale file, treat as not running | — |
| Connection drops mid-generation | Yellow LED, auto-reconnect; clean up preview layer, show "Connection interrupted" | Detect client disconnect, cancel in-flight API request, release stream resources |
| Launcher clean exit | Receives WebSocket close → enter reconnect | Close WebSocket → delete port file |
| Protocol version mismatch | `pong` version differs → show "Please update plugin", refuse requests | `ping` version unknown → return `pong` with `supported_versions` |

### Generation Error Codes

| NAI API Error | Code | User-Facing Message |
|---|---|---|
| 401 Unauthorized | `auth_failed` | Authentication failed, please re-login in Launcher |
| 402 / Insufficient Anlas | `insufficient_anlas` | Insufficient Anlas (remaining: N) |
| 429 Rate limit | `rate_limited` | Too many requests, please wait |
| 500 Server error | `server_error` | NovelAI server error |
| Network timeout | `timeout` | Network timeout |
| Stream interrupted | `stream_interrupted` | Generation interrupted |
| Another request in progress | `busy` | Previous request still processing |

Krita displays errors as red text in Dock panel bottom (auto-dismiss after 3 seconds).

### Canvas Validation (Krita-side, before sending)

| Check | Failure Behavior |
|---|---|
| No document open | Buttons greyed out, tooltip "Please open a document first" |
| Canvas < 64x64 | Reject, show "Canvas too small" |
| Inpaint but no mask | Show "Please mark the repaint area first" |
| Focused Inpaint but no rect selection | Show "Please use Rectangle Select tool to mark focus area" |
| Not connected | Buttons greyed out |

All validation is local — no WebSocket round-trip for invalid requests.

### Concurrency

Single-request model: one bridge generation at a time, plus explicit arbitration with the main Launcher generation pipeline.

- Krita: button becomes [Cancel] during generation, restored on result/error/cancelled
- Launcher: returns `error` code `busy` if a request arrives while another is in progress
- If the Launcher UI is already generating, Krita requests return `busy` and must not cancel the UI request.
- If a Krita request is active, the Launcher UI should either show a busy state or offer an explicit "cancel Krita request and generate here" action.
- `cancel` only cancels the request with the matching request id. It must not call a global cancel path unless that id owns the active `CancelToken`.

No request queuing — not worth the complexity for an interactive editing workflow.

### Large Canvas

| Canvas Size | Handling |
|---|---|
| <= 4096x4096 | Send as-is |
| > 4096x4096 + Focused Inpaint | Prefer crop-first flow after V1 if needed; for V1, show warning and require user confirmation before downscaling |
| > 4096x4096 + Normal Inpaint/Img2Img | Reject by default with "use Focused Inpaint or reduce canvas size"; do not silently downscale |

Base64 PNG of 4096x4096 is ~20-40 MB, acceptable for localhost WebSocket.

Silent downscale/upscale is not acceptable for normal editing because it loses detail and can misalign masks. If downscaling is allowed by explicit user confirmation, image, mask, and `selection_rect` must be transformed together and the result layer name should include the scale note.

### Safety During Generation

User can continue editing in Krita while generation is in progress:

- Preview layer is separate from user's working layers
- Final result writes to a new layer, never overwrites existing content
- WebSocket callbacks and layer writes must be marshalled onto Krita's main Qt thread
- `doc.refreshProjection()` is synchronous and should be throttled during preview updates

### State Recovery

| Scenario | Recovery |
|---|---|
| Krita restart | Plugin re-reads port file → auto-reconnect; Dock input fields not persisted (V1) |
| Launcher restart | New port written to file; Krita's next reconnect attempt picks up new port |
| Launcher crashes mid-generation | Krita detects disconnect → clean up preview layer → yellow LED → auto-reconnect |
| Krita crashes mid-generation | Launcher detects client disconnect → cancel API request → release resources |

### Storage, History, and Metadata

Krita-generated results should participate in Launcher history by default unless the user disables it.

| Data | V1 Behavior |
|---|---|
| Final PNG | Write to Krita as a new layer and save through existing Launcher generation save/history path |
| Prompt/negative prompt | Store in normal metadata and send back in `result.params` |
| Seed/model/sampler/steps/scale | Include in `result.params` and saved metadata |
| Mask/source canvas | Do not store by default; optional debug logging only with explicit user setting |
| Anlas/statistics | Count the same way as Launcher-side generation |
| Vibe encodings | Not available for streaming results; document this limitation if Vibe support is added later |

`result` should be extended with metadata fields:

```json
{
  "type": "result",
  "id": "req-001",
  "image": "<base64 PNG>",
  "name": "NAI Inpaint 10:30:05",
  "saved_path": "G:/.../image.png",
  "params": {
    "model": "nai-diffusion-4-5-full-inpainting",
    "seed": 12345,
    "prompt": "..."
  }
}
```

### Error Mapping

Bridge errors should map existing Launcher/API errors into stable protocol codes instead of forwarding raw exception strings.

| Source Error | Protocol Code |
|---|---|
| Not logged in / token missing / 401 | `auth_failed` |
| 402 / insufficient Anlas message | `insufficient_anlas` |
| 429 | `rate_limited` |
| Dio timeout / connection timeout | `timeout` |
| WebSocket unauthenticated | `unauthorized_bridge_client` |
| Active UI or bridge request | `busy` |
| Unsupported streaming, fallback succeeds | No error; continue with final result and no preview |
| Unsupported streaming, fallback fails | `streaming_unsupported` |
| Mask has no white pixels | `empty_mask` |
| Non-RGBA or unsupported Krita document write path | `unsupported_document_format` |

## License and Compliance

### Krita GPL v3

The Krita plugin must be GPL v3 if distributed. The Launcher is a separate program communicating over WebSocket — not subject to GPL copyleft. This is the same pattern as krita-ai-diffusion (GPL) + ComfyUI (separate process).

### NovelAI ToS

Section 5.3.2-5.3.4 prohibit third-party remote access and circumventing technical measures. The Krita integration:

- Runs on the same local machine (loopback only)
- Uses the user's own persistent API token (already stored in Launcher)
- Does not expose the API to third parties or over the network
- Does not send NovelAI credentials, session cookies, account IDs, or endpoint override settings to Krita
- Preserves the Launcher's existing account routing, request logging, Anlas/statistics accounting, and error handling
- Same compliance posture as the Launcher itself, provided the bridge stays local-only and authenticated by a session secret

### Distribution Boundary

If the Krita plugin is published separately, keep the packaging boundary explicit:

- `Aaalice NAI Launcher`: existing application license and release channel.
- `nai_launcher_bridge` Krita plugin: GPL-compatible distribution if shipped as a Krita Python plugin.
- Protocol document: stable JSON contract that both sides implement.
- Do not bundle NovelAI API keys, endpoint presets, generated images, or user settings in the plugin package.

## Implementation Phases

### Phase 0: Feasibility Spikes

These spikes should be completed before committing to the full integration:

1. Create a minimal Krita plugin with a dock widget and verify it appears under `Settings > Dockers`.
2. Verify whether `PyQt5.QtWebSockets.QWebSocket` is importable in the target Krita Windows build.
3. Export current Krita canvas to PNG bytes via `doc.projection(...).save(buffer, "PNG")` and reinsert the bytes onto a new layer.
4. Export a rectangular selection and a painted mask from Krita, then confirm pixel dimensions match the Launcher's expected source image and mask.
5. Send one authenticated `ping` from Krita to a temporary local WebSocket server and reject the same request with a wrong secret.

Exit criteria:

- Plugin discovery works from the documented `%APPDATA%/krita/pykrita/` layout.
- Canvas export and writeback preserve width, height, and alpha on a simple RGBA document.
- WebSocket fallback choice is known: QtWebSockets, vendored pure-Python client, or HTTP polling/SSE.

### Phase 1: Launcher Bridge Server

Implement the Launcher side first because it owns auth, request construction, queueing, history, and generation services.

Files to add or modify:

- Create `lib/core/krita/krita_bridge_models.dart` for protocol DTOs, JSON parsing, validation, and error codes.
- Create `lib/core/krita/krita_bridge_protocol.dart` for envelope encode/decode and size limits.
- Create `lib/core/krita/krita_bridge_server.dart` for loopback WebSocket lifecycle and port file publication.
- Create `lib/presentation/providers/krita/krita_bridge_notifier.dart` for enable/disable state, connection state, session secret, and active request state.
- Create `lib/presentation/providers/krita/krita_bridge_service.dart` for application-level orchestration against existing generation APIs.
- Modify settings UI to add a "Krita Bridge" settings section near existing external-tool integrations.
- Modify gallery send-destination flow to add `SendDestination.krita` rather than creating a second destination dialog.

Required behaviors:

- Bridge is disabled by default.
- Enabling the bridge creates a new random session secret and writes the discovery file atomically.
- Disabling the bridge deletes the discovery file and closes active sockets.
- No request is accepted before a valid `ping` containing the session secret.
- `inpaint` and `img2img` build normal `ImageParams` and pass through `NAIImageGenerationApiService.generateImageStream`.
- Focused Inpaint uses the existing internal crop/composite pipeline and streams full-canvas previews.

### Phase 2: Krita Plugin MVP

Implement the Krita side as a small transport and UI layer.

Files to add:

- `nai_launcher_bridge.desktop`
- `nai_launcher_bridge/__init__.py`
- `nai_launcher_bridge/nai_launcher_bridge.py`
- `nai_launcher_bridge/bridge_client.py`
- `nai_launcher_bridge/bridge_dock.py`
- `nai_launcher_bridge/canvas_utils.py`
- `nai_launcher_bridge/protocol.py`

Required behaviors:

- Read the Launcher discovery file and connect only to `127.0.0.1`.
- Authenticate with the discovery-file secret before showing the bridge as ready.
- Export visible canvas PNG, active selection rectangle, and grayscale mask PNG.
- Send `inpaint` and `img2img` messages with a unique request id.
- Display progress text and throttled preview updates.
- Insert final output as a new layer, without flattening or destructively replacing the document.
- Surface Launcher error codes in plain Chinese UI messages.

### Phase 3: Polish and Hardening

Do this after the MVP path is verified manually end-to-end:

- Add retry UI for disconnected bridge state.
- Add per-request cancel if the existing generation cancel path can be scoped safely by request id.
- Add "send gallery image to Krita" support via the existing destination dialog.
- Add telemetry-free local diagnostics in the Launcher logs for bridge lifecycle and request failures.
- Add a plugin package zip and install instructions.
- Add screenshots or a short GIF for release notes once the user-facing flow is stable.

## Validation Plan

### Launcher Unit Tests

Add focused tests for protocol and request mapping:

- Valid envelope parses when `id`, `type`, `secret`, and `payload` are present.
- Envelope is rejected when `secret` is missing, wrong, or sent after authentication reset.
- Oversized image payload is rejected before Base64 decode where possible.
- `minimum_context_pixels` maps to the existing focused-inpaint padding field and clamps to `0..192`.
- `inpaint` request maps to `ImageParams(action: ImageGenerationAction.infill)` with `image`, `maskImage`, `strength`, `noise`, `inpaintStrength`, and mask iteration fields populated.
- `img2img` request maps to `ImageParams(action: ImageGenerationAction.img2img)` with `strength` and `noise` populated.
- Unknown message types return `unsupported_message`.
- Busy generation state returns `busy` without starting a second request.

### Launcher Widget or Provider Tests

Add tests around observable state rather than WebSocket internals:

- Enabling the bridge creates a session and moves state to "listening".
- Disabling the bridge clears session state and active request state.
- Authenticated connection updates UI state to "connected".
- Auth failure updates last error without exposing account/token data.
- Incoming gallery destination action sends the selected image to an authenticated Krita connection when present.

### Krita Plugin Manual Tests

Krita plugin tests will be mostly manual unless a Krita Python test harness is added:

- Fresh install: plugin appears in Python Plugin Manager after copying `.desktop` and folder.
- Dock load: dock appears after enabling plugin and restarting Krita.
- Connect: dock reads discovery file and shows Launcher connection state.
- Auth failure: edited wrong secret fails without crashing.
- Img2Img: 1024x1024 canvas returns a new layer of the same dimensions.
- Inpaint: rectangular selection plus painted mask returns a full-canvas layer aligned with the original canvas.
- No selection: V1 either uses whole canvas for img2img or shows a clear message for inpaint.
- Large canvas: >4096 normal request is rejected or requires explicit Focused Inpaint confirmation.
- Disconnect during generation: UI surfaces timeout/disconnect and does not write a partial layer as final.

### End-to-End Acceptance Checklist

- Launcher bridge can be enabled and disabled from settings.
- Krita connects without the user copying tokens or ports manually.
- Krita can send the current canvas to NovelAI img2img via Launcher.
- Krita can send selection+mask to NovelAI inpaint via Launcher.
- Preview updates do not exceed the agreed throttle interval.
- Final result appears in Krita as a new layer aligned to the original canvas.
- Launcher history records the generated final image and key params.
- NovelAI token remains only inside Launcher.
- Bridge refuses unauthenticated local clients.
- Existing generation, gallery, and Vibe flows keep working when the bridge is disabled.

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Krita Windows build lacks `PyQt5.QtWebSockets` | Plugin cannot use preferred client | Complete Phase 0 spike; use vendored pure-Python WebSocket client or HTTP polling/SSE fallback |
| Krita pixel formats differ from Launcher assumptions | Corrupt colors, alpha, or masks | Use PNG round trip for V1; gate direct pixel write behind explicit validation |
| Focused Inpaint parameter naming mismatch | Crops too much/little context | Use `minimum_context_pixels` in protocol and map to current internal field deliberately |
| Multiple local clients spam generation | Anlas waste and race conditions | Session secret, one active socket, one bridge generation at a time, explicit busy response |
| Bridge bypasses request builder | Different NovelAI behavior than app UI | Route all requests through existing `ImageParams` and generation API service |
| Large Base64 frames freeze UI | Poor responsiveness or crashes | 64 MB frame cap, size validation, preview throttling, future binary-frame optimization |
| Plugin GPL boundary is misunderstood | Release/licensing confusion | Ship plugin as separate GPL-compatible package and document process boundary |
| Existing user workflows regress | Gallery/generation behavior changes unexpectedly | Keep bridge disabled by default and reuse existing providers/dialogs where possible |

## Implementation Decisions

The Phase 0/implementation pass resolved the original open decisions as follows:

- The supported Windows Krita build does not provide `PyQt5.QtWebSockets`, so V1 ships and tests the bundled stdlib WebSocket fallback client. The fallback client refuses non-loopback hosts.
- V1 supports cancellation from Krita. The Docker sends `cancel` with the current request id only, and Launcher cancels only the matching active bridge request.
- Large canvases are rejected in V1 instead of silently downscaling. Both Launcher protocol validation and the Krita canvas helper enforce the `64..4096` canvas edge range.
- The discovery file path remains user-session scoped at `%APPDATA%/nai-launcher/krita-bridge.json` for V1. A profile namespace can be added later if the Launcher adds multiple active profiles/accounts.
- Launcher-to-Krita `push_image` does not require an active Krita document. The plugin first tries to insert same-size images as a new layer in the active document; if there is no compatible active document, it opens the PNG as a new Krita document.

## Documentation Updates Required

Before release, add:

- User manual section: how to enable the Launcher Krita Bridge.
- Krita plugin install section with the exact `.desktop` and folder placement.
- Troubleshooting section for "plugin does not appear", "cannot connect", "wrong secret", "large canvas rejected", and "inpaint mask empty".
- Release notes describing that NovelAI credentials stay in Launcher and the bridge is local-only.
- Developer protocol reference with example messages, error codes, and versioning rules.

## Out of Scope (V1)

- ControlNet / Vibe Transfer from Krita (requires additional protocol messages)
- Multiple concurrent Krita connections
- Dock panel input persistence across Krita sessions
- Binary WebSocket frames for image transfer (optimization if Base64 proves too slow)
- Non-Windows platforms (Krita plugin is Python so it's portable, but testing is Windows-only for V1)
