# D-LAN Qt 6 Migration Delta

Last updated (UTC): 2026-02-21T14:00:00Z

## Purpose

Establish the list of Qt 5-specific APIs and modules still present in the codebase that would
need to change before a Qt 6 build is possible. The initial audit (H6) was read-only. All
low-effort items were subsequently migrated in H9 — see the status column in the Summary Table.

## What Is No Longer Present (No Action Needed)

### Phase 4 Migrations

| API | Replacement applied |
|---|---|
| `QRegExp` | `QRegularExpression` |
| `QLinkedList` | `QList` / `std::vector` |
| `QDesktopWidget` / `QApplication::desktop()` | `QScreen` APIs |
| `QTextCodec::setCodecForLocale` / `setCodecForMib` | Fully removed from all three `main.cpp` files; Qt 6 uses UTF-8 by default |
| `QTextStream::endl` | `Qt::endl` |
| `QString::fromAscii` / `toAscii` / `QChar::toAscii` | `fromLatin1` / `toLatin1` |
| `QHeaderView::setResizeMode` | `setSectionResizeMode` |
| `QHeaderView::setClickable` | `setSectionsClickable` |
| `qInstallMsgHandler` (vendored qtservice) | `qInstallMessageHandler` |
| `QCoreApplication::setEventFilter` (vendored qtservice) | `installNativeEventFilter` |
| `QPixmap::toWinHICON` / `fromWinHICON` | `QtWin::fromHICON` (QtWinExtras) |

### H9 Migrations

| API / Pattern | Replacement applied |
|---|---|
| `QScriptEngine` / `QScriptValue` (`QtScript`, Qt 6 removed) | `QJSEngine` / `QJSValue`; `Client.pro` `script` → `qml` (QJSEngine is in QtQml) |
| `QtWin::fromHICON()` (`QtWinExtras`, Qt 6 removed) | `QImage::fromHICON()` under `QT_VERSION_CHECK(6,0,0)` guard in `IconProvider.cpp`; Qt5 path retained |
| `QT += winextras` (removed in Qt 6) | `win32:greaterThan(QT_MAJOR_VERSION,4):lessThan(QT_MAJOR_VERSION,6): QT += winextras` in `GUI.pro` |
| `SIGNAL()`/`SLOT()` macros (42 remaining in tests/tools) | Typed function-pointer `connect()` syntax throughout |
| `Q_FOREACH` / `foreach()` macro (62 first-party occurrences) | C++11 range-based `for`; pointer types use `auto*`, value types use `const auto&` |

---

## Remaining Delta Items

### 1. `QtScript` module — **Removed in Qt 6**  `High effort`

**Module:** `QT += script` in `application/Client/Client.pro`

**Affected files:**
- `application/Client/D-LAN_Client.h` — declares `QScriptEngine engine`, `QScriptValue newConnection()`
- `application/Client/D-LAN_Client.cpp` — uses `engine.newQObject()`, `engine.globalObject().setProperty()`,
  `engine.scriptValueFromQMetaObject<T>()`, `engine.evaluate()`, `engine.hasUncaughtException()`

**What it does:** The `Client` component exposes a JavaScript-based scripting interface for
remote core control (command-line automation of a running Core instance).

**Qt 6 status:** `QtScript` was deprecated in Qt 5.5 and removed entirely in Qt 6. There is
no Qt5Compat shim. The alternatives are:

- **QJSEngine** (Qt 6 built-in, lightweight, ECMAScript 5.1) — closest drop-in for scripting
  without QML; `QJSEngine::newQObject()` maps directly to `QScriptEngine::newQObject()`.
- **QQmlEngine** (heavier, requires QML runtime) — overkill for a CLI automation tool.
- **Remove the `Client` component** — it is a secondary tool, not part of the Core/GUI runtime.
  The last upstream release did not mention it as a user-facing feature.

**Decision needed before migration:** whether to replace with `QJSEngine`, remove the component,
or defer it as a known non-building component when compiling against Qt 6.

