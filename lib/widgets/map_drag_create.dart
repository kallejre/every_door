import 'package:every_door/helpers/multi_icon.dart';
import 'package:every_door/providers/geolocation.dart';
import 'package:every_door/widgets/map.dart';
import 'package:every_door/widgets/round_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:logging/logging.dart';

class MapDragCreateButton extends ConsumerStatefulWidget {
  final MultiIcon icon;
  final Function()? onDragStart;
  final Function(LatLng)? onDragEnd;
  final Function()? onTap;
  final Alignment alignment;
  final CustomMapController map;

  static const kArrowSize = 60.0;
  static final _logger = Logger('MapDragCreateButton');

  const MapDragCreateButton({
    super.key,
    required this.map,
    required this.icon,
    this.onDragStart,
    this.onDragEnd,
    this.onTap,
    this.alignment = Alignment.bottomRight,
  });

  @override
  ConsumerState<MapDragCreateButton> createState() =>
      _MapDragCreateButtonState();
}

class _MapDragCreateButtonState extends ConsumerState<MapDragCreateButton> {
  static const kArrowSize = MapDragCreateButton.kArrowSize;
  static final _logger = MapDragCreateButton._logger;

  /// Whether location tracking was on when the drag started. Tracking moves
  /// (and auto-zooms) the map, so the spot under the arrow would shift while
  /// dragging; it is paused for the drag and resumed after the drop.
  bool _pausedTracking = false;

  @override
  Widget build(BuildContext context) {
    final safePadding =
        MediaQuery.of(context).padding.copyWith(top: 0, bottom: 0);
    const commonPadding =
        EdgeInsets.symmetric(horizontal: 10.0, vertical: 20.0);
    return Align(
      alignment: widget.alignment,
      child: Padding(
        padding: safePadding + commonPadding,
        child: Draggable(
          onDragStarted: () {
            _pausedTracking = ref.read(trackingProvider);
            if (_pausedTracking) {
              ref.read(trackingProvider.notifier).state = false;
            }
            if (widget.onDragStart != null) widget.onDragStart!();
          },
          onDragEnd: (details) {
            _handleDrop(details);
            // Resume tracking after the drop location has been computed.
            if (_pausedTracking) {
              _pausedTracking = false;
              ref.read(trackingProvider.notifier).state = true;
            }
          },
          feedbackOffset: Offset(kArrowSize / 2, 70.0),
          dragAnchorStrategy: (draggable, context, position) =>
              Offset(kArrowSize / 2, 70.0),
          feedback: CustomPaint(
            painter: _ArrowUpPainter(Theme.of(context).primaryColor),
            size: Size(kArrowSize, 100.0),
          ),
          childWhenDragging: Container(),
          child: RoundButton(icon: widget.icon, onPressed: widget.onTap),
        ),
      ),
    );
  }

  void _handleDrop(DraggableDetails details) {
    final map = widget.map;
    final onDragEnd = widget.onDragEnd;
    final camera = map.mapController?.camera;
    if (camera == null || onDragEnd == null) return;

    const offset = Offset(-kArrowSize / 2, -2.0);
    final pos = Offset(details.offset.dx, details.offset.dy);
    // To adjust offset, we need to know the location of everything.
    final globalMapOriginTr = map.mapKey?.currentContext!
        .findRenderObject()!
        .getTransformTo(null)
        .getTranslation();
    final globalMapOrigin = globalMapOriginTr == null
        ? Offset(0.0, 0.0)
        : Offset(globalMapOriginTr.x, globalMapOriginTr.y);
    _logger.fine('global: $globalMapOrigin, drop offset: ${pos - offset}.');
    final location = camera.offsetToCrs(pos - offset + globalMapOrigin);
    if (camera.visibleBounds.contains(location)) onDragEnd(location);
  }
}

class _ArrowUpPainter extends CustomPainter {
  final Color color;

  _ArrowUpPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const kShiftDown = 8.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.longestSide / 10.0
      ..strokeJoin = StrokeJoin.miter
      ..style = PaintingStyle.stroke;
    final wingLevel = size.width / 2 + kShiftDown;
    final path = Path()
      ..moveTo(size.width / 2, size.height / 30 + kShiftDown)
      ..lineTo(size.width / 2, size.height)
      ..moveTo(0, wingLevel)
      ..lineTo(size.width / 2, kShiftDown)
      ..lineTo(size.width, wingLevel);
    canvas.drawPath(path, paint);

    const kRedCircleRadius = 2.0;
    final redPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(size.width / 2, kRedCircleRadius), kRedCircleRadius, redPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
