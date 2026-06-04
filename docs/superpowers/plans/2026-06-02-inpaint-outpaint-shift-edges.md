# Inpaint Outpaint Shift Edges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add NovelAI-style outpainting to local inpaint mode by expanding source image edges, creating an automatic edge mask, snapping final request dimensions to multiples of 64, and providing both a Shift Edges dialog and canvas edge-drag interaction.

**Architecture:** Treat outpaint as an inpaint pre-processing transform, not as a new generation action. A pure core utility expands source and mask bytes; the editor exposes dialog and drag UI; workflow plumbing atomically updates source image, source dimensions, mask image, and inpaint state; the existing `ImageGenerationAction.infill` request builder remains the API path.

**Tech Stack:** Flutter desktop, Dart, Riverpod Notifier workflow state, `package:image` for byte-level image transforms, existing image editor layer system, existing inpaint mask utilities, `flutter_test` focused unit/provider/widget tests.

---

## Current State Summary

- `NAIImageRequestBuilder` already supports inpaint/infill requests with `image` and `mask`; no new remote API path is required.
- `ImageEditorScreen` in inpaint mode currently returns `maskImage`, Focused Inpaint settings, and no changed source image.
- `ImageWorkflowLauncher.openEditor` currently passes only the effective mask into `ImageWorkflowController.applyInpaintEditorResult`.
- `ImageWorkflowController.applyInpaintEditorResult` applies source size from the existing workflow source image, sets the mask, and switches request state to `ImageGenerationAction.infill`.
- `CanvasSizeDialog` and `ResizeCanvasAction` are general canvas editing tools. They do not know that newly added pixels should become inpaint mask, and they do not shift source image content when expanding left or top.
- `NaiResolutionAdapter.isCompatible` currently defines NAI-compatible dimensions as width and height that are both multiples of 64.
- `LayerPainter` currently draws checkerboard and then covers it with a white rectangle, so transparent outpaint regions will not look like the official checkerboard unless the painter receives an inpaint-transparent background mode.

## Scope Decisions

- This feature belongs inside inpaint mode. It is not a new `ImageGenerationAction`.
- The first implementation supports positive edge expansion only. Negative edge cropping is excluded from this plan because it creates source/mask crop semantics and can be added as a separate crop feature.
- Final expanded width and height must be multiples of 64.
- If raw edge input produces a non-compatible final size, snap outward to the next multiple of 64 so no source or requested expansion area is cropped.
- Snap remainder is applied to the active dragged side for drag interaction. In the dialog, snap remainder is applied to right and bottom unless the user edits a specific side last; the preview must show the applied edge values before the user confirms.
- Focused Inpaint and outpaint are mutually exclusive. Applying outpaint disables Focused Inpaint, clears the focused selection rectangle, clears preview selection state, and returns the editor to brush mode.
- Existing hand-drawn mask is preserved by shifting it with the source image offset and OR-merging it into the expanded mask.
- Expanded source image should preserve transparent pixels in the newly added regions. The request mask is the source of truth for what the model should fill.
- The drag-edge UI is a second-stage interaction that calls the same core outpaint transform as the dialog.

## Responsibility Map

- `lib/core/utils/inpaint_outpaint_utils.dart`: pure byte-level source/mask expansion, 64 snapping, mask merge, and validation.
- `test/core/utils/inpaint_outpaint_utils_test.dart`: deterministic tests for image expansion, source offset, mask generation, mask merge, and dimension snapping.
- `lib/presentation/providers/generation/image_workflow_controller.dart`: accept expanded source image and dimensions from the editor while applying inpaint results.
- `test/presentation/providers/generation/image_workflow_controller_test.dart`: provider tests for source/mask atomic updates, 64-size enforcement, and Focused Inpaint disablement on outpaint.
- `lib/presentation/services/image_workflow_launcher.dart`: pass expanded source result from editor to workflow and show correct toast.
- `lib/presentation/widgets/image_editor/image_editor_screen.dart`: track outpaint source changes, apply outpaint into editor state, export expanded source and mask, and disable Focused Inpaint when outpaint is applied.
- `lib/presentation/widgets/image_editor/widgets/panels/shift_edges_dialog.dart`: numeric top/right/bottom/left input, snapped-size preview, and confirm/cancel result.
- `test/presentation/widgets/image_editor/widgets/panels/shift_edges_dialog_test.dart`: widget tests for snapping preview and result values.
- `lib/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay.dart`: pointer handles around the inpaint canvas that convert screen drag into edge deltas.
- `test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart`: widget tests for drag-to-edge conversion and disabled states.
- `lib/presentation/widgets/image_editor/canvas/layer_painter.dart`: optional transparent-background mode for inpaint/outpaint visualization.
- `lib/presentation/widgets/image_editor/canvas/editor_canvas.dart`: optional pass-through parameter for transparent-background painting and overlay composition if needed.
- `lib/l10n/*.arb`: add labels only if this editor surface is already localized in the relevant area. If the surrounding strings are still hard-coded Chinese, keep this change hard-coded and defer broad l10n cleanup.

