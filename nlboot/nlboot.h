/*
 * nlboot — starts a HotSpot JVM inside the current process through the public
 * JNI Invocation API (jni.h, GPLv2 + Classpath Exception boundary).
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 NLauncher
 *
 * The same code is used three ways:
 *   1. Android, JVM in the app process (":game" or the main process) — via
 *      nlboot_jni.c (JNI_OnLoad registers natives for the Kotlin class);
 *   2. Android, JVM in a separate native process — the `nljava` executable
 *      (nlboot_main.c), packaged as lib/arm64-v8a/libnljava.so;
 *   3. host tests (Linux x86_64 with a desktop JDK 21).
 */
#ifndef NLBOOT_H
#define NLBOOT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NLBOOT_VERSION "0.1.0"

/* Flags for nlboot_config.flags */
enum {
    /* Pipe fd 1/2 into the log (logcat on Android + optional file). */
    NLBOOT_REDIRECT_STDIO = 1 << 0,
    /* Add -Xrs: HotSpot does not install SIGQUIT/SIGHUP/SIGINT/SIGTERM
     * handlers. Needed when ART lives in the same process (ART owns SIGQUIT). */
    NLBOOT_REDUCE_SIGNALS = 1 << 1,
    /* Pre-dlopen the JRE's core libraries in dependency order so that their
     * DT_NEEDED entries resolve by soname inside the app linker namespace. */
    NLBOOT_PRELOAD_JRE_LIBS = 1 << 2,
    /* Call DestroyJavaVM after main() returns (waits for non-daemon threads). */
    NLBOOT_DESTROY_VM = 1 << 3,
};

typedef struct nlboot_config {
    const char *java_home;      /* .../jre-21 (required) */
    const char *libjvm_path;    /* optional override, default <java_home>/lib/server/libjvm.so */
    const char *const *jvm_options; /* "-Xmx1g", "-Dfoo=bar", "-Djava.class.path=..." */
    int n_jvm_options;
    const char *main_class;     /* "net.minecraft.client.main.Main" or with slashes */
    const char *const *args;
    int n_args;
    size_t stack_size;          /* main Java thread stack, 0 → 16 MiB */
    const char *log_path;       /* optional: copy of stdout/stderr/JVM messages */
    const char *log_tag;        /* logcat tag, default "nlboot" */
    unsigned flags;
} nlboot_config;

/* Result codes (negative) — anything >= 0 is the Java exit status. */
enum {
    NLBOOT_ERR_ARGS = -1,
    NLBOOT_ERR_DLOPEN = -2,
    NLBOOT_ERR_DLSYM = -3,
    NLBOOT_ERR_CREATE_VM = -4,
    NLBOOT_ERR_MAIN_CLASS = -5,
    NLBOOT_ERR_EXCEPTION = -6,
    NLBOOT_ERR_THREAD = -7,
    NLBOOT_ERR_ALREADY = -8,
};

/* Runs the JVM on a new thread with the configured stack and waits for it.
 * Returns the exit status (System.exit code is reported via the exit hook,
 * which then terminates the process as HotSpot always does). Only one JVM per
 * process: a second call returns NLBOOT_ERR_ALREADY. */
int nlboot_run(const nlboot_config *cfg);

/* Starts the JVM thread and returns immediately (0 or negative error). */
int nlboot_start(const nlboot_config *cfg);
/* Waits for a JVM started by nlboot_start; returns the same as nlboot_run. */
int nlboot_wait(void);
/* 1 while the Java main thread is running. */
int nlboot_running(void);

/* Redirects fd 1 and 2 into the log (logcat + optional file). Idempotent. */
int nlboot_redirect_stdio(const char *log_path, const char *tag);

/* Logging used by all parts of nlboot (logcat on Android, stderr on host). */
void nlboot_log(int error, const char *fmt, ...)
#if defined(__GNUC__)
    __attribute__((format(printf, 2, 3)))
#endif
    ;

/* Text of the last error (static buffer). */
const char *nlboot_last_error(void);

/* Exit hook: called by HotSpot from System.exit() before the process dies. */
typedef void (*nlboot_exit_listener)(int code);
void nlboot_set_exit_listener(nlboot_exit_listener fn);

#ifdef __cplusplus
}
#endif
#endif
