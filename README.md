# nlauncher-android-natives

Android (NDK, bionic) builds of the **native libraries of upstream
[LWJGL 3.3.3](https://github.com/LWJGL/lwjgl3/tree/3.3.3)**, plus FreeType/HarfBuzz,
jemalloc and the JNA 5.14.0 `libjnidispatch.so`, for running Minecraft Java Edition
(1.21.x uses LWJGL 3.3.3 and JNA 5.14.0) inside an OpenJDK on Android.

LWJGL does not support Android officially, and its `natives-linux-arm64` jars are linked
against glibc, so they cannot be loaded by bionic. This repository compiles the **upstream
sources unchanged** (except for the patches listed below) with the Android NDK and publishes
the result as a release archive.

The `nlboot/` directory (MIT) — a small JVM launcher for Android — lives in this repository
as well and is built by the same workflow when present.

## Libraries

| File | Built from | Loaded by (LWJGL 3.3.3 / JNA) | License |
|---|---|---|---|
| `liblwjgl.so` | LWJGL `core` (`modules/lwjgl/core/src/{main,generated}/c`, `generated/c/linux`, bundled liburing) + **libffi 3.4.4** (static) | `org.lwjgl.system.Library` (`lwjgl`) | BSD-3 (LWJGL), MIT (libffi, liburing) |
| `liblwjgl_opengl.so` | LWJGL `opengl` generated JNI code (all but `WGL`) | `org.lwjgl.opengl.*` | BSD-3, Khronos (MIT-style) |
| `liblwjgl_stb.so` | LWJGL `stb` generated JNI code + stb headers | `org.lwjgl.stb.*` | BSD-3, stb MIT / Public Domain |
| `liblwjgl_tinyfd.so` | LWJGL `tinyfd` (tinyfiledialogs 3.13.3) | `org.lwjgl.util.tinyfd.*` | BSD-3, zlib |
| `libfreetype.so` | **FreeType 2.13.2** + **HarfBuzz 8.2.0** (linked in, API exported) | `org.lwjgl.util.freetype.FreeType` (and optionally `org.lwjgl.util.harfbuzz`) | FTL (chosen over GPLv2), MIT, zlib |
| `libjemalloc.so` | **jemalloc 5.3.0** (`je_` prefix) + `src/jemalloc_free_sized.c` | `org.lwjgl.system.jemalloc.JEmalloc` (default LWJGL allocator when present) | BSD-2 |
| `libjnidispatch.so` | **JNA 5.14.0** `native/dispatch.c`, `native/callback.c` + libffi 3.4.4 | `com.sun.jna.Native` | Apache-2.0 (chosen over LGPL-2.1) |
| `libnlboot.so`, `libnljava.so` | `nlboot/` (only when the directory exists) | the NLauncher app | MIT |

Notes on names — they follow what the LWJGL 3.3.3 Java code actually loads:

* There is **no `liblwjgl_freetype.so`** in LWJGL 3.3.3. `lwjgl-freetype` has no JNI code; it
  `dlopen`s a plain FreeType named `libfreetype.so` (`Configuration.FREETYPE_LIBRARY_NAME`)
  and resolves every `FT_*` function with `dlsym`. Upstream LWJGL builds that library as
  FreeType + HarfBuzz (LWJGL-CI/freetype, meson); we do the same with CMake.
* `lwjgl-jemalloc` likewise has no JNI code: it loads `libjemalloc.so` and resolves the
  `je_*` functions. If it fails, LWJGL silently falls back to the system allocator.
* GLFW and OpenAL are **not** built here: LWJGL loads `libglfw.so` / `libopenal.so` by name
  and those are provided by the application.

## What differs from upstream (patches and additions)

Everything is built from the pinned upstream archives in `versions.env` (sha256-checked).

| Change | Why |
|---|---|
| `patches/lwjgl/0001-liburing-compat-use-bionic-uapi-structs.patch` | LWJGL's hand-written `liburing/compat.h` defines `struct __kernel_timespec` and `struct open_how`; bionic's `<unistd.h>`/`<fcntl.h>` already pull them in from the kernel UAPI headers → "redefinition" errors. On `__ANDROID__` the UAPI headers are used instead (identical layout). |
| `src/jemalloc_free_sized.c` (ours, BSD-3) | LWJGL 3.3.3 is built against a jemalloc *dev* snapshot and resolves `je_free_sized` and `je_free_aligned_sized`, which the 5.3.0 release lacks. Without them `JEmalloc` fails to initialize. Both are implemented with `je_sdallocx` (same contract). |
| libffi compiled with `-Wno-error=implicit-function-declaration` | libffi 3.4.4 `src/tramp.c` calls `open_temp_exec_file()` without a prototype; clang ≥ 16 (NDK r26+) makes that an error. The function returns `int`, so the implicit declaration is ABI-correct. No source change. |
| JAWT JNI functions left out of `liblwjgl.so` (`NL_LWJGL_JAWT=OFF`) | They need `jawt_md.h` + X11 headers; there is no AWT on Android. Upstream Linux builds include them. |
| FreeType without libpng / brotli / bzip2, zlib from FreeType's bundled copy | Upstream (LWJGL-CI) links libpng and a static zlib; PNG-in-font (colour emoji bitmaps) is not needed for Minecraft. |

Everything else — source lists, defines (`LWJGL_LINUX`, `LWJGL_arm64`, `_GNU_SOURCE`, …), the
`config/linux/version.script` export list, jemalloc's configure flags
(`--with-jemalloc-prefix=je_ --disable-stats --disable-fill --disable-cxx
--disable-initial-exec-tls --with-lg-page=16`), libffi's configure — mirrors the upstream Linux
builds (`config/linux/build.xml` of LWJGL, the LWJGL-CI workflows, JNA's `native/Makefile`
"android" target).

All libraries are built with `-O2`, hidden visibility (only `Java_*`/`JNI_On*` or the
library's public C API is exported), `-Wl,-z,max-page-size=16384` (16 KB page devices,
Android 15+), minimum API 29 (`ANDROID_PLATFORM=29`), `c++_static` for HarfBuzz.

## Release artifact (contract)

Every release has exactly these assets:

```
lwjgl-3.3.3-android-arm64.tar.xz
lwjgl-3.3.3-android-arm64.tar.xz.sha256        "<sha256>  lwjgl-3.3.3-android-arm64.tar.xz"
```

Archive layout:

```
lwjgl-3.3.3-android-arm64/
├── lib/                       flat directory of .so files
│   ├── liblwjgl.so
│   ├── liblwjgl_opengl.so
│   ├── liblwjgl_stb.so
│   ├── liblwjgl_tinyfd.so
│   ├── libfreetype.so
│   ├── libjemalloc.so         (built by default)
│   ├── libjnidispatch.so      (built by default)
│   ├── libnlboot.so           (only when nlboot/ exists)
│   └── libnljava.so           (only when nlboot/ exists; the nljava executable)
├── licenses/                  all license texts + THIRD-PARTY-NOTICES.md
└── BUILD-INFO.txt             versions + sha256 of sources, patches, NDK, API, sha256 of each .so
```

Libraries are stripped (`llvm-strip --strip-unneeded`).

### Releases and tags

Tags are `lwjgl-<LWJGL version>-nl<N>`, e.g. `lwjgl-3.3.3-nl1`. `<N>` is `NL_BUILD_NUMBER` in
`versions.env` and is increased for every rebuild of the same LWJGL version (new patch, NDK,
component version, nlboot change). Pushing such a tag runs `.github/workflows/build.yml`,
which refuses the tag if it does not match `versions.env` and then creates the GitHub Release
with the two assets above.

```sh
# after bumping NL_BUILD_NUMBER in versions.env and committing:
git tag lwjgl-3.3.3-nl2 && git push origin lwjgl-3.3.3-nl2
```

### Using the libraries

```
-Dorg.lwjgl.librarypath=<dir with the .so files>
-Djna.boot.library.path=<same dir> -Djna.nosys=true -Djna.nounpack=true
```

With the stock LWJGL jars on the classpath LWJGL prints
`[LWJGL] [ERROR] Incompatible Java and native library versions detected.` once per library:
it compares each loaded file with the sha1 of the official build stored in the jar
(`Library.checkHash`, active unless `-Dorg.lwjgl.util.NoChecks=true`). The message is
cosmetic; nothing else depends on it.

### To verify on a device

* **libffi closures** (every LWJGL callback, e.g. the GLFW callbacks). libffi 3.4.4 on Android
  uses static trampolines: it re-maps the trampoline page of the file that contains it
  (`liblwjgl.so`, found via `/proc/self/maps`; the page is 16 KB aligned). That works when the
  libraries are loaded from the app's native library directory or straight from the APK.
  Fallbacks are anonymous RWX memory, then a temp file in `$TMPDIR` (which SELinux forbids to
  map executable from app data on targetSdk ≥ 29) — so do not load these libraries from a
  copy in app data, and set `TMPDIR` to the app cache directory anyway.
* `liblwjgl_stb.so` uses ELF TLS (general-dynamic model, supported by bionic from API 29).
  jemalloc is built without TLS (`--disable-initial-exec-tls`; bionic: pthread keys).
* tinyfiledialogs finds none of zenity/kdialog/xdialog on Android; dialogs return 0/NULL.

## Building

Requirements: Linux or macOS, CMake ≥ 3.22, make (or Ninja), curl, xz, a JDK (only `javac`,
for JNA's JNI headers), **Android NDK r28c (28.2.13676358)**.

```sh
scripts/fetch-sources.sh                       # downloads + verifies sources into sources/
export ANDROID_NDK_HOME=/path/to/android-ndk-r28c
scripts/build-android.sh                       # TARGET_ABI=arm64-v8a by default -> build/android-arm64-v8a/lib
scripts/package.sh                             # -> dist/lwjgl-3.3.3-android-arm64.tar.xz (+ .sha256)
```

`scripts/build-android.sh` refuses any other NDK revision unless `NL_ALLOW_OTHER_NDK=1`.
`TARGET_ABI=x86_64` builds for the emulator (not part of releases). CMake options:
`NL_WITH_FREETYPE`, `NL_WITH_HARFBUZZ`, `NL_WITH_JEMALLOC`, `NL_WITH_JNA`, `NL_LWJGL_JAWT`,
`NL_LIBFFI_STATIC_TRAMP` (pass them via `NL_CMAKE_ARGS`).

### nlboot

When `nlboot/CMakeLists.txt` exists, `scripts/build-android.sh` (or the CI step
"Build nlboot (if present)", which runs `scripts/build-nlboot.sh`) configures it as a separate
CMake project with the same NDK settings and copies `libnlboot.so` and the `nljava`
executable (renamed to `libnljava.so`, so that Android installs it into the app's native
library directory) into the same `lib/` directory.

## Host check (no NDK needed)

The same source lists can be compiled for linux x86_64 and loaded into a desktop JVM:

```sh
scripts/build-host.sh                          # cmake -DNL_HOST=ON -> build/host/lib
tests/host/run.sh build/host                   # needs JDK 11+
```

`tests/host/run.sh` downloads the plain LWJGL 3.3.3 / JNA 5.14.0 jars from Maven Central
(sha256-pinned, **no natives jars**) and runs `tests/host/NativesSmokeTest.java`, which

* loads every library through `-Dorg.lwjgl.librarypath` / `-Djna.boot.library.path` and checks
  in `/proc/self/maps` that our files (and nothing extracted from a jar) were mapped;
* uses `MemoryUtil` with the jemalloc allocator, `je_free_sized`, a raw `ffi_call`,
  STB image write → read through an LWJGL callback (libffi closure), tinyfd, FreeType
  (`FT_Init_FreeType`, rendering a glyph if a `.ttf` is installed), HarfBuzz shaping, and JNA
  calls + a JNA callback (`qsort`);
* checks that **every** `native` method of `lwjgl`, `lwjgl-opengl`, `lwjgl-stb`,
  `lwjgl-tinyfd` and `jna` resolves to an export of the corresponding library
  (no `UnsatisfiedLinkError` possible).

CI runs this as the `host-test` job.

## CI

* `.github/workflows/build.yml` — `ubuntu-24.04`: downloads NDK r28c from dl.google.com and
  checks its size and SHA-1 (from Google's SDK repository manifest), builds, checks ELF
  properties (AArch64, 16 KB `LOAD` alignment, no static TLS), packages and uploads the
  artifact; `host-test` job; on `lwjgl-*` tags a `release` job (the only job with
  `contents: write`).
* `.github/workflows/build-macos-selfhosted.yml` — manual build on the self-hosted Apple
  Silicon runner (`[self-hosted, macOS, ARM64]`) with NDK r28c from `ANDROID_NDK_HOME` or
  `~/Library/Android/sdk/ndk/28.2.13676358`.

## Provenance

Only upstream sources are used: LWJGL (github.com/LWJGL/lwjgl3, tag 3.3.3) and its CI
configuration repositories (LWJGL-CI), libffi, FreeType, HarfBuzz, jemalloc and JNA release
archives, and the Android NDK documentation. No code from other Android ports of LWJGL is
used.

## License

Build scripts, CMake files, tests, `src/` and `patches/`: BSD-3-Clause, see `LICENSE`.
Third-party components keep their licenses: see `THIRD-PARTY-NOTICES.md` and `NOTICE`.
FreeType is used under the FreeType License (FTL) — *Portions of this software are
copyright © The FreeType Project (www.freetype.org). All rights reserved.* — and JNA under
the Apache License 2.0.

---

## По-русски кратко

**Что это.** Сборка нативных библиотек апстрим-LWJGL 3.3.3 (и FreeType/HarfBuzz, jemalloc,
JNA `libjnidispatch.so`) под Android arm64-v8a через NDK r28c. Официально LWJGL Android не
поддерживает, а его `natives-linux-arm64` собраны под glibc и в bionic не загружаются. Мы
собираем апстрим без изменений, кроме перечисленных выше патчей.

**Что внутри архива.** `lwjgl-3.3.3-android-arm64.tar.xz` → каталог
`lwjgl-3.3.3-android-arm64/` с `lib/*.so` (плоско), `licenses/` и `BUILD-INFO.txt`; рядом
`.sha256`. Теги релизов — `lwjgl-3.3.3-nl<N>`, `<N>` = `NL_BUILD_NUMBER` из `versions.env`.

**Важно про имена.** В LWJGL 3.3.3 нет `liblwjgl_freetype.so`: модуль `lwjgl-freetype`
загружает обычный `libfreetype.so` (FreeType + HarfBuzz) и берёт функции через `dlsym`.
Так же `lwjgl-jemalloc` загружает `libjemalloc.so`. GLFW и OpenAL здесь не собираются —
`libglfw.so` и `libopenal.so` даёт приложение.

**Отличия от апстрима.** Патч `liburing/compat.h` для заголовков bionic; наши
`je_free_sized`/`je_free_aligned_sized` поверх jemalloc 5.3.0 (иначе LWJGL не принимает
jemalloc); libffi 3.4.4 собирается с `-Wno-error=implicit-function-declaration`; JAWT не
собирается (AWT на Android нет); FreeType без libpng.

**Сборка.** `scripts/fetch-sources.sh`, затем с `ANDROID_NDK_HOME` на NDK r28c —
`scripts/build-android.sh` и `scripts/package.sh`. Проверка без NDK:
`scripts/build-host.sh && tests/host/run.sh build/host` — те же списки исходников
собираются под linux x86_64 и грузятся в обычную JVM с jar'ами LWJGL/JNA с Maven Central;
тест проверяет, что все `native`-методы Java находят свои JNI-символы.

**nlboot** (MIT, загрузчик JVM) живёт в этом же репозитории в `nlboot/`; если каталог есть,
CI собирает его и кладёт `libnlboot.so` и `libnljava.so` в тот же `lib/`.
