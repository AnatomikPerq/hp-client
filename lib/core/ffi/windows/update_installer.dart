import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:onexray/core/ffi/windows/core_process.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// Created by the installer's update mode (`[Code]` in
/// `windows/packaging/exe/inno_setup.iss`) in its elevated part, that is once
/// UAC was accepted, right before it waits for the App to exit. The name is
/// session-local, like the App's own `HyperClientAppRunning`.
const windowsUpdateMutexName = 'HyperClientUpdating';

/// The installer's update mode: no wizard pages, a progress window, and the
/// App started again as the original user once the files are in place.
List<String> windowsUpdateArguments(String logFile) => [
  '/SILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/SP-',
  '/HCUPDATE=1',
  '/LOG=$logFile',
];

enum WindowsInstallerState {
  /// The elevated installer runs and waits for the App to exit.
  waitingForApp,

  /// The installer exited before that: UAC was declined or it failed.
  exited,

  /// Nobody answered the UAC prompt in time.
  timedOut,
}

final class WindowsInstallerOutcome {
  final WindowsInstallerState state;
  final int? exitCode;

  const WindowsInstallerOutcome(this.state, [this.exitCode]);
}

/// Keeps a verified installer open without write or delete sharing, so the
/// file Windows elevates is the one whose hash was checked: the update folder
/// is writable by every process of the user.
final class WindowsFileLock {
  final int _handle;
  var _released = false;

  WindowsFileLock._(this._handle);

  static WindowsFileLock open(String path) {
    final opened = using(
      (arena) => CreateFile(
        PCWSTR(arena.pwstr(path)),
        GENERIC_READ,
        FILE_SHARE_READ,
        null,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        null,
      ),
    );
    if (!opened.value.isValid) {
      throw StateError('CreateFile failed: ${opened.error}');
    }
    return WindowsFileLock._(opened.value.address);
  }

  void release() {
    if (_released) return;
    _released = true;
    CloseHandle(HANDLE(Pointer.fromAddress(_handle)));
  }
}

class WindowsUpdateInstaller {
  const WindowsUpdateInstaller();

  /// Starts [installer] unelevated (Inno Setup elevates itself, which keeps
  /// its "run as original user" for the App it starts afterwards) and waits
  /// until the elevated part signals or the installer exits.
  Future<WindowsInstallerOutcome> launch(
    String installer,
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 15),
  }) => Isolate.run(() => _launchAndWait(installer, arguments, timeout));
}

WindowsInstallerOutcome _launchAndWait(
  String installer,
  List<String> arguments,
  Duration timeout,
) {
  final process = _shellExecute(installer, arguments);
  try {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final waited = WaitForSingleObject(process, 250);
      if (waited.value == WAIT_OBJECT_0) {
        return WindowsInstallerOutcome(
          WindowsInstallerState.exited,
          _exitCode(process),
        );
      }
      if (waited.value != WAIT_TIMEOUT) {
        throw StateError('WaitForSingleObject failed: ${waited.error}');
      }
      if (windowsMutexExists(windowsUpdateMutexName)) {
        return const WindowsInstallerOutcome(
          WindowsInstallerState.waitingForApp,
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        return const WindowsInstallerOutcome(WindowsInstallerState.timedOut);
      }
    }
  } finally {
    CloseHandle(process);
  }
}

HANDLE _shellExecute(String executable, List<String> arguments) {
  final initialized = CoInitializeEx(COINIT_APARTMENTTHREADED);
  if (initialized.isError) throw WindowsException(initialized);
  try {
    return using((arena) {
      final info = arena<SHELLEXECUTEINFO>();
      info.ref
        ..cbSize = sizeOf<SHELLEXECUTEINFO>()
        ..fMask =
            0x40 |
            0x100 // NOCLOSEPROCESS | NOASYNC
        ..lpFile = arena.pwstr(executable)
        ..lpDirectory = arena.pwstr(p.windows.dirname(executable))
        ..lpParameters = arena.pwstr(
          arguments.map(quoteWindowsArgument).join(' '),
        )
        ..nShow = SW_SHOWNORMAL;
      final result = ShellExecuteEx(info);
      if (!result.value || !info.ref.hProcess.isValid) {
        throw StateError('ShellExecuteEx failed: ${result.error}');
      }
      return info.ref.hProcess;
    });
  } finally {
    CoUninitialize();
  }
}

int? _exitCode(HANDLE process) => using((arena) {
  final code = arena<Uint32>();
  return GetExitCodeProcess(process, code).value ? code.value : null;
});

final _openMutex = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer Function(Uint32, Int32, Pointer<Utf16>),
      Pointer Function(int, int, Pointer<Utf16>)
    >('OpenMutexW', isLeaf: true);

/// An elevated creator's default DACL may deny this process SYNCHRONIZE;
/// "access denied" still means the mutex exists.
bool windowsMutexExists(String name) => using((arena) {
  final nativeName = arena.pwstr(name);
  GetLastError();
  final handle = _openMutex(SYNCHRONIZE, FALSE, nativeName);
  final error = GetLastError();
  if (handle != nullptr) {
    CloseHandle(HANDLE(handle));
    return true;
  }
  return error == ERROR_ACCESS_DENIED;
});
