import 'package:every_door/constants.dart';
import 'package:every_door/generated/l10n/app_localizations.dart';
import 'package:every_door/helpers/geometry/area_coverage.dart';
import 'package:every_door/helpers/geometry/tile_range.dart';
import 'package:every_door/helpers/tile_calculator.dart';
import 'package:every_door/models/osm_area.dart';
import 'package:every_door/providers/area.dart';
import 'package:every_door/providers/cur_imagery.dart';
import 'package:every_door/providers/downloaders.dart';
import 'package:every_door/providers/imagery.dart';
import 'package:every_door/providers/location.dart';
import 'package:every_door/providers/overlays.dart';
import 'package:every_door/widgets/attribution.dart';
import 'package:every_door/widgets/tile_bounds_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TileCacheDownloader extends ConsumerStatefulWidget {
  const TileCacheDownloader({super.key});

  @override
  ConsumerState<TileCacheDownloader> createState() =>
      _TileCacheDownloaderState();
}

class _TileCacheDownloaderState extends ConsumerState<TileCacheDownloader> {
  static const kBaseZoom = 15; // 85 tiles to zoom 18, ~1 km on side
  static const kMaxTilesToDownload = 20;

  /// Downloaded data areas are drawn in solid colours under this one shared
  /// opacity, so overlapping areas don't get darker.
  static const kDataOpacity = 0.4;

  final Set<Tile> _selected = {};

  /// Downloaded OSM data areas, oldest first.
  List<OsmDownloadedArea> _areas = [];

  /// How downloaded OSM data covers each square of the grid.
  Map<Tile, TileCoverage> _coverage = {};

  @override
  void initState() {
    super.initState();
    _updateDownloadedAreas();
  }

  Future<void> _updateDownloadedAreas() async {
    final areas = await ref.read(downloadedAreaProvider).getAllAreaRecords();
    if (!mounted) return;
    areas.sort((a, b) => a.downloaded.compareTo(b.downloaded));
    setState(() {
      _areas = areas;
      _coverage = tileCoverage(areas, kBaseZoom);
    });
  }

  /// Green for fresh data, then amber when it gets obsolete, and red when
  /// "Purge obsolete data" would delete it.
  static Color _dataColor(Duration age) => age <= kObsoleteData
      ? Colors.green.shade700
      : (age <= kSuperObsoleteData ? Colors.amber : Colors.red);

  bool _hasFreshData(Tile tile) {
    final coverage = _coverage[tile];
    return coverage != null &&
        coverage.full &&
        DateTime.now().difference(coverage.downloaded) <= kObsoleteData;
  }

  bool _needDownloadData() =>
      _selected.any((tile) => !_hasFreshData(tile));

