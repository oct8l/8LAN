TEMPLATE = subdirs
CONFIG += ordered
MAKEFILE = Makefile-GUI
SUBDIRS = Common \
   Common/LogManager \
   Common/RemoteCoreController \
   GUI
TRANSLATIONS = translations/8lan_gui.fr.ts \
   translations/8lan_gui.ko.ts
CODECFORTR = UTF-8
