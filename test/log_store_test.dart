import 'package:every_door/helpers/log_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

/// A log record with a chosen time, to fill the log with older messages.
class _RecordAt extends LogRecord {
  final DateTime _time;

  _RecordAt(String message, this._time) : super(Level.INFO, message, 'Test');

  @override
  DateTime get time => _time;
}

void main() {
  final now = DateTime.now();
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  const tenMinutes = Duration(minutes: 10);

  test('newerThan keeps only messages from the given time span', () {
    final store = LogStore();
    store.addFromLogger(_RecordAt('old', ago(15)));
    store.addFromLogger(_RecordAt('recent', ago(5)));
    store.addFromLogger(_RecordAt('new', now));

    final shown = store.newerThan(tenMinutes);
    expect(shown, hasLength(2));
    expect(shown.first, endsWith('I/Test: recent'));
    expect(shown.last, endsWith('I/Test: new'));
    // Copy and share still get everything.
    expect(store.lines, hasLength(3));
  });

  test('newerThan is empty when nothing is recent', () {
    final store = LogStore();
    store.addFromLogger(_RecordAt('old', ago(60)));
    expect(store.newerThan(tenMinutes), isEmpty);
    expect(store.isEmpty, isFalse);
  });

  test('newerThan still works after clear', () {
    final store = LogStore();
    store.addFromLogger(_RecordAt('old', ago(15)));
    store.clear();
    store.addFromLogger(_RecordAt('a', now));
    store.addFromLogger(_RecordAt('b', now));
    expect(store.newerThan(tenMinutes), hasLength(2));
  });

  test('errors and their stack traces count as recent', () {
    final store = LogStore();
    store.addFromLogger(_RecordAt('old', ago(15)));
    store.addFromZone(StateError('deliberate test error'), StackTrace.current);

    final shown = store.newerThan(tenMinutes);
    expect(shown, hasLength(2)); // the message and its stack trace
    expect(shown.first, contains('Async: Bad state: deliberate test error'));
  });
}
