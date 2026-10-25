# Сборка HYPER CLIENT

## Раскладка рабочей папки

`build_scripts/app/builder.py` ищет соседей от **родителя** этого
репозитория, поэтому раскладка обязательна именно такая:

```
<рабочая папка>/
  hp-client/   — этот репозиторий (у владельца: Рабочий стол\projects)
  libXray/     — НАШ форк: github.com/AnatomikPerq/libXray
  output/      — сюда складываются готовые пакеты
```

Отдельный checkout Xray-core больше не нужен: версию ядра задаёт `go.mod`
форка libXray, а десктопное ядро `HyperClientCore` собирается из его же
`desktop_bin/`. libXray именно наш форк, а не апстрим: в него встроены
нестандартные протоколы и защищённое управление ядром (см.
[protocols/README.md](../protocols/README.md)). Апстрим XTLS/libXray
подключён вторым remote под именем `upstream`.

## Инструменты

| Что | Где на машине владельца | Зачем |
|---|---|---|
| Flutter stable | `C:\Users\BADAB\flutter\stable` | приложение; `git clone --depth 1 --branch stable` |
| Go | `C:\Program Files\Go` | libXray и ядро. `go.mod` требует go 1.27+, при `GOTOOLCHAIN=auto` нужный тулчейн скачивается сам |
| llvm-mingw | `C:\Users\BADAB\toolchains\llvm-mingw-*-ucrt-x86_64` | `gcc` для c-shared `libXray.dll`. **gcc из w64devkit не годится**: он по умолчанию пишет объектники big-obj, которые cgo не читает («cannot parse gcc output … as ELF, Mach-O, PE») |
| LLVM | `C:\Program Files\LLVM` | `dart run ffigen` ищет `bin\libclang.dll` строго там |
| Visual Studio Build Tools | 2026 с MSVC 14.50 | `flutter build windows`; нужен workload C++ |
| Inno Setup 6.7.3 | `C:\Users\BADAB\toolchains\inno-setup` (поставлен с `/CURRENTUSER`, без прав администратора); путь в `INNO_SETUP_PATH` | установщик (через Fastforge) |
| Fastforge | `%LOCALAPPDATA%\Pub\Cache\bin` (`dart pub global activate fastforge`) | упаковка EXE и ZIP; каталог должен быть в `PATH` |

## Путь с кириллицей

Путь `…\Рабочий стол\projects\hp-client` ломает Dart-тулинг: `flutter analyze`
падает на разборе JSON анализатора, `dart run` пишет «package_config.json
did not contain its own root package». Рецепт — ASCII-junction и
**PowerShell** (bash из Git разворачивает junction обратно в настоящий путь):

```powershell
New-Item -ItemType Junction -Path C:\Users\BADAB\dev\hp-client -Target 'C:\Users\BADAB\Рабочий стол\projects\hp-client'
New-Item -ItemType Junction -Path C:\Users\BADAB\dev\libXray   -Target 'C:\Users\BADAB\Рабочий стол\projects\libXray'
Set-Location C:\Users\BADAB\dev\hp-client
$env:Path = "C:\Users\BADAB\flutter\stable\bin;" + $env:Path
flutter pub get
dart run ffigen                       # lib/core/ffi/generated_bindings.dart, в .gitignore
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

## Артефакты ядра

```shell
cd ../libXray
export GOTOOLCHAIN=auto PATH="/c/Users/BADAB/toolchains/llvm-mingw-20260922-ucrt-x86_64/bin:$PATH"

# библиотека в процессе приложения: разбор ссылок, пинг, minewire, controlXray
CGO_ENABLED=1 CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ \
  go build -trimpath -ldflags "-s -w" -o windows_dll/libXray.dll -buildmode=c-shared ./cgo_bridge

# десктопное ядро (отдельный процесс; в TUN запускается с правами администратора)
CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags "-s -w -buildid=" -o bin/xray.exe ./desktop_bin

# GeoData для assets/dat
go run download_geo/main.go