  Iterable<DiscreteTileRange> _groupTiles() {
    // Very simple greedy algorithm.
    // Complexity: O(tiles * log(tiles)), quadratic worst case.

    // Better algorithms (with complexity O(grid size * tiles)):
    // 1. https://leetcode.com/problems/maximal-rectangle/solutions/5014890/faster-lesser-detailed-explaination-stack-height-step-by-step-explaination-python-java/
    // 2. https://bravenewmethod.com/2015/01/18/finding-maximal-rectangles-in-a-grid/
    // 3. https://discussions.unity.com/t/largest-rectangle-of-tiles/185528

    Set<Tile> tiles = Set.of(_selected);
    final ranges = <DiscreteTileRange>[];
    while (tiles.isNotEmpty) {
      // 1. Find the top left tile.
      Tile tile = tiles.first;
      for (final nextTile in tiles) {
        if (nextTile.y < tile.y ||
            (nextTile.y == tile.y && nextTile.x < tile.x)) tile = nextTile;
      }

      // 2. Find the x for the rightmost tile extending from this one.
      Tile rightTile = Tile(tile.x + 1, tile.y, tile.zoom);
      while (tiles.contains(rightTile)) {
        rightTile = Tile(rightTile.x + 1, tile.y, tile.zoom);
      }
      int rightX = rightTile.x - 1;

      // 3. Having the horizontal range, check tiles below to form a rectangle.
      Tile topTile = Tile(tile.x, tile.y + 1, tile.zoom);
      while (tiles.contains(topTile)) {
        if (topTile.x < rightX) {
          topTile = Tile(topTile.x + 1, topTile.y, tile.zoom);
        } else {
          topTile = Tile(tile.x, topTile.y + 1, tile.zoom);
        }
      }

      // 4. We were scanning left to right and top to bottom, and found
      // a missing tile. Now walk back a bit.
      topTile = Tile(rightX, topTile.y - 1, tile.zoom);

      // 5. We've found a rectangle between tile and topTile.
      // Register it and remove the tiles.
      final range = DiscreteTileRange(tile.zoom, tile, topTile);
      tiles.removeAll(range.tiles);
      ranges.add(range);
    }
    return ranges;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final base = ref.watch(baseImageryProvider);
    final imagery = ref.watch(imageryProvider);

    ref.listen(downloadedAreaProvider, (o, n) {
      _updateDownloadedAreas();
    });

    Widget? osmButton;
    Widget? baseButton;
    Widget? imageryButton;

    final osmDownloadStatus = ref.watch(osmDataDownloadProvider);
    if (_needDownloadData() ||
        _selected.isEmpty ||
        osmDownloadStatus.downloading) {
      // We're at the OSM download stage.
      if (osmDownloadStatus.downloading) {
        // When downloading, display a cancel button and the download progress.
        osmButton = ElevatedButton(
          child: Text(loc.settingsCachesCancel(osmDownloadStatus.percent)),
          onPressed: () {
            ref.read(osmDataDownloadProvider.notifier).cancel();
          },
        );
      } else {
        // Not started yet, and ready to download (or no tiles selected).
        osmButton = ElevatedButton(
          child: Text(loc.settingsCachesDownloadData),
          onPressed: _selected.isEmpty
              ? null
              : () {
                  ref
                      .read(osmDataDownloadProvider.notifier)
                      .start(_groupTiles().map((r) => r.toBounds()));
                },
        );
      }
    } else {
      final baseStatus = ref.watch(imageryDownloadProvider(base));
      final imageryStatus = ref.watch(imageryDownloadProvider(imagery));

      if (baseStatus.downloading) {
        baseButton = ElevatedButton(
          child: Text(loc.settingsCachesCancel(baseStatus.percent)),
          onPressed: () {
            ref.read(imageryDownloadProvider(base).notifier).cancel();
          },
        );
      } else {
        bool canDownload =
            ref.read(imageryDownloadProvider(base).notifier).canDownload();
        baseButton = ElevatedButton(
          child: Text(loc.settingsCachesDownloadMap),
          onPressed: !canDownload
              ? null
              : () {
                  ref
                      .read(imageryDownloadProvider(base).notifier)
                      .start(_selected);
                },
        );
      }

      // Now absolutely the same for satellite imagery.
      if (imageryStatus.downloading) {
        imageryButton = ElevatedButton(
          child: Text(loc.settingsCachesCancel(imageryStatus.percent)),
          onPressed: () {
            ref.read(imageryDownloadProvider(imagery).notifier).cancel();
          },
        );
      } else {
        bool canDownload =
            ref.read(imageryDownloadProvider(imagery).notifier).canDownload();
        imageryButton = ElevatedButton(
          child: Text(loc.settingsCachesDownloadSatellite),
          onPressed: !canDownload
              ? null
              : () {
                  ref
                      .read(imageryDownloadProvider(imagery).notifier)
                      .start(_selected);
                },
        );
      }

      // TODO: what about overlays?
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.settingsCacheTiles),
        actions: [
          if (_selected.isNotEmpty) ...[
            // Tapping more squares does nothing past the limit, so show it.
            Center(child: Text('${_selected.length}/$kMaxTilesToDownload')),
            IconButton(
              icon: Icon(Icons.deselect),
              tooltip: loc.settingsCachesDeselectAll,
              onPressed: () {
                setState(() {
                  _selected.clear();
                });
              },
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: ref.watch(effectiveLocationProvider),
                  initialZoom: 14.0,
                  minZoom: 10.0,
                  maxZoom: 16.0,
                  interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.all -
                        InteractiveFlag.rotate -
                        InteractiveFlag.flingAnimation,
                  ),
                ),
                children: [
                  base.buildLayer(reset: true),
                  ...ref.watch(overlayImageryProvider),
                  AttributionWidget(imagery),
                  Opacity(
                    opacity: kDataOpacity,
                    child: PolygonLayer(
                      polygons: [
                        // Oldest first, so newer areas are drawn on top.
                        for (final area in _areas)
                          Polygon(
                            points: [
                              area.bounds.northWest,
                              area.bounds.northEast,
                              area.bounds.southEast,
                              area.bounds.southWest,
                            ],
                            color: _dataColor(
                                DateTime.now().difference(area.downloaded)),
                          ),
                      ],
                    ),
                  ),
                  TileBoundsGrid(
                    tileZoom: kBaseZoom,
                    fill: Map.fromEntries(_selected.map((tile) =>
                        MapEntry(tile, Colors.blue.withValues(alpha: 0.7)))),
                    onTap: (point, doSet) {
                      if (doSet) {
                        if (_selected.length >= kMaxTilesToDownload &&
                            !_selected.contains(point)) {
                          // Maximum tiles reached, display an error panel.
                          // TODO
                        } else {
                          if (_selected.add(point)) setState(() {});
                        }
                      } else {
                        if (_selected.remove(point)) setState(() {});
                      }
                    },
                  ),
                ],
              ),
            ),
            buildLegend(context),
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 10.0,
              children: [
                if (_selected.isEmpty)
                  TextButton(child: Text(loc.settingsCachesSelectTiles, style: kFieldTextStyle,), onPressed: null),
                if (osmButton != null && _selected.isNotEmpty) osmButton,
                if (baseButton != null) baseButton,
                if (imageryButton != null) imageryButton,
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Explains the area colours from [_dataColor].
  Widget buildLegend(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    Widget item(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16.0,
              height: 16.0,
              decoration: BoxDecoration(
                color: color.withValues(alpha: kDataOpacity),
                border: Border.all(color: Colors.black26),
              ),
            ),
            SizedBox(width: 4.0),
            Text(label),
          ],
        );
    final obsoleteDays = kObsoleteData.inDays;
    final purgeDays = kSuperObsoleteData.inDays;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Wrap(
        spacing: 12.0,
        runSpacing: 4.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(loc.settingsCachesDataAge),
          item(_dataColor(Duration.zero),
              loc.settingsCachesDataDays(0, obsoleteDays)),
          item(_dataColor(kSuperObsoleteData),
              loc.settingsCachesDataDays(obsoleteDays, purgeDays)),
          item(_dataColor(kSuperObsoleteData * 2), loc.settingsCachesDataOlder),
        ],
      ),
    );
  }
}
