# Minimal EmbedLite browser shell for the N950: one QmlMozView, an address
# line, back/forward/reload. A test bed for the engine and qtmozembed until
# the MeeGo-style browser UI exists.
TEMPLATE = app
TARGET = embedlite-shell
QT += quick qml
CONFIG += link_pkgconfig c++17
QMAKE_CXXFLAGS += -std=gnu++20
PKGCONFIG += qt5embedwidget-next153 xcb
SOURCES += main.cpp
RESOURCES += shell.qrc
target.path = /usr/bin
INSTALLS += target
# libxul's own libraries (its NSS, codecs, SQLite) sit next to it: an
# RPATH, unlike a RUNPATH, also serves the libraries libxul pulls in.
QMAKE_LFLAGS += -Wl,--disable-new-dtags -Wl,-rpath,/usr/lib/arm-linux-gnueabihf/xulrunner-qt5-153.6.0
