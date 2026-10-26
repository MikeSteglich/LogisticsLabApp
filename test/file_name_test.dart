/// Saving: the extension exactly once - the save panel of macOS sometimes adds it to a name with another dot.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:logisticslab_app/ui/file_ops.dart';

void main() {
  test('the extension once', () {
    expect(FileOps.withExtension('/a/dahme-spreewald.dlpx.llab.llab', 'llab'), '/a/dahme-spreewald.dlpx.llab');
    expect(FileOps.withExtension('/a/drogma.dlpx.llab', 'llab'), '/a/drogma.dlpx.llab');
    expect(FileOps.withExtension('/a/drogma', 'llab'), '/a/drogma.llab');
    expect(FileOps.withExtension('/a/tour.LLAB', 'llab'), '/a/tour.llab');
    expect(FileOps.withExtension('/a/tour.llsol.llsol', 'llsol'), '/a/tour.llsol');
  });
}
