import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';

import '../../app/theme/line_colors.dart';
import '../../core/models/line.dart';
import '../../core/models/station.dart';

class NetworkPainter extends CustomPainter {
  NetworkPainter({
    required this.network,
    required this.catalog,
    required this.selectedLine,
    required this.scale,
    required this.scheme,
    required this.onStationTap,
  });

  final MetroNetwork network;
  final StationCatalog catalog;
  final int? selectedLine;
  final double scale;
  final ColorScheme scheme;
  final ValueChanged<int> onStationTap;

  static const canvasSize = Size(2460, 2020);

  Color _lineColor(int id) {
    final color = LineColors.colorOf(id);
    return scheme.brightness == Brightness.dark
        ? Color.lerp(color, Colors.white, .1)! : color;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lines = network.resolvedLines(catalog);
    final paint = Paint()..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    // Paint the selected line last so it stays legible at every crossing.
    final ordered = [...lines]..sort((a, b) =>
      (a.id == selectedLine ? 1 : 0).compareTo(b.id == selectedLine ? 1 : 0));
    for (final line in ordered) {
      final selected = selectedLine == null || selectedLine == line.id;
      paint.color = _lineColor(line.id).withValues(alpha: selected ? 1 : .24);
      paint.strokeWidth = (selectedLine == line.id ? 6 : selectedLine == null ? 3 : 2) / scale;
      for (var i = 1; i < line.stationIds.length; i++) {
        final a = network.points[line.stationIds[i - 1]]?.position;
        final b = network.points[line.stationIds[i]]?.position;
        if (a == null || b == null) continue;
        final delta = b - a;
        final diagonal = math.min(delta.dx.abs(), delta.dy.abs());
        final elbow = a + Offset(delta.dx.sign * diagonal, delta.dy.sign * diagonal);
        canvas.drawPath(Path()..moveTo(a.dx, a.dy)
          ..lineTo(elbow.dx, elbow.dy)..lineTo(b.dx, b.dy), paint);
      }
    }
    for (final point in network.points.values) {
      final station = catalog.stationById(point.id);
      if (station == null) continue;
      final active = selectedLine == null || station.lineIds.contains(selectedLine);
      if (!active && scale < .4) continue;
      final transfer = station.lineIds.length > 1;
      final radius = (transfer ? 5.5 : 3.5) / scale;
      canvas.drawCircle(point.position, radius,
        Paint()..color = scheme.surface.withValues(alpha: active ? 1 : .6));
      canvas.drawCircle(point.position, radius, Paint()
        ..color = (transfer ? scheme.onSurface : _lineColor(station.lineIds.first))
            .withValues(alpha: active ? 1 : .25)
        ..style = PaintingStyle.stroke..strokeWidth = 1.5 / scale);
      if (transfer) {
        canvas.drawCircle(point.position, 2 / scale,
          Paint()..color = scheme.onSurface.withValues(alpha: active ? 1 : .25));
      }
      final showName = active && (scale >= .65 ||
        (transfer && scale >= .3) ||
        (selectedLine != null && scale >= .4));
      if (!showName) continue;
      final text = TextPainter(
        text: TextSpan(text: station.name, style: TextStyle(
          color: scheme.onSurface,
          fontSize: 11 / scale,
          fontWeight: transfer ? FontWeight.w600 : FontWeight.w400,
          backgroundColor: scheme.surface.withValues(alpha: .88),
        )),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final offset = point.id.isEven
          ? Offset(8 / scale, -text.height - 5 / scale)
          : Offset(8 / scale, 5 / scale);
      text.paint(canvas, point.position + offset);
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) => [
    for (final point in network.points.values)
      if (catalog.stationById(point.id) case final Station station)
        if (selectedLine == null || station.lineIds.contains(selectedLine))
          CustomPainterSemantics(
            rect: Rect.fromCenter(center: point.position, width: 48 / scale, height: 48 / scale),
            properties: SemanticsProperties(
              label: '${station.name}，${station.lineIds.map((id) => '$id号线').join('，')}',
              button: true,
              textDirection: TextDirection.ltr,
              onTap: () => onStationTap(point.id),
            ),
          ),
  ];

  @override
  bool shouldRepaint(NetworkPainter oldDelegate) =>
      oldDelegate.network != network || oldDelegate.catalog != catalog ||
      oldDelegate.selectedLine != selectedLine || oldDelegate.scale != scale ||
      oldDelegate.scheme != scheme;

  @override
  bool shouldRebuildSemantics(NetworkPainter oldDelegate) => shouldRepaint(oldDelegate);
}
