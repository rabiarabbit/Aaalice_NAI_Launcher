import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/inpaint_outpaint_utils.dart';
import '../core/canvas_controller.dart';

typedef OutpaintEdgeDragPreviewChanged = void Function(OutpaintEdges edges);
typedef OutpaintEdgeDragCommitted = Future<void> Function(
  OutpaintEdges edges, {
  required OutpaintHorizontalSnapTarget horizontalSnapTarget,
  required OutpaintVerticalSnapTarget verticalSnapTarget,
});

class OutpaintEdgeDragOverlay extends StatefulWidget {
  final Size canvasSize;
  final CanvasController controller;
  final OutpaintEdgeDragPreviewChanged? onPreviewChanged;
  final OutpaintEdgeDragCommitted onCommitted;
  final bool enabled;

  const OutpaintEdgeDragOverlay({
    super.key,
    required this.canvasSize,
    required this.controller,
    this.onPreviewChanged,
    required this.onCommitted,
    this.enabled = true,
  });

  @override
  State<OutpaintEdgeDragOverlay> createState() =>
      _OutpaintEdgeDragOverlayState();
}

class _OutpaintEdgeDragOverlayState extends State<OutpaintEdgeDragOverlay> {
  static const double _handleSize = 22;
  static const double _cornerHandleSize = 24;
  static const int _snapSize = 64;

  _OutpaintDragHandle? _activeHandle;
  int? _activePointer;
  Offset? _lastGlobalPosition;
  Offset _dragDelta = Offset.zero;
  OutpaintEdges _previewEdges = const OutpaintEdges();
  bool _isCommitting = false;
  Timer? _outsideCommitTimer;

  bool get _canRenderOverlay =>
      widget.enabled &&
      widget.controller.rotation == 0 &&
      !widget.controller.isMirroredHorizontally;

  bool get _canShowHandles => _canRenderOverlay && !_isCommitting;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            if (!_canRenderOverlay) {
              return const SizedBox.shrink();
            }

            final canvasRect = _screenCanvasRect;
            final preview = _activeHandle == null
                ? null
                : _OutpaintAppliedPreview.resolve(
                    canvasSize: widget.canvasSize,
                    edges: _previewEdges,
                    horizontalSnapTarget: _horizontalSnapTarget(_activeHandle!),
                    verticalSnapTarget: _verticalSnapTarget(_activeHandle!),
                  );