## Task 1: Add Pure Outpaint Expansion Utility

**Files:**

- Create: `lib/core/utils/inpaint_outpaint_utils.dart`
- Create: `test/core/utils/inpaint_outpaint_utils_test.dart`
- Read: `lib/core/utils/inpaint_mask_utils.dart`
- Read: `lib/core/utils/nai_resolution_adapter.dart`

- [ ] **Step 1: Write failing tests for source expansion and edge mask**

Use tiny images so assertions inspect exact pixels. The tests should create a 4x4 source image, expand it by left=2, top=1, right=3, bottom=2, and expect a 64-snapped output only when snap is requested. Include one test that disables snapping for exact small-pixel validation, and one test that enables snapping for production behavior.

```dart
test('expands source with transparent edges and white outpaint mask', () {
  final source = _solidPng(width: 4, height: 4, r: 10, g: 20, b: 30);

  final result = InpaintOutpaintUtils.expand(
    sourceImage: source,
    edges: const OutpaintEdges(left: 2, top: 1, right: 3, bottom: 2),
    snapTo64: false,
  );

  expect(result.width, 9);
  expect(result.height, 7);
  expect(result.sourceOffsetX, 2);
  expect(result.sourceOffsetY, 1);

  final expanded = img.decodeImage(result.sourceImage)!;
  expect(expanded.getPixel(2, 1).r.toInt(), 10);
  expect(expanded.getPixel(0, 0).a.toInt(), 0);

  final mask = img.decodeImage(result.maskImage)!;
  expect(mask.getPixel(0, 0).r.toInt(), 255);
  expect(mask.getPixel(2, 1).r.toInt(), 0);
  expect(mask.getPixel(8, 6).r.toInt(), 255);
});
```

- [ ] **Step 2: Write failing tests for existing mask shift and OR merge**

```dart
test('shifts existing mask into expanded coordinates', () {
  final source = _solidPng(width: 4, height: 4, r: 10, g: 20, b: 30);
  final existingMask = _maskPng(width: 4, height: 4, whitePixels: const [
    Point(1, 2),
  ]);

  final result = InpaintOutpaintUtils.expand(
    sourceImage: source,
    existingMask: existingMask,
    edges: const OutpaintEdges(left: 2, top: 1, right: 0, bottom: 0),
    snapTo64: false,
  );

  final mask = img.decodeImage(result.maskImage)!;
  expect(mask.getPixel(3, 3).r.toInt(), 255);
  expect(mask.getPixel(2, 1).r.toInt(), 0);
});
```

- [ ] **Step 3: Write failing tests for 64 snapping**

```dart
test('snaps final size outward to 64 multiples', () {
  final source = _solidPng(width: 1024, height: 1216, r: 10, g: 20, b: 30);

  final result = InpaintOutpaintUtils.expand(
    sourceImage: source,
    edges: const OutpaintEdges(left: 200, top: 200, right: 200, bottom: 200),
    horizontalSnapTarget: OutpaintHorizontalSnapTarget.right,
    verticalSnapTarget: OutpaintVerticalSnapTarget.bottom,
  );

  expect(result.width % 64, 0);
  expect(result.height % 64, 0);
  expect(result.width, 1472);
  expect(result.height, 1664);
  expect(result.appliedEdges.left, 200);
  expect(result.appliedEdges.right, 248);
  expect(result.appliedEdges.top, 200);
  expect(result.appliedEdges.bottom, 248);
});
```

- [ ] **Step 4: Implement `OutpaintEdges`, snap targets, and result type**

Use immutable simple classes, not generated models.

```dart
class OutpaintEdges {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const OutpaintEdges({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  bool get isEmpty => left == 0 && top == 0 && right == 0 && bottom == 0;
}

enum OutpaintHorizontalSnapTarget { left, right }
enum OutpaintVerticalSnapTarget { top, bottom }

class OutpaintExpansionResult {
  final Uint8List sourceImage;
  final Uint8List maskImage;
  final int width;
  final int height;
  final int sourceOffsetX;
  final int sourceOffsetY;
  final OutpaintEdges requestedEdges;
  final OutpaintEdges appliedEdges;

  const OutpaintExpansionResult({
    required this.sourceImage,
    required this.maskImage,
    required this.width,
    required this.height,
    required this.sourceOffsetX,
    required this.sourceOffsetY,
    required this.requestedEdges,
    required this.appliedEdges,
  });
}
```

- [ ] **Step 5: Implement `InpaintOutpaintUtils.expand`**

Required behavior:

- Decode source with `img.decodeImage`; throw `FormatException('Unable to decode source image')` when decoding fails.
- Decode existing mask when provided; throw `ArgumentError('Existing mask dimensions must match source image dimensions')` when decoded mask dimensions differ from source.
- Reject negative edges with `ArgumentError('Outpaint edges must be non-negative')`.
- Reject final dimensions over 4096 with `ArgumentError('Expanded image dimensions exceed 4096')`.
- Snap final dimensions upward to 64 multiples by adding horizontal remainder to selected horizontal snap target and vertical remainder to selected vertical snap target.
- Create expanded source as transparent RGBA.
- Composite original source at `(appliedEdges.left, appliedEdges.top)`.
- Create binary mask as black RGBA.
- Fill every pixel outside the shifted original source rect with white.
- Normalize existing mask with `InpaintMaskUtils.normalizeMaskBytes`, decode it, shift white pixels by the source offset, and OR them into the expanded mask.

