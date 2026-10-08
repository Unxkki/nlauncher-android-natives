# Sources log

What was consulted while writing and fixing the code and build scripts of this repository.
Each change adds a line: date, component, sources.

| Date | Component | Sources |
|---|---|---|
| 2026-10-06 | LWJGL / JNA / libffi / FreeType / HarfBuzz / jemalloc build | Upstream sources and build files of LWJGL 3.3.3 (and LWJGL-CI), JNA 5.14.0, libffi 3.4.4, FreeType 2.13.2, HarfBuzz, jemalloc 5.3.0 |
| 2026-10-06 | `nlboot/` | JNI Invocation API specification (Java SE 21); `jni.h` of JDK 21; Android NDK / bionic documentation (`dlopen`, linker namespaces); POSIX man pages |
| 2026-10-08 | `nlboot/nlboot.c`: `JNI_VERSION_1_8` when the NDK `<jni.h>` lacks it | JNI specification (version constants: `JNI_VERSION_1_8` = `0x00010008`); NDK r28c sysroot `<jni.h>` (stops at `JNI_VERSION_1_6`); our CI failure log |
