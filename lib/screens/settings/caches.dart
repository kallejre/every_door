import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:every_door/constants.dart';
import 'package:every_door/generated/l10n/app_localizations.dart';
import 'package:every_door/helpers/tile_caches.dart';
import 'package:every_door/models/imagery/vector/cache_kinds.dart';
import 'package:every_door/models/imagery/vector/tile_cacher.dart';
import 'package:every_door/providers/need_update.dart';
import 'package:every_door/providers/notes.dart';
import 'package:every_door/providers/osm_data.dart';
import 'package:every_door/screens/settings/downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropdown_alert/alert_controller.dart';
import 'package:flutter_dropdown_alert/model/data_alert.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

class CachesPage extends ConsumerStatefulWidget {
  const CachesPage({super.key});

  @override
  ConsumerState<CachesPage> createState() => _CachesPageState();
}

class _CachesPageState extends ConsumerState<CachesPage> {
  int? _baseCacheSize;
  int? _imageryCacheSize;
  int? _downloadedCacheSize;
  int? _vectorCacheSize;
  int? _renderedVectorCacheSize;

  @override
  void initState() {
    super.initState();
    _fetchCacheSizes();
  }

  Future<void> _fetchCacheSizes() async {
    _baseCacheSize = (await FMTCStore(kTileCacheBase).stats.size).toInt();
    _imageryCacheSize = (await FMTCStore(kTileCacheImagery).stats.size).toInt();
    _downloadedCacheSize =
        (await FMTCStore(kTileCacheDownload).stats.size).toInt();

    final vectorSizes = await measureVectorCache();
    _vectorCacheSize = vectorSizes.values.fold<int>(0, (a, b) => a + b);
    _renderedVectorCacheSize = vectorSizes[CachedFileKind.rendered] ?? 0;

    setState(() {});
  }

  Future<void> _clearCaches() async {
    for (final cache in [kTileCacheBase, kTileCacheImagery]) {
      await FMTCStore(cache).manage.reset();
    }
    await _fetchCacheSizes();
  }

  Future<void> _clearDownloaded(String size) async {
    // Unlike the browsing caches, these tiles were downloaded on purpose
    // for offline use, and take a while to get back.
    final loc = AppLocalizations.of(context)!;
    final answer = await showOkCancelAlertDialog(
      context: context,
      title: loc.settingsCachesClearManualTitle,
      message: loc.settingsCachesClearManualMessage(size),
      isDestructiveAction: true,
      okLabel: loc.buttonYes,
      cancelLabel: loc.buttonNo,
    );
    if (answer != OkCancelResult.ok) return;
    await FMTCStore(kTileCacheDownload).manage.reset();
    await _fetchCacheSizes();
  }

  String _formatBytes(int? amount, {int factor = 1}) {
    double total = ((amount ?? 0) * factor).toDouble();
    final suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    int suffix = 0;
    while (true) {
      if (total < 900) {
        total = (total * 10).roundToDouble() / 10;
        return '$total ${suffixes[suffix]}';
      }
      total /= 1024;
      suffix += 1;
    }
  }

  Future<void> _purgeData(bool all) async {
    final loc = AppLocalizations.of(context)!;
    if (all) {
      final answer = await showOkCancelAlertDialog(
        context: context,
        title: loc.settingsPurgeDataTitle,
        message: loc.settingsPurgeDataMessage,
        isDestructiveAction: true,
        okLabel: loc.buttonYes,
        cancelLabel: loc.buttonNo,
      );
      if (answer != OkCancelResult.ok) return;
    }

    int count = await ref.read(osmDataProvider).purgeData(all);
    if (all) {
      // Also delete unmodified notes.
      count += await ref.read(notesProvider).purgeNotes(DateTime.now());
      AlertController.show(loc.settingsPurgedAllTitle,
          loc.settingsPurgedMessage(count), TypeAlert.success);
    } else {
      AlertController.show(loc.settingsPurgedObsoleteTitle,
          loc.settingsPurgedMessage(count), TypeAlert.success);
    }
    ref.read(needMapUpdateProvider).trigger();
  }

  @override
  Widget build(BuildContext context) {
    final osmData = ref.watch(osmDataProvider);
    NumberFormat numFormat;
    try {
      numFormat = NumberFormat.compact(
          locale: Localizations.localeOf(context).toLanguageTag());
    } catch (e) {
      numFormat = NumberFormat.compact(locale: 'en');
    }
    final dataLength = numFormat.format(osmData.length);
    final obsoleteDataLength = numFormat.format(osmData.obsoleteLength);

    final cacheLength = _formatBytes(_baseCacheSize, factor: 1000);
    final downloadedLength = _formatBytes(_downloadedCacheSize, factor: 1000);
    final vectorCacheLength = _formatBytes(_vectorCacheSize);
    final renderedVectorCacheLength = _formatBytes(_renderedVectorCacheSize);
    bool onlyRendered = (_renderedVectorCacheSize ?? 0) > 0;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.settingsDataManagement),
      ),
      body: ListView(
        children: [
          // Both options, so that everything can be purged even when
          // some data is obsolete.
          ListTile(
            title: Text(
              loc.settingsPurgeAllData,
              style: TextStyle(color: Colors.red.shade900),
            ),
            trailing: Text(dataLength),
            enabled: osmData.length > 0,
            onTap: () => _purgeData(true),
          ),
          ListTile(
            title: Text(loc.settingsPurgeData),
            subtitle: Text(
                loc.settingsPurgeDataSubtitle(kSuperObsoleteData.inDays)),
            trailing: Text(obsoleteDataLength),
            enabled: osmData.obsoleteLength > 0,
            onTap: () => _purgeData(false),
          ),
          ListTile(
            title: Text(loc.settingsCachesClearRaster),
            trailing: _baseCacheSize == null && _imageryCacheSize == null
                ? null
                : Text(cacheLength),
            onTap: () {
              _clearCaches();
            },
          ),
          ListTile(
            title: Text(onlyRendered
                ? loc.settingsCachesClearRenderedVector
                : loc.settingsCachesClearVector),
            trailing: Text(
                onlyRendered ? renderedVectorCacheLength : vectorCacheLength),
            onTap: () async {
              await clearVectorCache(!onlyRendered);
              await _fetchCacheSizes();
            },
          ),
          Divider(),
          ListTile(
            title: Text(loc.settingsCacheTiles),
            trailing: Icon(Icons.navigate_next),
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TileCacheDownloader()));
              await _fetchCacheSizes();
            },
          ),
          if ((_downloadedCacheSize ?? 0) > 0)
            ListTile(
              title: Text(loc.settingsCachesClearManual),
              trailing: Text(downloadedLength),
              onTap: () {
                _clearDownloaded(downloadedLength);
              },
            ),
        ],
      ),
    );
  }
}
