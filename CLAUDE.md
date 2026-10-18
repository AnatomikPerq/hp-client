# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Read `AGENTS.md` first.** It holds the fork preface and the upstream contract (layering `pages → service → core`, `ConnectionCoordinator`, generated files, UI conventions). The upstream docs under `docs/` describe upstream behavior; this file lists what the fork does differently and the operational rules that cost time to rediscover.

## This repo is one of two

`build_scripts/app/builder.py` resolves siblings from the **parent** of this checkout:

```
<workspace>/
  hp-client/   this repository (on the owner's machine: C:\Users\BADAB\Рабочий стол\projects\hp-client)
  libXray/     OUR FORK: AnatomikPerq/libXray (upstream XTLS/libXray is remote `upstream`)
  output/      packaged builds land here
```

No Xray-core checkout is needed: libXray's `go.mod` pins the core, and the desktop Core `HyperClientCore(.exe)` is built from libXray's `desktop_bin/`. Changing a non-standard protocol, the desktop Core or the control API means editing **two repositories**: the Go side in `libXray/`, then rebuilding and copying artifacts into `windows/app/`.

`windows/app/` (`libXray.dll`, `HyperClientCore.exe`, `wintun.dll`), `linux/app/` and `assets/dat/` are gitignored build inputs. A fresh clone has none of them; see `readme/BUILD.md`.

## Commands

The Cyrillic path breaks Dart tooling (`flutter analyze` crashes, `dart run` misses its own package). Work through the ASCII junction `C:\Users\BADAB\dev\hp-client` **from PowerShell**; Git Bash resolves the junction back to the real path. If the workspace moves, re-point the junctions (`dev\hp-client`, `dev\libXray`) with `New-Item -ItemType Junction`; a dangling one makes every Dart command fail. Toolchains on the owner's machine:

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

Exit watching is upstream's `CoreProcessMonitor` (`lib/core/ffi/core_process_monitor.dart`) on Windows and Linux. The fork hooks into it from the FFI APIs: a `disconnected` it reports (the Core exited on its own) and a start that finds no Core both restore the system proxy, and a stop restores it first, then writes `core.stop`, then terminates.

