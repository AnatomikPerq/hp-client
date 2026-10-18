import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/servers/catalog.dart';

CoreConfigData _row(int id, String tag, {int delay = -1, String? country}) =>
    CoreConfigData(
      id: id,
      name: tag,
      type: 'outbound',
      tags: 'vless',
      data: base64Encode(
        utf8.encode(jsonEncode({'tag': tag, 'protocol': 'vless'})),
      ),
      delay: delay,
      subId: 0,
      countryCode: country,
      favorite: false,
    );

void main() {
  test('a ping round reuses parsed nodes, an edit parses again', () {
    final catalog = ServerCatalog(
      servers: [_row(1, 'Main'), _row(2, 'Reserve')],
    );
    final first = catalog.displays[1]!;
    expect(first.name, 'Main');

    // A ping writes only delay and location.
    final pinged = catalog.copyWith(
      servers: [
        _row(1, 'Main', delay: 120, country: 'NL'),
        _row(2, 'Reserve', delay: 300),
      ],
    );
    expect(pinged.displays[1], same(first));
    expect(pinged.servers.first.delay, 120);

    final edited = pinged.copyWith(
      servers: [_row(1, 'Renamed', delay: 120), _row(3, 'New')],
    );
    expect(edited.displays[1]!.name, 'Renamed');
    expect(edited.displays.keys, [1, 3]);
    expect(edited.displays[3]!.name, 'New');
  });
}
