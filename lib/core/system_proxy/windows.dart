import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:onexray/core/system_proxy/model.dart';

const _optionPerConnection = 75; // INTERNET_OPTION_PER_CONNECTION_OPTION
const _optionSettingsChanged = 39; // INTERNET_OPTION_SETTINGS_CHANGED
const _optionRefresh = 37; // INTERNET_OPTION_REFRESH

const _connFlags = 1; // INTERNET_PER_CONN_FLAGS
const _connProxyServer = 2; // INTERNET_PER_CONN_PROXY_SERVER
const _connProxyBypass = 3; // INTERNET_PER_CONN_PROXY_BYPASS
const _connAutoConfigUrl = 4; // INTERNET_PER_CONN_AUTOCONFIG_URL
const _connFlagsUi = 10; // INTERNET_PER_CONN_FLAGS_UI

const _typeDirect = 0x1; // PROXY_TYPE_DIRECT
const _typeProxy = 0x2; // PROXY_TYPE_PROXY
const _typeAutoProxyUrl = 0x4; // PROXY_TYPE_AUTO_PROXY_URL
const _typeAutoDetect = 0x8; // PROXY_TYPE_AUTO_DETECT

final class _OptionValue extends Union {
  @Uint32()
  external int dwValue;

  external Pointer<Utf16> pszValue;
}

final class _PerConnOption extends Struct {
  @Uint32()
  external int dwOption;

  external _OptionValue value;
}

final class _PerConnOptionList extends Struct {
  @Uint32()
  external int dwSize;

  external Pointer<Utf16> pszConnection;

  @Uint32()
  external int dwOptionCount;

  @Uint32()
  external int dwOptionError;

  external Pointer<_PerConnOption> pOptions;
}

typedef _QueryNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Void>,
  Pointer<Uint32>,
);
typedef _Query = int Function(
  Pointer<Void>,
  int,
  Pointer<Void>,
  Pointer<Uint32>,
);
typedef _SetNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Void>,
  Uint32,
);
typedef _Set = int Function(Pointer<Void>, int, Pointer<Void>, int);
typedef _GlobalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastError = int Function();
typedef _RegGetValueNative = Uint32 Function(
  IntPtr,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Uint32,
  Pointer<Uint32>,
  Pointer<Void>,
  Pointer<Uint32>,
);
typedef _RegGetValue = int Function(
  int,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Uint32>,
  Pointer<Void>,
  Pointer<Uint32>,
);
typedef _RegSetKeyValueNative = Uint32 Function(
  IntPtr,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Uint32,
  Pointer<Void>,
  Uint32,
);
typedef _RegSetKeyValue = int Function(
  int,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Void>,
  int,
);
typedef _RegDeleteKeyValueNative = Uint32 Function(
  IntPtr,
  Pointer<Utf16>,
  Pointer<Utf16>,
);
typedef _RegDeleteKeyValue = int Function(int, Pointer<Utf16>, Pointer<Utf16>);

// (HKEY)(ULONG_PTR)(LONG)0x80000001, sign-extended like the Windows headers.
const _hkeyCurrentUser = -0x7FFFFFFF;
const _internetSettings =
    r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
const _regDword = 4; // REG_DWORD
const _regSz = 1; // REG_SZ
const _rrfRtDword = 0x18; // RRF_RT_DWORD
const _rrfRtSz = 0x2; // RRF_RT_REG_SZ
const _errorFileNotFound = 2;
const _errorMoreData = 234;

/// The legacy per-user copy that some software reads and writes directly.
const _legacyDwords = ['ProxyEnable'];
const _legacyStrings = ['ProxyServer', 'ProxyOverride', 'AutoConfigURL'];

/// WinINet per-connection proxy options: the settings shown in Windows
/// "Proxy" settings and used by browsers and most desktop apps.
///
/// [connection] names a dial-up/VPN connection; `null` is the LAN setting the
/// App manages. Tests use a throwaway name so they never touch the real proxy.
class WindowsSystemProxyBackend implements SystemProxyBackend {
  final String? connection;

  /// Broadcast the change to running WinINet clients. Tests on a throwaway
  /// connection leave the LAN users undisturbed.
  final bool notify;

