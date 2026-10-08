import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/services/update_service.dart';

UpdateInfo _info(String current, String latest) => UpdateInfo(
      currentVersion: current,
      latestVersion: latest,
      downloadUrl: '',
      releaseUrl: '',
    );

void main() {
  test('same version is not an update, even with a build suffix', () {
    expect(_info('0.4.78', '0.4.78').isNewerThan, isFalse);
    expect(_info('0.4.78+178', '0.4.78').isNewerThan, isFalse);
  });

  test('newer patch, minor and major are updates', () {
    expect(_info('0.4.78', '0.4.79').isNewerThan, isTrue);
    expect(_info('0.4.78+178', '0.5.1').isNewerThan, isTrue);
    expect(_info('0.4.78', '1.0.0').isNewerThan, isTrue);
  });

  test('older release is not an update', () {
    expect(_info('0.4.78', '0.4.1').isNewerThan, isFalse);
    expect(_info('0.4.1', '0.4.78').isNewerThan, isTrue);
  });
}
