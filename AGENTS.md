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

Cross-platform Flutter Xray-core client. [Current contracts](docs/README.md)
describe shipped behavior; Git history holds retired plans and progress logs.

### Engineering rules

- Dependencies flow `pages → service → core`. Services own business logic;
  custom page controllers extend `PageCubit` and expose Bloc state.
  Text, scroll, focus and third-party controllers remain UI resources.
- Prefer shared `lib/pages/theme/` changes: `AppTheme.appBarTheme`,
  `ThemeData.textTheme` / `AppTypography`, and `LucideIcons`. Keep typography
  out of individual pages. UI-only changes preserve behavior and data contracts.
- Verify dependency maintenance and SDK/platform compatibility before adoption:
  archive status, dated releases, substantive commits and maintainer responses.
- Keep `LIBXRAY_REF` in `.github/workflows/build.yml` set to `main` unless the
  user explicitly requests a different ref.
- Edit source models, ARB, Pigeon and FFI definitions, then regenerate outputs.
  Generated Dart, Kotlin, Swift, Drift, FFI and localization files are not sources.

### Read for the task

- Startup, permissions, navigation, UI or desktop windows: [App behavior](docs/app.md).
- Configuration, validation, connection lifecycle, native VPN or traffic:
  [Xray configuration](docs/xray-configuration.md).
- Database, Geodata, queues, updates or cleanup: [data management](docs/data-management.md).
- Import, subscriptions, age or sharing: [servers and sharing](docs/subscriptions-and-sharing.md).
- Backup protocol, restore or cloud storage: [backup](docs/backup.md).
- Local HTTP API, Android broadcasts or command authorization:
  [external interfaces](docs/external-interfaces.md).
- Packaging, signing or CI releases: [build scripts](build_scripts/README.md).
  Apple/Android release commands may upload to stores; they are not local checks.
- Visual parity: use the relevant [prototype source](../references/onexray-app-prototype/src/)
  and approved translations. Current App contracts take precedence over the prototype.
- Native bridge changes: inspect `pigeon/message.dart`, `lib/core/pigeon/`,
  Swift/Kotlin consumers and the [libXray API](../libXray/README.md#api).

### Agent skills

The upstream issue-tracker, triage-label and domain-doc skill configs under
`docs/agents/` describe `OneXray/OneXray` and are kept only to ease merges.
This fork does not use them: work goes straight to `main` of
`AnatomikPerq/hp-client` (see `CLAUDE.md`).

### Verification

All Flutter/Dart commands run serially across terminals and agents because
`.dart_tool` and native build state are shared. Use [verification](docs/validation.md)
for scenario selection, checks and platform-specific acceptance.

- Android emulator validation may start VPN. On macOS, do not start VPN or take
  screenshots; Windows/Linux builds and runs require their own hosts.
- Keep demos, fixtures and evidence in workspace `references/`, with isolated
  data and minimal setup; never validate against the developer's main database.
- Match checks to the change and run `git diff --check`. Documentation-only work
  needs path/link checks, not App tests. Report static, automated, device and
  release results separately. Commit, push and PR actions require user authority.
