set(APP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/app")

install(CODE "file(REMOVE_RECURSE \"${CMAKE_INSTALL_PREFIX}/bin\")"
        COMPONENT Runtime)

# Flat runtime layout next to the App executable. Missing native dependencies
# must fail the build instead of producing an incomplete package.
#
# HYPER CLIENT ships only the EXE mode, so the VCore/MSIX artifacts of the
# upstream are not installed. Non-standard protocol engines are not separate
# files either: they are compiled into libXray.dll (see protocols/README.md).
install(FILES
        "${APP_DIR}/libXray.dll"
        "${APP_DIR}/wintun.dll"
        DESTINATION "${CMAKE_INSTALL_PREFIX}"
        COMPONENT Runtime)

install(PROGRAMS
        "${APP_DIR}/HyperClientCore.exe"
        DESTINATION "${CMAKE_INSTALL_PREFIX}"
        COMPONENT Runtime)