            return MouseRegion(
              onExit: (_) {
                if (_activeHandle != null && !_previewEdges.isEmpty) {
                  _scheduleOutsideCommit();
                }
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (preview != null && !_previewEdges.isEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _OutpaintEdgePreviewPainter(
                            canvasRect: canvasRect,
                            preview: preview,
                          ),
                        ),
                      ),
                    ),
                  if (preview != null && !_previewEdges.isEmpty)
                    _PreviewLabel(
                      canvasRect: canvasRect,
                      handle: _activeHandle!,
                      preview: preview,
                      viewportSize: viewportSize,
                    ),
                  if (_canShowHandles)
                    ..._buildHandles(canvasRect, viewportSize),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Rect get _screenCanvasRect {
    final topLeft = widget.controller.canvasToScreen(
      Offset.zero,
      canvasSize: widget.canvasSize,
    );
    final bottomRight = widget.controller.canvasToScreen(
      Offset(widget.canvasSize.width, widget.canvasSize.height),
      canvasSize: widget.canvasSize,
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  List<Widget> _buildHandles(Rect canvasRect, Size viewportSize) {
    return [
      _buildHandle(
        key: const Key('outpaint_handle_left'),
        handle: _OutpaintDragHandle.left,
        center: Offset(canvasRect.left, canvasRect.center.dy),
        viewportSize: viewportSize,
      ),
      _buildHandle(
        key: const Key('outpaint_handle_right'),
        handle: _OutpaintDragHandle.right,
        center: Offset(canvasRect.right, canvasRect.center.dy),
        viewportSize: viewportSize,
      ),
      _buildHandle(
        key: const Key('outpaint_handle_top'),
        handle: _OutpaintDragHandle.top,
        center: Offset(canvasRect.center.dx, canvasRect.top),
        viewportSize: viewportSize,
      ),
      _buildHandle(
        key: const Key('outpaint_handle_bottom'),
        handle: _OutpaintDragHandle.bottom,
        center: Offset(canvasRect.center.dx, canvasRect.bottom),
        viewportSize: viewportSize,
      ),
      _buildHandle(
        key: const Key('outpaint_handle_top_left'),
        handle: _OutpaintDragHandle.topLeft,
        center: canvasRect.topLeft,
        isCorner: true,
        viewportSize: viewportSize,
      ),
      _buildHandle(
        key: const Key('outpaint_handle_top_right'),
        handle: _OutpaintDragHandle.topRight,
        center: canvasRect.topRight,
        isCorner: true,
        viewportSize: viewportSize,
      ),
      _buildHandle(
        key: const Key('outpaint_handle_bottom_left'),
        handle: _OutpaintDragHandle.bottomLeft,
        center: canvasRect.bottomLeft,
        isCorner: true,
        viewportSize: viewportSize,
      ),
      _buildHandle(
        key: const Key('outpaint_handle_bottom_right'),
        handle: _OutpaintDragHandle.bottomRight,
        center: canvasRect.bottomRight,
        isCorner: true,
        viewportSize: viewportSize,
      ),
    ];
  }

  Widget _buildHandle({
    required Key key,
    required _OutpaintDragHandle handle,
    required Offset center,
    required Size viewportSize,
    bool isCorner = false,
  }) {
    final size = isCorner ? _cornerHandleSize : _handleSize;
    final visibleCenter = _clampHandleCenter(center, size, viewportSize);
    return Positioned(
      left: visibleCenter.dx - size / 2,
      top: visibleCenter.dy - size / 2,
      width: size,
      height: size,
      child: Listener(
        key: key,
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _handlePointerDown(event, handle),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(isCorner ? 6 : 999),
            border: Border.all(
              color: Theme.of(context).colorScheme.onPrimary,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePointerDown(
    PointerDownEvent event,
    _OutpaintDragHandle handle,
  ) {
    if (_isCommitting || _activePointer != null) {
      return;
    }

    _activePointer = event.pointer;
    _lastGlobalPosition = event.position;
    GestureBinding.instance.pointerRouter.addRoute(
      event.pointer,
      _handleRoutedPointerEvent,
    );
    _startDrag(handle);
  }

  void _handleRoutedPointerEvent(PointerEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }

    if (event is PointerMoveEvent) {
      final previousPosition = _lastGlobalPosition ?? event.position;
      _lastGlobalPosition = event.position;
      _updateDrag(
        event.position - previousPosition,
        globalPosition: event.position,
      );
      return;
    }

    if (event is PointerUpEvent) {
      _stopPointerRoute();
      unawaited(_commitDrag());
      return;
    }

    if (event is PointerCancelEvent) {
      _stopPointerRoute();
      if (_previewEdges.isEmpty) {
        _resetDrag();
      } else {
        unawaited(_commitDrag());
      }
    }
  }

  void _stopPointerRoute() {
    final activePointer = _activePointer;
    if (activePointer != null) {
      GestureBinding.instance.pointerRouter.removeRoute(
        activePointer,
        _handleRoutedPointerEvent,
      );
    }
    _activePointer = null;
    _lastGlobalPosition = null;
  }

  Offset _clampHandleCenter(Offset center, double size, Size viewportSize) {
    final halfSize = size / 2;
    final maxX = math.max(halfSize, viewportSize.width - halfSize);
    final maxY = math.max(halfSize, viewportSize.height - halfSize);
    return Offset(
      center.dx.clamp(halfSize, maxX).toDouble(),
      center.dy.clamp(halfSize, maxY).toDouble(),
    );
  }

  void _startDrag(_OutpaintDragHandle handle) {
    if (_isCommitting) {
      return;
    }

    setState(() {
      _activeHandle = handle;
      _dragDelta = Offset.zero;
      _previewEdges = const OutpaintEdges();
    });
  }

  void _updateDrag(Offset delta, {required Offset globalPosition}) {
    if (_isCommitting) {
      return;
    }

    final activeHandle = _activeHandle;
    if (activeHandle == null) {
      return;
    }

    _dragDelta += delta;
    final scale = widget.controller.scale;
    final sourceDx = (_dragDelta.dx / scale).round();
    final sourceDy = (_dragDelta.dy / scale).round();
    final edges = _edgesForDrag(activeHandle, sourceDx, sourceDy);

    setState(() {
      _previewEdges = edges;
    });
    widget.onPreviewChanged?.call(edges);

    if (!edges.isEmpty &&
        (activeHandle.affectsLeft || _isOutsideOverlay(globalPosition))) {
      _scheduleOutsideCommit();
    } else {
      _outsideCommitTimer?.cancel();
    }
  }

  bool _isOutsideOverlay(Offset globalPosition) {
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox || !renderBox.hasSize) {
      return false;
    }

    final localPosition = renderBox.globalToLocal(globalPosition);
    return localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx > renderBox.size.width ||
        localPosition.dy > renderBox.size.height;
  }

  OutpaintEdges _edgesForDrag(
    _OutpaintDragHandle handle,
    int sourceDx,
    int sourceDy,
  ) {
    return OutpaintEdges(
      left: handle.affectsLeft ? math.max(0, -sourceDx) : 0,
      top: handle.affectsTop ? math.max(0, -sourceDy) : 0,
      right: handle.affectsRight ? math.max(0, sourceDx) : 0,
      bottom: handle.affectsBottom ? math.max(0, sourceDy) : 0,
    );
  }

  Future<void> _commitDrag() async {
    if (_isCommitting) {
      return;
    }
    _stopPointerRoute();
    _outsideCommitTimer?.cancel();

    final activeHandle = _activeHandle;
    final edges = _previewEdges;

    if (activeHandle == null || edges.isEmpty) {
      _resetDrag();
      return;
    }

    setState(() {
      _isCommitting = true;
    });

    try {
      await widget.onCommitted(
        edges,
        horizontalSnapTarget: _horizontalSnapTarget(activeHandle),
        verticalSnapTarget: _verticalSnapTarget(activeHandle),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCommitting = false;
          _activeHandle = null;
          _dragDelta = Offset.zero;
          _previewEdges = const OutpaintEdges();
        });
      }
    }
  }

  void _resetDrag() {
    if (_isCommitting) {
      return;
    }
    _stopPointerRoute();
    _outsideCommitTimer?.cancel();

    setState(() {
      _activeHandle = null;
      _dragDelta = Offset.zero;
      _previewEdges = const OutpaintEdges();
    });
  }

  void _scheduleOutsideCommit() {
    if (_isCommitting) {
      return;
    }

    _outsideCommitTimer?.cancel();
    _outsideCommitTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) {
        return;
      }
      unawaited(_commitDrag());
    });
  }

  @override
  void dispose() {
    _stopPointerRoute();
    _outsideCommitTimer?.cancel();
    super.dispose();
  }

  OutpaintHorizontalSnapTarget _horizontalSnapTarget(
    _OutpaintDragHandle handle,
  ) {
    return handle.affectsLeft
        ? OutpaintHorizontalSnapTarget.left
        : OutpaintHorizontalSnapTarget.right;
  }

  OutpaintVerticalSnapTarget _verticalSnapTarget(_OutpaintDragHandle handle) {
    return handle.affectsTop
        ? OutpaintVerticalSnapTarget.top
        : OutpaintVerticalSnapTarget.bottom;
  }
}

