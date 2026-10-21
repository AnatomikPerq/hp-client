import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/desktop_kill_switch.dart';
import 'package:onexray/core/pigeon/model.dart';

import 'kill_switch_fake.dart';

void main() {
  late Directory directory;
  late FakeKillSwitchLib lib;
  late DesktopKillSwitchControl control;

  setUp(() async {
    final root = Directory('../references/kill-switch-tests').absolute;
    await root.create(recursive: true);
    directory = await root.createTemp('run-');
    addTearDown(() => directory.delete(recursive: true));
    lib = FakeKillSwitchLib();
    control = lib.control(directory.path);
  });

  const lenient = DesktopKillSwitch(allowLan: true, strict: false);
  const strict = DesktopKillSwitch(allowLan: true, strict: true);

  test('arming records the session, a start without it forgets', () async {
    await control.arm(lenient);
    final hold = await control.hold();
    expect(hold?.strict, isFalse);
    expect(hold?.session.logon, '0-1');

    await control.arm(null);
    expect(await control.hold(), isNull);
  });

  test('a hold from this session stays at App start', () async {
    await control.arm(lenient);
    lib.engaged = true;
    // Clock corrections move the computed boot time a little.
    lib.session = {'bootedAt': 1030000, 'logon': '0-1'};

    expect(await control.settle(), isTrue);
    expect(lib.engaged, isTrue);
    expect(await control.hold(), isNotNull);
  });

  test('a new logon lifts a lenient hold, even with the same boot', () async {
    await control.arm(lenient);
    lib.engaged = true;
    // Fast startup: the same boot time, a new logon.
    lib.session = {'bootedAt': 1000000, 'logon': '0-2'};

    expect(await control.settle(), isFalse);
    expect(lib.engaged, isFalse);
    expect(await control.hold(), isNull);
  });

  test('a reboot lifts a lenient hold', () async {
    await control.arm(lenient);
    lib.session = {'bootedAt': 9000000, 'logon': '0-1'};
    expect(await control.settle(), isFalse);
    expect(await control.hold(), isNull);
  });

  test('a strict hold survives a new session', () async {
    await control.arm(strict);
    lib.engaged = true;
    lib.session = {'bootedAt': 9000000, 'logon': '0-9'};

    expect(await control.settle(), isTrue);
    expect(lib.engaged, isTrue);
  });

  test('filters without a hold are lifted at App start', () async {
    lib.engaged = true;
    expect(await control.settle(), isFalse);
    expect(lib.engaged, isFalse);
  });

  test('an unreadable hold blocks rather than leaks', () async {
    await DesktopKillSwitchHold.file(directory.path).writeAsString('{oops');
    final hold = await control.hold();
    expect(hold?.strict, isTrue);
    expect(await control.settle(), isTrue);
  });

  test('a broken libXray never fails the App start', () async {
    await control.arm(lenient);
    lib.broken = true;
    expect(await control.settle(), isTrue);

    await DesktopKillSwitchHold.clear(directory.path);
    expect(await control.settle(), isFalse);
  });

  test('an unreadable session never fails arming', () async {
    lib.broken = true;
    await control.arm(lenient);
    final hold = await control.hold();
    expect(hold?.strict, isFalse);
    expect(hold?.session.logon, isEmpty);
  });

  test('lifting falls back to the elevated helper only when denied', () async {
    lib.engaged = true;
    await control.liftFilters();
    expect(lib.elevatedLifts, 0);
    expect(lib.engaged, isFalse);

    lib
      ..engaged = true
      ..denyLift = true;
    await control.liftFilters();
    expect(lib.elevatedLifts, 1);
    expect(lib.engaged, isFalse);

    // Nothing engaged: no elevated prompt even when lifting is denied.
    await control.liftFilters();
    expect(lib.elevatedLifts, 1);
  });

  test('disarm lifts the filters and forgets the hold', () async {
    await control.arm(strict);
    lib.engaged = true;
    await control.disarm();
    expect(lib.engaged, isFalse);
    expect(await control.hold(), isNull);
  });

  test('sessions match by logon and a boot time within two minutes', () {
    const base = KillSwitchSession(bootedAt: 1000000, logon: 'a');
    expect(
      base.sameAs(const KillSwitchSession(bootedAt: 1119000, logon: 'a')),
      isTrue,
    );
    expect(
      base.sameAs(const KillSwitchSession(bootedAt: 1121000, logon: 'a')),
      isFalse,
    );
    expect(
      base.sameAs(const KillSwitchSession(bootedAt: 1000000, logon: 'b')),
      isFalse,
    );
  });
}
