import 'package:every_door/helpers/tile_calculator.dart';
import 'package:every_door/models/osm_area.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart' show LatLng;

/// Gaps and overlaps smaller than this (in degrees, ~0.1 m) are ignored,
/// so rounding errors don't leave thin uncovered slivers.
const _kEpsilon = 1e-6;

/// How downloaded data areas cover one map tile.
class TileCoverage {
  /// Whether the areas cover the whole tile.
  final bool full;

  /// For a fully covered tile, when the oldest area needed to cover it
  /// was downloaded. Otherwise, when the newest area touching it was.
  final DateTime downloaded;

  const TileCoverage(this.full, this.downloaded);

  @override
  String toString() => 'TileCoverage(full: $full, downloaded: $downloaded)';
}

/// Whether two boxes share some area. Unlike [LatLngBounds.isOverlapping],
/// boxes that only touch at an edge do not count.
bool boundsOverlap(LatLngBounds a, LatLngBounds b) =>
    a.south < b.north - _kEpsilon &&
    b.south < a.north - _kEpsilon &&
    a.west < b.east - _kEpsilon &&
    b.west < a.east - _kEpsilon;

/// Parts of [base] not covered by [cut]: zero to four boxes
/// that don't overlap each other.
List<LatLngBounds> subtractBounds(LatLngBounds base, LatLngBounds cut) {
  if (!boundsOverlap(base, cut)) return [base];
  final parts = <LatLngBounds>[];
  double north = base.north;
  double south = base.south;
  if (cut.north < north - _kEpsilon) {
    parts.add(LatLngBounds(
        LatLng(cut.north, base.west), LatLng(north, base.east)));
    north = cut.north;
  }
  if (cut.south > south + _kEpsilon) {
    parts.add(LatLngBounds(
        LatLng(south, base.west), LatLng(cut.south, base.east)));
    south = cut.south;
  }
  if (cut.west > base.west + _kEpsilon) {
    parts.add(LatLngBounds(LatLng(south, base.west), LatLng(north, cut.west)));
  }
  if (cut.east < base.east - _kEpsilon) {
    parts.add(LatLngBounds(LatLng(south, cut.east), LatLng(north, base.east)));
  }
  return parts;
}

/// For every tile at [zoom] that any of [areas] overlaps, how well the areas
/// cover it. Newer areas are used first, so a tile covered by both fresh and
/// old data counts as fresh when the fresh areas alone cover it.
Map<Tile, TileCoverage> tileCoverage(
    Iterable<OsmDownloadedArea> areas, int zoom) {
  final sorted = areas.toList()
    ..sort((a, b) => b.downloaded.compareTo(a.downloaded));
  final calc = TileCalculator(zoom);

  final tiles = <Tile>{};
  for (final area in sorted) {
    final nw = calc.locationToTile(area.bounds.northWest);
    final se = calc.locationToTile(area.bounds.southEast);
    for (int x = nw.x; x <= se.x; x++) {
      for (int y = nw.y; y <= se.y; y++) {
        tiles.add(Tile(x, y, zoom));
      }
    }
  }

  final result = <Tile, TileCoverage>{};
  for (final tile in tiles) {
    final bounds = calc.tileBounds(tile);
    List<LatLngBounds> uncovered = [bounds];
    DateTime? newest;
    for (final area in sorted) {
      if (!boundsOverlap(bounds, area.bounds)) continue;
      newest ??= area.downloaded;
      uncovered = [
        for (final part in uncovered) ...subtractBounds(part, area.bounds)
      ];
      if (uncovered.isEmpty) {
        result[tile] = TileCoverage(true, area.downloaded);
        break;
      }
    }
    if (uncovered.isNotEmpty && newest != null) {
      result[tile] = TileCoverage(false, newest);
    }
  }
  return result;
}
