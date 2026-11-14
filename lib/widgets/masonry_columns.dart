import 'dart:math' show max;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays out children in [columns] equal-width columns, putting each child
/// into the currently shortest column ("masonry"). Unlike [Wrap], there are
/// no row gaps under shorter children.
class MasonryColumns extends MultiChildRenderObjectWidget {
  final int columns;
  final double spacing;

  const MasonryColumns({
    required this.columns,
    required this.spacing,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMasonryColumns(columns, spacing);

  @override
  void updateRenderObject(
      BuildContext context, RenderMasonryColumns renderObject) {
    renderObject
      ..columns = columns
      ..spacing = spacing;
  }
}

class _MasonryParentData extends ContainerBoxParentData<RenderBox> {}

class RenderMasonryColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MasonryParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MasonryParentData> {
  RenderMasonryColumns(this._columns, this._spacing);

  int _columns;
  double _spacing;

  set columns(int value) {
    if (value == _columns) return;
    _columns = value;
    markNeedsLayout();
  }

  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MasonryParentData) {
      child.parentData = _MasonryParentData();
    }
  }

  /// Places children (unless [dry]) and returns the total size.
  Size _layOut(BoxConstraints constraints, {required bool dry}) {
    final width = constraints.maxWidth;
    final columnWidth = (width - _spacing * (_columns - 1)) / _columns;
    final childConstraints = BoxConstraints.tightFor(width: columnWidth);
    final heights = List<double>.filled(_columns, 0.0);
    RenderBox? child = firstChild;
    while (child != null) {
      int column = 0;
      for (int i = 1; i < _columns; i++) {
        if (heights[i] < heights[column]) column = i;
      }
      final Size childSize;
      if (dry) {
        childSize = child.getDryLayout(childConstraints);
      } else {
        child.layout(childConstraints, parentUsesSize: true);
        childSize = child.size;
      }
      final parentData = child.parentData as _MasonryParentData;
      if (!dry) {
        parentData.offset =
            Offset(column * (columnWidth + _spacing), heights[column]);
      }
      heights[column] += childSize.height + _spacing;
      child = parentData.nextSibling;
    }
    final height = firstChild == null ? 0.0 : heights.reduce(max) - _spacing;
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    size = _layOut(constraints, dry: false);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layOut(constraints, dry: true);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
