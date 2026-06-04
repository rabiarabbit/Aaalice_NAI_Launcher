# Inpaint Editor Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make inpaint editing feel smooth in both normal mask painting and outpaint resizing by reducing unnecessary repaint work, moving expensive pixel work away from interaction frames, and preserving existing inpaint/outpaint behavior.

**Architecture:** Separate realtime interaction previews from materialized image/mask commits. Reuse low-cost paint primitives and frame-coalesced render notifications across normal inpaint and outpaint. Keep large PNG/mask/source-image generation outside drag and brush-move frames, then commit final editor state in batched updates.

**Tech Stack:** Flutter desktop, Dart, CustomPainter, ChangeNotifier/Listenable, Flutter `SchedulerBinding`, `dart:isolate`, existing image editor layer model, `flutter_test`, focused widget/unit tests, Windows release build verification.

---

## Current State Summary

The inpaint editor now supports normal mask painting and outpaint resizing, but the two flows still do too much work on interaction-sensitive frames.

- Normal mask painting calls `EditorState.updateStroke()` on every pointer move, which immediately calls `renderNotifier.notifyListeners()` and asks `LayerPainter` to repaint the canvas.
- The canvas painter draws the transparent checkerboard, all visible layers, and the current stroke preview in the same paint pass.
- Outpaint drag preview uses `_OutpaintEdgePreviewPainter`, which draws the checkerboard with nested loops over the expanded rectangle and computes the new region using `Path.combine`.
- Outpaint commit already moves image expansion to an isolate, but still exports existing masks, decodes PNGs into `ui.Image`, adds/removes/replaces layers, changes canvas size, fits the viewport, and requests UI updates in one visible chain.
- Save/close in normal inpaint mode exports the mask through Flutter `Canvas`/`toImage`/`toByteData`, so export can remain expensive even after drag/paint interaction improves.

## Scope Decisions

- Optimize interaction responsiveness first: pointer move and drag frames must avoid expensive pixel generation, large path combination, and avoidable full-stack repaint.
- Preserve existing editor semantics: source image layer, mask layer, focused inpaint mutual exclusion, 64-multiple outpaint snapping, left/top/right/bottom edge behavior, and existing save/close output shape.
- Every task must preserve the Safety Invariants below. If an optimization conflicts with those invariants, stop that task and keep the reliable behavior.
- Do not start with a virtual outpaint architecture. Treat virtual outpaint as a later optional phase if batched materialization still feels slow.
- Do not rewrite the whole layer manager. Add focused helpers where needed and keep current file ownership intact.
- Keep tests focused on changed behavior and regression risk. Use existing test paths where possible because new test files may need `.gitignore` allowlist updates.
- Use direct Flutter SDK commands for focused validation in this repository.

## Safety Invariants

- Preview rendering may be cached, coalesced, or split into overlays, but final data semantics must not change. Final `sourceImage`, `maskImage`, `canvasSize`, source offset, and applied outpaint edges must be decided by the same shared outpaint geometry/materialization logic used by tests.
- Pointer and stroke input data must never be coalesced or dropped. Only repaint notifications and preview notifications may be coalesced. `pointerUp`, `endStroke()`, and outpaint commit must flush the latest raw input state before committing.
- Live stroke preview is visual only. Final stroke data, undo/redo behavior, and mask export semantics must continue to flow through `HistoryManager`, `AddStrokeAction`, `LayerManager`, and the existing layer export path unless a later task replaces that path with pixel-equivalent tests.
- Outpaint commit must have an explicit pending state. While an outpaint commit is pending, a second outpaint drag is blocked and Save & Close must either wait for the commit to finish or be disabled; exporting a half-committed source/mask state is not allowed.
- Outpaint materialization must be transactional. Source layer image, mask layer, canvas size, outpaint source tracking fields, focused inpaint disabled state, and UI refresh must either complete as one coherent state change or roll back to the pre-commit state.

## Responsibility Map

