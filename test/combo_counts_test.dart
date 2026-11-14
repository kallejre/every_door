import 'dart:convert';

import 'package:every_door/providers/osm_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// The per-key counting rules from [OsmDataHelper.getComboOptionsCount],
/// which [countComboValues] must reproduce for all keys at once.
Map<String, int> countOneKey(List<Map<String, String>> elements, String key) {
  final counter = <String, int>{};
  for (final tags in elements) {
    if (key.endsWith(':')) {
      tags.forEach((k, _) {
        if (k.startsWith(key)) {
          final v = k.substring(key.length);
          counter[v] = (counter[v] ?? 0) + 1;
        }
      });
    } else {
      final v = tags[key];
      if (v != null) counter[v] = (counter[v] ?? 0) + 1;
    }
  }
  return counter;
}

void main() {
  final elements = <Map<String, String>>[
    {'amenity': 'cafe', 'cuisine': 'coffee_shop', 'payment:visa': 'yes', 'payment:cash': 'no'},
    {'amenity': 'cafe', 'cuisine': 'coffee_shop;cake', 'wheelchair': 'yes'},
    {'shop': 'kiosk', 'payment:visa': 'yes', 'payment:contactless:nfc': 'yes', 'payment:': 'odd'},
    {'building': 'yes', 'building:levels': '3', 'wheelchair': 'limited'},
    {'drink:beer': 'yes', 'drink:': 'empty suffix', 'diet:vegan': 'only'},
    {},
  ];
  const keys = {
    'cuisine', 'wheelchair', 'building', 'building:levels', 'payment:',
    'payment:contactless:', 'drink:', 'diet:', 'missing', 'missing:',
  };

  test('countComboValues matches per-key counting for every key', () {
    final result =
        countComboValues((elements.map(jsonEncode).toList(), keys));
    for (final key in keys) {
      expect(result[key] ?? const {}, equals(countOneKey(elements, key)),
          reason: 'key "$key"');
    }
    // Spot checks of the trickier rules.
    expect(result['payment:'], {'visa': 2, 'cash': 1, 'contactless:nfc': 1, '': 1});
    expect(result['payment:contactless:'], {'nfc': 1});
    expect(result['drink:'], {'beer': 1, '': 1});
    expect(result.containsKey('missing'), isFalse);
  });

  test('countComboValues skips malformed rows', () {
    final result = countComboValues((['[]', '"x"', '{"cuisine":"pizza"}'], {'cuisine'}));
    expect(result, {'cuisine': {'pizza': 1}});
  });
}