enum _OutpaintDragHandle {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get affectsLeft => this == left || this == topLeft || this == bottomLeft;
  bool get affectsRight =>
      this == right || this == topRight || this == bottomRight;
  bool get affectsTop => this == top || this == topLeft || this == topRight;
  bool get affectsBottom =>
      this == bottom || this == bottomLeft || this == bottomRight;
}

class _OutpaintAppliedPreview {
  final OutpaintEdges appliedEdges;
  final int appliedWidth;
  final int appliedHeight;

  const _OutpaintAppliedPreview({
    required this.appliedEdges,
    required this.appliedWidth,
    required this.appliedHeight,
  });

  factory _OutpaintAppliedPreview.resolve({
    required Size canvasSize,
    required OutpaintEdges edges,
    required OutpaintHorizontalSnapTarget horizontalSnapTarget,
    required OutpaintVerticalSnapTarget verticalSnapTarget,
  }) {
    final requestedWidth = canvasSize.width.round() + edges.left + edges.right;
    final requestedHeight =
        canvasSize.height.round() + edges.top + edges.bottom;

    final widthRemainder = _snapRemainder(requestedWidth);
    final heightRemainder = _snapRemainder(requestedHeight);

    var appliedLeft = edges.left;
    var appliedTop = edges.top;
    var appliedRight = edges.right;
    var appliedBottom = edges.bottom;

    if (horizontalSnapTarget == OutpaintHorizontalSnapTarget.left) {
      appliedLeft += widthRemainder;
    } else {
      appliedRight += widthRemainder;
    }

    if (verticalSnapTarget == OutpaintVerticalSnapTarget.top) {
      appliedTop += heightRemainder;
    } else {
      appliedBottom += heightRemainder;
    }

    return _OutpaintAppliedPreview(
      appliedEdges: OutpaintEdges(
        left: appliedLeft,
        top: appliedTop,
        right: appliedRight,
        bottom: appliedBottom,
      ),
      appliedWidth: requestedWidth + widthRemainder,
      appliedHeight: requestedHeight + heightRemainder,
    );
  }

