# nlboot (MIT)

Starts a HotSpot JVM inside an Android app process through the public JNI
Invocation API (`JNI_CreateJavaVM` from `jni.h`, GPLv2 + Classpath Exception),
plus `nljava` — a tiny `java`-like executable for the "separate process" variant
(packaged as `lib/arm64-v8a/libnljava.so`, the only place Android lets apps exec from).

- `libnlboot.so`: C API (`nlboot.h`) and a JNI bridge registered in `JNI_OnLoad`
  for the Kotlin class `net.nlauncher.game.boot.NativeBoot` (override with
  `-DNLBOOT_JNI_CLASS=...`).
- Loads `libjvm.so` with `dlopen(RTLD_LOCAL)` and resolves `JNI_CreateJavaVM`
  from that handle (never the global scope: ART exports its own).
- Optional: `-Xrs` when ART shares the process (ART owns SIGQUIT), pre-loading of the
  JRE core libraries in DT_NEEDED order, stdout/stderr → logcat + file,
  vfprintf/exit/abort hooks.

Published under the MIT license (see `LICENSE`) so that the boundary between the
GPL JVM and the closed NLauncher app is a small, public, permissively licensed
loader. Same source as `native/nlboot` in the private app repository.

Build (host, for tests): `cmake -S nlboot -B build-host && cmake --build build-host`,
then `build-host/nljava --java-home $JAVA_HOME -cp app.jar Main`.