- `lib/presentation/widgets/image_editor/canvas/layer_painter.dart`: keep main canvas painting efficient; cache checkerboard drawing; stop repainting more than necessary.
- `lib/presentation/widgets/image_editor/canvas/editor_canvas.dart`: host repaint boundaries and stroke-preview overlay wiring.
- `lib/presentation/widgets/image_editor/core/editor_state.dart`: coalesce render notifications for high-frequency pointer updates while preserving all stroke points.
- `lib/presentation/widgets/image_editor/core/stroke_manager.dart`: keep full point collection and expose current-stroke state for the separated current-stroke overlay.
- `lib/presentation/widgets/image_editor/layers/layer.dart`: preserve existing rasterization/cache behavior and keep committed-stroke rendering separate from live-stroke preview rendering.
- `lib/presentation/widgets/image_editor/layers/layer_manager.dart`: add batched layer image operations for outpaint commit state changes.
- `lib/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay.dart`: replace expensive drag preview drawing with constant-cost rectangles, cached checker patterns, frame-coalesced preview updates, and pending-preview behavior.
- `lib/presentation/widgets/image_editor/image_editor_screen.dart`: hold pending outpaint commit state, batch outpaint state updates, and coordinate normal/outpaint inpaint behavior.
- `lib/presentation/widgets/image_editor/export/image_exporter_new.dart`: keep save/close export stable and provide an optimized hard-edge mask export path when Task 10 evidence shows export remains slow.
- `lib/core/utils/inpaint_outpaint_utils.dart`: keep isolate-based materialization, own shared outpaint geometry resolution, and avoid adding UI dependencies.
- `lib/core/utils/inpaint_mask_utils.dart`: keep mask normalization and editor overlay conversion; avoid synchronous UI-frame calls.
- `test/presentation/widgets/image_editor/canvas/`: add painter/render notification tests for shared canvas optimizations.
- `test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart`: extend outpaint drag behavior tests.
- `test/core/utils/inpaint_outpaint_utils_test.dart`: preserve source/mask materialization expectations.
- `test/presentation/widgets/image_editor/layers/layer_manager_test.dart`: add batched notification tests for outpaint commit state changes.

## Task 1: Characterize Performance-Sensitive Behavior

**Files:**

- Modify: `test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart`
- Modify: `test/core/utils/inpaint_outpaint_utils_test.dart`
- Create: `test/presentation/widgets/image_editor/canvas/editor_render_scheduler_test.dart`
- Modify: `test/presentation/widgets/image_editor/canvas/layer_painter_test.dart`
- Inspect: `.gitignore`

**Steps:**

- [ ] Inspect `.gitignore` before adding new test files. If `test/presentation/widgets/image_editor/canvas/` is ignored, add precise allowlist rules for the new test files.
- [ ] Add an outpaint overlay test proving repeated pointer moves that do not change the snapped applied size do not emit redundant preview changes.
- [ ] Add an outpaint overlay test proving a corner drag emits one coherent preview with both horizontal and vertical edges, not separate partial commits.
- [ ] Add an outpaint geometry test proving preview-resolved applied edges and materialized `InpaintOutpaintUtils.expandAsync` applied edges match for left, top, right, bottom, and all four corner drag directions.
- [ ] Add a render scheduler test proving high-frequency render requests are coalesced to at most one notification per frame.
- [ ] Add a checkerboard test at the unit/widget boundary that verifies cache invalidation happens when canvas size, scale bucket, or theme-relevant colors change.
- [ ] Keep red-phase failures limited to the behavior being optimized. Existing outpaint behavior tests must continue to pass.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/utils/inpaint_outpaint_utils_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/canvas/editor_render_scheduler_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/canvas/layer_painter_test.dart
```

**Expected outcome:**

- Tests expose redundant drag-preview and render-notification behavior before implementation.
- Existing outpaint edge behavior stays protected while performance-focused changes land.

**Suggested commit:**

```text
test(image-editor): characterize inpaint performance paths
```

## Task 2: Cache Shared Canvas Checkerboard Rendering

**Files:**

- Modify: `lib/presentation/widgets/image_editor/canvas/layer_painter.dart`
- Test: `test/presentation/widgets/image_editor/canvas/layer_painter_test.dart`

**Steps:**

- [ ] Extract checkerboard drawing in `LayerPainter` into a small cacheable helper inside `layer_painter.dart` or a focused sibling file if the helper grows beyond the painter's local responsibility.
- [ ] Replace per-cell drawing on every paint with a cached `ui.Picture`, shader pattern, or image pattern that is rebuilt only when the relevant cell size, canvas extent, or colors change.
- [ ] Keep transparent-canvas behavior unchanged in inpaint mode and non-inpaint mode.
- [ ] Ensure cache disposal is handled when cached `ui.Image` or similar disposable objects are used.
- [ ] Add tests or painter assertions that repeated paints at the same size reuse the cached checkerboard path while a size change rebuilds it.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/canvas/layer_painter_test.dart
```

