import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/inpaint_outpaint_utils.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/canvas_controller.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/widgets/outpaint_edge_drag_overlay.dart';

Widget _wrapOverlay({
  required CanvasController controller,
  required OutpaintEdgeDragCommitted onCommitted,
  OutpaintEdgeDragPreviewChanged? onPreviewChanged,
  bool enabled = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 400,
        child: OutpaintEdgeDragOverlay(
          canvasSize: const Size(128, 96),
          controller: controller,
          onPreviewChanged: onPreviewChanged,
          onCommitted: onCommitted,
          enabled: enabled,
        ),
      ),
    ),
  );
}

void main() {
  late CanvasController controller;

  setUp(() {
    controller = CanvasController()
      ..setScale(0.5)
      ..setOffset(const Offset(100, 100));
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets(
    'right handle converts screen drag through scale and commits right edge',
    (tester) async {
      OutpaintEdges? committedEdges;
      OutpaintHorizontalSnapTarget? horizontalTarget;
      OutpaintVerticalSnapTarget? verticalTarget;

      await tester.pumpWidget(
        _wrapOverlay(
          controller: controller,
          onCommitted: (
            edges, {
            required horizontalSnapTarget,
            required verticalSnapTarget,
          }) async {
            committedEdges = edges;
            horizontalTarget = horizontalSnapTarget;
            verticalTarget = verticalSnapTarget;
          },
        ),
      );

      await tester.drag(
        find.byKey(const Key('outpaint_handle_right')),
        const Offset(32, 0),
      );
      await tester.pumpAndSettle();

      expect(committedEdges, isNotNull);
      expect(committedEdges!.right, 64);
      expect(committedEdges!.left, 0);
      expect(committedEdges!.top, 0);
      expect(committedEdges!.bottom, 0);
      expect(horizontalTarget, OutpaintHorizontalSnapTarget.right);
      expect(verticalTarget, OutpaintVerticalSnapTarget.bottom);
    },
  );

  testWidgets(
    'left handle stays hittable near viewport edge and commits left edge',
    (tester) async {
      controller.setOffset(const Offset(-20, 100));
      OutpaintEdges? committedEdges;
      OutpaintHorizontalSnapTarget? horizontalTarget;

      await tester.pumpWidget(
        _wrapOverlay(
          controller: controller,
          onCommitted: (
            edges, {
            required horizontalSnapTarget,
            required verticalSnapTarget,
          }) async {
            committedEdges = edges;
            horizontalTarget = horizontalSnapTarget;
          },
        ),
      );

      final leftHandle = find.byKey(const Key('outpaint_handle_left'));
      final handleCenter = tester.getCenter(leftHandle);

      expect(handleCenter.dx, greaterThanOrEqualTo(11));

      await tester.drag(leftHandle, const Offset(-32, 0));
      await tester.pumpAndSettle();

      expect(committedEdges, isNotNull);
      expect(committedEdges!.left, 64);
      expect(committedEdges!.right, 0);
      expect(horizontalTarget, OutpaintHorizontalSnapTarget.left);
    },
  );

  testWidgets(
    'top-left corner converts both axes through scale and commits left and top',
    (tester) async {
      OutpaintEdges? committedEdges;
      OutpaintHorizontalSnapTarget? horizontalTarget;
      OutpaintVerticalSnapTarget? verticalTarget;

      await tester.pumpWidget(
        _wrapOverlay(
          controller: controller,
          onCommitted: (
            edges, {
            required horizontalSnapTarget,
            required verticalSnapTarget,
          }) async {
            committedEdges = edges;
            horizontalTarget = horizontalSnapTarget;
            verticalTarget = verticalSnapTarget;
          },
        ),
      );

      await tester.drag(
        find.byKey(const Key('outpaint_handle_top_left')),
        const Offset(-32, -16),
      );
      await tester.pumpAndSettle();

      expect(committedEdges, isNotNull);
      expect(committedEdges!.left, 64);
      expect(committedEdges!.top, 32);
      expect(committedEdges!.right, 0);
      expect(committedEdges!.bottom, 0);
      expect(horizontalTarget, OutpaintHorizontalSnapTarget.left);
      expect(verticalTarget, OutpaintVerticalSnapTarget.top);
    },
  );

  testWidgets('emits live preview and applied snapped size while dragging', (
    tester,
  ) async {
    final previews = <OutpaintEdges>[];

    await tester.pumpWidget(
      _wrapOverlay(
        controller: controller,
        onPreviewChanged: previews.add,
        onCommitted: (
          edges, {
          required horizontalSnapTarget,
          required verticalSnapTarget,
        }) async {},
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('outpaint_handle_right'))),
    );
    await gesture.moveBy(const Offset(32, 0));
    await tester.pump();

    expect(previews, isNotEmpty);
    expect(previews.last.right, 64);
    expect(find.text('Applied: 192 x 128'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('does not commit when drag returns to zero edges',
      (tester) async {
    var commitCount = 0;

    await tester.pumpWidget(
      _wrapOverlay(
        controller: controller,
        onCommitted: (
          edges, {
          required horizontalSnapTarget,
          required verticalSnapTarget,
        }) async {
          commitCount++;
        },
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('outpaint_handle_right'))),
    );
    await gesture.moveBy(const Offset(32, 0));
    await gesture.moveBy(const Offset(-32, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(commitCount, 0);
  });

  testWidgets('blocks a second drag while commit is pending', (tester) async {
    final firstCommit = Completer<void>();
    var commitCount = 0;

    await tester.pumpWidget(
      _wrapOverlay(
        controller: controller,
        onCommitted: (
          edges, {
          required horizontalSnapTarget,
          required verticalSnapTarget,
        }) {
          commitCount++;
          return firstCommit.future;
        },
      ),
    );

    await tester.drag(
      find.byKey(const Key('outpaint_handle_right')),
      const Offset(32, 0),
    );
    await tester.pump();

    expect(commitCount, 1);
    expect(find.byKey(const Key('outpaint_handle_right')), findsNothing);

    await tester.dragFrom(const Offset(164, 124), const Offset(32, 0));
    await tester.pump();

    expect(commitCount, 1);

    firstCommit.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('outpaint_handle_right')), findsOneWidget);
  });

  testWidgets('keeps preview visible while commit is pending', (tester) async {
    final firstCommit = Completer<void>();

    await tester.pumpWidget(
      _wrapOverlay(
        controller: controller,
        onCommitted: (
          edges, {
          required horizontalSnapTarget,
          required verticalSnapTarget,
        }) {
          return firstCommit.future;
        },
      ),
    );

    await tester.drag(
      find.byKey(const Key('outpaint_handle_right')),
      const Offset(32, 0),
    );
    await tester.pump();

    expect(find.text('Applied: 192 x 128'), findsOneWidget);
    expect(find.byKey(const Key('outpaint_handle_right')), findsNothing);

    firstCommit.complete();
    await tester.pumpAndSettle();

    expect(find.text('Applied: 192 x 128'), findsNothing);
    expect(find.byKey(const Key('outpaint_handle_right')), findsOneWidget);
  });

  testWidgets('commits active left drag after idle when pointer up is lost', (
    tester,
  ) async {
    OutpaintEdges? committedEdges;
    OutpaintHorizontalSnapTarget? horizontalTarget;

    await tester.pumpWidget(
      _wrapOverlay(
        controller: controller,
        onCommitted: (
          edges, {
          required horizontalSnapTarget,
          required verticalSnapTarget,
        }) async {
          committedEdges = edges;
          horizontalTarget = horizontalSnapTarget;
        },
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('outpaint_handle_left'))),
    );
    await gesture.moveBy(const Offset(-32, 0));
    await tester.pump();

    expect(find.text('Applied: 192 x 128'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();

    expect(committedEdges, isNotNull);
    expect(committedEdges!.left, 64);
    expect(horizontalTarget, OutpaintHorizontalSnapTarget.left);
    expect(find.text('Applied: 192 x 128'), findsNothing);

    await gesture.up();
  });

  testWidgets('hides handles when disabled, rotated, or mirrored', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapOverlay(
        controller: controller,
        enabled: false,
        onCommitted: (
          edges, {
          required horizontalSnapTarget,
          required verticalSnapTarget,
        }) async {},
      ),
    );

    expect(find.byKey(const Key('outpaint_handle_left')), findsNothing);
    expect(find.byKey(const Key('outpaint_handle_right')), findsNothing);

    await tester.pumpWidget(
      _wrapOverlay(
        controller: controller..rotateRight(),
        onCommitted: (
          edges, {
          required horizontalSnapTarget,
          required verticalSnapTarget,
        }) async {},
      ),
    );

    expect(find.byKey(const Key('outpaint_handle_top')), findsNothing);
    expect(find.byKey(const Key('outpaint_handle_bottom')), findsNothing);

    controller.resetRotation();
    controller.toggleMirrorHorizontal();
    await tester.pumpWidget(
      _wrapOverlay(
        controller: controller,
        onCommitted: (
          edges, {
          required horizontalSnapTarget,
          required verticalSnapTarget,
        }) async {},
      ),
    );

    expect(find.byKey(const Key('outpaint_handle_top_left')), findsNothing);
    expect(find.byKey(const Key('outpaint_handle_bottom_right')), findsNothing);
  });
}
