import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';

/// Row type under which 0.1.0-beta.3 stored minewire nodes. The current
/// schema reads only `outbound` and `raw`, so such rows would silently drop
/// out of every list after an update.
const legacyMinewireType = 'minewire';

/// Rewrites beta.3 minewire rows as ordinary outbound rows, in place.
///
/// The id stays, so a selected node remains selected and a subscription
/// refresh still replaces its own nodes. An unreadable row is left as it is
/// rather than deleted. Returns the number of upgraded rows.
Future<int> upgradeLegacyMinewireRows(AppDatabase db) async {
  final rows = await db.coreConfigDao.rowsOfLegacyType(legacyMinewireType);
  var upgraded = 0;
  for (final row in rows) {
    final link = readLegacyMinewire(row);
    if (link == null) {
      ygLogger('legacy minewire row ${row.id} is unreadable; kept as is');
      continue;
    }
    final saved = outboundCompanion(link.toOutbound(), databaseName: row.name);
    final replaced = await db.coreConfigDao.upgradeLegacyRow(
      row.id,
      legacyMinewireType,
      CoreConfigCompanion(
        type: saved.type,
        tags: saved.tags,
        data: saved.data,
        delay: saved.delay,
      ),
    );
    if (replaced) upgraded++;
  }
  return upgraded;
}

/// beta.3 kept `base64({"minewire": {host, port, password, name, mode,
/// proxy}})` in `data`; `proxy` described its sidecar and has no meaning now.
@visibleForTesting
MinewireLink? readLegacyMinewire(CoreConfigData row) {
  final data = row.data;
  if (data == null || data.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(base64Decode(data)));
  } on FormatException {
    return null;
  }
  final payload = decoded is Map ? decoded['minewire'] : null;
  if (payload is! Map) return null;
  final legacyName = payload['name'];
  final name = row.name.isNotEmpty
      ? row.name
      : legacyName is String && legacyName.isNotEmpty
      ? legacyName
      : MinewireLink.defaultName;
  // Same validation as a stored outbound: port range, known mode.
  return MinewireLink.fromOutbound({
    'tag': name,
    'protocol': MinewireLink.protocol,
    'settings': {
      'address': payload['host'],
      'port': payload['port'],
      'password': payload['password'],
      'mode': payload['mode'] ?? MinewireLink.defaultMode,
    },
  });
}
