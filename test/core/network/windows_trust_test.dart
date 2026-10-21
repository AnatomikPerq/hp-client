import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/network/windows_trust.dart';

final class _Certificate implements X509Certificate {
  @override
  final Uint8List der;

  _Certificate(this.der);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Windows refuses what it cannot parse', () {
    expect(
      WindowsTrust.trusts(
        _Certificate(Uint8List.fromList([0x30, 0x03, 1, 2, 3])),
        'example.com',
        443,
      ),
      isFalse,
    );
    expect(
      WindowsTrust.trusts(_Certificate(Uint8List(0)), 'example.com', 443),
      isFalse,
    );
  }, skip: !Platform.isWindows);
}
