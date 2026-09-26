# HYPER CLIENT

HYPER CLIENT is a Flutter VPN client forked from OneXray and developed
independently; the upstream name must not appear in product-facing text.
Releases are built for Windows x64 (EXE mode only; the upstream MSIX/VCore mode
is not shipped). Read `CLAUDE.md` for the multi-repository layout, the desktop
process model and fork-specific operational rules.

Beyond Xray-core protocols, the client hosts **non-standard transports**. Their
engines are compiled **into our libXray fork** (`AnatomikPerq/libXray`) and ship
inside the shared library, not as sidecar executables: Android and iOS cannot
spawn a bundled executable. Their links are parsed **in Dart, before libXray**,
because Xray-core does not know those schemes. See `protocols/README.md`.

The internal Dart package name stays `onexray`, and internal identifiers keep
upstream names (`OneXrayAppLinkParser`, `ONEXRAY_WINDOWS_MODE`, …). Renaming
them would rewrite the tree and conflict with every upstream merge; rename only
what users see.

The rest of this file is the upstream contract and applies unchanged unless
`CLAUDE.md` says otherwise. Documents under `docs/` describe upstream behavior;
fork additions are listed in `CLAUDE.md`.

## Upstream contract

Cross-platform Flutter Xray-core client. Current contracts are indexed in
[docs](docs/README.md); old refactor plans and progress logs are historical evidence.

### Engineering boundaries

- Dependencies flow `pages → service → core`, never backwards. Services own
  business logic; pages compose UI and bind callbacks to their controllers.
- Custom page controllers extend `PageCubit`; use Bloc for observable state,
  including dialogs, loading and expansion. Text/scroll/focus and third-party
  controllers are UI resources, not a second state-management system.
- `ServiceManager` owns normal startup, storage, Geodata and platform/permission
  checks; normal startup must not depend on Setup. Establish a valid absolute
  native data root before storage access.
- Route connection actions, shortcuts and tray actions through
  `ConnectionCoordinator`. Native VPN state is authoritative. After a failed
  stop/start transition, do not restart the previous connection.
  Android Widget/Tile may restart the existing complete `run/start.json` directly
  in the VPN service; missing inputs or permissions fall back to the App.
- Smart and ordinary Custom configuration use `XrayJson`; Advanced Custom
  templates and full Raw retain user JSON through separate Map compilation.
  Database JSON stays Base64; preserve legacy
  Raw rows above the new-item limit and keep retired Profile/Multi-node rows
  outside product flows.
- Current-session traffic and speed come only from Xray metrics HTTP. Visible
  connection pages share one foreground App sampler; Android's VPN
  service owns notification/widget sampling independently of Flutter. Do not
  persist traffic or maintain device totals.
  iOS simulator SOCKS adaptation belongs in Swift, not App UI or business state.
- Prefer shared theme changes in `lib/pages/theme/`. Use `AppTheme.appBarTheme`
  for AppBar styling, `ThemeData.textTheme`/`AppTypography` for typography, and
  `LucideIcons` for icons. Pages must not hardcode font sizes, families, letter spacing
  or line heights; override AppBar styling only when the theme cannot express it.
- UI-only work preserves fields, semantics, platform visibility, persistence
  and validation unless the user explicitly requests those changes.
- Before adopting or replacing a third-party dependency, verify archive status,
  dated releases, substantive commits and maintainer responses to
  issues/PRs, alongside current SDK/platform compatibility. Record the evidence
  and maintenance risks; popularity or a working demo alone is insufficient.
- Edit source models, ARB files, `pigeon/message.dart` or FFI definitions, then
  regenerate the corresponding outputs. Never hand-edit generated Dart,
  Kotlin, Swift, Drift, FFI or localization code. ARB files are source files.

### Read for the task

- Startup, recovery or permissions: [app startup](docs/app-startup.md).
- Configuration, Raw JSON, connection lifecycle or statistics:
  [Xray configuration](docs/xray-configuration.md).
- Database, migration, Geodata or updates:
  [data management](docs/data-management.md).
- Import, links or sharing: [subscriptions and sharing](docs/subscriptions-and-sharing.md);
  for age keys/decryption, also read [age subscriptions](docs/age-encrypted-subscriptions.md).
- UI/navigation: [navigation](docs/app-navigation.md). For requested visual parity,
  consult the relevant [prototype source](../references/onexray-app-prototype/src/)
  and reuse approved translations for unchanged features. The old
  [product model](../references/onexray-app-prototype/PRODUCT-MODEL.md) is historical:
  current App contracts take precedence; do not restore retired features from it.
- Native contracts: `lib/core/pigeon/`, `pigeon/message.dart`, `swift/`,
  Android's Kotlin bridge, and [libXray API](../libXray/README.md#api).
  Before packaging, read [build scripts](build_scripts/README.md) and, for Windows,
  [Windows builds](docs/windows-build.md). Apple/Android release scripts may
  upload to stores; they are not local validation commands.

### Agent skills

The upstream issue-tracker, triage-label and domain-doc skill configs under
`docs/agents/` describe `OneXray/OneXray` and are kept only to ease merges.
This fork does not use them: work goes straight to `main` of
`AnatomikPerq/hp-client` (see `CLAUDE.md`).

### Verification

All `flutter` and `dart` commands must run serially across terminals, tool calls
and agents: they share `.dart_tool` and native-asset state.

- Match generation/checks to the change; available checks are in
  [verification](docs/refactor-validation.md#自动验证). Verify changed native
  contracts with the relevant supported platform build.
- UI validation follows [platform limits](docs/refactor-validation.md#平台边界):
  Android emulator may start VPN; macOS must not start VPN or take screenshots.
  Skip Windows/Linux builds and runs on the current macOS host; record skips.
- Keep demos and evidence in workspace `references/`, not system temp.
  Use isolated test data, never the developer's main database; keep demos minimal.
- Run `git diff --check`. Documentation-only work needs path/link checks,
  not Flutter tests or native builds. Broaden or repeat verification only for
  new changes, failures or unresolved concerns; distinguish static checks from
  actual device/VPN validation.