  const WindowsSystemProxyBackend({this.connection, this.notify = true});

  @override
  Future<SystemProxySettings> read() {
    final connection = this.connection;
    return Isolate.run(() => _read(connection));
  }

  @override
  Future<void> write(SystemProxySettings settings) {
    final connection = this.connection;
    final notify = this.notify;
    return Isolate.run(() => _write(connection, settings, notify));
  }
}

final class _WinInet {
  final _Query query;
  final _Set set;
  final Pointer<Void> Function(Pointer<Void>) globalFree;
  final _GetLastError lastError;
  final _RegGetValue regGetValue;
  final _RegSetKeyValue regSetKeyValue;
  final _RegDeleteKeyValue regDeleteKeyValue;

  _WinInet._(
    this.query,
    this.set,
    this.globalFree,
    this.lastError,
    this.regGetValue,
    this.regSetKeyValue,
    this.regDeleteKeyValue,
  );

  factory _WinInet() {
    final wininet = DynamicLibrary.open('wininet.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final advapi32 = DynamicLibrary.open('advapi32.dll');
    return _WinInet._(
      wininet.lookupFunction<_QueryNative, _Query>('InternetQueryOptionW'),
      wininet.lookupFunction<_SetNative, _Set>('InternetSetOptionW'),
      kernel32.lookupFunction<_GlobalFreeNative, _GlobalFreeNative>(
        'GlobalFree',
      ),
      kernel32.lookupFunction<_GetLastErrorNative, _GetLastError>(
        'GetLastError',
      ),
      advapi32.lookupFunction<_RegGetValueNative, _RegGetValue>('RegGetValueW'),
      advapi32.lookupFunction<_RegSetKeyValueNative, _RegSetKeyValue>(
        'RegSetKeyValueW',
      ),
      advapi32.lookupFunction<_RegDeleteKeyValueNative, _RegDeleteKeyValue>(
        'RegDeleteKeyValueW',
      ),
    );
  }

  Map<String, Object?> readLegacy() => using((arena) {
    final key = arena.pwstr(_internetSettings);
    final values = <String, Object?>{};
    for (final name in _legacyDwords) {
      final data = arena<Uint32>();
      final size = arena<Uint32>()..value = sizeOf<Uint32>();
      final result = regGetValue(
        _hkeyCurrentUser,
        key,
        arena.pwstr(name),
        _rrfRtDword,
        nullptr,
        data.cast(),
        size,
      );
      values[name] = result == 0 ? data.value : _missing(result, name);
    }
    for (final name in _legacyStrings) {
      var capacity = 1024;
      while (true) {
        final data = arena<Uint16>(capacity ~/ 2);
        final size = arena<Uint32>()..value = capacity;
        final result = regGetValue(
          _hkeyCurrentUser,
          key,
          arena.pwstr(name),
          _rrfRtSz,
          nullptr,
          data.cast(),
          size,
        );
        if (result == _errorMoreData) {
          capacity = size.value + 2;
          continue;
        }
        values[name] = result == 0
            ? data.cast<Utf16>().toDartString()
            : _missing(result, name);
        break;
      }
    }
    return values;
  });

  Null _missing(int result, String name) {
    if (result == _errorFileNotFound) return null;
    throw StateError('RegGetValue($name) failed: $result');
  }

  void writeLegacy(Map<String, Object?> values) => using((arena) {
    final key = arena.pwstr(_internetSettings);
    for (final entry in values.entries) {
      final name = arena.pwstr(entry.key);
      final value = entry.value;
      final int result;
      if (value == null) {
        result = regDeleteKeyValue(_hkeyCurrentUser, key, name);
        if (result == _errorFileNotFound) continue;
      } else if (value is int && _legacyDwords.contains(entry.key)) {
        final data = arena<Uint32>()..value = value;
        result = regSetKeyValue(
          _hkeyCurrentUser,
          key,
          name,
          _regDword,
          data.cast(),
          sizeOf<Uint32>(),
        );
      } else if (value is String && _legacyStrings.contains(entry.key)) {
        final data = value.toNativeUtf16(allocator: arena);
        result = regSetKeyValue(
          _hkeyCurrentUser,
          key,
          name,
          _regSz,
          data.cast(),
          (value.length + 1) * 2,
        );
      } else {
        throw FormatException('Invalid legacy proxy value ${entry.key}');
      }
      if (result != 0) {
        throw StateError('Registry write of ${entry.key} failed: $result');
      }
    }
  });
}

SystemProxySettings _read(String? connection) {
  final api = _WinInet();
  return using((arena) {
    // FLAGS_UI reports what the user configured; FLAGS may also carry the
    // auto-detect bit WinINet sets internally. Older systems only know FLAGS.
    for (final flagsOption in const [_connFlagsUi, _connFlags]) {
      final options = arena<_PerConnOption>(4);
      options[0].dwOption = flagsOption;
      options[1].dwOption = _connProxyServer;
      options[2].dwOption = _connProxyBypass;
      options[3].dwOption = _connAutoConfigUrl;
      final list = _list(arena, connection, options, 4);
      final size = arena<Uint32>()..value = sizeOf<_PerConnOptionList>();
      if (api.query(nullptr, _optionPerConnection, list.cast(), size) == 0) {
        if (flagsOption == _connFlagsUi) continue;
        throw StateError('InternetQueryOption failed: ${api.lastError()}');
      }
      String take(int index) {
        final pointer = options[index].value.pszValue;
        if (pointer == nullptr) return '';
        final value = pointer.toDartString();
        api.globalFree(pointer.cast());
        return value;
      }

      final flags = options[0].value.dwValue;
      return SystemProxySettings(
        enabled: flags & _typeProxy != 0,
        server: take(1),
        bypass: take(2),
        autoConfigUrl: take(3),
        autoConfigEnabled: flags & _typeAutoProxyUrl != 0,
        autoDetect: flags & _typeAutoDetect != 0,
        // Only the LAN setting has a legacy copy.
        native: connection == null ? api.readLegacy() : const {},
      );
    }
    throw StateError('InternetQueryOption failed');
  });
}

void _write(String? connection, SystemProxySettings settings, bool notify) {
  final api = _WinInet();
  using((arena) {
    final options = arena<_PerConnOption>(4);
    options[0].dwOption = _connFlags;
    options[0].value.dwValue =
        _typeDirect |
        (settings.enabled ? _typeProxy : 0) |
        (settings.autoConfigEnabled ? _typeAutoProxyUrl : 0) |
        (settings.autoDetect ? _typeAutoDetect : 0);
    options[1].dwOption = _connProxyServer;
    options[1].value.pszValue = arena.pwstr(settings.server);
    options[2].dwOption = _connProxyBypass;
    options[2].value.pszValue = arena.pwstr(settings.bypass);
    options[3].dwOption = _connAutoConfigUrl;
    options[3].value.pszValue = arena.pwstr(settings.autoConfigUrl);
    final list = _list(arena, connection, options, 4);
    if (api.set(
          nullptr,
          _optionPerConnection,
          list.cast(),
          sizeOf<_PerConnOptionList>(),
        ) ==
        0) {
      throw StateError('InternetSetOption failed: ${api.lastError()}');
    }
    // WinINet has just rewritten the legacy copy from its own view; put back
    // what was there, which may hold entries only other software knows about.
    if (connection == null && settings.native.isNotEmpty) {
      api.writeLegacy(settings.native);
    }
    if (notify) {
      api.set(nullptr, _optionSettingsChanged, nullptr, 0);
      api.set(nullptr, _optionRefresh, nullptr, 0);
    }
  });
}

Pointer<_PerConnOptionList> _list(
  Arena arena,
  String? connection,
  Pointer<_PerConnOption> options,
  int count,
) {
  final list = arena<_PerConnOptionList>();
  list.ref
    ..dwSize = sizeOf<_PerConnOptionList>()
    ..pszConnection = connection == null ? nullptr : arena.pwstr(connection)
    ..dwOptionCount = count
    ..dwOptionError = 0
    ..pOptions = options;
  return list;
}

extension on Arena {
  Pointer<Utf16> pwstr(String value) => value.toNativeUtf16(allocator: this);
}
