# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Read `AGENTS.md` first.** It holds the fork preface and the upstream contract (layering `pages → service → core`, `ConnectionCoordinator`, generated files, UI conventions). The upstream docs under `docs/` describe upstream behavior; this file lists what the fork does differently and the operational rules that cost time to rediscover.

## This repo is one of two

`build_scripts/app/builder.py` resolves siblings from the **parent** of this checkout:

```
<workspace>/
  hp-client/   this repository (on the owner's machine: C:\Users\BADAB\Рабочий стол\hp-client)
  libXray/     OUR FORK: AnatomikPerq/libXray (upstream XTLS/libXray is remote `upstream`)
  output/      packaged builds land here
```

No Xray-core checkout is needed: libXray's `go.mod` pins the core, and the desktop Core `HyperClientCore(.exe)` is built from libXray's `desktop_bin/`. Changing a non-standard protocol, the desktop Core or the control API means editing **two repositories**: the Go side in `libXray/`, then rebuilding and copying artifacts into `windows/app/`.

`windows/app/` (`libXray.dll`, `HyperClientCore.exe`, `wintun.dll`), `linux/app/` and `assets/dat/` are gitignored build inputs. A fresh clone has none of them; see `readme/BUILD.md`.

## Commands

The Cyrillic path breaks Dart tooling (`flutter analyze` crashes, `dart run` misses its own package). Work through the ASCII junction `C:\Users\BADAB\dev\hp-client` **from PowerShell**; Git Bash resolves the junction back to the real path. Toolchains on the owner's machine:

```powershell
$env:Path = "C:\Users\BADAB\flutter\stable\bin;" + $env:Path
Set-Location C:\Users\BADAB\dev\hp-client
dart analyze lib test                                  # prefer over `flutter analyze`
flutter test                                           # whole suite, ~5 min
flutter test test/service/connect/live_swap_test.dart  # one file
flutter test <file> --plain-name "<test name>"         # one test
dart run build_runner build --delete-conflicting-outputs
dart run ffigen                                        # needs C:\Program Files\LLVM\bin\libclang.dll
flutter gen-l10n
```

`flutter test` reports **one expected failure on Windows**: `test/core/desktop_startup/linux_adapter_test.dart` asserts an unescaped `TryExec` for a POSIX path, while `_escapeDesktopValue` correctly escapes a Windows temp path. It passes on Linux. Do not weaken the assertion.

libXray builds with `GOTOOLCHAIN=auto` (go.mod wants 1.27+) and **llvm-mingw**, not w64devkit gcc (its big-obj objects break cgo). Exact commands are in `readme/BUILD.md`. `-s -w` is not optional.

ARB files: keys are added with a script that appends lines (see git history of `lib/l10n`); round-tripping through `json.dump` reformats `app_en.arb`/`app_fa.arb` wholesale.

## Desktop process model

On Windows and Linux the Xray core is a **separate process** `HyperClientCore`, found by exact process name (no PID files). `libXray.dll` runs inside the App: link parsing, ping, GeoData, minewire engines and `controlXray`.

`desktopCoreRunArguments` (`lib/core/ffi/base_ffi_api.dart`) builds its CLI:

- `-dns`/`-interface` only in TUN mode: they pin the Core's own DNS to the physical interface. System proxy mode passes neither.
- `-config-sha256`: the config lives in a directory any process of the user can write; the elevated Core refuses a config swapped after UAC.
- `-error-file`, and the log paths in the config, are opened by the Core first and refused if their final path is redirected (junction/symlink); the handles stay open to pin the paths.
- `-stop-file <run>/core.stop`: the Core exits gracefully once the file appears, so disconnecting an elevated Core needs **no second UAC prompt**. `WindowsExeFfiApi._stopGracefully` creates it and falls back to terminate (UAC) for Cores too old to know the flag.

TUN mode starts the Core elevated (`ShellExecuteEx runas`); system proxy mode starts it detached and unelevated. The installer is **per machine (Program Files)** so unprivileged processes cannot replace the binary that UAC elevates; the ZIP build does not have this protection.

### Live node switch

`LiveControl` (`lib/service/connect/live_control.dart`) adds to every desktop non-Raw config an `api` section **without `listen`**, a loopback SOCKS inbound `app-control` with a random per-session password, and a first routing rule `app-control → api`. `controlXray` in libXray dials the gRPC API through that inbound only; Xray's API has no authentication of its own.

`ConnectionCoordinator._trySwap` runs when only the selection changes (same policy, not Raw): it prepares the next runtime **reusing the running Core's ports, control password and start time**, checks `LiveControl.swappable` (only outbounds, routing rules and balancers may differ) and applies `LiveControl.operations`. Traps:

- Xray's `AddRule` without `append` **replaces every rule and balancer**; the operations therefore always send the full new routing, including the control rule.
- Removing the default (first) outbound leaves Xray without one until the next `addOutbound`; the first outbound is always replaced.
- A balancer with `fallbackTag` needs `observatory`, and `RoutingService` needs `stats`; App configs always have both, hand-written test configs often do not ("not all dependencies are resolved").

Any failure falls back to a full restart: a half-configured tunnel is worse than an extra prompt.