Windows TUN inbounds carry `autoSystemWfpBlockLeak: ["dns"]` (upstream #209): the Core blocks DNS that leaves outside the TUN, except its own, with WFP filters. Not yet checked live together with minewire engines.

### Live node switch

`LiveControl` (`lib/service/connect/live_control.dart`) adds to every desktop non-Raw config an `api` section **without `listen`**, a loopback SOCKS inbound `app-control` with a random per-session password, and a first routing rule `app-control → api`. `controlXray` in libXray dials the gRPC API through that inbound only; Xray's API has no authentication of its own.

`ConnectionCoordinator._trySwap` runs when only the selection changes (same policy, not Raw): it prepares the next runtime **reusing the running Core's ports, control password and start time**, checks `LiveControl.swappable` (only outbounds, routing rules and balancers may differ) and applies `LiveControl.operations`. Traps:

- Xray's `AddRule` without `append` **replaces every rule and balancer**; the operations therefore always send the full new routing, including the control rule.
- Removing the default (first) outbound leaves Xray without one until the next `addOutbound`; the first outbound is always replaced.
- A balancer with `fallbackTag` needs `observatory`, and `RoutingService` needs `stats`; App configs always have both, hand-written test configs often do not ("not all dependencies are resolved").
- The `proxy` balancer's `fallbackTag` is its own first node (`proxyFallbackTag`), **never `direct`**. Between `removeOutbound` and `addOutbound` of the same tag the balancer matches nothing and takes the fallback; Xray drops a connection routed to a missing tag, so the window fails closed. With `direct` it sent tunnel DNS, DoT and smart-mode proxy traffic out from the real address (verified on the real Core with loopback targets).

Any failure falls back to a full restart: a half-configured tunnel is worse than an extra prompt.

## Connection health and logs

`ConnectionHealthMonitor` (`lib/service/connect/health.dart`, desktop) exists because the coordinator says "connected" while the Core runs, even when nothing gets through (17.10: a minewire engine lost its session, nothing in the UI or any log showed it). 5 s after a connection or node switch and then every 30 s it runs `LivePingProbe` along the path system traffic takes and reads `minewireState` for the runtime's engines. Three failures in a row (10 s apart) make it `unreachable`: Home shows "No connection" with the reason, the tray tooltip says so, one notification is posted; the first success clears it. A verdict is keyed by runtime identity **and node ids** (`ConnectionHealth.keyOf`): a live switch keeps the identity, not the verdict. It is a separate `ValueNotifier`, not a `ConnectionView` field (those are built in a dozen places in the coordinator).

Release builds keep two logs in the run directory, rotated at 1 MiB to `*.1`:

- `app.log` via `AppLog` (`lib/core/tools/app_log.dart`): connection failures by reason code and error type, a live switch falling back to a restart, a VPN that stopped without a command, health changes. **Only short explicit messages**: `ygLogger` output (which prints nothing in release) may carry configs, links and stack traces and must never be routed there.
- `minewire.log`: runtime engines get `logFile` in `startMinewire`; libXray appends their logins, drops, errors and yamux keepalive failures, each line tagged with the engine's port. Ping engines pass none.

## System proxy mode

`PlatformPolicy.desktop` = `{runMode: tun|systemProxy, proxyPort: 10820}` (10808/10809 are the defaults of another common client, which runs on the owner's machine). A desktop `StartVpnRequest` **without `tun`** means proxy mode and its `socksPort` is the user-facing port; this keeps the native Kotlin/Swift model contract unchanged. The compiler turns `tunIn` into a loopback SOCKS/HTTP inbound (same tag, so traffic counters keep working) and drops `sockopt.interface`.

`SystemProxyManager` (`lib/core/system_proxy/`) saves the previous settings to `run/system-proxy.json` **before** applying and restores them on stop, on an unexpected Core exit and on the next App start, but only while the system still points at the App's port. Windows keeps a legacy registry copy (`ProxyEnable`, `ProxyServer`, `ProxyOverride`, `AutoConfigURL`) next to the WinINet view; other software may write only that copy and it may disagree with WinINet (it does on the owner's machine), so it is snapshotted and restored verbatim.

The exception list is `systemProxyDefaultBypass` (local networks, `<local>` last) plus the user's hosts from Settings → Advanced → VPN tunnel (`desktop.proxyBypass` in `PlatformPolicy`). They reach the FFI layer as `StartVpnRequest.systemProxyBypass`, a desktop-only optional field that mobile requests never carry. Changing them in proxy mode is a runtime change (reconnect without UAC).

## Config generation

`ConnectionPreparation` (`lib/service/connect/preparation.dart`) resolves, allocates ports and calls the pure `ConnectionCompiler`. After compiling it applies map transforms, in this order: the minewire bypass rules first in `routing.rules`, `MinewireRuntime.applyTcpDns` when a minewire engine is in the runtime, then `LiveControl.apply`, whose rule must end up above everything.

In TUN mode `_applyOutboundPolicy` binds every outbound to the physical interface **except one whose servers are all on loopback** (`outboundDialsLoopback`, a minewire engine): Windows rejects a dial to `127.0.0.1` bound to `Ethernet` ("not valid in its context"), which left TUN with minewire completely dead. For the same reason Fragment (upstream #213, `XrayFragment.connectEntries`) never sets `dialerProxy: fragment` on a loopback entry.

LAN proxy sharing (upstream #213, Settings → Advanced → Xray) is a SOCKS5/HTTP inbound on `0.0.0.0`. Upstream shares it without authentication; the fork requires an account (`lanProxy.user`/`password` in `PlatformPolicy`, made once when sharing is turned on, shown with copy buttons on the sharing page). `RuntimeOptions` and `createLanProxyInbound` refuse sharing without one.

Fork deviations from the upstream Raw contract, enforced in `ConnectionCompiler._rawRuntimeMap` (Raw and Advanced templates):

- an inbound without `listen` gets `127.0.0.1` (Xray's default is every interface); an explicit outside `listen` on socks/http/mixed requires accounts;
- `env` keeps only `xray.*` keys (it becomes the Core's process environment);
- on desktop a Raw `api` section, its rules and API-only inbounds are dropped.

## JSON subscriptions

Some providers serve a JSON array of full Xray client configs instead of links (v2rayN/Happ style, Remnawave's JSON format, the owner's home server for INCY). `xrayConfigOutbounds` (`lib/service/shared/share/xray_config_share.dart`), called first in `XrayShareReader.parseShareText`, turns each config's proxy outbound into an ordinary node named after its `remarks`, **keeping `mux`**, which VLESS links cannot carry. The provider's inbounds, DNS, routing and balancers are dropped, so the App's own routing, live switch and health check apply. Outbounds that need another one of their config (`dialerProxy`, `proxySettings`) are skipped. Each node is checked with `testXray` (`XrayValidation.nodes`), **not** `convertShareLinksToXrayJson`: libXray's projection drops `mux` and other fields. A bare `{"outbounds": [...]}` still goes to libXray; a single full config pasted into import is still a Raw configuration.

## Non-standard protocols

See `protocols/README.md`. minewire nodes are ordinary server rows whose outbound has `"protocol": "minewire"`; `MinewireRuntime` starts one engine per node in the App process before compiling and swaps the node for `socks` to its loopback port. Engines connect in the background: the runtime waits for `connected`, not just a listening port. Server addresses are resolved **before** the tunnel comes up. Engine ports are stored in the runtime metadata so a Core that survives an App restart gets its engines back on the same ports.

minewire carries **TCP only** (the engine refuses SOCKS UDP, the server has no UDP). DNS that may cross it must be TCP: `applyTcpDns` turns plain-IP DNS servers (except `app-dns-direct`) into `tcp://` and sets `network: tcp` on a `dns` outbound not dialed through `direct`. With UDP, every Xray lookup waited out the 4 s DNS timeout in proxy mode and the system resolver got no answer at all in TUN. In TUN the engines also bind their uplinks to the physical interface (`MinewireRuntime.uplinkInterface`, `startMinewire.interface`). A minewire node's ping is a throwaway engine plus the ordinary libXray probe through it, with the session setup added (`MinewirePingProbe`); a bare TCP connect always won the automatic selection.

The engine itself is a patched copy of upstream's `src/core` in `libXray/third_party/minewire-cli` (`replace` in libXray's `go.mod`, changes in its `PATCHES.md`): whole frames per write, an injectable dialer, no process-killing panics on malformed frames. The wire protocol is unchanged.

### AmneziaWG

Unlike minewire, AmneziaWG is an outbound **inside the Core**: `"protocol": "amneziawg"` is `libXray/amneziawg`, Xray's WireGuard client ported onto `amneziawg-go/v3` (its README lists every difference). So UDP, live switch, balancers, ping, stats and the health check need nothing special. Only v3 knows the keys of current AmneziaWG 2.0 configs (S3/S4, H ranges, `HeaderProtectionKey`, timing ranges, `RandomTrailers`, `DisableCookies`); 1.x and `master` do not, and v3 dropped J1-J3/Itime. Things that cost time:

- Xray's outbound JSON loader is unexported; `amneziawg.go` reaches `infra/conf.outboundConfigLoader` with `go:linkname` and its `cache` field with `reflect`/`unsafe`. `TestXrayLoadsTheAmneziawgProtocol` fails if an Xray bump changes them. `config.pb.go` is regenerated with `go run .` in `amneziawg/protogen` (own module, no protoc).
- amneziawg-go's TUN reader computes the room for the S4 padding *before* it blocks in `Read`, and it starts with the device, before any keys: the first packet went out unpadded and the server dropped it (a first in-tunnel DNS query waited 5 s, a datagram was lost for good). `netTun.WakeReader` makes `Read` return nothing once after the keys are set.
- The device keys are set in `NewClient`, so a bad I1 tag or overlapping headers fail `testXray`; peers are set on the first connection.
- The server's domain goes to the system resolver (pinned to the physical interface in TUN). Xray's own `wireguard` asks Xray's DNS, which in the App routes through the proxy, into the tunnel that is not up yet; that is also why plain WireGuard from `.conf` and links without `reserved` is imported as `amneziawg` without keys (labeled WIREGUARD by `outboundTags`). WARP links with `reserved` stay Xray `wireguard`.
- Links (`awg://` = base64 `.conf`, AmneziaVPN `vpn://` = Qt-compressed JSON, `wireguard://`/`wg://`) and pasted `.conf` blocks are parsed in Dart (`lib/service/amneziawg/`) before libXray, like `mw://`, and every node is checked with `testXray` like JSON subscription nodes. A picked `.conf` file becomes an `awg://` link named after the file.
- Fragment skips WireGuard and AmneziaWG (UDP, no TLS hello); `outboundDialsLoopback` reads their `peers[].endpoint`, never `settings.address` (their own side of the tunnel).

Checks: `go test ./amneziawg/` runs an AmneziaWG server device in the test process and carries UDP and TCP from a Core. A real node was checked with the isolated chain (unelevated Core, loopback SOCKS and a `tunnel` inbound to `1.1.1.1:53` for UDP) and with `pingBatch` from Python `ctypes`; TUN and system proxy remain the owner's.

## UI layout

The fork reworked navigation for usability after tunnel clients like INCY; the navigation part of `docs/app.md` still describes upstream's four tabs.

- **Window caption** (Windows, Linux): `DesktopCaption` (`lib/pages/main/desktop_caption.dart`) replaces window_manager's `WindowCaption`, like INCY: brand in `palette.brand`, version, thin Lucide buttons. It sits above the Navigator, so it wraps itself in a `Material` (otherwise text inherits `MaterialApp`'s debug style) and cannot use tooltips. On Windows 11 `WindowService.updateFrameColor` sets the DWM border color instead of the system accent. The sidebar hides its version where the caption shows it.
- **Three tabs**: Home (`AppPrimaryDestination.connect`, path `/connect`), Servers, Settings. Advanced is no longer a tab: Settings → Advanced pushes `AppPageDestination.advanced` with `extra` 0 (VPN tunnel) or 1 (Xray). The desktop sidebar collapses to icons (`_sidebarCollapsed`, in memory only).
- **Home** (`lib/pages/connect/view.dart`) has no app bar: TUN/proxy pill, ↑ speed · session clock · ↓ speed, the orb (the accessible connect control), the selected node with its flag, "Check connection" (`LivePingProbe`), the routing pill, Add / Paste / All servers, then `HomeServerList`: Automatic, favorites and the subscription holding the current selection. `ConnectPage` owns a second `ServersController` for that list, so rows, menus and pings behave exactly as on Servers. Speeds rebuild only through `trafficBuilder`; `ConnectView` itself is filtered by `sameContentAs`.
- **Servers** is one scrolling list of collapsible `ServerGroupCard`s (no master/detail pane) with search, by-subscription/by-location toggle and filter chips (favorites, primary protocol). Collapse state and filters live in `ServersPageState`.
- **Selecting a node never asks to reconnect**: `ServersController.choose` passes `confirmReconnect: false` to `applyConnectionChange`, relying on the live swap (and the coordinator's restart fallback). Tray changes and routing-method changes still confirm.
- `ServerNodeTile` is the one node row. Node menus are popups at the `…` button on desktop and the existing bottom-sheet dialogs on mobile (`menus_test.dart` covers the latter); favorite moved into the menu (`ServerAction.favorite`).
- **Node icons**: the first emoji of a server or subscription name is its icon (`splitNameEmoji`, `NameIcon`); names without one show the flag of the measured `countryCode`, then a globe. Grouping by location still uses only the measured code. The code comes from `pingBatch`'s `locationUrl` probe, which **upstream removed** (libXray #165, and app #220 drops the `country_code` column without a merge conflict): the fork keeps both, and any upstream merge must keep them. Images are Twemoji 15.1 (CC-BY 4.0, see `LICENSE-THIRD-PARTY.md`): `assets/emoji/<hex code points without FE0F>.png` and `assets/flags/<iso>.png`, built by `tool/twemoji.py`, which also writes the key table `twemoji_keys.dart`. Windows has no glyphs for regional-indicator flags and prints "NL", so flags are removed from the text; other emoji stay. Both folders are excluded from `flutter_gen`.
- **New subscription name**: the add form fills the empty name with the provider's `Profile-Title` (`SubscriptionService.readTitle`, 500 ms after typing stops) and replaces it only while the user has not edited it. Widget tests that type a link into an empty form must stub `readSubscriptionTitle` and pump past the delay.
- **Tray** (`lib/service/shared/menu/tray/service.dart`): upstream's `TrayPlatform` on tray_manager 0.8 (nativeapi), which opens the menu from a hidden host window and initializes the notify icon data; the 0.5.3 workarounds (`bringAppToFront`, a tooltip set right after the first icon against garbage text) are gone. The fork adds `TrayPlatform.setToolTip` for its tooltip ("HYPER CLIENT · state · node", or "No connection"); icon and tooltip are set only when they change. On Windows the left button opens the App and only the right one opens the menu (upstream opens it on either). nativeapi calls its `isolateLocal` listeners synchronously from the Windows message loop, outside any engine task, and Flutter drains microtasks only after its own tasks: everything after the first `await` in a handler waited for the next engine task, so with the window hidden and no VPN running a click did nothing and the menu popped up later at random (on a click at the taskbar or Start menu). `_resume` in `platform.dart` runs each native event handler and then `Timer.run`, which is such a task; `_openMenu` also drops a request older than 2 s. Tests drive a fake `TrayPlatform`, not the method channel.
- **Rebuild costs**: `AppTheme.material`/`shad` return cached instances. A fresh `ThemeData` never equals the last (its `WidgetStateProperty` closures have no `==`), so `MaterialApp`'s `AnimatedTheme` animated 200 ms on every rebuild; the shell's `BlocBuilder<AppEventBus>` also rebuilds only on theme or language now. `ServerCatalog.copyWith` reuses parsed `ServerDisplay`s for rows whose data did not change (a ping only writes delay and location). libXray calls run on a worker isolate; `pingBatch` has its own so a batch does not hold up Connect, a live switch or minewire state.
- Visual check without running the App or computer use: a throwaway widget test can load real fonts with `FontLoader` (Geist and Lucide from the pub cache, Segoe UI for Cyrillic), `precacheImage` the flags and emoji inside `tester.runAsync`, and write `RenderRepaintBoundary.toImage()` to PNG. Text in buttons inherits no family and still renders as Ahem boxes there. Do not leave such a test in `test/`: CI runs everything.

## Testing the VPN

**Never start the tunnel or the system proxy mode system-wide on the owner's machine.** It runs another VPN through the system proxy (`127.0.0.1:10808`) that must not be disturbed.

- **WinINet writes are never isolated.** Even a throwaway per-connection entry rewrites the legacy LAN registry values. Tests of `lib/core/system_proxy/windows.dart` are read-only; writes are covered with a fake backend.
- The environment has `HTTP_PROXY`/`HTTPS_PROXY=127.0.0.1:10808` and `NO_PROXY=localhost,127.0.0.1`: Dart `HttpClient` and Go follow them unless told otherwise, curl skips a `--socks5` proxy for 127.0.0.1 targets without `--noproxy ""`, and Python urllib bypasses proxies for localhost.
- Isolated chain check: run `HyperClientCore.exe run -config <file> [-config-sha256 …] [-stop-file …]` unelevated with only loopback inbounds, drive it through `libXray.dll` from Python `ctypes` (`CGoInvoke`/`CGoFree`, `apiVersion: 3`), and fetch a local HTTP target with `curl --noproxy "" --socks5-hostname`.

App state is faster to read from `%APPDATA%\HYPER CLIENT\HYPER CLIENT\db.sqlite` with Python `sqlite3` than through the UI. The elevated Core cannot be driven by UI automation (UIPI), so connection testing through TUN and the real system proxy is the owner's job.

## Git and releases

Push straight to `main`; do not create branches. Every full version gets a GitHub release with binaries. Merging upstream: `git fetch upstream` in both repositories; in the app, resolve conflicts toward upstream's architecture and re-port fork behavior (this file lists it). Merge in stages (one merge commit per upstream PR group, tests between them); a detached worktree at an ASCII path (`git worktree add --detach C:\Users\BADAB\dev\hp-merge HEAD`, then fast-forward `main`) keeps the main tree free for builds and needs no branch.

The app is merged up to upstream `b88e456` (#218). **Upstream #220 (Remnawave configurations) and everything after it wait** until the fork has its own resilient routing (switching away from a dead node) and a kill switch (`ROADMAP.md`), by the owner's decision of 18.10.2026: #220 runs the provider's whole config, which bypasses the App's routing, live switch and leak protections. What the fork needed from it, JSON subscriptions with mux, is done its own way (see above). Upstream's build scripts, workflows and installer are never taken: the fork's keep the wintun hash check and provenance receipts.

Two GitHub quirks cost real time here:

- An **em dash in a commit subject** makes `git push` fail with `remote rejected ... (Internal Server Error)`. Body text is fine. Keep subjects plain.
- `gh release create` fails with a false `workflow scope may be required`. Create via `gh api -X POST repos/<owner>/<repo>/releases --input <json>`, then upload the asset with `curl -X POST -H "Authorization: Bearer $(gh auth token)" --data-binary "@file" "https://uploads.github.com/repos/<owner>/<repo>/releases/<id>/assets?name=<name>"`.

Publish releases as regular releases, not pre-releases: the in-app update check asks `/releases/latest`, which GitHub never answers with a pre-release (until beta.4 it returned 404, so no update was ever offered). Tag the exact commit the binaries were built from; the provenance file in `output/` records it. CI has two workflows. `validate.yml` runs on every push to `main` and on pull requests (Linux: build_scripts tests, generated sources, format, layer check, analyze, `flutter test`). `build.yml` builds the Windows x64 installer and ZIP on a `v*` tag or by hand (`workflow_dispatch`, optional libXray ref) and only uploads workflow artifacts plus the provenance receipt; it refuses a tag that does not match the pubspec version. Creating a release creates its tag, so every release gets an independent CI rebuild. Upstream's publish, Microsoft Store and winget workflows were removed: they published to upstream's listings and to pre-releases.

Multi-line commit messages must be passed with `git commit -F <file>`; double quotes inside a PowerShell here-string break native argument passing.

## Fork boundaries

Auto-update, issue, source, documentation and privacy links point at this fork, never upstream; the update page URL from the API is accepted only for this repository's release pages. The version is `0.1.0-beta.x`. The internal Dart package name stays `onexray`, and internal identifiers keep upstream names to keep merges cheap; only user-visible text is rebranded. The upstream donation screen was removed on purpose (it showed the upstream author's wallet).

Bundled third-party engines are documented in `LICENSE-THIRD-PARTY.md`. Since they are compiled in rather than aggregated, the combined work ships under GPL-3.0 and their own notices must be preserved.
