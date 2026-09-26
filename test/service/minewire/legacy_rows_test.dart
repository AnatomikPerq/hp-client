import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/minewire/legacy_rows.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// A row exactly as 0.1.0-beta.3 wrote it.
CoreConfigCompanion _beta3Row(String name, Object? payload, {int subId = 7}) =>
    CoreConfigCompanion.insert(
      name: name,
      type: legacyMinewireType,
      tags: 'minewire,fast,socks5',
      data: Value(base64Encode(utf8.encode(jsonEncode(payload)))),
      delay: 120,
      subId: subId,
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('beta.3 minewire rows become outbound rows in place', () async {
    final id = await db.coreConfigDao.insertRow(
      _beta3Row('Мой узел', {
        'minewire': {
          'password': 'p@ss',
          'host': 'mw.example.org',
          'port': 25565,
          'name': 'from link',
          'mode': 'realistic',
          'proxy': 'socks5',
        },
      }),
    );

    expect(await upgradeLegacyMinewireRows(db), 1);

    final row = (await db.coreConfigDao.searchRow(id))!;
    expect(row.type, CoreConfigType.outbound.name);
    expect(row.name, 'Мой узел');
    expect(row.subId, 7);
    expect(row.delay, PingDelayConstants.unknown);
    final link = MinewireLink.fromOutbound(readOutboundFromDbData(row))!;
    expect(link.host, 'mw.example.org');
    expect(link.port, 25565);
    expect(link.password, 'p@ss');
    expect(link.mode, 'realistic');
    // Visible again to the ordinary subscription query.
    expect(
      (await db.coreConfigDao.allOutboundRowsWithDataBySubId(7))
          .map((r) => r.id),
      [id],
    );
  });

  test(
    'unreadable rows are kept untouched and the upgrade is idempotent',
    () async {
      final broken = await db.coreConfigDao.insertRow(
        _beta3Row('broken', {
          'minewire': {'host': 'mw.example.org', 'port': 0, 'password': 'x'},
        }, subId: DBConstants.defaultId),
      );
      final garbage = await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: 'garbage',
          type: legacyMinewireType,
          tags: '',
          data: const Value('%%%'),
          delay: 0,
          subId: DBConstants.defaultId,
        ),
      );

      expect(await upgradeLegacyMinewireRows(db), 0);
      expect(await upgradeLegacyMinewireRows(db), 0);
      for (final id in [broken, garbage]) {
        expect(
          (await db.coreConfigDao.searchRow(id))!.type,
          legacyMinewireType,
        );
      }
    },
  );

  test(
    'a beta.3 database keeps its minewire node through the update',
    () async {
      final directory = await Directory.systemTemp.createTemp('hc-beta3-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/db.sqlite');
      // Schema 2 as beta.3 shipped it, with one manually added minewire node.
      final legacy = sqlite.sqlite3.open(file.path);
      try {
        legacy.execute('''
        CREATE TABLE core_config (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, type TEXT NOT NULL, tags TEXT NOT NULL,
          data TEXT, delay INTEGER NOT NULL, sub_id INTEGER NOT NULL
        );
        CREATE TABLE subscription (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, url TEXT NOT NULL, timestamp INTEGER NOT NULL,
          count INTEGER NOT NULL,
          expanded INTEGER NOT NULL CHECK (expanded IN (0, 1)),
          age_secret_key TEXT, age_public_key TEXT
        );
        CREATE TABLE geo_data (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, type TEXT NOT NULL, url TEXT NOT NULL,
          timestamp INTEGER NOT NULL, category_count INTEGER NOT NULL,
          rule_count INTEGER NOT NULL
        );
        PRAGMA user_version = 2;
      ''');
        legacy.execute(
          '''
        INSERT INTO core_config (id, name, type, tags, data, delay, sub_id)
        VALUES (5, 'Minewire', 'minewire', 'minewire,fast,socks5', ?, 80, 0)
      ''',
          [
            base64Encode(
              utf8.encode(
                jsonEncode({
                  'minewire': {
                    'password': 'secret',
                    'host': 'mw.example.org',
                    'port': 25565,
                    'name': 'Minewire',
                    'mode': 'fast',
                    'proxy': 'socks5',
                  },
                }),
              ),
            ),
          ],
        );
      } finally {
        legacy.close();
      }

      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      try {
        expect(await upgradeLegacyMinewireRows(upgraded), 1);
        final row = (await upgraded.coreConfigDao.searchRow(5))!;
        expect(row.type, CoreConfigType.outbound.name);
        expect(row.subId, DBConstants.defaultId);
        expect(
          MinewireLink.fromOutbound(readOutboundFromDbData(row))!.password,
          'secret',
        );
      } finally {
        await upgraded.close();
      }
    },
  );

  test('an empty name falls back to the name from the link', () {
    final row = CoreConfigData(
      id: 1,
      name: '',
      type: legacyMinewireType,
      tags: '',
      data: base64Encode(
        utf8.encode(
          jsonEncode({
            'minewire': {
              'password': 'x',
              'host': 'h.example',
              'port': 1,
              'name': 'from link',
            },
          }),
        ),
      ),
      delay: 0,
      subId: DBConstants.defaultId,
      favorite: false,
    );
    final link = readLegacyMinewire(row)!;
    expect(link.name, 'from link');
    expect(link.mode, MinewireLink.defaultMode);
  });
}