## System proxy mode

`PlatformPolicy.desktop` = `{runMode: tun|systemProxy, proxyPort: 10820}` (10808/10809 are the defaults of another common client, which runs on the owner's machine). A desktop `StartVpnRequest` **without `tun`** means proxy mode and its `socksPort` is the user-facing port; this keeps the native Kotlin/Swift model contract unchanged. The compiler turns `tunIn` into a loopback SOCKS/HTTP inbound (same tag, so traffic counters keep working) and drops `sockopt.interface`.

`SystemProxyManager` (`lib/core/system_proxy/`) saves the previous settings to `run/system-proxy.json` **before** applying and restores them on stop, on an unexpected Core exit and on the next App start, but only while the system still points at the App's port. Windows keeps a legacy registry copy (`ProxyEnable`, `ProxyServer`, `ProxyOverride`, `AutoConfigURL`) next to the WinINet view; other software may write only that copy and it may disagree with WinINet (it does on the owner's machine), so it is snapshotted and restored verbatim.

## Config generation

`ConnectionPreparation` (`lib/service/connect/preparation.dart`) resolves, allocates ports and calls the pure `ConnectionCompiler`. After compiling it applies two map transforms, in this order: the minewire bypass rules first in `routing.rules`, then `LiveControl.apply`, whose rule must end up above everything.

Fork deviations from the upstream Raw contract, enforced in `ConnectionCompiler._rawRuntimeMap` (Raw and Advanced templates):

- an inbound without `listen` gets `127.0.0.1` (Xray's default is every interface); an explicit outside `listen` on socks/http/mixed requires accounts;
- `env` keeps only `xray.*` keys (it becomes the Core's process environment);
- on desktop a Raw `api` section, its rules and API-only inbounds are dropped.

## Non-standard protocols

See `protocols/README.md`. minewire nodes are ordinary server rows whose outbound has `"protocol": "minewire"`; `MinewireRuntime` starts one engine per node in the App process before compiling and swaps the node for `socks` to its loopback port. Engines connect in the background: the runtime waits for `connected`, not just a listening port. Server addresses are resolved **before** the tunnel comes up. Engine ports are stored in the runtime metadata so a Core that survives an App restart gets its engines back on the same ports.

## Testing the VPN

**Never start the tunnel or the system proxy mode system-wide on the owner's machine.** It runs another VPN through the system proxy (`127.0.0.1:10808`) that must not be disturbed.

- **WinINet writes are never isolated.** Even a throwaway per-connection entry rewrites the legacy LAN registry values. Tests of `lib/core/system_proxy/windows.dart` are read-only; writes are covered with a fake backend.
- The environment has `HTTP_PROXY`/`HTTPS_PROXY=127.0.0.1:10808` and `NO_PROXY=localhost,127.0.0.1`: Dart `HttpClient` and Go follow them unless told otherwise, curl skips a `--socks5` proxy for 127.0.0.1 targets without `--noproxy ""`, and Python urllib bypasses proxies for localhost.
- Isolated chain check: run `HyperClientCore.exe run -config <file> [-config-sha256 …] [-stop-file …]` unelevated with only loopback inbounds, drive it through `libXray.dll` from Python `ctypes` (`CGoInvoke`/`CGoFree`, `apiVersion: 3`), and fetch a local HTTP target with `curl --noproxy "" --socks5-hostname`.

App state is faster to read from `%APPDATA%\HYPER CLIENT\HYPER CLIENT\db.sqlite` with Python `sqlite3` than through the UI. The elevated Core cannot be driven by UI automation (UIPI), so connection testing through TUN and the real system proxy is the owner's job.

## Git and releases

Push straight to `main`; do not create branches. Every full version gets a GitHub release with binaries. Merging upstream: `git fetch upstream` in both repositories; in the app, resolve conflicts toward upstream's architecture and re-port fork behavior (this file lists it).

Two GitHub quirks cost real time here:

- An **em dash in a commit subject** makes `git push` fail with `remote rejected ... (Internal Server Error)`. Body text is fine. Keep subjects plain.
- `gh release create` fails with a false `workflow scope may be required`. Create via `gh api -X POST repos/<owner>/<repo>/releases --input <json>`, then upload the asset with `curl -X POST -H "Authorization: Bearer $(gh auth token)" --data-binary "@file" "https://uploads.github.com/repos/<owner>/<repo>/releases/<id>/assets?name=<name>"`.

Multi-line commit messages must be passed with `git commit -F <file>`; double quotes inside a PowerShell here-string break native argument passing.

## Fork boundaries

Auto-update, issue, source, documentation and privacy links point at this fork, never upstream; the update page URL from the API is accepted only for this repository's release pages. The version is `0.1.0-beta.x`. The internal Dart package name stays `onexray`, and internal identifiers keep upstream names to keep merges cheap; only user-visible text is rebranded. The upstream donation screen was removed on purpose (it showed the upstream author's wallet).

Bundled third-party engines are documented in `LICENSE-THIRD-PARTY.md`. Since they are compiled in rather than aggregated, the combined work ships under GPL-3.0 and their own notices must be preserved.
