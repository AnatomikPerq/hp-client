import 'dart:io';

import 'package:ffigen/ffigen.dart';

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  // ffigen looks under Program Files\LLVM; LIBCLANG_PATH names another
  // libclang, such as the Android NDK's (readme/BUILD.md), whose resource
  // headers (stddef.h) lie next to it rather than where ffigen looks, and
  // FFIGEN_INCLUDE the C library headers it lacks (llvm-mingw's include).
  final libclang = Platform.environment['LIBCLANG_PATH'];
  final resourceHeaders = libclang == null ? null : _resourceHeaders(libclang);
  final includes = [
    ?resourceHeaders,
    ...?Platform.environment['FFIGEN_INCLUDE']
        ?.split(';')
        .where((path) => path.isNotEmpty),
  ];
  const functions = {
    'CGoInvoke',
    'CGoFree',
    'VoleWindowsVpnInvoke',
    'VoleFree',
  };

  final generator = FfiGenerator(
    input: Input(
      entryPoints: [
        packageRoot.resolve('c/include/libXray.h'),
        packageRoot.resolve('c/include/vole.h'),
        packageRoot.resolve('c/include/vole_windows_uwp.h'),
      ],
      // Emit the Windows-only entry point on every generation host.
      compilerOptions: ['-D_WIN32', for (final path in includes) '-I$path'],
      appendCompilerOptions: true,
    ),
    output: Output(
      dart: DartOutput(
        path: packageRoot.resolve('lib/core/ffi/generated_bindings.dart'),
      ),
      style: const DynamicLibraryBindings(
        wrapperName: 'NativeLibrary',
        wrapperDocComment: 'Generated native bindings for libXray and Vole.',
      ),
    ),
    visitors: [
      Visitor(
        func: (node) => node.isIncluded = functions.contains(node.originalName),
      ),
    ],
  );
  await generator.generate(
    libclangDylib: libclang == null ? null : Uri.file(libclang),
  );
}

/// `<llvm>/lib/clang/<version>/include` for `<llvm>/bin/libclang.dll`.
String? _resourceHeaders(String libclang) {
  final clang = Directory.fromUri(
    File(libclang).absolute.uri.resolve('../lib/clang/'),
  );
  if (!clang.existsSync()) return null;
  for (final version in clang.listSync().whereType<Directory>()) {
    final include = Directory.fromUri(version.uri.resolve('include/'));
    if (File.fromUri(include.uri.resolve('stddef.h')).existsSync()) {
      return include.path;
    }
  }
  return null;
}
