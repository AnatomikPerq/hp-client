set(APP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/app")
set(APP_BIN_DIR "${CMAKE_INSTALL_PREFIX}/bin")

install(FILES "${APP_DIR}/libXray.dll"
        DESTINATION "${CMAKE_INSTALL_PREFIX}"
        COMPONENT Runtime)

install(PROGRAMS
        "${APP_DIR}/HyperClientCore.exe"
        DESTINATION "${APP_BIN_DIR}"
        COMPONENT Runtime)

install(FILES "${APP_DIR}/wintun.dll"
        DESTINATION "${APP_BIN_DIR}"
        COMPONENT Runtime)

# Нестандартные протоколы. Их бинарники лежат В РЕПОЗИТОРИИ (protocols/),
# а не в игнорируемом windows/app/: клиент задуман как дом для протоколов,
# которых не понимают обычные клиенты, и сборка из чистого клона обязана
# получать их автоматически.
set(PROTOCOLS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../protocols")

# minewire: права администратора не нужны — в отличие от ядра он лишь
# открывает локальный SOCKS5.
install(PROGRAMS
        "${PROTOCOLS_DIR}/minewire/windows/x64/minewire.exe"
        DESTINATION "${APP_BIN_DIR}"
        COMPONENT Runtime)