cp windows_dll/libXray.dll       ../hp-client/windows/app/libXray.dll
cp bin/xray.exe                  ../hp-client/windows/app/HyperClientCore.exe
mkdir -p ../hp-client/assets/dat && cp dat/* ../hp-client/assets/dat/
```

`-s -w` не опционален: без него библиотека вдвое тяжелее. `wintun.dll` берут
из официального `wintun-0.14.1.zip` (SHA-256 зашит в
`build_scripts/app/windows.py`), только `bin/amd64/wintun.dll`.

`windows/app/`, `linux/app/` и `assets/dat/` в `.gitignore`: это артефакты
сборки, чистый клон их не содержит.

## Проверка

```powershell
dart analyze lib test
flutter test          # одно ожидаемое падение на Windows: linux_adapter_test
flutter build windows --release
```

В libXray: `go test ./control/ ./desktop_bin/ ./minewire/ ./amneziawg/ .` (тест `dns`
падает на машинах, где у первого интерфейса нет маршрута до 8.8.8.8, — это
апстрим).

## Релизная сборка

```powershell
$env:Path = "C:\Users\BADAB\flutter\stable\bin;C:\Program Files\Go\bin;C:\Users\BADAB\toolchains\llvm-mingw-20260922-ucrt-x86_64\bin;$env:LOCALAPPDATA\Pub\Cache\bin;" + $env:Path
$env:GOTOOLCHAIN = "auto"
$env:BUILD_NUMBER = "4"          # версия станет <marketing>+404: база 400 из config.py
$env:INNO_SETUP_PATH = "C:\Users\BADAB\toolchains\inno-setup"
$env:PYTHONUTF8 = "1"
Set-Location C:\Users\BADAB\dev\hp-client
python build_scripts/main.py HyperClient windows --windows-mode exe
```

Скрипт сам пересобирает `libXray.dll` и ядро из соседнего `libXray`,
обновляет GeoData, скачивает списки runetfreedom для профиля
«Заблокированное в России» в `assets/ru_blocked/` и берёт wintun
(SHA-256 закреплён). Результат лежит в
`..\output`: `HyperClient-windows-amd64.exe` (установщик), `.zip` и
`provenance-windows-x64-exe.json` с ревизиями и хешами. Оба дерева должны
быть закоммичены: протокол записывает, были ли они чистыми.

Собирается только режим EXE: MSIX/VCore апстрима не поставляется.
Установщик ставит программу **в Program Files для всех пользователей** и
просит права администратора: ядро TUN запускается с повышенными правами из
папки установки, поэтому писать в неё обычным процессам нельзя. ZIP-сборка
этой защиты не даёт (её можно распаковать куда угодно) — для TUN только
установщик.

## Android

| Что | Где на машине владельца | Зачем |
|---|---|---|
| Android SDK | `%LOCALAPPDATA%\Android\sdk`: platform 37.0, build-tools 37, `cmdline-tools\latest` | `compileSdk = 37` |
| NDK 30.0.16248370 | там же, `ndk\30.0.16248370` | `gomobile bind` (`ANDROID_NDK_HOME`) и `ndkVersion` приложения; NDK 28 Gradle докачивает сам для плагинов |
| JDK | `C:\Program Files\Android\Android Studio\jbr` (`JAVA_HOME`) | Gradle, `keytool` |
| gomobile | `%USERPROFILE%\go\bin`, ставит сам `build/main.py android` | `libXray.aar` |
| Ключ подписи | `C:\Users\BADAB\dev\keys\hyperclient-release.jks`, пароль в `hyperclient-release.properties` рядом | **хранить копию**: обновление встаёт поверх только с тем же ключом |

`applicationId` форка — `io.github.anatomikperq.hyperclient` (рядом с
OneXray из Google Play), а пространство имён Kotlin осталось апстримовским.
`android/keystore/keystore.properties` (в `.gitignore`) — копия файла с
паролем; без неё релизный скрипт отказывается собирать: Gradle подписал бы
отладочным ключом, и такой APK нельзя обновить подписанным.

Gradle не собирает из пути с кириллицей и раскрывает junction обратно, поэтому
Android собирается с **подставленного диска** (`subst` Java не раскрывает).
Исходники плагинов при этом лежат на `C:` (pub cache), а сборка на `P:`, и
инкрементальная компиляция Kotlin падает («different roots») — её
выключает `--android-project-arg kotlin.incremental=false`:

```powershell
subst P: "C:\Users\BADAB\Рабочий стол\projects"   # до перезагрузки
$env:Path = "C:\Users\BADAB\flutter\stable\bin;$env:USERPROFILE\go\bin;" + $env:Path
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\sdk"
$env:ANDROID_NDK_HOME = "$env:ANDROID_HOME\ndk\30.0.16248370"
$env:GOTOOLCHAIN = "auto"; $env:BUILD_NUMBER = "10"; $env:PYTHONUTF8 = "1"
Set-Location P:\hp-client
python build_scripts/main.py HyperClient android
```

Скрипт собирает `libXray.aar` (`gomobile bind`, все ABI), кладёт его в
`android/app/libs/` и собирает три подписанных APK:
`..\output\HyperClient-<версия>-android-{arm64-v8a,armeabi-v7a,x86_64}.apk`.
Под этими именами они и выкладываются в релиз: обновление внутри приложения
ищет APK своего ABI по имени.

Отладочная сборка для эмулятора — `flutter build apk --debug
--target-platform android-x64 --android-project-arg kotlin.incremental=false`
с того же диска `P:`. Эмулятор `hc-test` (Android 16, x86_64) лежит на
`D:\VMs\android\avd`: запускать с `ANDROID_AVD_HOME=D:\VMs\android\avd`.

## Сборка в CI

`.github/workflows/build.yml` собирает то же самое на `windows-2025`: на
теге `v*` (тег появляется при создании релиза) и вручную через
`workflow_dispatch`, где можно указать ветку или коммит libXray. Номер
сборки берётся из `pubspec.yaml`, тег обязан совпадать с версией оттуда.
Результат — артефакты запуска `windows-x64` (установщик и ZIP) и
`provenance-windows-x64-exe`; в релиз workflow ничего не выкладывает.
Секреты не нужны.

## Грабли

- **Прерванная сборка оставляет `pubspec.yaml` и `make_config.yaml`
  переписанными.** Скрипт правит их временно и чинит в `finally`, который
  при убийстве процесса не выполняется. После прерывания — `git status`.
- **Переименование бинарника требует удалить `build/`**: CMake кеширует имя
  цели и потом ругается `No target "..."`.
- **Имя ядра прописано жёстко** в `windows/app.cmake`, `linux/app.cmake`,
  `lib/core/ffi/windows/core_process.dart`, `exe_ffi_api.dart` и
  `linux_ffi_api.dart` отдельно от `BINARY_NAME`.
- **build_runner переписывает `lib/gen/assets.gen.dart`**, если нет
  `assets/dat/`: сначала GeoData, потом генерация.