---

### 2. `QtWinExtras` module — **Removed in Qt 6**  `Medium effort`

**Module:** `win32:greaterThan(QT_MAJOR_VERSION, 4): QT += winextras` in `application/GUI/GUI.pro`

**Affected file:**
- `application/GUI/IconProvider.cpp` — uses `#include <QtWinExtras/QtWin>` and
  `QtWin::fromHICON(psfi.hIcon)` to convert a Windows HICON into a `QIcon`

**What it does:** Extracts the shell-assigned icon for a file extension (e.g., `.mp3` gets its
associated app icon from the OS). Used in the browse/download file list view to show per-type icons.

**Qt 6 status:** `QtWinExtras` is removed; no Qt5Compat shim. The code already has a Qt 4
fallback path (`QPixmap::fromWinHICON()`), so conditional-compilation scaffolding is already
in place.

**Qt 6 replacement for `QtWin::fromHICON(HICON)`:**
```cpp
// Qt 6: must call the Windows API directly, then wrap
ICONINFO ii;
GetIconInfo(hIcon, &ii);
QPixmap px = QPixmap::fromImage(
    QImage::fromHICON(hIcon)  // added in Qt 6.0 (QImage::fromHICON)
);
```
`QImage::fromHICON()` was added to Qt 6.0 as the direct replacement.

**Migration path:** Replace the `QtWinExtras/QtWin` include and `QtWin::fromHICON()` call
with `QImage::fromHICON()` under a `QT_VERSION_CHECK(6, 0, 0)` guard; remove `winextras`
from the `QT +=` line for Qt 6 builds.

---

### 3. `QTextCodec` guards — **Done**  `Trivial`

All three `main.cpp` files (`Core`, `GUI`, `Client`) had their `#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)`
`QTextCodec` blocks fully removed. Qt 6 uses UTF-8 everywhere by default; no replacement needed.

---

### 4. Remaining `SIGNAL()` / `SLOT()` string macros — **Deprecated, still works**  `Low effort`

**Count:** 42 occurrences across 11 files

**Location breakdown:** Primarily in `Tools/LogViewer/` (19 occurrences) and test files under
`Core/FileManager/TestsFileManager/`, `Core/PeerManager/TestsPeerManager/`,
`Core/NetworkListener/Tests/`, and `GUI/Search/`.

**Qt 6 status:** The macros still compile and work in Qt 6 but produce deprecation noise and
lose compile-time signal/slot type checking. They are not on a removal schedule for Qt 6.x,
but will eventually be removed.

**Migration:** Mechanical conversion to functor-pointer syntax, identical to what Phase 4 did
for runtime code. Tests and `LogViewer` were not covered by Phase 4. This is safe to defer
until the Qt 6 migration is actually underway.

---

### 5. Vendored `qtservice` library — **Partially Qt 6 ready**  `Low effort`

**Location:** `application/Libs/qtservice/src/`

**Already handled with conditional compilation:**
- `qInstallMsgHandler` → `qInstallMessageHandler` (patched in Phase 4)
- `QCoreApplication::setEventFilter` → `installNativeEventFilter` (Qt 5+ path already active)

**Remaining concern:** `qtservice` is a Qt 4-era library with no upstream maintenance. Its
internal usage of `QSysInfo::windowsVersion()` and `QSysInfo::macVersion()` (both removed
in Qt 6; replaced by `QOperatingSystemVersion`) has not been audited. These are in code paths
that only execute on Windows service startup.

**Action for Qt 6:** Do a targeted grep for `windowsVersion` and `macVersion` in `qtservice/src/`
and update those call sites. The rest of the library appears compatible.

---

### 6. `foreach()` macro — **Deprecated, still compiles**  `Low effort`

**Count:** 63 occurrences across the codebase.