- [ ] **Step 6: Run focused utility tests**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/utils/inpaint_outpaint_utils_test.dart
```

Expected:

```text
All tests passed.
```

Suggested commit:

```text
feat(inpaint): add outpaint expansion utility
```

## Task 2: Extend Workflow To Accept Expanded Source And Mask Atomically

**Files:**

- Modify: `lib/presentation/providers/generation/image_workflow_controller.dart`
- Modify: `test/presentation/providers/generation/image_workflow_controller_test.dart`
- Read: `lib/presentation/providers/generation/generation_params_notifier.dart`

- [ ] **Step 1: Write failing provider test for expanded source application**

```dart
test('applyInpaintEditorResult can atomically replace source and mask for outpaint', () {
  final controller = container.read(imageWorkflowControllerProvider.notifier);
  controller.replaceSourceImage(_validImageBytes(width: 1024, height: 1216));

  final expandedSource = _validImageBytes(width: 1472, height: 1664);
  final expandedMask = _validMaskBytes(width: 1472, height: 1664);

  controller.applyInpaintEditorResult(
    sourceImage: expandedSource,
    sourceWidth: 1472,
    sourceHeight: 1664,
    maskImage: expandedMask,
    focusedInpaintEnabled: true,
    focusedSelectionRect: const Rect.fromLTWH(10, 10, 100, 100),
    minimumContextMegaPixels: 88,
    forceDisableFocusedInpaint: true,
  );

  final workflow = container.read(imageWorkflowControllerProvider);
  final params = container.read(generationParamsNotifierProvider);

  expect(workflow.mode, ImageWorkflowMode.inpaint);
  expect(workflow.sourceWidth, 1472);
  expect(workflow.sourceHeight, 1664);
  expect(workflow.focusedInpaintEnabled, isFalse);
  expect(workflow.focusedSelectionRect, isNull);
  expect(params.sourceImage, same(expandedSource));
  expect(params.maskImage, same(expandedMask));
  expect(params.width, 1472);
  expect(params.height, 1664);
  expect(params.action, ImageGenerationAction.infill);
});
```

- [ ] **Step 2: Extend method signature**

Use optional source fields so existing inpaint callers do not break.

```dart
void applyInpaintEditorResult({
  Uint8List? sourceImage,
  int? sourceWidth,
  int? sourceHeight,
  required Uint8List? maskImage,
  required bool focusedInpaintEnabled,
  required Rect? focusedSelectionRect,
  required double minimumContextMegaPixels,
  bool forceDisableFocusedInpaint = false,
})
```

- [ ] **Step 3: Implement atomic source update**

Inside `applyInpaintEditorResult`:

- If `sourceImage != null`, require `sourceWidth != null && sourceHeight != null`.
- Validate `sourceWidth` and `sourceHeight` through `NaiResolutionAdapter.isCompatible`.
- Call `_paramsNotifier.setSourceImage(sourceImage)` before `_applySourceSizeToParams()`.
- Update `state.sourceWidth` and `state.sourceHeight` in the same `state.copyWith(...)` transition that enters `ImageWorkflowMode.inpaint`.
- If `forceDisableFocusedInpaint` is true, set `focusedInpaintEnabled` to false and clear focused selection.
- Keep the existing behavior when `sourceImage` is null.

- [ ] **Step 4: Add dimension mismatch guard**

Add a private helper in the controller if tests need local validation:

```dart
void _validateOutpaintSourceDimensions(int width, int height) {
  if (!NaiResolutionAdapter.isCompatible(width, height)) {
    throw ArgumentError('Outpaint source dimensions must be 64-compatible');
  }
}
```

Do not decode bytes in the controller. Byte-level dimensions are already produced by the core utility and editor. The provider test should cover the state transition, not image decoding.

- [ ] **Step 5: Run focused workflow tests**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/generation/image_workflow_controller_test.dart
```

Expected:

```text
All tests passed.
```

Suggested commit:

```text
feat(inpaint): apply outpaint source in workflow
```

## Task 3: Carry Expanded Source Through Editor Result And Launcher

**Files:**

- Modify: `lib/presentation/widgets/image_editor/image_editor_screen.dart`
- Modify: `lib/presentation/services/image_workflow_launcher.dart`
- Modify: `test/presentation/providers/generation/image_workflow_controller_test.dart` if helper fixtures are reused

- [ ] **Step 1: Extend `ImageEditorResult`**

Add fields with explicit outpaint naming instead of overloading normal edit-mode `modifiedImage`.

```dart
final Uint8List? outpaintSourceImage;
final int? outpaintSourceWidth;
final int? outpaintSourceHeight;
final bool hasOutpaintChanges;
```

