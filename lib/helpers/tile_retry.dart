import 'dart:async';

import 'package:every_door/constants.dart';
import 'package:flutter_map/flutter_map.dart' show TileImage;
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// Reloads tiles that failed because there was no network.
///
/// flutter_map never retries a failed tile while it stays on screen, so after
/// a connection drop the gaps stayed until the app was restarted. Here we poll
/// the last failed tile URL every [kTileRetryInterval], and once the server
/// answers at all, fire [stream] so the tile layers reset and reload.
///
/// We probe instead of resetting blindly, because a reset reloads every tile
/// in the layer, and doing that every few seconds offline makes the map flash.
class TileRetryController {
  static final _logger = Logger('TileRetry');

  /// Errors that mean "no network", not "the server has no such tile".
  static const _kRetryableErrors = {
    FMTCBrowsingErrorType.noConnectionDuringFetch,
    FMTCBrowsingErrorType.unknownFetchException,
  };

  final _resets = StreamController<void>.broadcast();
  String? _probeUrl;
  Timer? _timer;

  /// Fires when failed tiles should be loaded again.
  Stream<void> get stream => _resets.stream;

  /// Pass to [TileLayer.errorTileCallback].
  void onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (error is! FMTCBrowsingError) return;
    if (!_kRetryableErrors.contains(error.type)) return;
    _probeUrl = error.networkUrl;
    // The failed load was the last attempt, so wait a full interval from now.
    _timer ??= Timer(kTileRetryInterval, _probe);
  }

  Future<void> _probe() async {
    final url = _probeUrl;
    if (url == null) {
      _timer = null;
      return;
    }

    try {
      // Any HTTP response, even an error status, means we're back online.
      await http
          .head(Uri.parse(url), headers: {'User-Agent': kTileRetryUserAgent})
          .timeout(kTileRetryInterval);
    } catch (_) {
      _timer = Timer(kTileRetryInterval, _probe);
      return;
    }

    _logger.info('Network is back, reloading failed tiles');
    _probeUrl = null;
    _timer = null;
    _resets.add(null);
  }
}

final tileRetry = TileRetryController();
