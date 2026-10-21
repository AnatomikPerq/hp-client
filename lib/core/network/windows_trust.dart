import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:onexray/core/tools/app_log.dart';

/// BoringSSL in the Dart VM trusts the roots that are in the Windows store
/// when the process starts. Windows ships few of them and fetches the others
/// the first time its own chain building meets one (Automatic Root
/// Certificates Update), which Dart never triggers: on a fresh Windows that
/// had not met Let's Encrypt yet (ISRG Root X1/X2), every download from a
/// panel with such a certificate failed with CERTIFICATE_VERIFY_FAILED until
/// another program fetched the root and the App restarted.
///
/// These overrides make each HttpClient of the isolate ask Windows when
/// BoringSSL refuses a certificate. Windows builds the chain, fetching
/// missing intermediates and roots the way a browser on it would, and checks
/// it with its SSL policy for the host name. Only a certificate Windows
/// trusts for that host is accepted; clients with their own SecurityContext
/// are left alone.
final class WindowsTrustOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (context == null) client.badCertificateCallback = WindowsTrust.trusts;
    return client;
  }
}

abstract final class WindowsTrust {
  static _Crypt32? _crypt32;
  static bool _logged = false;

  static bool trusts(X509Certificate certificate, String host, int _) {
    try {
      final trusted = (_crypt32 ??= _Crypt32()).verify(certificate.der, host);
      if (trusted && !_logged) {
        _logged = true;
        AppLog.info('TLS certificate verified by Windows after BoringSSL');
      }
      return trusted;
    } catch (_) {
      return false;
    }
  }
}

const _certificateEncoding =
    0x00010001; // X509_ASN_ENCODING | PKCS_7_ASN_ENCODING
const _usageMatchAnd = 0; // USAGE_MATCH_TYPE_AND
const _serverAuthentication = '1.3.6.1.5.5.7.3.1'; // szOID_PKIX_KP_SERVER_AUTH
const _authTypeServer = 2; // AUTHTYPE_SERVER
const _policySsl = 4; // CERT_CHAIN_POLICY_SSL

final class _CertEnhKeyUsage extends Struct {
  @Uint32()
  external int cUsageIdentifier;

  external Pointer<Pointer<Utf8>> rgpszUsageIdentifier;
}

final class _CertUsageMatch extends Struct {
  @Uint32()
  external int dwType;

  external _CertEnhKeyUsage usage;
}

final class _CertChainPara extends Struct {
  @Uint32()
  external int cbSize;

  external _CertUsageMatch requestedUsage;
}

final class _SslExtraPolicyPara extends Struct {
  @Uint32()
  external int cbSize;

  @Uint32()
  external int dwAuthType;

  @Uint32()
  external int fdwChecks;

  external Pointer<Utf16> pwszServerName;
}

final class _PolicyPara extends Struct {
  @Uint32()
  external int cbSize;

  @Uint32()
  external int dwFlags;

  external Pointer<Void> pvExtraPolicyPara;
}

final class _PolicyStatus extends Struct {
  @Uint32()
  external int cbSize;

  @Uint32()
  external int dwError;

  @Int32()
  external int lChainIndex;

  @Int32()
  external int lElementIndex;

  external Pointer<Void> pvExtraPolicyStatus;
}

typedef _CreateContextNative = Pointer<Void> Function(
  Uint32,
  Pointer<Uint8>,
  Uint32,
);
typedef _CreateContext = Pointer<Void> Function(int, Pointer<Uint8>, int);
typedef _FreeNative = Int32 Function(Pointer<Void>);
typedef _Free = int Function(Pointer<Void>);
typedef _FreeChainNative = Void Function(Pointer<Void>);
typedef _FreeChain = void Function(Pointer<Void>);
typedef _GetChainNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<_CertChainPara>,
  Uint32,
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _GetChain = int Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<_CertChainPara>,
  int,
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _VerifyPolicyNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<_PolicyPara>,
  Pointer<_PolicyStatus>,
);
typedef _VerifyPolicy = int Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<_PolicyPara>,
  Pointer<_PolicyStatus>,
);

final class _Crypt32 {
  final _CreateContext createContext;
  final _Free freeContext;
  final _GetChain getChain;
  final _FreeChain freeChain;
  final _VerifyPolicy verifyPolicy;

  _Crypt32._(
    this.createContext,
    this.freeContext,
    this.getChain,
    this.freeChain,
    this.verifyPolicy,
  );

  factory _Crypt32() {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    return _Crypt32._(
      crypt32.lookupFunction<_CreateContextNative, _CreateContext>(
        'CertCreateCertificateContext',
      ),
      crypt32.lookupFunction<_FreeNative, _Free>('CertFreeCertificateContext'),
      crypt32.lookupFunction<_GetChainNative, _GetChain>(
        'CertGetCertificateChain',
      ),
      crypt32.lookupFunction<_FreeChainNative, _FreeChain>(
        'CertFreeCertificateChain',
      ),
      crypt32.lookupFunction<_VerifyPolicyNative, _VerifyPolicy>(
        'CertVerifyCertificateChainPolicy',
      ),
    );
  }

  /// Whether Windows trusts the server certificate [der] for [host]. Only
  /// the leaf is known here; Windows fetches the intermediates it names.
  bool verify(List<int> der, String host) => using((arena) {
    if (der.isEmpty) return false;
    final data = arena<Uint8>(der.length);
    data.asTypedList(der.length).setAll(0, der);
    final certificate = createContext(_certificateEncoding, data, der.length);
    if (certificate == nullptr) return false;
    try {
      final usage = arena<Pointer<Utf8>>()
        ..value = _serverAuthentication.toNativeUtf8(allocator: arena);
      final chainPara = arena<_CertChainPara>();
      chainPara.ref
        ..cbSize = sizeOf<_CertChainPara>()
        ..requestedUsage.dwType = _usageMatchAnd
        ..requestedUsage.usage.cUsageIdentifier = 1
        ..requestedUsage.usage.rgpszUsageIdentifier = usage;
      final chain = arena<Pointer<Void>>();
      final built = getChain(
        nullptr,
        certificate,
        nullptr,
        nullptr,
        chainPara,
        0,
        nullptr,
        chain,
      );
      if (built == 0) return false;
      try {
        final ssl = arena<_SslExtraPolicyPara>();
        ssl.ref
          ..cbSize = sizeOf<_SslExtraPolicyPara>()
          ..dwAuthType = _authTypeServer
          ..fdwChecks = 0
          ..pwszServerName = host.toNativeUtf16(allocator: arena);
        final policy = arena<_PolicyPara>();
        policy.ref
          ..cbSize = sizeOf<_PolicyPara>()
          ..pvExtraPolicyPara = ssl.cast();
        final status = arena<_PolicyStatus>();
        status.ref.cbSize = sizeOf<_PolicyStatus>();
        final checked = verifyPolicy(
          Pointer.fromAddress(_policySsl),
          chain.value,
          policy,
          status,
        );
        return checked != 0 && status.ref.dwError == 0;
      } finally {
        freeChain(chain.value);
      }
    } finally {
      freeContext(certificate);
    }
  });
}