Constructor defaults:

```dart
this.outpaintSourceImage,
this.outpaintSourceWidth,
this.outpaintSourceHeight,
this.hasOutpaintChanges = false,
```

- [ ] **Step 2: Track outpaint changes in `ImageEditorScreen`**

Add private state fields:

```dart
Uint8List? _outpaintSourceImage;
int? _outpaintSourceWidth;
int? _outpaintSourceHeight;
bool _hasOutpaintChanges = false;
```

- [ ] **Step 3: Export outpaint source when saving inpaint result**

In `_exportAndClose`, include outpaint fields in `ImageEditorResult`. Do not set `modifiedImage` for inpaint mode.

```dart
ImageEditorResult(
  modifiedImage: modifiedImage,
  maskImage: maskImage,
  hasImageChanges: !_isInpaintMode && hasImageChanges,
  hasMaskChanges: _isInpaintMode && (hasMaskChanges || useFocusedSelectionAsMask),
  outpaintSourceImage: _isInpaintMode ? _outpaintSourceImage : null,
  outpaintSourceWidth: _isInpaintMode ? _outpaintSourceWidth : null,
  outpaintSourceHeight: _isInpaintMode ? _outpaintSourceHeight : null,
  hasOutpaintChanges: _isInpaintMode && _hasOutpaintChanges,
  focusAreaRect: focusAreaRect,
  minimumContextMegaPixels: _minimumContextMegaPixels,
  focusedInpaintEnabled: focusedInpaintEnabled,
)
```

- [ ] **Step 4: Pass outpaint source in launcher**

In `ImageWorkflowLauncher.openEditor`, pass these fields into `applyInpaintEditorResult`.

```dart
workflowNotifier.applyInpaintEditorResult(
  sourceImage: result.hasOutpaintChanges ? result.outpaintSourceImage : null,
  sourceWidth: result.hasOutpaintChanges ? result.outpaintSourceWidth : null,
  sourceHeight: result.hasOutpaintChanges ? result.outpaintSourceHeight : null,
  maskImage: effectiveMask,
  focusedInpaintEnabled: result.focusedInpaintEnabled,
  focusedSelectionRect: result.focusAreaRect,
  minimumContextMegaPixels: result.minimumContextMegaPixels,
  forceDisableFocusedInpaint: result.hasOutpaintChanges,
);
```

- [ ] **Step 5: Update launcher logging**

Include `hasOutpaintChanges`, `outpaintSourceWidth`, and `outpaintSourceHeight` in the existing `AppLogger.d` message.

- [ ] **Step 6: Run focused workflow tests**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/generation/image_workflow_controller_test.dart
```

Expected:

```text
All tests passed.
```

Suggested commit:

```text
feat(inpaint): return outpaint source from editor
```

## Task 4: Apply Outpaint Inside The Editor

**Files:**

- Modify: `lib/presentation/widgets/image_editor/image_editor_screen.dart`
- Modify: `lib/presentation/widgets/image_editor/layers/layer_manager.dart`
- Read: `lib/presentation/widgets/image_editor/layers/layer.dart`
- Read: `lib/presentation/widgets/image_editor/export/image_exporter_new.dart`
- Read: `lib/core/utils/inpaint_mask_utils.dart`
- Read: `lib/core/utils/inpaint_outpaint_utils.dart`

- [ ] **Step 1: Add a layer manager helper for replacing a layer image**

Add a focused method that notifies listeners after replacing a layer base image. This avoids direct `Layer.setBaseImage(...)` calls from `ImageEditorScreen` that would bypass layer manager notifications.

```dart
Future<bool> replaceLayerImage(String layerId, Uint8List imageBytes) async {
  final layer = getLayerById(layerId);
  if (layer == null) return false;
  await layer.setBaseImage(imageBytes);
  invalidateSnapshot();
  notifyListeners();
  return true;
}
```

- [ ] **Step 2: Add private method `_applyOutpaintEdges`**

Expected signature:

```dart
Future<void> _applyOutpaintEdges(
  OutpaintEdges edges, {
  OutpaintHorizontalSnapTarget horizontalSnapTarget =
      OutpaintHorizontalSnapTarget.right,
  OutpaintVerticalSnapTarget verticalSnapTarget =
      OutpaintVerticalSnapTarget.bottom,
}) async
```

Required behavior:

- Return early unless `_isInpaintMode`.
- Require `_sourceLayerId != null`.
- Read current source bytes from source layer `baseImageBytes`; show `AppToast.error(context, 'Unable to read current source image.')` if unavailable, or use an existing localized equivalent if this editor area is localized during implementation.
- Export current mask with `ImageExporterNew.exportMaskFromLayers(...)` excluding `_sourceLayerId`.
- Treat exported mask as `existingMask` only when `InpaintMaskUtils.hasMaskedPixels(exportedMask)` returns true.
- Call `InpaintOutpaintUtils.expand(...)`.
- Replace the source layer image with `result.sourceImage`.
- Set `_state.canvasSize` to `Size(result.width.toDouble(), result.height.toDouble())`.
- Remove non-source layers.
- Convert `result.maskImage` to editor overlay with `InpaintMaskUtils.maskToEditorOverlay(...)`.
- Add one mask layer above source using the existing inpaint mask-layer display name from the editor.
- Set `_outpaintSourceImage`, `_outpaintSourceWidth`, `_outpaintSourceHeight`, and `_hasOutpaintChanges`.
- Disable Focused Inpaint by setting `_focusedInpaintEnabled = false`, clearing `_focusedSelectionState`, clearing selection/preview, and setting tool to `brush`.
- Call `_state.canvasController.fitToViewport(_state.canvasSize)` so the expanded image remains visible.
- Call `_state.requestUiUpdate()` and `setState`.

- [ ] **Step 3: Add small helper to remove non-source layers**

Use one private method to avoid duplicating the current reset/fill-mask removal loops.

```dart
void _removeAllMaskLayers() {
  final removableLayerIds = _state.layerManager.layers
      .where((layer) => layer.id != _sourceLayerId)
      .map((layer) => layer.id)
      .toList(growable: false);

  for (final layerId in removableLayerIds) {
    _state.layerManager.removeLayer(layerId);
  }
}
```

Replace existing repeated loops in `_fillClosedMaskRegionsAt` and `_resetInpaintMask` only if the change stays mechanical and covered by focused tests/manual checks.

- [ ] **Step 4: Keep undo scope explicit**

Do not wire outpaint into `ResizeCanvasAction`. If undo support is added in this task, create a dedicated outpaint history action that stores old source bytes, old canvas size, and old exported mask. If that action is not added in this pass, leave outpaint as a save/cancel editor transform and do not claim Ctrl+Z support for it in UI copy.

- [ ] **Step 5: Run focused static checks**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe analyze lib/core/utils/inpaint_outpaint_utils.dart lib/presentation/widgets/image_editor/image_editor_screen.dart lib/presentation/widgets/image_editor/layers/layer_manager.dart lib/presentation/services/image_workflow_launcher.dart lib/presentation/providers/generation/image_workflow_controller.dart
```