**Expected outcome:**

- Normal inpaint repaint and expanded outpaint canvas repaint no longer redraw transparent checker cells from scratch every frame.
- Canvas appearance remains visually equivalent.

**Suggested commit:**

```text
perf(image-editor): cache transparent checkerboard painting
```

## Task 3: Coalesce High-Frequency Render Notifications

**Files:**

- Modify: `lib/presentation/widgets/image_editor/core/editor_state.dart`
- Modify: `lib/presentation/widgets/image_editor/core/stroke_manager.dart`
- Test: `test/presentation/widgets/image_editor/canvas/editor_render_scheduler_test.dart`
- Existing behavior check: `test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart`

**Steps:**

- [ ] Add a frame-coalesced render notification path in `EditorState`, using `SchedulerBinding` or an equivalent Flutter frame callback.
- [ ] Route high-frequency pointer update paths through the coalesced notification path.
- [ ] Keep immediate render notification available for discrete state changes that must repaint immediately, such as tool switch, layer image replacement, canvas size change, undo/redo, or selection clear.
- [ ] Ensure `StrokeManager` still records every point; only the render notification is coalesced.
- [ ] Add tests proving three or more update calls before the next frame produce one render notification, and another update after the frame produces a new notification.
- [ ] Add a regression test proving `endStroke()` still flushes the final visible stroke state.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/canvas/editor_render_scheduler_test.dart
```

**Expected outcome:**

- Normal brush and eraser painting no longer request a full canvas repaint for every raw pointer event.
- No stroke points are lost.

**Suggested commit:**

```text
perf(image-editor): coalesce stroke repaint notifications
```

## Task 4: Add Repaint Boundaries Around Independent Editor Layers

**Files:**

- Modify: `lib/presentation/widgets/image_editor/image_editor_screen.dart`
- Modify: `lib/presentation/widgets/image_editor/canvas/editor_canvas.dart`
- Modify: `lib/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay.dart`
- Test: `test/presentation/widgets/image_editor/canvas/layer_painter_test.dart`
- Test: `test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart`

**Steps:**

- [ ] Wrap the main `EditorCanvas` with a `RepaintBoundary` where it is composed in `image_editor_screen.dart`.
- [ ] Wrap outpaint drag overlay painting with its own `RepaintBoundary` so preview repaint does not invalidate the main canvas subtree.
- [ ] Wrap focused inpaint and mask-fill overlays with separate boundaries if they share the same Stack layer and repaint independently.
- [ ] Keep hit testing unchanged for brush, selection, and outpaint handles.
- [ ] Run widget tests that exercise normal painting, outpaint handle dragging, and focused inpaint overlay display to catch hit-test regressions.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/canvas/layer_painter_test.dart
```

**Expected outcome:**

- Overlay-only updates do not unnecessarily repaint the full canvas widget subtree.
- Existing input behavior remains unchanged.

**Suggested commit:**

```text
perf(image-editor): isolate editor overlay repaints
```

## Task 5: Simplify Outpaint Drag Preview Painting

**Files:**

- Modify: `lib/core/utils/inpaint_outpaint_utils.dart`
- Modify: `lib/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay.dart`
- Test: `test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart`
- Test: `test/core/utils/inpaint_outpaint_utils_test.dart`

**Steps:**

