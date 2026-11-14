import 'dart:math' show max;

import 'package:every_door/constants.dart';
import 'package:every_door/widgets/masonry_columns.dart';
import 'package:every_door/models/amenity.dart';
import 'package:every_door/providers/area.dart';
import 'package:every_door/providers/changes.dart';
import 'package:every_door/providers/need_update.dart';
import 'package:every_door/providers/poi_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:every_door/generated/l10n/app_localizations.dart' show AppLocalizations;
import 'poi_tile.dart';

class PoiPane extends ConsumerStatefulWidget {
  final List<OsmChange> amenities;
  final Function(OsmChange, int)? isCountedOld;

  const PoiPane(this.amenities, {this.isCountedOld});

  @override
  ConsumerState<PoiPane> createState() => _PoiPaneState();
}

class _PoiPaneState extends ConsumerState<PoiPane> {
  @override
  Widget build(BuildContext context) {
    return widget.amenities.isEmpty
        ? nothingAroundPane(context)
        : Container(
            color: Colors.grey.shade100,
            child: kPoiListScrollsVertically
                ? buildGridVertical(context)
                : buildGridHorizontal(context),
          );
  }

  Widget nothingAroundPane(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final hasFilter = ref.watch(poiFilterProvider).isNotEmpty;
    final needDownload = ref.read(areaStatusProvider).value != AreaStatus.fresh;

    String message;
    if (needDownload)
      message = loc.tileDragDownload;
    else if (hasFilter)
      message = loc.tileDragOrUnfilter;
    else
      message = loc.tileDragTheMap;

    return Center(
        child: Padding(
      padding: const EdgeInsets.all(15.0),
      child: Text(
        loc.tileNothingAround(kVisibilityRadius) + '\n' + message,
        style: TextStyle(fontSize: 18.0),
        textAlign: TextAlign.center,
      ),
    ));
  }

  void toggleCheck(OsmChange element) async {
    setState(() {
      element.toggleCheck();
    });
    final changes = ref.read(changesProvider);
    await changes.saveChange(element);
    ref.read(needMapUpdateProvider.notifier).trigger();
  }

  /// Columns of tiles stretched to fill the width, scrolling down. Each tile
  /// goes into the shortest column, so there are no gaps under short tiles.
  /// A cut-off tile at the bottom shows that there is more.
  Widget buildGridVertical(BuildContext context) {
    const kMinTileWidth = 190.0;
    const kSpacing = 2.0;
    // Room after the last row, so it can scroll clear of the round + button.
    const kBottomRoom = 80.0;
    final tiles = widget.amenities.asMap().entries.toList();

    return SafeArea(
      left: false,
      top: false,
      bottom: false,
      child: LayoutBuilder(builder: (context, constraints) {
        final columns = max(
            1, (constraints.maxWidth + kSpacing) ~/ (kMinTileWidth + kSpacing));
        final tileWidth =
            (constraints.maxWidth - kSpacing * (columns - 1)) / columns;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: kBottomRoom),
          child: MasonryColumns(
            columns: columns,
            spacing: kSpacing,
            children: [
              for (final entry in tiles)
                PoiTile(
                  index: entry.key + 1,
                  amenity: entry.value,
                  width: tileWidth,
                  onToggleCheck: () {
                    toggleCheck(entry.value);
                  },
                  isCountedOld: widget.isCountedOld,
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget buildGridHorizontal(BuildContext context) {
    var tiles = widget.amenities.asMap().entries.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SafeArea(
        left: false,
        top: false,
        bottom: false,
        child: Wrap(
          direction: Axis.vertical,
          alignment: WrapAlignment.start,
          runSpacing: 2.0,
          spacing: 2.0,
          children: [
            for (final entry in tiles)
              PoiTile(
                index: entry.key + 1,
                amenity: entry.value,
                width: 190.0,
                onToggleCheck: () {
                  toggleCheck(entry.value);
                },
                isCountedOld: widget.isCountedOld,
              ),
          ],
        ),
      ),
    );
  }
}