Expected:

```text
No issues found!
```

Suggested commit:

```text
feat(inpaint): apply outpaint in editor
```

## Task 5: Add Shift Edges Dialog

**Files:**

- Create: `lib/presentation/widgets/image_editor/widgets/panels/shift_edges_dialog.dart`
- Create: `test/presentation/widgets/image_editor/widgets/panels/shift_edges_dialog_test.dart`
- Modify: `lib/presentation/widgets/image_editor/image_editor_screen.dart`

- [ ] **Step 1: Define dialog result**

```dart
class ShiftEdgesResult {
  final OutpaintEdges requestedEdges;
  final OutpaintEdges appliedEdges;
  final int width;
  final int height;
  final OutpaintHorizontalSnapTarget horizontalSnapTarget;
  final OutpaintVerticalSnapTarget verticalSnapTarget;

  const ShiftEdgesResult({
    required this.requestedEdges,
    required this.appliedEdges,
    required this.width,
    required this.height,
    required this.horizontalSnapTarget,
    required this.verticalSnapTarget,
  });
}
```

- [ ] **Step 2: Add widget test for numeric fields and snapped preview**

```dart
testWidgets('shows requested and snapped outpaint size', (tester) async {
  await tester.pumpWidget(_wrapDialog(
    sourceWidth: 1024,
    sourceHeight: 1216,
  ));

  await tester.enterText(find.byKey(const Key('shift_edges_left')), '200');
  await tester.enterText(find.byKey(const Key('shift_edges_top')), '200');
  await tester.enterText(find.byKey(const Key('shift_edges_right')), '200');
  await tester.enterText(find.byKey(const Key('shift_edges_bottom')), '200');
  await tester.pump();

  expect(find.text('Requested: 1424 x 1616'), findsOneWidget);
  expect(find.text('Applied: 1472 x 1664'), findsOneWidget);
});
```

- [ ] **Step 3: Implement dialog UI**

Dialog requirements:

- Four integer fields: top, right, bottom, left.
- Reject negative values inline.
- Show current size, requested size, and snapped applied size.
- Show applied edge values after snapping.
- Confirm button disabled when all edges are zero.
- Confirm button disabled when final dimensions exceed 4096.
- `Enter` confirms when valid.
- `Escape` cancels.

- [ ] **Step 4: Wire dialog to editor**

Add `_showShiftEdgesDialog()` in `ImageEditorScreen`:

```dart
Future<void> _showShiftEdgesDialog() async {
  if (!_isInpaintMode) return;
  final result = await ShiftEdgesDialog.show(
    context,
    sourceWidth: _state.canvasSize.width.round(),
    sourceHeight: _state.canvasSize.height.round(),
  );
  if (result == null || !mounted) return;
  await _applyOutpaintEdges(
    result.requestedEdges,
    horizontalSnapTarget: result.horizontalSnapTarget,
    verticalSnapTarget: result.verticalSnapTarget,
  );
}
```

