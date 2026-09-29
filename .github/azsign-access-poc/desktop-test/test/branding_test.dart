import 'package:flutter_test/flutter_test.dart';
import '../../../../flutter/lib/common/azsign/azsign_branding.dart';

void main() {
  test('normalizes display names without changing unrelated text', () {
    expect(azsignDisplayText('Senha do AZSignRemotePilot'), 'Senha do AZSign Remote');
    expect(azsignDisplayText('AZSign Remote Pilot'), 'AZSign Remote');
    expect(azsignDisplayText('AZSign Remote PoC'), 'AZSign Remote');
    expect(azsignDisplayText('Powered by RustDesk'), 'Powered by RustDesk');
  });
}
