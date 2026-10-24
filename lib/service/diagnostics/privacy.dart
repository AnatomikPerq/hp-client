import 'dart:io';
import 'dart:typed_data';

import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/diagnostics/settings.dart';

/// The App and system a report came from, when the settings allow it.
class ReportClient {
  final String app;
  final String system;

  const ReportClient({required this.app, required this.system});

  Map<String, dynamic> toJson() => {'app': app, 'system': system};
}

/// Applies the settings to libXray's report. The result is both what the
/// page shows and what is shared: the user sees exactly what leaves.
Map<String, dynamic> redactReport(
  Map<String, dynamic> raw,
  NetworkReportSettings settings, {
  ReportClient? client,
}) {
  final report = JsonTool.copyMap(raw);
  final network = report['network'];
  if (network is Map<String, dynamic>) {
    for (final key in const ['ipv4', 'ipv6']) {
      final external = network[key];
      if (external is! Map<String, dynamic>) continue;
      switch (settings.address) {
        case ReportAddressMode.hidden:
          external.remove('ip');
        case ReportAddressMode.network:
          if (external['ip'] case final String ip) {
            external['ip'] = maskAddress(ip);
          }
        case ReportAddressMode.full:
          break;
      }
      if (!settings.provider) {
        external
          ..remove('asn')
          ..remove('holder')
          ..remove('prefix');
      }
      switch (settings.location) {
        case ReportLocationMode.hidden:
          external
            ..remove('country')
            ..remove('city');
        case ReportLocationMode.country:
          external.remove('city');
        case ReportLocationMode.city:
          break;
      }
      external.remove('lookup');
    }
    final adapter = network['interface'];
    if (adapter is Map<String, dynamic>) {
      if (!settings.connectionType) adapter.remove('kind');
      if (!settings.adapter) {
        adapter
          ..remove('name')
          ..remove('description')
          ..remove('addresses')
          ..remove('gateways');
      }
      if (!settings.dnsServers) adapter.remove('dns');
    }
  }
  if (!settings.adapter) report.remove('interface');
  final dns = report['dns'];
  if (dns is Map<String, dynamic> && !settings.dnsServers) {
    dns.remove('system');
    if (dns['resolvers'] case final List resolvers) {
      for (final resolver in resolvers) {
        if (resolver is Map<String, dynamic> && resolver['system'] == true) {
          resolver['address'] = '';
        }
      }
    }
  }
  if (settings.device && client != null) {
    report['client'] = client.toJson();
  } else {
    report.remove('client');
  }
  return report;
}

/// The network part of an address: the /24 of IPv4, the /48 of IPv6.
String maskAddress(String text) {
  final address = InternetAddress.tryParse(text);
  if (address == null) return '';
  final bytes = address.rawAddress;
  final keep = address.type == InternetAddressType.IPv4 ? 3 : 6;
  final masked = [
    for (var index = 0; index < bytes.length; index++)
      index < keep ? bytes[index] : 0,
  ];
  final network = InternetAddress.fromRawAddress(
    Uint8List.fromList(masked),
    type: address.type,
  );
  return '${network.address}/${keep * 8}';
}