- [ ] **Step 5: Add toolbar/menu entry**

For desktop, place a compact action near current canvas/mask actions with tooltip `Shift Edges`. For mobile, add it to the bottom toolbar or overflow sheet. Use `Icons.open_in_full` unless an existing icon better matches the editor style.

- [ ] **Step 6: Run dialog tests**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/panels/shift_edges_dialog_test.dart
```

Expected:

```text
All tests passed.
```

Suggested commit:

```text
feat(inpaint): add shift edges dialog
```

## Task 6: Enforce Focused Inpaint And Outpaint Mutual Exclusion

**Files:**

- Modify: `lib/presentation/widgets/image_editor/image_editor_screen.dart`
- Modify: `lib/presentation/providers/generation/image_workflow_controller.dart`
- Modify: `test/presentation/providers/generation/image_workflow_controller_test.dart`

- [ ] **Step 1: Add controller test for forced Focused Inpaint disablement**

```dart
test('outpaint result clears focused inpaint state', () {
  final controller = container.read(imageWorkflowControllerProvider.notifier);
  controller.replaceSourceImage(_validImageBytes(width: 1024, height: 1216));

  controller.applyInpaintEditorResult(
    sourceImage: _validImageBytes(width: 1088, height: 1280),
    sourceWidth: 1088,
    sourceHeight: 1280,
    maskImage: _validMaskBytes(width: 1088, height: 1280),
    focusedInpaintEnabled: true,
    focusedSelectionRect: const Rect.fromLTWH(64, 64, 256, 256),
    minimumContextMegaPixels: 120,
    forceDisableFocusedInpaint: true,
  );

  final workflow = container.read(imageWorkflowControllerProvider);
  expect(workflow.focusedInpaintEnabled, isFalse);
  expect(workflow.focusedSelectionRect, isNull);
});
```

- [ ] **Step 2: Disable Focused Inpaint in editor after outpaint**

In `_applyOutpaintEdges`, use one helper:

```dart
void _disableFocusedInpaintForOutpaint() {
  _focusedInpaintEnabled = false;
  _focusedSelectionState.clear();
  _state.clearSelection(saveHistory: false);
  _state.clearPreview();
  _state.setToolById('brush');
}
```

- [ ] **Step 3: Guard Focused Inpaint toggle when outpaint changes exist**

If `_hasOutpaintChanges` is true and the user taps Focused Inpaint, show:

```dart
AppToast.warning(context, 'Outpaint cannot be used together with Focused Inpaint.');
```

Keep the result-level controller guard as the final source of truth.

- [ ] **Step 4: Run workflow tests**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/generation/image_workflow_controller_test.dart
```

Expected:

```text
All tests passed.
```

Suggested commit:

```text
fix(inpaint): keep focused inpaint separate from outpaint
```

## Task 7: Add Drag-Edge Outpaint Overlay

**Files:**

- Create: `lib/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay.dart`
- Create: `test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart`
- Modify: `lib/presentation/widgets/image_editor/image_editor_screen.dart`
- Read: `lib/presentation/widgets/image_editor/core/canvas_controller.dart`

- [ ] **Step 1: Define overlay callback contract**

```dart
typedef OutpaintEdgeDragPreviewChanged = void Function(OutpaintEdges edges);
typedef OutpaintEdgeDragCommitted = Future<void> Function(
  OutpaintEdges edges, {
  required OutpaintHorizontalSnapTarget horizontalSnapTarget,
  required OutpaintVerticalSnapTarget verticalSnapTarget,
});
```

- [ ] **Step 2: Implement overlay only for unrotated, non-mirrored view**

For this pass, handles should be visible only when:

```dart
controller.rotation == 0 && !controller.isMirroredHorizontally
```

When view rotation or mirroring is active, hide drag handles and keep the Shift Edges dialog available.

- [ ] **Step 3: Convert drag deltas into source-space pixels**

Use current scale:

```dart
final sourceDelta = (screenDelta / controller.scale).round();
```

Rules:

- Drag left handle left increases `left`.
- Drag right handle right increases `right`.
- Drag top handle up increases `top`.
- Drag bottom handle down increases `bottom`.
- Corner handles update both adjacent edges.
- Dragging inward clamps that edge at zero.

- [ ] **Step 4: Show live preview**

Preview requirements:

- Draw applied expanded boundary around the current canvas.
- Fill new regions with semi-transparent checkerboard or tinted overlay.
- Show a compact label near the active side with `Applied: WIDTH x HEIGHT`.
- Use snap preview from `InpaintOutpaintUtils.resolveAppliedEdges(...)` or the same calculation used by `expand(...)` without decoding image bytes.

If the helper from Task 1 does not expose snap-only calculation yet, add:

```dart
static OutpaintAppliedSize resolveAppliedSize({
  required int sourceWidth,
  required int sourceHeight,
  required OutpaintEdges edges,
  OutpaintHorizontalSnapTarget horizontalSnapTarget =
      OutpaintHorizontalSnapTarget.right,
  OutpaintVerticalSnapTarget verticalSnapTarget =
      OutpaintVerticalSnapTarget.bottom,
})
```

