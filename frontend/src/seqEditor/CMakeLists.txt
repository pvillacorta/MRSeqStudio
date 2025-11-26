cmake_minimum_required(VERSION 3.16)

project(appMRSeqStudio VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find Qt
find_package(Qt6 6.4 REQUIRED COMPONENTS Quick QuickControls2 Widgets)

# vcpkg and packages
include_directories(${PROJECT_SOURCE_DIR}/include)
include($ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake)
find_package(nlohmann_json CONFIG REQUIRED)

qt_standard_project_setup()

qt_add_executable(appMRSeqStudio
    main.cpp
    backend.cpp
    backend.h
)

add_dependencies(appMRSeqStudio nlohmann_json)

set(qml_resource_files
    "qml/Main.qml"
    "qml/BlockItem.qml"
    "qml/BlockMenu.qml"
    "qml/ScannerMenu.qml"
    "qml/VariablesMenu.qml"
    "qml/SimulatorMenu.qml"
    "qml/TextInputItem.qml"
    "qml/MenuLabel.qml"
    "qml/ButtonsMenu.qml"
    "qml/PopUp.qml"
    "qml/DeleteButton.qml"
    "qml/Seq_Example.qml"
    "qml/ComboBoxItem.qml"
    "qml/MenuPresets.qml"
    "qml/StyledButton.qml"
    "icons/arrow.png"
    "icons/arrow_gray.png"
    "icons/delete_white.png"
    "icons/delete_black.png"
    "icons/dark/angle.png"
    "icons/dark/clock.png"
    "icons/dark/misc.png"
    "icons/dark/readout.png"
    "icons/dark/rf.png"
    "icons/dark/plus.png"
    "icons/dark/epi.png"
    "icons/light/angle.png"
    "icons/light/clock.png"
    "icons/light/misc.png"
    "icons/light/readout.png"
    "icons/light/rf.png"
    "icons/light/plus.png"
    "icons/light/epi.png"
    "icons/balloon.png"
)

qt6_add_resources(appMRSeqStudio "qml"
    PREFIX
        "/"
    FILES
        ${qml_resource_files}
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(appMRSeqStudio PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appMRSeqStudio
    PRIVATE Qt6::Quick
    PRIVATE Qt6::QuickControls2
    PRIVATE Qt6::Widgets
    PRIVATE nlohmann_json::nlohmann_json
)

include(GNUInstallDirs)
install(TARGETS appMRSeqStudio
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)