- [ ] Move outpaint requested-size, snapped-size, applied-edge, and source-offset resolution into a shared helper in `InpaintOutpaintUtils`.
- [ ] Update `_OutpaintEdgePreviewPainter` and related preview state to consume the shared helper instead of calculating preview dimensions independently.
- [ ] Update `InpaintOutpaintUtils.expand` and `expandAsync` to consume the same shared helper before materializing source and mask bytes.
- [ ] Replace `_OutpaintEdgePreviewPainter`'s `Path.combine(PathOperation.difference, ...)` approach with direct drawing of up to four rectangular edge regions.
- [ ] Replace per-cell checker drawing inside the preview painter with the shared cached checker pattern from Task 2 or with a low-cost translucent fill if a checker pattern is still too expensive.
- [ ] Keep preview border drawing and applied-size label behavior.
- [ ] Ensure corner drags draw a single coherent expanded rectangle and all affected edge strips.
- [ ] Update tests to assert the preview state for top-left, top-right, bottom-left, and bottom-right drags.
- [ ] Update tests to assert preview applied width, applied height, applied edges, and materialized expansion result are identical for the same drag inputs.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/utils/inpaint_outpaint_utils_test.dart
```

**Expected outcome:**

- Outpaint drag preview paint cost becomes constant with respect to edge count and avoids area-proportional nested loops.
- Four-corner resize handles feel materially smoother.

**Suggested commit:**

```text
perf(inpaint): simplify outpaint resize preview
```

## Task 6: Coalesce Outpaint Drag Preview Updates

**Files:**

- Modify: `lib/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay.dart`
- Test: `test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart`

**Steps:**

- [ ] Store raw drag delta immediately on pointer move, but only call `setState` or emit preview changes when the resolved applied preview changes.
- [ ] If raw pointer events arrive faster than the display frame, schedule preview resolution once per frame.
- [ ] Keep outside-overlay auto-commit behavior intact for left-edge and out-of-bounds drag cases.
- [ ] Keep pointer route cleanup on pointer up/cancel.
- [ ] Add tests proving same-snapped-size moves do not emit repeated preview changes.
- [ ] Add tests proving final pointer up commits the latest raw drag delta, even if the last scheduled preview frame has not fired yet.
- [ ] Add tests proving pointer cancel and pointer-up paths flush the latest raw drag delta through the shared outpaint geometry helper before any commit starts.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart
```

**Expected outcome:**

- Outpaint drag interaction no longer rebuilds the overlay on every raw pointer event.
- Commit still uses the final drag position.

**Suggested commit:**

```text
perf(inpaint): coalesce outpaint drag previews
```

## Task 7: Freeze Pending Outpaint Preview During Background Commit

**Files:**

- Modify: `lib/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay.dart`
- Modify: `lib/presentation/widgets/image_editor/image_editor_screen.dart`
- Test: `test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart`
- Create: `test/presentation/widgets/image_editor/image_editor_screen_outpaint_commit_test.dart`

**Steps:**

- [ ] Add a pending preview state that remains visible after pointer up while `onCommitted` is running.
- [ ] Add an editor-level pending outpaint commit state in `image_editor_screen.dart`.
- [ ] Block new outpaint drags while a commit is pending, as current tests already expect for pending commit behavior.
- [ ] Block Save & Close while a commit is pending, or make Save & Close await the pending commit before exporting. Choose one behavior and cover it with a widget test.
- [ ] Display the final snapped preview immediately after release instead of clearing the overlay before real mask/source materialization completes.
- [ ] Clear the pending preview only after `_applyOutpaintEdges` successfully commits or fails and reports the error.
- [ ] Preserve current behavior for zero-edge drags: no pending preview and no commit.
- [ ] Extend tests that currently check pending commit visibility to cover corner drags and delayed completion.
- [ ] Add tests proving Save & Close cannot export a half-committed outpaint state while the pending commit is unresolved.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart
```

**Expected outcome:**

- The user sees immediate final-size feedback after releasing the drag handle.
- Any remaining source/mask materialization time is hidden behind stable preview state instead of perceived blank waiting.

**Suggested commit:**

```text
perf(inpaint): keep outpaint preview during commit
```

## Task 8: Batch Outpaint Materialization State Updates

**Files:**

- Modify: `lib/presentation/widgets/image_editor/image_editor_screen.dart`
- Modify: `lib/presentation/widgets/image_editor/layers/layer_manager.dart`
- Test: `test/presentation/widgets/image_editor/layers/layer_manager_test.dart`
- Test: `test/core/utils/inpaint_outpaint_utils_test.dart`

**Steps:**

- [ ] Audit `_applyOutpaintEdges` for intermediate notifications from adding the mask layer, replacing source image, removing old mask layers, setting canvas size, fitting viewport, and requesting UI update.
- [ ] If intermediate `LayerManager.notifyListeners()` calls are avoidable, add a focused batch method or scoped batch section that performs multiple structural changes and emits one final notification.
- [ ] Keep failure rollback behavior explicit: if source replacement fails, remove the newly added mask layer and restore outpaint source tracking fields.
- [ ] Treat source layer image, mask layer, canvas size, outpaint source bytes, outpaint source dimensions, focused inpaint disabled state, and final UI refresh as one transaction.
- [ ] Ensure `_disableFocusedInpaintForOutpaint()` runs only as part of a successful transaction or is rolled back if a later transaction step fails.
- [ ] Keep `InpaintOutpaintUtils.expandAsync` as the pixel materialization boundary.
- [ ] Preserve `includeEditorOverlay: true` so editor overlay generation remains in the isolate expansion path.
- [ ] Add tests proving batched layer operations emit one structural notification and leave layer order correct.
- [ ] Add tests proving a simulated source replacement failure restores the previous outpaint source tracking fields, removes the new mask layer, preserves the old canvas size, and does not disable focused inpaint.
- [ ] Run outpaint utility tests to verify source/mask bytes and 64 snapping are unchanged.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/layers/layer_manager_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/utils/inpaint_outpaint_utils_test.dart
```