- [ ] **Step 5: Commit on pointer up**

On drag end, call `_applyOutpaintEdges(...)` with the active snap targets. If all edges are zero, do nothing.

- [ ] **Step 6: Add widget tests for drag conversion**

Test one side and one corner:

```dart
testWidgets('dragging right edge commits right expansion', (tester) async {
  OutpaintEdges? committed;
  await tester.pumpWidget(_wrapOverlay(
    canvasSize: const Size(1024, 1216),
    scale: 0.5,
    onCommit: (edges, {required horizontalSnapTarget, required verticalSnapTarget}) async {
      committed = edges;
    },
  ));

  await tester.drag(find.byKey(const Key('outpaint_handle_right')), const Offset(32, 0));
  await tester.pumpAndSettle();

  expect(committed?.right, 64);
});
```

- [ ] **Step 7: Wire overlay into `_buildCanvasArea`**

Add overlay above `EditorCanvas` and below Focused Inpaint visual overlay. Hide it when Focused Inpaint is enabled.

- [ ] **Step 8: Run overlay tests**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart
```

Expected:

```text
All tests passed.
```

Suggested commit:

```text
feat(inpaint): support dragging edges to outpaint
```

## Task 8: Improve Transparent Outpaint Visualization

**Files:**

- Modify: `lib/presentation/widgets/image_editor/canvas/layer_painter.dart`
- Modify: `lib/presentation/widgets/image_editor/canvas/editor_canvas.dart`
- Modify: `lib/presentation/widgets/image_editor/image_editor_screen.dart`

- [ ] **Step 1: Add a background mode flag**

Add a boolean parameter to `EditorCanvas` and pass it into `LayerPainter`.

```dart
final bool showTransparentCanvasBackground;
```

Default:

```dart
this.showTransparentCanvasBackground = false,
```

- [ ] **Step 2: Keep white background for normal edit mode**

In `LayerPainter`, draw checkerboard first. Draw the white rectangle only when transparent background is not requested.

```dart
_drawCheckerboard(canvas, canvasSize);

if (!showTransparentCanvasBackground) {
  canvas.drawRect(
    Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
    Paint()..color = Colors.white,
  );
}
```

- [ ] **Step 3: Enable transparent background for inpaint mode**

In `ImageEditorScreen._buildCanvasArea`, pass:

```dart
showTransparentCanvasBackground: _isInpaintMode,
```

- [ ] **Step 4: Manual visual check**

Run the app, open inpaint editor, expand edges, and confirm:

- Original source image remains visible.
- Expanded edge region shows checkerboard before generation.
- Mask overlay remains visible above source.
- Normal edit mode still has white canvas background.

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot run -d windows
```

Expected:

```text
The Windows app launches and the inpaint editor shows checkerboard outpaint regions.
```

Suggested commit:

```text
fix(inpaint): show transparent outpaint regions
```

## Task 9: Validate Infill Request Compatibility

**Files:**

- Modify: `test/core/network/request_builders/nai_image_request_builder_test.dart`
- Read: `lib/core/network/request_builders/nai_image_request_builder.dart`

- [ ] **Step 1: Add request-builder regression test**

Use expanded 64-compatible source and mask and verify the builder still sends `image`, `mask`, `strength`, `noise`, disables `add_original_image`, and does not attach Vibe Transfer.

```dart
test('outpaint infill request sends expanded source and mask', () async {
  final source = _validPngBytes(width: 1472, height: 1664);
  final mask = _validMaskBytes(width: 1472, height: 1664);

  final params = ImageParams(
    action: ImageGenerationAction.infill,
    model: 'nai-diffusion-4-5-full',
    width: 1472,
    height: 1664,
    sourceImage: source,
    maskImage: mask,
    strength: 0.42,
    noise: 0.13,
    addOriginalImage: true,
  );

  final builder = NAIImageRequestBuilder(
    params: params,
    encodeVibe: _fakeEncodeVibe,
  );

  final result = await builder.build(sampler: 'k_euler');

  expect(base64Decode(result.requestParameters['image'] as String), source);
  expect(result.requestParameters['mask'], isNotNull);
  expect(result.requestParameters['width'], 1472);
  expect(result.requestParameters['height'], 1664);
  expect(result.requestParameters['add_original_image'], isFalse);
});
```

- [ ] **Step 2: Run request-builder tests**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/network/request_builders/nai_image_request_builder_test.dart
```

Expected:

```text
All tests passed.
```

Suggested commit:

```text
test(inpaint): cover outpaint infill request
```

## Task 10: Final Validation

**Files:**

- All files touched by Tasks 1 through 9.

- [ ] **Step 1: Format touched Dart files**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe format lib/core/utils/inpaint_outpaint_utils.dart test/core/utils/inpaint_outpaint_utils_test.dart lib/presentation/providers/generation/image_workflow_controller.dart test/presentation/providers/generation/image_workflow_controller_test.dart lib/presentation/services/image_workflow_launcher.dart lib/presentation/widgets/image_editor/image_editor_screen.dart lib/presentation/widgets/image_editor/layers/layer_manager.dart lib/presentation/widgets/image_editor/widgets/panels/shift_edges_dialog.dart test/presentation/widgets/image_editor/widgets/panels/shift_edges_dialog_test.dart lib/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay.dart test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart lib/presentation/widgets/image_editor/canvas/layer_painter.dart lib/presentation/widgets/image_editor/canvas/editor_canvas.dart test/core/network/request_builders/nai_image_request_builder_test.dart
```

