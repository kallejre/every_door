// bundleCombo: a multi-select field where each option carries its own bundle
// of tags. Selecting an option stamps all of its tags; deselecting removes
// them (unless another still-selected option needs the same key). Implements
// the proposal in ideditor/schema-builder#284 for the Every Door fork.
//
// Plugin YAML:
//   fields:
//     ee_recycling:
//       label: "Container colours"
//       type: bundleCombo
//       key: "recycling:colour"      # OPTIONAL: records selected values here, ;-joined
//       options:
//         - value: yellow
//           label: "🟨 Segapakend"
//           tags:
//             "recycling:plastic": "yes"
//             "recycling:cans": "yes"
//             "recycling:beverage_cartons": "yes"
//         - value: green
//           label: "🟩 Klaas"
//           tags:
//             "recycling:glass_bottles": "yes"
//             "recycling:glass_jars": "yes"
//
// NOTE on YAML booleans: write tag values as quoted strings ("yes"), not bare
// `yes` — bare yes/no parse as booleans. This parser coerces bool->yes/no as a
// safety net, but quoting is clearer.

import 'package:every_door/models/amenity.dart';
import 'package:every_door/models/field.dart';
import 'package:every_door/widgets/radio_field.dart';
import 'package:flutter/material.dart';

/// One selectable choice that applies a whole set of tags at once.
class BundleOption {
  final String value; // identity, and written to [primaryKey] if set
  final String? label; // display text
  final Widget? widget; // display icon
  final Map<String, String> tags; // tags applied when this option is selected

  const BundleOption({required this.value, this.label, this.widget, this.tags = const {}});
}

class BundleComboPresetField extends PresetField {
  final List<BundleOption> bundles;
  final String? primaryKey;

  BundleComboPresetField({
    required this.bundles,
    required super.label,
    super.icon,
    super.prerequisite,
    super.locationSet,
    this.primaryKey,
  }) : super(key: primaryKey ?? bundles.first.value);

  @override
  Widget buildWidget(OsmChange element) => BundleComboField(this, element);

  @override
  bool hasRelevantKey(Map<String, String> tags) => bundles.any((b) =>
      b.tags.keys.any((k) => tags.containsKey(k)) ||
      (primaryKey != null && tags.containsKey(primaryKey)));
}

class BundleComboField extends StatefulWidget {
  final BundleComboPresetField field;
  final OsmChange element;

  const BundleComboField(this.field, this.element);

  @override
  State<BundleComboField> createState() => _BundleComboFieldState();
}

class _BundleComboFieldState extends State<BundleComboField> {
  /// An option counts as selected when every tag in its bundle is present
  /// with the expected value.
  bool _isSelected(BundleOption b, Map<String, String> tags) =>
      b.tags.isNotEmpty &&
      b.tags.entries.every((e) => tags[e.key] == e.value);

  List<String> _selectedValues() {
    final tags = widget.element.getFullTags();
    return [
      for (final b in widget.field.bundles)
        if (_isSelected(b, tags)) b.value
    ];
  }

  void _onChange(List<String> selected) {
    final bundles = widget.field.bundles;
    for (final b in bundles) {
      if (selected.contains(b.value)) {
        // apply this bundle's tags
        b.tags.forEach((k, v) => widget.element[k] = v);
      } else {
        // remove this bundle's tags, but keep any key that a still-selected
        // option also relies on (bundles can overlap)
        for (final k in b.tags.keys) {
          final stillNeeded = bundles.any((o) =>
              o.value != b.value &&
              selected.contains(o.value) &&
              o.tags.containsKey(k));
          if (!stillNeeded) widget.element.removeTag(k);
        }
      }
    }

    final pk = widget.field.primaryKey;
    if (pk != null && pk.isNotEmpty) {
      if (selected.isEmpty) {
        widget.element.removeTag(pk);
      } else {
        widget.element[pk] = selected.join(';');
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bundles = widget.field.bundles;
    final options = [for (final b in bundles) b.value];
    final hasWidgets = bundles.any((b) => b.widget != null);
    return RadioField(
      options: options,
      labels: [for (final b in bundles) b.label ?? b.value],
      // hasWidget is true when any option has icon
      widgetLabels: hasWidgets
          // However if any option doesn't have icon nor label,
          // then falls back to raw tag value
          ? [for (final b in bundles) b.widget ?? Text(b.label ?? b.value)]
          : null,
      values: _selectedValues(),
      multi: true,
      onMultiChange: _onChange,
    );
  }
}