**Expected outcome:**

- Outpaint commit performs the same logical state transition with fewer visible intermediate rebuilds.
- Source image, mask image, editor overlay, offsets, and snapped dimensions remain correct.

**Suggested commit:**

```text
perf(inpaint): batch outpaint commit updates
```

## Task 9: Separate Current Stroke Preview From Full Layer Repaint

**Files:**

- Modify: `lib/presentation/widgets/image_editor/canvas/editor_canvas.dart`
- Modify: `lib/presentation/widgets/image_editor/canvas/layer_painter.dart`
- Modify: `lib/presentation/widgets/image_editor/core/editor_state.dart`
- Create: `lib/presentation/widgets/image_editor/canvas/stroke_preview_painter.dart`
- Test: `test/presentation/widgets/image_editor/canvas/layer_painter_test.dart`
- Test: `test/presentation/widgets/image_editor/canvas/editor_render_scheduler_test.dart`

**Steps:**

- [ ] Extract current-stroke drawing from `LayerPainter` into a dedicated `StrokePreviewPainter` or equivalent overlay painter.
- [ ] Keep base layer rendering in `LayerPainter` so cached layers, source image, mask layers, and transparent canvas background stay stable during active stroke movement.
- [ ] Have stroke pointer updates repaint only the stroke preview overlay when possible.
- [ ] Ensure `endStroke()` commits the stroke to the active layer and causes the base layer painter to repaint once with the committed stroke.
- [ ] Ensure live stroke preview never writes to layer data, history, undo, redo, or exported mask state directly.
- [ ] Preserve brush, eraser, blur, and clone stamp preview appearance.
- [ ] Add tests proving active stroke updates trigger stroke preview repaint without forcing a base layer repaint notification.
- [ ] Add tests proving committed strokes appear in the base layer after pointer up.
- [ ] Add tests proving undo/redo still uses the committed `AddStrokeAction` path and does not depend on live preview state.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/canvas/layer_painter_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/canvas/editor_render_scheduler_test.dart
```

**Expected outcome:**

- Normal mask painting no longer repaints the full layer stack for every in-progress stroke frame.
- Brush and eraser feel smoother on large images and after outpaint expands the canvas.

**Suggested commit:**

```text
perf(image-editor): isolate live stroke preview rendering
```

## Task 10: Optimize Normal Inpaint Save/Close Mask Export If Still Needed

**Files:**

- Modify: `lib/presentation/widgets/image_editor/export/image_exporter_new.dart`
- Modify: `lib/core/utils/inpaint_mask_utils.dart`
- Test: `test/core/utils/inpaint_mask_utils_test.dart`
- Create: `test/presentation/widgets/image_editor/export/image_exporter_new_test.dart`

**Steps:**

- [ ] After Tasks 2 through 9, manually verify whether normal inpaint save/close still has noticeable delay.
- [ ] If delay remains, add an optimized hard-edge mask export path that can run outside UI-sensitive interaction frames.
- [ ] Keep Flutter `Canvas` export path for soft-edge masks or unsupported blend modes if a direct raster path cannot match behavior.
- [ ] Preserve `forceHardEdges: true` behavior used by inpaint and outpaint mask export.
- [ ] Add tests comparing optimized hard-edge mask output against the current exporter for representative brush strokes, eraser strokes, single-point strokes, and multi-segment strokes.
- [ ] Do not replace the exporter globally until byte-level or pixel-level behavior matches expected mask semantics.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/utils/inpaint_mask_utils_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/export/image_exporter_new_test.dart
```

