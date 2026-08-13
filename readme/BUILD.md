# Сборка HYPER CLIENT

## Раскладка рабочей папки

Скрипты сборки ищут соседей от корня рабочей папки, поэтому раскладка
обязательна именно такая:

```
hp-client/
  app/         — этот репозиторий
  libXray/     — ветка main
  Xray-core/   — тег под версию libXray (сейчас v26.7.28)
  output/      — сюда складываются готовые пакеты
```

## Инструменты

Flutter — последний stable:

```shell
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$HOME/flutter/stable"
export PATH="$HOME/flutter/stable/bin:$PATH"
flutter pub get
```

Для Windows нужны сразу все, иначе сборка падает на середине:

| Что | Куда | Зачем |
|---|---|---|
| Go | любой в `PATH` | сборка `libXray` и ядра |
| Visual Studio 2022 | — | **именно workload** `Microsoft.VisualStudio.Workload.NativeDesktop`; отдельных компонентов Flutter не засчитывает |
| LLVM | `C:\Program Files\LLVM` | `ffigen` ищет `libclang.dll` строго там |
| llvm-mingw | любой в `PATH` | `gcc` для `libXray.dll` — она собирается как c-shared с `CGO_ENABLED=1` |
| Inno Setup 6 | путь передать в `INNO_SETUP_PATH` | установщик |
| Режим разработчика Windows | — | симлинки для плагинов Flutter |

Python-зависимости ставить **в venv**, не в системный интерпретатор:

```shell
python -m venv .venv
.venv/Scripts/pip install pyyaml requests typer fastforge
```

## Артефакты ядра

```shell
cd ../libXray
python3 build/main.py windows local   # или linux / android / apple
```

Затем разложить результат:

```shell
# Windows
mkdir -p windows/app
cp ../libXray/windows_dll/libXray.dll windows/app/
(cd ../Xray-core && CGO_ENABLED=0 go build -o ../app/windows/app/HyperClientCore.exe \
   -trimpath -buildvcs=false -ldflags="-s -w -buildid=" ./main)

# Linux
mkdir -p linux/app
cp ../libXray/linux_so/libXray.so linux/app/
(cd ../Xray-core && CGO_ENABLED=0 go build -o ../app/linux/app/HyperClientCore \
   -trimpath -buildvcs=false -ldflags="-s -w -buildid=" ./main)
```

`wintun.dll` приходит не из `libXray` — её кладут в `windows/app/` отдельно.

Каталог `windows/app/` (и `linux/app/`) в `.gitignore`: это артефакты
сборки. **Бинарники нестандартных протоколов туда не кладут** — они живут в
[`protocols/`](../protocols/) под контролем версий и попадают в сборку сами.

## Отладочный запуск

```shell
flutter run -d windows
flutter run -d linux    # нужны ninja-build clang cmake pkg-config libgtk-3-dev
                        # liblzma-dev libblkid-dev libsecret-1-dev
                        # libayatana-appindicator3-dev file
flutter run -d android
```

Для Apple перед запуском — `cd ios && pod install`.

## Релизная сборка

```shell
BUILD_NUMBER=1 GOARCH=amd64 ONEXRAY_WINDOWS_ARCH=x64 \
  python build_scripts/main.py HyperClient windows
```

Готовые пакеты появятся в `../output/`.

## Грабли

- **Прерванная сборка оставляет `pubspec.yaml` и `make_config.yaml`
  переписанными.** Скрипт правит их временно и чинит в `finally`, который
  при убийстве процесса не выполняется. После прерывания — `git status`.
- **Переименование бинарника требует удалить `app/build`**: CMake кеширует
  имя цели и потом ругается `No target "..."`.
- **Имя ядра прописано жёстко** в `windows/app.cmake` и `linux/app.cmake`
  отдельно от `BINARY_NAME` в `CMakeLists.txt` — менять надо в обоих местах.
- **Повторная локальная сборка Windows** раньше падала на `wintun.dll`:
  `shutil.move` не перезаписывает существующий файл. Исправлено в
  `build_scripts/app/windows.py`.

## `.env`

Для отладки может быть пустым: переменные `FASTLANE_*` нужны только для
публикации в магазины. `BUILD_NUMBER` требуется скриптам упаковки.
