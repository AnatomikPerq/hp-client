/// Network reports shaped like libXray's netreport output, with
/// documentation addresses in place of real ones. The whitelist one mirrors
/// a measured mobile network in white list mode, the filtered one a home
/// provider that blocks some services and spoofs DNS.
library;

Map<String, dynamic> step(String status, [int ms = 50]) => {
  'status': status,
  'ms': ms,
};

Map<String, dynamic> site(
  String id,
  String name,
  String verdict, {
  String dns = 'ok',
  String tls = 'ok',
  Map<String, dynamic>? split,
  String? fragment,
}) => {
  'id': id,
  'name': name,
  'group': 'other',
  'host': '$id.example',
  'dns': dns,
  'tcp': step('ok'),
  'tls': step(tls),
  'split': ?split,
  if (fragment != null) ...{
    'fragment': step('ok'),
    'fragmentTransfer': {'status': fragment, 'bytes': 98304},
  },
  'verdict': verdict,
};

Map<String, dynamic> hosting(
  String id,
  String name,
  String verdict, {
  String country = '',
  bool foreign = true,
  String? whiteTransfer,
  String? fragment,
}) => {
  'id': id,
  'name': name,
  'country': country,
  'host': '$id.example',
  'foreign': foreign,
  'tcp': step('ok'),
  'tls': step(verdict == 'ok' ? 'ok' : 'timeout', 4000),
  if (whiteTransfer != null) ...{
    'whiteName': 'ya.ru',
    'whiteSni': step('ok'),
    'whiteTransfer': {'status': whiteTransfer, 'bytes': 262144},
  },
  if (fragment != null) ...{
    'split': step('timeout', 4000),
    'fragment': step('ok'),
    'fragmentTransfer': {'status': fragment, 'bytes': 262144},
  },
  'verdict': verdict,
};

Map<String, dynamic> whitelistReport() => {
  'version': 1,
  'started': '2026-10-25T00:36:00Z',
  'durationMs': 124850,
  'interface': 'Ethernet 4',
  'network': {
    'interface': {
      'name': 'Ethernet 4',
      'description': 'Remote NDIS based Internet Sharing Device',
      'kind': 'usb_tethering',
      'mtu': 1500,
      'addresses': ['10.0.0.2/24'],
      'gateways': ['10.0.0.1'],
      'dns': ['10.0.0.1'],
    },
    'ipv4': {
      'ip': '198.51.100.237',
      'prefix': '198.51.100.0/22',
      'asn': 25159,
      'holder': 'SONICDUO-AS - PJSC MegaFon, RU',
      'country': 'RU',
      'city': 'Moscow',
    },
    'nat': true,
  },
  'dns': {
    'system': ['10.0.0.1'],
    'port53Intercepted': false,
    'resolvers': [
      {
        'id': 'system',
        'name': 'System',
        'address': '10.0.0.1',
        'system': true,
        'status': 'ok',
        'lossPct': 0,
        'names': [
          {'name': 'rutracker.org', 'status': 'ok'},
        ],
      },
      {
        'id': 'google',
        'name': 'Google',
        'address': '8.8.8.8',
        'status': 'ok',
        'lossPct': 0,
        'egress': {'ip': '192.0.2.10', 'holder': 'GOOGLE - Google LLC, US'},
        'names': [
          {'name': 'rutracker.org', 'status': 'nxdomain'},
          {'name': 'www.youtube.com', 'status': 'nxdomain'},
        ],
      },
    ],
  },
  'sites': [
    site('youtube', 'YouTube', 'sni_whitelist', tls: 'timeout'),
    site('x', 'X', 'nosni_only', tls: 'timeout'),
    site('chatgpt', 'ChatGPT', 'sni_blocked', tls: 'timeout'),
    site('telegram', 'Telegram', 'ip_blocked', tls: 'skipped'),
    site('github', 'GitHub', 'sni_whitelist', tls: 'timeout'),
    site('yandex', 'Yandex', 'ok'),
    site('vk', 'VK', 'ok'),
  ],
  'hosting': [
    hosting('cloudflare', 'Cloudflare', 'nosni_only'),
    hosting('hetzner-fsn', 'Hetzner', 'tls_blocked', country: 'DE'),
    hosting(
      'hetzner-ash',
      'Hetzner',
      'sni_whitelist',
      country: 'US',
      whiteTransfer: 'ok',
    ),
    hosting('vultr-ams', 'Vultr', 'nosni_only', country: 'NL'),
    hosting(
      'selectel',
      'Selectel',
      'sni_whitelist',
      country: 'RU',
      foreign: false,
      whiteTransfer: 'ok',
    ),
    hosting(
      'yandex-cloud',
      'Yandex Cloud',
      'ok',
      country: 'RU',
      foreign: false,
    ),
  ],
  'sni': {
    'host': 'www.google.com',
    'ip': '192.0.2.20',
    'filtered': true,
    'passed': ['mail.ru', 'ya.ru'],
    'failed': ['vk.com'],
  },
  'udp': {
    'stun': [
      {'id': 'google', 'name': 'Google', 'status': 'ok', 'ms': 58},
      {'id': 'cloudflare', 'name': 'Cloudflare', 'status': 'timeout'},
    ],
    'quic': [
      {'id': 'google', 'name': 'Google', 'status': 'ok', 'ms': 84},
    ],
  },
  'facts': {
    'mode': 'sni_whitelist',
    'sniFiltering': true,
    'whitelistBySni': true,
    'dnsSpoofing': ['google'],
    'blockedSites': ['youtube', 'x', 'chatgpt', 'telegram', 'github'],
    'blockedHosting': [
      'cloudflare',
      'hetzner-fsn',
      'hetzner-ash',
      'vultr-ams',
      'selectel',
    ],
    'openHosting': ['yandex-cloud'],
    'bypassTried': 6,
    'udp': 'partial',
    'quic': 'ok',
  },
};