**Expected outcome:**

- Save/close mask export remains correct and becomes faster only if a safe optimized path is proven.
- If export delay is already acceptable after interaction optimizations, this task can be closed with evidence and no production change.

**Suggested commit:**

```text
perf(inpaint): optimize hard-edge mask export
```

## Task 11: Manual Interaction Verification

**Files:**

- Touched files from Tasks 2 through 10.
- Release output: `build\windows\x64\runner\Release\data\app.so`
- Release output: `build\windows\x64\runner\Release\data\flutter_assets`

**Steps:**

- [ ] Launch the app locally in Windows desktop mode.
- [ ] Verify normal inpaint mask painting with brush at small, medium, and large brush sizes.
- [ ] Verify normal inpaint erasing over an existing mask.
- [ ] Verify painting on a large image after zooming and panning.
- [ ] Verify outpaint dragging left, top, right, bottom, and all four corners.
- [ ] Verify outpaint release immediately keeps a final preview visible while the real mask/source update completes.
- [ ] Verify Save & Close is disabled or waits while an outpaint commit is pending.
- [ ] Verify left-edge outpaint still works after the previous left-side fix.
- [ ] Verify final outpaint dimensions snap to multiples of 64.
- [ ] Verify preview applied dimensions match the final materialized outpaint dimensions after commit.
- [ ] Verify Focused Inpaint and outpaint are still mutually exclusive.
- [ ] Verify Save & Close returns the expected source and mask in normal inpaint and outpaint cases.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot run -d windows
```

**Expected outcome:**

- Normal mask painting is visibly smoother.
- Outpaint edge and corner dragging are visibly smoother.
- Release-to-preview has no blank or confusing waiting state.
- Existing inpaint/outpaint correctness is preserved.

**Suggested commit:**

```text
test(inpaint): verify editor performance interactions
```

## Task 12: Final Focused Validation and Release Build

**Files:**

- All files touched by Tasks 1 through 10.
- Generated release output under `build\windows\x64\runner\Release`.

**Steps:**

- [ ] Run focused outpaint tests.
- [ ] Run focused canvas/render scheduler tests.
- [ ] Run focused layer manager tests if batching changed.
- [ ] Run focused inpaint utility tests.
- [ ] Format touched Dart files.
- [ ] Run analyzer on touched Dart files first; if repo-level analyzer noise appears, separate inherited noise from introduced issues.
- [ ] Build Windows release.
- [ ] Confirm `build\windows\x64\runner\Release\data\app.so` and `build\windows\x64\runner\Release\data\flutter_assets` timestamps refresh. Do not rely only on `nai_launcher.exe`.
- [ ] Inspect `git status --short` and keep unrelated user changes out of any final commit.

**Validation:**

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/canvas/editor_render_scheduler_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/canvas/layer_painter_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/layers/layer_manager_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/utils/inpaint_outpaint_utils_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/utils/inpaint_mask_utils_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe format lib test
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot analyze
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot build windows --release
Get-Item build\windows\x64\runner\Release\data\app.so | Select-Object FullName,Length,LastWriteTime | Format-List
Get-Item build\windows\x64\runner\Release\data\flutter_assets | Select-Object FullName,LastWriteTime | Format-List
```

**Expected outcome:**

- Focused tests pass.
- Analyzer has no new issues from touched files.
- Windows release build completes.
- Release freshness is confirmed through `app.so` and `flutter_assets`.

**Suggested final commit:**

```text
perf(inpaint): smooth editor painting and outpaint resize
```

## Deferred Phase: Virtual Outpaint Architecture

This phase is intentionally not part of the first implementation pass. Start it only if Tasks 1 through 12 still leave unacceptable outpaint commit latency.

**Architecture direction:**

- Represent outpaint as virtual editor state: `canvasSize`, `sourceOffset`, `appliedEdges`, and procedural mask regions.
- Avoid immediately materializing a larger transparent source PNG during editor interaction.
- Avoid immediately adding an image-backed mask layer for outpaint preview.
- Materialize real `sourceImage` and `maskImage` only at Save & Close or request-building time.