Expected:

```text
Formatted ... files
```

- [ ] **Step 2: Run focused tests**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/utils/inpaint_outpaint_utils_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/providers/generation/image_workflow_controller_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/panels/shift_edges_dialog_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay_test.dart
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot test test/core/network/request_builders/nai_image_request_builder_test.dart
```

Expected:

```text
All tests passed.
```

- [ ] **Step 3: Run analyzer**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot analyze
```

Expected:

```text
No issues found!
```

- [ ] **Step 4: Run Windows release build**

Run:

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\dev\flutter\bin\cache\flutter_tools.snapshot build windows --release
```

Expected:

```text
Built build\windows\x64\runner\Release\nai_launcher.exe
```

- [ ] **Step 5: Verify release freshness**

Check:

```powershell
Get-Item build\windows\x64\runner\Release\data\app.so
Get-Item build\windows\x64\runner\Release\data\flutter_assets
```

Expected:

```text
app.so and flutter_assets timestamps are refreshed after the release build.
```

- [ ] **Step 6: Inspect final diff**

Run:

```powershell
git status --short
git diff --stat
```

Expected:

```text
Only outpaint-related source, test, and optional localization files are changed.
```

Suggested final commit:

```text
feat(inpaint): add shift edges outpaint
```

## Implementation Order

1. Add the pure outpaint utility and tests.
2. Extend workflow to accept expanded source and mask atomically.
3. Carry expanded source through editor result and launcher.
4. Apply outpaint inside the editor with automatic mask refresh.
5. Add Shift Edges dialog and toolbar entry.
6. Enforce Focused Inpaint mutual exclusion.
7. Add drag-edge overlay using the same outpaint core.
8. Improve transparent region visualization.
9. Add request-builder regression coverage.
10. Run focused tests, analyzer, release build, and final diff audit.

## Risks And Mitigations

- Risk: arbitrary official-style edge values such as 200 produce sizes that are not multiples of 64.
  Mitigation: snap final size outward to the next 64 multiple and show both requested and applied sizes before confirmation.

- Risk: source and mask dimensions drift apart.
  Mitigation: generate both source and mask from `InpaintOutpaintUtils.expand(...)`, pass them together through editor result, and update workflow state atomically.

- Risk: Focused Inpaint context crop hides the expanded region.
  Mitigation: disable Focused Inpaint at editor and workflow levels whenever outpaint is applied.

- Risk: drag-edge UI becomes hard to test if mixed with image byte transforms.
  Mitigation: keep drag overlay as a thin `OutpaintEdges` producer and keep byte transforms in `InpaintOutpaintUtils`.

- Risk: current canvas resize code appears similar but has incompatible semantics.
  Mitigation: do not reuse `ResizeCanvasAction` for outpaint; outpaint must shift source, generate edge mask, update source bytes, and update workflow dimensions.

- Risk: transparent expanded pixels look white in the editor.
  Mitigation: add a transparent-background painting mode for inpaint canvas while preserving white background in normal edit mode.

- Risk: adding new widget tests under a path ignored by `.gitignore`.
  Mitigation: check `git status --short` after adding tests and add precise allowlist entries only if a test file is unexpectedly ignored.

## Completion Criteria

- Dialog-based Shift Edges can expand any positive combination of top, right, bottom, and left edges.
- Dragging canvas edges or corners can expand the same top, right, bottom, and left edge values.
- Final outpaint source and mask dimensions are multiples of 64.
- Left and top expansion shifts original source content by the applied left/top offset.
- Newly expanded pixels are transparent in source image bytes and white in the request mask.
- Existing inpaint mask content is preserved and shifted into the expanded coordinate space.
- Applying outpaint disables Focused Inpaint and clears focused selection state.
- Saving the inpaint editor sends expanded source, expanded mask, expanded width, and expanded height into the existing infill request chain.
- Existing non-outpaint inpaint behavior remains unchanged.
- Focused tests, analyzer, and Windows release build have been run or any environment-specific failures have been reported separately from production-code failures.

## Self Review

- Spec coverage: The plan covers 64 snapping, Focused Inpaint mutual exclusion, dialog Shift Edges, drag-edge expansion, source/mask update, transparent visualization, and existing infill request reuse.
- Placeholder scan: The plan contains concrete files, method signatures, tests, validation commands, expected results, and completion criteria.
- Type consistency: `OutpaintEdges`, snap target enums, and `OutpaintExpansionResult` are defined in Task 1 and reused consistently by dialog, overlay, editor, and workflow tasks.
