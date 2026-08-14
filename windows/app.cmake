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

# Нестандартные протоколы отдельными файлами сюда НЕ кладутся: они
# скомпилированы внутрь libXray.dll и приезжают вместе с ней. Подробности —
# в protocols/README.md.
