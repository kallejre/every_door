import 'dart:math' show Point;

import 'package:every_door/helpers/geometry/area_coverage.dart';
import 'package:every_door/helpers/tile_calculator.dart';
import 'package:every_door/models/osm_area.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;

void main() {
  const zoom = 15;
  final now = DateTime(2026, 11, 14, 12);
  final tile = Tile(18630, 9480, zoom); // Tallinn
  final b = tile.tileBounds();
  final midLon = (b.west + b.east) / 2;
  final midLat = (b.south + b.north) / 2;

  LatLngBounds box(double s, double w, double n, double e) =>
      LatLngBounds(LatLng(s, w), LatLng(n, e));
  OsmDownloadedArea area(LatLngBounds bounds, int daysAgo) =>
      OsmDownloadedArea(bounds, now.subtract(Duration(days: daysAgo)));
  double size(LatLngBounds x) => (x.north - x.south) * (x.east - x.west);

  test('Area equal to a tile covers only that tile', () {
    final result = tileCoverage([area(b, 1)], zoom);
    expect(result.keys, [tile]);
    expect(result[tile]!.full, isTrue);
    expect(result[tile]!.downloaded, now.subtract(Duration(days: 1)));
  });

  test('Area of two tiles covers both, and not their neighbours', () {
    final right = (tile + Point(1, 0)).tileBounds();
    final result = tileCoverage(
        [area(box(b.south, b.west, b.north, right.east), 0)], zoom);
    expect(result.keys.toSet(), {tile, tile + Point(1, 0)});
    expect(result.values.every((c) => c.full), isTrue);
  });

  test('Halves of different age: full, dated by the older half', () {
    final result = tileCoverage([
      area(box(b.south, b.west, b.north, midLon), 1),
      area(box(b.south, midLon, b.north, b.east), 10),
    ], zoom);
    expect(result[tile]!.full, isTrue);
    expect(result[tile]!.downloaded, now.subtract(Duration(days: 10)));
  });

  test('Fresh data covering the tile wins over older data', () {
    final result = tileCoverage([area(b, 20), area(b, 1)], zoom);
    expect(result[tile]!.downloaded, now.subtract(Duration(days: 1)));
  });

  test('Half covered: partial, dated by the newest area', () {
    final result = tileCoverage([
      area(box(b.south, b.west, b.north, midLon), 5),
      area(box(b.south - 1, b.west - 1, b.south + 1e-4, b.east + 1), 2),
    ], zoom);
    expect(result[tile]!.full, isFalse);
    expect(result[tile]!.downloaded, now.subtract(Duration(days: 2)));
  });

  test('Left strip and a corner leave the top right uncovered', () {
    // The old check (BoundPoints.difference) treated this as covered.
    final result = tileCoverage([
      area(box(b.south, b.west, b.north, midLon), 1),
      area(box(b.south - 1, midLon - 1e-3, midLat, b.east + 1), 1),
    ], zoom);
    expect(result[tile]!.full, isFalse);
  });

  test('Areas touching only at an edge do not count', () {
    final above = box(b.north, b.west, b.north + 0.01, b.east);
    final result = tileCoverage([area(above, 1)], zoom);
    expect(result.containsKey(tile), isFalse);
  });

  test('subtractBounds leaves exactly the uncovered area', () {
    final cut = box(midLat - 1e-3, midLon - 1e-3, midLat + 1e-3, midLon + 1e-3);
    final parts = subtractBounds(b, cut);
    expect(parts.length, 4);
    final total = parts.fold(0.0, (sum, p) => sum + size(p));
    expect(total, closeTo(size(b) - size(cut), 1e-12));
    expect(subtractBounds(b, b), isEmpty);
  });
}
