import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/routing/profiles/catalog.dart';
import 'package:onexray/service/connect/routing/profiles/editor.dart';
import 'package:onexray/service/connect/routing/profiles/profile.dart';
import 'package:onexray/service/connect/settings.dart';

TrafficProfile _custom(String id, {String name = 'Work'}) => TrafficProfile(
  id: id,
  name: name,
  action: TrafficProfileAction.direct,
  domains: const ['domain:corp.example'],
);

void main() {
  test('settings round-trip through the connection JSON', () {
    final settings = ConnectionSettings(
      trafficMode: TrafficMode.selective,
      profiles: TrafficProfileSettings(
        enabled: const [TrafficProfiles.youtube, 'custom-1'],
        custom: [_custom('custom-1')],
      ),
    );
    final json = settings.toJson();
    expect(json['trafficMode'], 'selective');
    expect(json['profiles']['enabled'], ['custom-1', 'youtube']);
    final read = ConnectionSettings.fromJson(json);
    expect(read.toJson(), json);
    expect(read.profiles.isEnabled(TrafficProfiles.youtube), isTrue);
    expect(read.profiles.custom.single.action, TrafficProfileAction.direct);
    expect(read.requiredEntries(), read.smart.entryCount);
  });

  test('Selective shares the Smart final exit', () {
    final settings = ConnectionSettings(
      trafficMode: TrafficMode.selective,
      smart: SmartRoutingSettings(finalExitId: 7),
    );
    expect(settings.finalExitId, 7);
    expect(
      ConnectionSettings(
        trafficMode: TrafficMode.allVpn,
        smart: SmartRoutingSettings(finalExitId: 7),
      ).finalExitId,
      isNull,
    );
  });

  test('toggles, custom profiles and their ids', () {
    var settings = const TrafficProfileSettings();
    expect(settings.isDefault, isTrue);
    expect(settings.nextCustomId(), 'custom-1');
    settings = settings
        .withCustom(_custom('custom-1'))
        .toggle('custom-1', true);
    settings = settings.withCustom(_custom('custom-3'));
    expect(settings.nextCustomId(), 'custom-4');
    settings = settings.withCustom(_custom('custom-1', name: 'Renamed'));
    expect(settings.custom.map((profile) => profile.name), ['Renamed', 'Work']);
    settings = settings.withoutCustom('custom-1');
    expect(settings.isEnabled('custom-1'), isFalse);
    expect(settings.custom.single.id, 'custom-3');
    expect(
      TrafficProfiles.active(
        settings.toggle(TrafficProfiles.games, true).toggle('custom-3', true),
      ).map((profile) => profile.id),
      [TrafficProfiles.games, 'custom-3'],
    );
  });

  test('custom input lines become Xray values', () {
    expect(
      TrafficProfile.normalizeDomain(' Example.COM '),
      'domain:example.com',
    );
    expect(
      TrafficProfile.normalizeDomain('*.example.com'),
      'domain:example.com',
    );
    expect(
      TrafficProfile.normalizeDomain('geosite:netflix'),
      'geosite:netflix',
    );
    expect(TrafficProfile.normalizeDomain('full:a.example'), 'full:a.example');
    expect(TrafficProfile.normalizeDomain('torrent'), 'torrent');
    expect(
      TrafficProfile.normalizeProcess(r' C:\Program Files\App\app.exe '),
      'C:/Program Files/App/app.exe',
    );
    expect(
      TrafficProfile.lines(
        'a.example\n\n  b.example \r\na.example',
        TrafficProfile.normalizeDomain,
      ),
      ['domain:a.example', 'domain:b.example'],
    );
  });

  test('custom profiles need a name and a condition', () {
    expect(_custom('custom-1').validate, returnsNormally);
    expect(
      () => _custom('custom-1', name: ' ').validate(),
      throwsFormatException,
    );
    expect(
      () => TrafficProfile(
        id: 'custom-1',
        name: 'Empty',
        action: TrafficProfileAction.proxy,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => TrafficProfile(
        id: 'custom-1',
        name: 'Spaces',
        action: TrafficProfileAction.proxy,
        domains: const ['bad value'],
      ).validate(),
      throwsFormatException,
    );
    expect(() => _custom(TrafficProfiles.ai).validate(), throwsFormatException);
    final six = TrafficProfileSettings(
      custom: [for (var i = 1; i <= 6; i++) _custom('custom-$i')],
    );
    expect(six.validate, throwsFormatException);
  });

  test('a profile change in a direction the mode ignores needs no restart', () {
    final selective = ConnectionSettings(
      trafficMode: TrafficMode.selective,
      profiles: const TrafficProfileSettings(enabled: [TrafficProfiles.ai]),
    );
    expect(
      TrafficProfilesEditorService.sameRuntime(
        selective,
        selective.profiles.toggle(TrafficProfiles.games, true),
      ),
      isTrue,
    );
    expect(
      TrafficProfilesEditorService.sameRuntime(
        selective,
        selective.profiles.toggle(TrafficProfiles.discord, true),
      ),
      isFalse,
    );
    final allVpn = ConnectionSettings(trafficMode: TrafficMode.allVpn);
    expect(
      TrafficProfilesEditorService.sameRuntime(
        allVpn,
        allVpn.profiles.toggle(TrafficProfiles.youtube, true),
      ),
      isTrue,
    );
  });
}