**Qt 6 status:** `foreach` is defined via `Q_FOREACH` and still compiles in Qt 6 unless
`QT_NO_FOREACH` is defined. Qt 6 discourages it in favour of range-based `for`; it will not
be removed in Qt 6.x but is likely to go in Qt 7.

**Migration:** Mechanical replacement with `for (const auto& x : container)`. Safe to defer;
not a blocker.

---

### 7. `.pro` file module declarations — **Needs conditional guards**  `Low effort`

Two `QT +=` declarations reference removed modules:

| File | Declaration | Qt 6 action |
|---|---|---|
| `application/Client/Client.pro` | `QT += core network script` | Remove `script`; see item 1 |
| `application/GUI/GUI.pro` | `win32:greaterThan(QT_MAJOR_VERSION, 4): QT += winextras` | Already Qt 4-guarded; add `lessThan(QT_MAJOR_VERSION, 6):` or remove; see item 2 |

---

## Items Confirmed Clean (No Action Needed for Qt 6)

| Area | Notes |
|---|---|
| `QVariant` type system | No deprecated `QVariant(QVariant::Type)` or `.type()` patterns found |
| `QSortFilterProxyModel` / item models | No deprecated model APIs |
| `QProcess::startDetached` | Current usage form is compatible |
| `QFont` / `QPalette` | No deprecated usage |
| `QDateTime` / `QDate` / `QTime` | No deprecated format/parse patterns |
| `QNetworkAccessManager` / `QNetworkReply` | Not used in examined paths |
| `QSignalMapper` | Zero occurrences |
| `Q_ENUMS` / `Q_FLAGS` (old macros) | Zero occurrences |
| OpenGL / `QGL*` | Not used |
| `Qt::endl` | Still present and functional in Qt 6 |
| `Qt::ItemFlag` / `Qt::MatchFlag` | No deprecated values used |
| `QUrl` usage | No deprecated parsing-mode arguments; `fromLocalFile()` already used |

---

## Summary Table

| # | Item | Qt 6 Status | Effort | Protocol break? | H9 Status |
|---|---|---|---|---|---|
| 1 | `QtScript` in Client | Removed | High | No (secondary tool) | **Done** — replaced with `QJSEngine` |
| 2 | `QtWinExtras` in IconProvider | Removed | Medium | No (Windows GUI only) | **Done** — `QImage::fromHICON` + version guard |
| 3 | `QTextCodec` guards in `main.cpp` | Removed | Trivial | No | **Done** — blocks fully deleted from all three `main.cpp` files |
| 4 | `SIGNAL()`/`SLOT()` macros (42) | Deprecated; works | Low | No | **Done** — all 42 converted |
| 5 | `qtservice` `QSysInfo` audit | Likely broken | Low | No | **Clean** — grep found zero occurrences |
| 6 | `foreach()` macro (63) | Deprecated; works | Low | No | **Done** — 62/63 converted; 1 in vendored qtservice |
| 7 | `.pro` module declarations | Must update | Low | No | **Done** — `script`→`qml`; `winextras` version-guarded |

**All items resolved.** Qt 6 build is feasible for first-party D-LAN code.

---

## Remaining Pre-Migration Step

Only one item is left before a Qt 6 build attempt:

1. ~~Decide the fate of the `Client` component~~ — resolved: replaced with `QJSEngine`.
2. ~~Add guards around `QT += script` and `QT += winextras`~~ — done in H9.
3. ~~Replace `QtWin::fromHICON()`~~ — done in H9.
4. ~~Grep `qtservice/src/` for `windowsVersion` / `macVersion`~~ — confirmed clean in H9.
5. ~~Remove the `#if QT_VERSION < 6` `QTextCodec` blocks~~ — done; all three `main.cpp` files cleaned up.
6. ~~Convert remaining `SIGNAL()`/`SLOT()` macros (tests and `LogViewer`)~~ — done in H9.
7. ~~Convert `foreach()` loops~~ — done in H9 (62/63; vendored qtservice left as-is).
