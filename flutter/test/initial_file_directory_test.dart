import 'package:flutter_hbb/utils/initial_file_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first Android connection uses shared storage without a physical path',
      () {
    expect(initialFileDirectories(isRemoteAndroid: true), ['/sdcard', '']);
  });

  test('Android preserves current, saved and advertised absolute paths', () {
    expect(
      initialFileDirectories(
        isRemoteAndroid: true,
        current: '/storage/emulated/10/Download',
        saved: '/storage/emulated/10',
        home: '/storage/emulated/10',
      ),
      ['/storage/emulated/10/Download', '/storage/emulated/10', '/sdcard', ''],
    );
  });

  test('Android does not interpret relative or Windows paths as its home', () {
    expect(
      initialFileDirectories(
          isRemoteAndroid: true,
          current: '.',
          saved: r'C:\Users\test',
          home: '.'),
      ['/sdcard', ''],
    );
  });

  test('other platforms keep their existing initial-directory order', () {
    expect(
      initialFileDirectories(
          isRemoteAndroid: false,
          current: '.',
          saved: r'C:\Users\test',
          home: ''),
      ['.', r'C:\Users\test', ''],
    );
  });
}