  static int _snapRemainder(int value) {
    return (_OutpaintEdgeDragOverlayState._snapSize -
            value % _OutpaintEdgeDragOverlayState._snapSize) %
        _OutpaintEdgeDragOverlayState._snapSize;
  }
}

class _PreviewLabel extends StatelessWidget {
  static const double _width = 128;
  static const double _height = 28;

  final Rect canvasRect;
  final _OutpaintDragHandle handle;
  final _OutpaintAppliedPreview preview;
  final Size viewportSize;

  const _PreviewLabel({
    required this.canvasRect,
    required this.handle,
    required this.preview,
    required this.viewportSize,
  });

  @override
  Widget build(BuildContext context) {
    final topLeft = _labelTopLeft;
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: _width,
      height: _height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'Applied: ${preview.appliedWidth} x ${preview.appliedHeight}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Offset get _labelTopLeft {
    final center = _labelCenter;
    final maxX = math.max(0.0, viewportSize.width - _width);
    final maxY = math.max(0.0, viewportSize.height - _height);
    return Offset(
      (center.dx - _width / 2).clamp(0.0, maxX).toDouble(),
      (center.dy - _height / 2).clamp(0.0, maxY).toDouble(),
    );
  }

  Offset get _labelCenter {
    if (handle.affectsLeft) {
      return Offset(canvasRect.left - 72, canvasRect.center.dy);
    }
    if (handle.affectsRight) {
      return Offset(canvasRect.right + 72, canvasRect.center.dy);
    }
    if (handle.affectsTop) {
      return Offset(canvasRect.center.dx, canvasRect.top - 28);
    }
    return Offset(canvasRect.center.dx, canvasRect.bottom + 28);
  }
}

class _OutpaintEdgePreviewPainter extends CustomPainter {
  final Rect canvasRect;
  final _OutpaintAppliedPreview preview;

  const _OutpaintEdgePreviewPainter({
    required this.canvasRect,
    required this.preview,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = canvasRect.width / previewSourceWidth;
    final scaleY = canvasRect.height / previewSourceHeight;
    final expandedRect = Rect.fromLTRB(
      canvasRect.left - preview.appliedEdges.left * scaleX,
      canvasRect.top - preview.appliedEdges.top * scaleY,
      canvasRect.right + preview.appliedEdges.right * scaleX,
      canvasRect.bottom + preview.appliedEdges.bottom * scaleY,
    );

    final expandedPath = Path()..addRect(expandedRect);
    final sourcePath = Path()..addRect(canvasRect);
    final newRegion = Path.combine(
      PathOperation.difference,
      expandedPath,
      sourcePath,
    );

    canvas.drawPath(
      newRegion,
      Paint()..color = const Color(0x5560AAFF),
    );
    _drawChecker(canvas, expandedRect, newRegion);

    canvas.drawRect(
      expandedRect,
      Paint()
        ..color = const Color(0xFF60AAFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  int get previewSourceWidth =>
      preview.appliedWidth -
      preview.appliedEdges.left -
      preview.appliedEdges.right;

  int get previewSourceHeight =>
      preview.appliedHeight -
      preview.appliedEdges.top -
      preview.appliedEdges.bottom;

  void _drawChecker(Canvas canvas, Rect expandedRect, Path clipPath) {
    canvas.save();
    canvas.clipPath(clipPath);
    const cell = 8.0;
    final light = Paint()..color = Colors.white.withValues(alpha: 0.16);
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.10);

    for (var y = expandedRect.top; y < expandedRect.bottom; y += cell) {
      for (var x = expandedRect.left; x < expandedRect.right; x += cell) {
        final checkerX = ((x - expandedRect.left) / cell).floor();
        final checkerY = ((y - expandedRect.top) / cell).floor();
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          (checkerX + checkerY).isEven ? light : dark,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OutpaintEdgePreviewPainter oldDelegate) {
    return canvasRect != oldDelegate.canvasRect ||
        preview.appliedWidth != oldDelegate.preview.appliedWidth ||
        preview.appliedHeight != oldDelegate.preview.appliedHeight ||
        preview.appliedEdges.left != oldDelegate.preview.appliedEdges.left ||
        preview.appliedEdges.top != oldDelegate.preview.appliedEdges.top ||
        preview.appliedEdges.right != oldDelegate.preview.appliedEdges.right ||
        preview.appliedEdges.bottom != oldDelegate.preview.appliedEdges.bottom;
  }
}
