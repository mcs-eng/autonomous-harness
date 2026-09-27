import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:harness/core/exclusive_directory.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('exclusive-folder-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('one concurrent caller reserves a literal path without reusing an empty folder', () async {
    final folder = p.join(root.path, 'literal %PATH% & spaces');
    final answers = await Future.wait(
      List.generate(8, (_) => createExclusiveDirectory(folder)),
    );
    expect(answers.where((created) => created), hasLength(1));
    expect(await createExclusiveDirectory(folder), isFalse);
    final marker = File(p.join(folder, 'preserve.txt'));
    await marker.writeAsString('original');
    expect(await createExclusiveDirectory(folder), isFalse);
    expect(await marker.readAsString(), 'original');
    expect(await root.list().length, 1);
  });
}
