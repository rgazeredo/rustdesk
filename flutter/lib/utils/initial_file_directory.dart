import 'package:path/path.dart' as path;

List<String> initialFileDirectories({
  required bool isRemoteAndroid,
  String current = '',
  String saved = '',
  String home = '',
}) {
  final candidates = <String>{
    if (current.isNotEmpty) current,
    if (saved.isNotEmpty) saved,
    if (home.isNotEmpty) home,
  };
  if (isRemoteAndroid) {
    candidates.removeWhere((candidate) => !path.posix.isAbsolute(candidate));
    // Android resolves this alias for its current user. Do not assume user 0
    // or treat the operator's Windows home as a path on the remote device.
    // The server still authorizes the read; scoped-storage devices may deny it.
    candidates.add('/sdcard');
  }
  candidates.add(home.isEmpty || isRemoteAndroid ? '' : home);
  return candidates.toList();
}
