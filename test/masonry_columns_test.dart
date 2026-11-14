import 'package:every_door/widgets/masonry_columns.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('each child goes into the shortest column, no row gaps',
      (tester) async {
    // Heights 30, 40, 10, 50, 20 in two columns with 2 px spacing:
    // left:  0 (30), 32 (10), 44 (20)   right: 0 (40), 42 (50)
    const heights = [30.0, 40.0, 10.0, 50.0, 20.0];
    final keys = [for (var i = 0; i < heights.length; i++) GlobalKey()];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 202,
          child: MasonryColumns(
            columns: 2,
            spacing: 2,
            children: [
              for (var i = 0; i < heights.length; i++)
                SizedBox(key: keys[i], height: heights[i]),
            ],
          ),
        ),
      ),
    ));

    Offset pos(int i) => tester.getTopLeft(find.byKey(keys[i]));
    expect(pos(0), const Offset(0, 0));
    expect(pos(1), const Offset(102, 0));
    expect(pos(2), const Offset(0, 32)); // right under the 30 px tile, not at 42
    expect(pos(3), const Offset(102, 42));
    expect(pos(4), const Offset(0, 44));
    expect(tester.getSize(find.byKey(keys[0])).width, 100);
    expect(tester.getSize(find.byType(MasonryColumns)), const Size(202, 92));
  });

  testWidgets('no children takes no height', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
            width: 200,
            child: MasonryColumns(columns: 2, spacing: 2, children: [])),
      ),
    ));
    expect(tester.getSize(find.byType(MasonryColumns)).height, 0);
  });
}
