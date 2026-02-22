win32 {
   PROTOBUF_FOUND = false

   # Derive the active MinGW prefix from qmake so CI paths like
   # D:/a/_temp/msys64/mingw64 are handled (not only C:/msys64/mingw64).
   MSYS2_MINGW = $$[QT_INSTALL_PREFIX]
   isEmpty(MSYS2_MINGW): MSYS2_MINGW = C:/msys64/mingw64
   MSYS2_PROTOBUF_LIB_EXISTS = false
   exists($$MSYS2_MINGW/lib/libprotobuf.dll.a): MSYS2_PROTOBUF_LIB_EXISTS = true
   exists($$MSYS2_MINGW/lib/libprotobuf.a): MSYS2_PROTOBUF_LIB_EXISTS = true
   exists($$MSYS2_MINGW/lib/libprotobuf.lib): MSYS2_PROTOBUF_LIB_EXISTS = true

   # Prefer native MSYS2 protobuf when available.
   exists($$MSYS2_MINGW/include/google/protobuf/message.h):equals(MSYS2_PROTOBUF_LIB_EXISTS, true) {
      INCLUDEPATH += $$MSYS2_MINGW/include
      LIBS += -L$$MSYS2_MINGW/lib -lprotobuf
      DEFINES += PROTOBUF_USE_DLLS

      # Modern protobuf headers/libraries pull in Abseil symbols at link time.
      LIBS += -labsl_log_internal_check_op -labsl_log_internal_message \
         -labsl_log_internal_nullguard -labsl_raw_logging_internal -labsl_raw_hash_set
      PROTOBUF_FOUND = true
   }

   # Optional override for non-MSYS2 local Windows environments.
   # Expected layout:
   #   <PROTOBUF_ROOT>/include/google/protobuf/message.h
   #   <PROTOBUF_ROOT>/lib/libprotobuf*.*
   PROTOBUF_ROOT = $$(PROTOBUF_ROOT)
   PROTOBUF_ROOT_LIB_EXISTS = false
   !isEmpty(PROTOBUF_ROOT):exists($$PROTOBUF_ROOT/lib/libprotobuf.dll.a): PROTOBUF_ROOT_LIB_EXISTS = true
   !isEmpty(PROTOBUF_ROOT):exists($$PROTOBUF_ROOT/lib/libprotobuf.a): PROTOBUF_ROOT_LIB_EXISTS = true
   !isEmpty(PROTOBUF_ROOT):exists($$PROTOBUF_ROOT/lib/libprotobuf.lib): PROTOBUF_ROOT_LIB_EXISTS = true
   !equals(PROTOBUF_FOUND, true):!isEmpty(PROTOBUF_ROOT):exists($$PROTOBUF_ROOT/include/google/protobuf/message.h):equals(PROTOBUF_ROOT_LIB_EXISTS, true) {
      INCLUDEPATH += $$PROTOBUF_ROOT/include
      LIBS += -L$$PROTOBUF_ROOT/lib -lprotobuf
      PROTOBUF_FOUND = true
   }

   !equals(PROTOBUF_FOUND, true) {
      error("Protobuf not found. Install MSYS2 mingw-w64-x86_64-protobuf or set PROTOBUF_ROOT to a valid prefix.")
   }
}

unix:!macx {
   LIBS += -lprotobuf
}

macx {
   # Homebrew protobuf is keg-only; headers land under its keg prefix, not the
   # general Homebrew include dir.  PROTOBUF_PREFIX is exported by ci-macos-setup.sh.
   PROTOBUF_PREFIX = $$(PROTOBUF_PREFIX)
   isEmpty(PROTOBUF_PREFIX):exists(/opt/homebrew/opt/protobuf/include/google/protobuf/message.h) {
      PROTOBUF_PREFIX = /opt/homebrew/opt/protobuf
   }
   isEmpty(PROTOBUF_PREFIX) {
      PROTOBUF_PREFIX = /usr/local
   }
   INCLUDEPATH += $$PROTOBUF_PREFIX/include

   # Abseil is a non-keg-only transitive header dependency of protobuf 4.x; its
   # headers are linked into the general Homebrew include prefix (e.g. /opt/homebrew/include).
   # HOMEBREW_PREFIX is exported by ci-macos-setup.sh; fall back to common locations.
   HOMEBREW_PREFIX = $$(HOMEBREW_PREFIX)
   isEmpty(HOMEBREW_PREFIX):exists(/opt/homebrew) {
      HOMEBREW_PREFIX = /opt/homebrew
   }
   isEmpty(HOMEBREW_PREFIX) {
      HOMEBREW_PREFIX = /usr/local
   }
   INCLUDEPATH += $$HOMEBREW_PREFIX/include

   # Abseil shared libs land in the general Homebrew lib prefix (non-keg-only).
   # Protobuf 4.x generated code references Abseil symbols at link time even
   # when linking against libprotobuf.dylib; they must be listed explicitly.
   LIBS += -L$$PROTOBUF_PREFIX/lib -L$$HOMEBREW_PREFIX/lib -lprotobuf
   LIBS += -labsl_log_internal_check_op -labsl_log_internal_message \
      -labsl_log_internal_nullguard -labsl_raw_logging_internal -labsl_raw_hash_set
}
