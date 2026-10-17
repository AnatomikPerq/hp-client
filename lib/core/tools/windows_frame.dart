import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Colors the thin border Windows 11 draws around a window, which otherwise
/// takes the system accent color. Windows 10 rejects the attribute and keeps
/// its own border; that is not an error for the App.
void setWindowsBorderColor(int hwnd, int argb) => using((arena) {
  final value = arena<Uint32>()..value = windowsColorRef(argb);
  try {
    DwmSetWindowAttribute(
      HWND(Pointer.fromAddress(hwnd)),
      DWMWA_BORDER_COLOR,
      value,
      sizeOf<Uint32>(),
    );
  } on WindowsException {
    // Unsupported before Windows 11 build 22000.
  }
});

/// `0xAARRGGBB` to a Win32 `COLORREF` (`0x00BBGGRR`).
int windowsColorRef(int argb) =>
    ((argb & 0xFF) << 16) | (argb & 0xFF00) | ((argb >> 16) & 0xFF);
