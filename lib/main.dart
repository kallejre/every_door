import 'dart:async';
import 'dart:io';

import 'package:every_door/helpers/tags/element_kind.dart';
import 'package:every_door/helpers/log_store.dart';
import 'package:every_door/helpers/perf_log.dart';
import 'package:every_door/providers/app_links_provider.dart';
import 'package:every_door/providers/language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:every_door/constants.dart';
import 'package:every_door/screens/loading.dart';
import 'package:flutter/services.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:every_door/generated/l10n/app_localizations.dart' show AppLocalizations;
import 'package:flutter_dropdown_alert/dropdown_alert.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  Logger.root.level = kDebugMode ? Level.INFO : Level.WARNING;
  setupPerfLogging();
  Logger.root.onRecord.listen((event) {
    logStore.addFromLogger(event);
  });
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await setupSqfliteThreads();
    installCertificate();
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      logStore.addFromFlutter(details);
    };
    ElementKind.reset();
    runApp(ProviderScope(child: const EveryDoorApp()));
  }, (error, stack) {
    logStore.addFromZone(error, stack);
  });
}

/// By default sqflite on Android runs every query of every database on one
/// thread, so a slow query in every_door.db (e.g. counting tag values after
/// a download) makes all presets.db lookups wait. With two threads, different
/// databases run in parallel; queries on the same database keep their order.
/// Must run before any database is opened: changing it later restarts the
/// worker pool and drops queued queries.
Future<void> setupSqfliteThreads() async {
  if (!Platform.isAndroid) return;
  try {
    // ignore: deprecated_member_use
    await Sqflite.devSetOptions(SqfliteOptions()..androidThreadCount = 2);
  } catch (e) {
    Logger('main').warning('Could not set sqflite thread count: $e');
  }
}

Future<void> installCertificate() async {
  ByteData data =
      await PlatformAssetBundle().load('assets/lets-encrypt-r3.pem');
  SecurityContext.defaultContext
      .setTrustedCertificatesBytes(data.buffer.asUint8List());
}

class EveryDoorApp extends ConsumerWidget {
  const EveryDoorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Portal(
      child: MaterialApp(
        title: kAppTitle,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          hintColor:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          useMaterial3: false,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        // Adding "en" to the front so it's used by default.
        supportedLocales: [Locale('en')] + AppLocalizations.supportedLocales,
        locale: ref.watch(languageProvider),
        navigatorKey: ref.read(geoIntentProvider).navigatorKey,
        home: LoadingPage(),
        builder: (context, child) => Stack(children: [
          if (child != null) child,
          DropdownAlert(delayDismiss: 5000),
        ]),
      ),
    );
  }
}