Map<String, dynamic> filteredReport() => {
  'version': 1,
  'started': '2026-10-25T00:22:00Z',
  'durationMs': 78196,
  'network': {
    'interface': {
      'name': 'Ethernet',
      'kind': 'ethernet',
      'dns': ['10.0.1.1'],
    },
    'ipv4': {
      'ip': '203.0.113.27',
      'asn': 31363,
      'holder': 'MOSCOW-AS - JSC "ER-Telecom Holding", RU',
      'country': 'RU',
    },
  },
  'dns': {
    'resolvers': [
      {
        'id': 'google',
        'name': 'Google',
        'address': '8.8.8.8',
        'status': 'ok',
        'lossPct': 20,
        'names': [
          {'name': 'rutracker.org', 'status': 'injected'},
        ],
      },
    ],
  },
  'sites': [
    site('youtube', 'YouTube', 'ok'),
    site(
      'tiktok',
      'TikTok',
      'sni_blocked',
      tls: 'timeout',
      split: step('ok'),
      fragment: 'ok',
    ),
    site(
      'signal',
      'Signal',
      'sni_blocked',
      tls: 'timeout',
      fragment: 'stalled',
    ),
    site('instagram', 'Instagram', 'ip_blocked', tls: 'skipped'),
    site('chatgpt', 'ChatGPT', 'geo'),
    site('github', 'GitHub', 'ok'),
  ],
  'hosting': [
    hosting('cloudflare', 'Cloudflare', 'ok'),
    hosting('hetzner-fsn', 'Hetzner', 'nosni_only', country: 'DE'),
    hosting('vultr-ams', 'Vultr', 'nosni_only', country: 'NL', fragment: 'ok'),
    hosting('scaleway', 'Scaleway', 'ok', country: 'FR'),
    hosting('ovh', 'OVH', 'frozen', country: 'FR'),
  ],
  'sni': {'filtered': false},
  'udp': {
    'stun': [
      {'id': 'google', 'name': 'Google', 'status': 'ok'},
    ],
    'quic': [
      {'id': 'google', 'name': 'Google', 'status': 'ok'},
    ],
  },
  'facts': {
    'mode': 'filtered',
    'dnsSpoofing': ['google'],
    'dnsInjection': true,
    'blockedSites': ['tiktok', 'signal', 'instagram'],
    'geoBlocked': ['chatgpt'],
    'bypassTried': 3,
    'udp': 'ok',
    'quic': 'ok',
  },
};