**Likely files:**

- `lib/presentation/widgets/image_editor/image_editor_screen.dart`
- `lib/presentation/widgets/image_editor/canvas/layer_painter.dart`
- `lib/presentation/widgets/image_editor/layers/layer.dart`
- `lib/presentation/widgets/image_editor/export/image_exporter_new.dart`
- `lib/core/utils/inpaint_outpaint_utils.dart`
- Generation request builder tests that consume final inpaint source/mask bytes.

**Start criteria:**

- Manual verification still shows commit latency after pending preview and batched commit changes.
- The remaining delay is confirmed to come from PNG decode/materialization or large `ui.Image` replacement.
- Existing source/mask export tests are strong enough to protect a representation change.

## Implementation Order

1. Characterize behavior and add focused tests.
2. Cache shared checkerboard rendering.
3. Coalesce high-frequency render notifications.
4. Add repaint boundaries around independent editor layers.
5. Simplify outpaint preview painting.
6. Coalesce outpaint drag preview updates.
7. Keep pending outpaint preview visible during background commit.
8. Batch outpaint materialization state updates.
9. Separate current stroke preview from full layer repaint.
10. Optimize hard-edge mask export only if save/close remains slow.
11. Perform manual interaction verification.
12. Run focused validation and Windows release build.

## Risks and Mitigations

- Risk: frame coalescing drops visible final stroke state.
  Mitigation: keep all stroke points in `StrokeManager`, flush on `endStroke()`, and test final committed stroke visibility.

- Risk: outpaint preview geometry diverges from final materialized source/mask geometry.
  Mitigation: use one shared outpaint geometry resolver for preview and materialization, and test preview applied edges against `InpaintOutpaintUtils.expandAsync` results.

- Risk: repaint boundaries break hit testing or pointer routing.
  Mitigation: add boundaries outside pointer-sensitive widgets where possible and run brush/outpaint handle widget tests.

- Risk: cached checkerboard leaks disposable Flutter image resources.
  Mitigation: prefer `ui.Picture` or shader caching where possible; if caching `ui.Image`, dispose old cache on rebuild and widget disposal.

- Risk: outpaint pending preview hides a failed commit.
  Mitigation: clear pending preview on error and show the existing error toast from `_applyOutpaintEdges`.

- Risk: Save & Close exports a half-committed outpaint state.
  Mitigation: pending outpaint commit must block or delay Save & Close until the commit is resolved, with a widget test covering the chosen behavior.

- Risk: layer manager batching changes layer order or active layer selection.
  Mitigation: write tests for layer order, active layer id, and notification count before changing batch behavior.

- Risk: live stroke preview becomes a second source of truth for mask data.
  Mitigation: keep live preview visual-only and test that committed strokes, undo/redo, and export still flow through `HistoryManager`, `AddStrokeAction`, and `LayerManager`.

- Risk: hard-edge mask export optimization diverges from current mask semantics.
  Mitigation: keep current exporter as fallback and compare pixel output before switching.

- Risk: new tests may be ignored by repository `.gitignore`.
  Mitigation: check ignore status before adding tests and add precise allowlist entries only for intended test files.

## Completion Criteria

- Normal inpaint brush and eraser movement feel smooth on large images.
- Outpaint side and corner dragging feel smooth and do not stutter from area-proportional preview painting.
- Releasing an outpaint drag immediately shows a stable final preview while the real source/mask commit finishes.
- Outpaint preview applied edges, final materialized applied edges, final source offset, and final canvas size match for every side and corner drag path.
- Save & Close cannot export while outpaint commit state is half-finished.
- Existing left/top/right/bottom outpaint behavior works.
- Final outpaint dimensions still snap to multiples of 64.
- Focused Inpaint and outpaint remain mutually exclusive.
- Live stroke preview remains visual-only; committed mask data and undo/redo still use the existing committed stroke path.
- Save & Close returns correct source and mask bytes for normal inpaint and outpaint cases.
- Focused tests for outpaint overlay, canvas scheduling, layer painting, layer batching, and inpaint utilities pass.
- Analyzer reports no new touched-file issues.
- Windows release build succeeds and refreshed `app.so` plus `flutter_assets` are reported.
