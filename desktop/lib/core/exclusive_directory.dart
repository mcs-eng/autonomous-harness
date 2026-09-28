import 'dart:io';

import 'package:path/path.dart' as p;

Future<bool> createExclusiveDirectory(String folder) async {
  if (!Platform.isWindows) {
    // Directory.create accepts existing directories; mkdir reserves exclusively.
    return (await Process.run('mkdir', [folder])).exitCode == 0;
  }
  // Windows has no mkdir executable. Renaming a private, empty sibling uses
  // MoveFileEx without REPLACE_EXISTING, so it cannot reuse even an empty folder.
  // Keep this Windows-only: POSIX rename can replace an empty destination.
  final staging = await Directory(p.dirname(folder))
      .createTemp('.harness-project-');
  var moved = false;
  try {
    await staging.rename(folder);
    moved = true;
    return true;
  } on FileSystemException {
    return false;
  } finally {
    if (!moved) await staging.delete();
  }
}
