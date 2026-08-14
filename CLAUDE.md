# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Read `AGENTS.md` first.** It defines the layering rules (`core → service → pages`, no reverse calls), the runtime config flow, generated-file policy, and UI conventions (LucideIcons only, no numeric font sizes). This file covers what AGENTS.md does not: the multi-repository setup, the desktop process model, and operational rules specific to this fork.

## This repo is one of three

`build_scripts/app/builder.py` resolves sibling repositories from the parent of this checkout, so the layout is mandatory:

```
hp-client/
  app/         this repository
  libXray/     OUR FORK: AnatomikPerq/libXray (upstream XTLS/libXray is remote `upstream`)
  Xray-core/   tag matching the libXray revision
  output/      packaged builds land here
```

`libXray` is a fork, not a checkout of upstream: non-standard protocol engines are compiled into it. Changing such a protocol means editing **two repositories** — the Go engine wrapper in `libXray/`, then rebuilding the shared library and copying it into `windows/app/`.

`windows/app/` and `linux/app/` are gitignored build inputs (`libXray.dll`, `HyperClientCore.exe`, `wintun.dll`). A fresh clone has none of them; see `readme/BUILD.md`.

## Commands

Neither Flutter nor Go is on `PATH` on the usual dev machine:

```shell
$env:Path = "C:\Users\local\flutter\stable\bin;" + $env:Path
$env:Path = "C:\Users\local\toolchains\go\bin;C:\Users\local\toolchains\llvm-mingw-20260616-ucrt-x86_64\bin;" + $env:Path
```

```shell
flutter analyze lib
flutter test                                          # whole suite
flutter test test/service/xray/core_api_test.dart     # one file
flutter test <file> --plain-name "<test name>"        # one test
dart run build_runner build --delete-conflicting-outputs
flutter build windows --release
```

`flutter test` reports **one expected failure on Windows**: `test/core/desktop_startup/linux_adapter_test.dart` builds a POSIX desktop-entry path and asserts an unescaped `TryExec`, while `_escapeDesktopValue` correctly escapes the backslashes of a Windows temp path. It passes on Linux. Do not "fix" it by weakening the assertion.

Rebuilding the shared library after touching `libXray/`:

```shell
cd ../libXray
CGO_ENABLED=1 CC=x86_64-w64-mingw32-gcc go build -trimpath -ldflags "-s -w" \
  -o windows_dll/libXray.dll -buildmode=c-shared ./cgo_bridge
cp windows_dll/libXray.dll ../app/windows/app/libXray.dll
```

`-s -w` is not optional: without it the library is 66 MB instead of 32 MB.

## Desktop process model

On Windows and Linux the Xray core is **not** in-process. `WindowsFfiApi` launches `bin/HyperClientCore.exe` (plain Xray) through `ShellExecuteEx` with verb `runas`, so TUN mode costs a UAC prompt. `libXray.dll` runs inside the app process and handles link parsing, ping, GeoData — and the embedded protocol engines.

Because restarting the core means another UAC prompt, **switching nodes does not restart it**. `XrayCoreApi` (`lib/service/xray/core_api.dart`) enables Xray's control interface in the generated config and drives it through the core binary's own `api` subcommand (`rmo` / `ado` / `rmrules` / `adrules`), which runs unelevated over loopback — no gRPC dependency in Dart. `VpnService._tryHotSwapNode` takes this path only when the run mode and routing mode are unchanged; anything else falls back to a full restart. Any failure falls back too: a half-configured tunnel is worse than an extra prompt.

Trade-off to keep in mind: while connected, the core listens on a loopback control port **with no authentication** — that is how Xray's API works. Tests assert it can only ever bind `127.0.0.1`.

## Config generation

`XrayRuntimeConfigService` (`lib/service/vpn/runtime_config.dart`) is the single place where the runtime Xray JSON is assembled; `_writeSelectedConfig` branches per `CoreConfigType`. Two ordering traps:

- `XrayRoutingModeFix.applyToXrayJson` **deletes `routing` entirely** in Global mode. Anything that must survive (such as the minewire bypass rule) has to be re-applied *after* the routing-mode fix, not added to the profile beforehand.
- Adding a `CoreConfigType` value is not enough to make a node visible. Two silent filters drop unknown types: `SubscriptionService._readConfigs` and the explicit type lists in `lib/core/db/dao/core_config.dart`. Exhaustive `switch`es are caught by the compiler; these filters are not.

## Non-standard protocols

Engines are Go packages compiled into `libXray` and exposed as methods in its `Invoke` registry (`startMinewire`, `stopMinewire`, `minewireState`), reached from Dart through `AppHostApi`. Each engine opens a loopback SOCKS5 listener that Xray dials as an ordinary `socks` outbound.

A protocol not written in Go cannot be embedded this way, and a sidecar process has no path to mobile. `protocols/README.md` documents the procedure for adding one.

In TUN mode an engine's own uplink is captured by the tunnel that leads back into it. `XrayMinewireBypass` adds a first-position routing rule for the resolved server IPs, tagged so the live core can drop it via `rmrules`. Server addresses are resolved **before** the tunnel comes up, since DNS afterwards may depend on the tunnel that is not working yet.

## Testing the VPN

**Never start the tunnel system-wide.** The machine runs another VPN through the system proxy that must not be disturbed, and the app's Proxy run mode rewrites system proxy settings.

Isolated verification instead:

- Chain check: run `bin/HyperClientCore.exe run -config <hand-written config>` with only a loopback SOCKS inbound, then `curl -x socks5h://127.0.0.1:<port> https://ifconfig.me/ip` and compare against the direct address.
- Protocol engine: call `libXray.dll` directly from Python via `ctypes` (`CGoInvoke` / `CGoFree`, `apiVersion: 2`). Engines open their local port immediately but connect in the background — poll `minewireState` for `connected`, not just for an accepting socket.

App state is faster to read from `%APPDATA%\HYPER CLIENT\HYPER CLIENT\db.sqlite` with Python `sqlite3` than by clicking through the UI. The elevated core cannot be driven by UI automation (Windows UIPI blocks input to elevated windows), so connection testing through TUN is the owner's job.

## Git and releases

Push straight to `main`; do not create branches. Every full version gets a GitHub release with binaries.

Two GitHub quirks cost real time here:

- An **em dash in a commit subject** makes `git push` fail with `remote rejected ... (Internal Server Error)`. Body text is fine. Keep subjects plain.
- `gh release create` fails with a false `workflow scope may be required`. Create via `gh api -X POST repos/<owner>/<repo>/releases --input <json>`, then upload the asset with `curl -X POST -H "Authorization: Bearer $(gh auth token)" --data-binary "@file" "https://uploads.github.com/repos/<owner>/<repo>/releases/<id>/assets?name=<name>"`.

Multi-line commit messages must be passed with `git commit -F <file>`; double quotes inside a PowerShell here-string break native argument passing.

## Fork boundaries

Auto-update, issue, and source links point at this fork, never upstream — the version is `0.1.0-beta.x`, so checking against upstream releases would offer to install a different application. The internal Dart package name stays `onexray` deliberately.

Bundled third-party engines are documented in `LICENSE-THIRD-PARTY.md`. Since they are compiled in rather than aggregated, the combined work ships under GPL-3.0 and their own notices must be preserved.
