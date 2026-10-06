/*
 * nlboot — see nlboot.h.
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 NLauncher
 *
 * Written from the JNI Invocation API specification
 * (docs.oracle.com/en/java/javase/21/docs/specs/jni/invocation.html) and the
 * Android NDK / bionic documentation. No third-party launcher code is used.
 */
#define _GNU_SOURCE
#include "nlboot.h"

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <jni.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifdef __ANDROID__
#include <android/log.h>
#endif

typedef jint (JNICALL *create_vm_fn)(JavaVM **, void **, void *);

/* ------------------------------------------------------------------ log -- */

static pthread_mutex_t g_log_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_log_fd = -1;        /* copy of everything, optional */
static int g_host_err_fd = -1;   /* original stderr (host builds) */
static char g_tag[48] = "nlboot";
static char g_last_error[512];
static nlboot_exit_listener g_exit_listener;

static void log_write_line(int error, const char *line, size_t len)
{
    pthread_mutex_lock(&g_log_lock);
#ifdef __ANDROID__
    char buf[1024];
    size_t n = len < sizeof buf - 1 ? len : sizeof buf - 1;
    memcpy(buf, line, n);
    buf[n] = 0;
    __android_log_write(error ? ANDROID_LOG_ERROR : ANDROID_LOG_INFO, g_tag, buf);
#else
    int fd = g_host_err_fd >= 0 ? g_host_err_fd : 2;
    if (write(fd, line, len) < 0 || write(fd, "\n", 1) < 0) { /* nothing to do */ }
#endif
    if (g_log_fd >= 0) {
        if (write(g_log_fd, line, len) < 0 || write(g_log_fd, "\n", 1) < 0) { /* ignore */ }
    }
    pthread_mutex_unlock(&g_log_lock);
}

static void log_vprintf(int error, const char *fmt, va_list ap)
{
    char buf[2048];
    int n = vsnprintf(buf, sizeof buf, fmt, ap);
    if (n < 0) return;
    size_t len = (size_t)n < sizeof buf ? (size_t)n : sizeof buf - 1;
    /* split on newlines so that logcat shows one entry per line */
    size_t start = 0;
    for (size_t i = 0; i <= len; i++) {
        if (i == len || buf[i] == '\n') {
            if (i > start || (i == len && start == 0)) log_write_line(error, buf + start, i - start);
            start = i + 1;
        }
    }
}

void nlboot_log(int error, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    log_vprintf(error, fmt, ap);
    va_end(ap);
}

static void set_error(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(g_last_error, sizeof g_last_error, fmt, ap);
    va_end(ap);
    nlboot_log(1, "%s", g_last_error);
}

const char *nlboot_last_error(void) { return g_last_error; }

void nlboot_set_exit_listener(nlboot_exit_listener fn) { g_exit_listener = fn; }

static void open_log_file(const char *path)
{
    if (!path || !*path) return;
    pthread_mutex_lock(&g_log_lock);
    if (g_log_fd < 0) g_log_fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    pthread_mutex_unlock(&g_log_lock);
}

/* ------------------------------------------------------- stdio redirect -- */

static int g_redirected;

static void *stdio_pump(void *arg)
{
    int fd = (int)(intptr_t)arg;
    char buf[4096];
    size_t used = 0;
    for (;;) {
        ssize_t r = read(fd, buf + used, sizeof buf - used);
        if (r <= 0) {
            if (r < 0 && errno == EINTR) continue;
            break;
        }
        used += (size_t)r;
        size_t start = 0;
        for (size_t i = 0; i < used; i++) {
            if (buf[i] == '\n') {
                log_write_line(0, buf + start, i - start);
                start = i + 1;
            }
        }
        if (start == 0 && used == sizeof buf) { /* very long line: flush as is */
            log_write_line(0, buf, used);
            used = 0;
        } else if (start > 0) {
            memmove(buf, buf + start, used - start);
            used -= start;
        }
    }
    if (used) log_write_line(0, buf, used);
    return NULL;
}

int nlboot_redirect_stdio(const char *log_path, const char *tag)
{
    if (tag && *tag) snprintf(g_tag, sizeof g_tag, "%s", tag);
    open_log_file(log_path);
    if (g_redirected) return 0;
    if (g_host_err_fd < 0) g_host_err_fd = fcntl(2, F_DUPFD_CLOEXEC, 3);
    int p[2];
    if (pipe(p) != 0) {
        set_error("pipe: %s", strerror(errno));
        return -1;
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    if (dup2(p[1], 1) < 0 || dup2(p[1], 2) < 0) {
        set_error("dup2: %s", strerror(errno));
        close(p[0]);
        close(p[1]);
        return -1;
    }
    close(p[1]);
    pthread_t t;
    pthread_attr_t a;
    pthread_attr_init(&a);
    pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
    int rc = pthread_create(&t, &a, stdio_pump, (void *)(intptr_t)p[0]);
    pthread_attr_destroy(&a);
    if (rc != 0) {
        set_error("pthread_create(stdio): %s", strerror(rc));
        return -1;
    }
#if defined(__ANDROID__) || defined(__GLIBC__)
    pthread_setname_np(t, "nl-stdio");
#endif
    g_redirected = 1;
    return 0;
}

/* ---------------------------------------------------------- JVM hooks -- */

static jint JNICALL hook_vfprintf(FILE *fp, const char *fmt, va_list args)
{
    (void)fp;
    va_list copy;
    va_copy(copy, args);
    log_vprintf(0, fmt, copy);
    va_end(copy);
    return 0;
}

static void JNICALL hook_exit(jint code)
{
    nlboot_log(0, "NLBOOT EXIT %d", (int)code);
    if (g_exit_listener) g_exit_listener((int)code);
    fflush(stdout);
    fflush(stderr);
}

static void JNICALL hook_abort(void)
{
    nlboot_log(1, "NLBOOT ABORT (JVM fatal error, see hs_err file)");
}

/* ------------------------------------------------------------ state ---- */

struct boot_state {
    char *java_home;
    char *libjvm;
    char **opts;
    int n_opts;
    char *main_class;
    char **args;
    int n_args;
    size_t stack;
    unsigned flags;
    pthread_t thread;
    int result;
};

static pthread_mutex_t g_state_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_started;          /* JVM can only be created once per process */
static volatile int g_running;
static struct boot_state g_st;

static char *xstrdup(const char *s) { return s ? strdup(s) : NULL; }

static char *path_join(const char *a, const char *b)
{
    size_t la = strlen(a), lb = strlen(b);
    char *r = malloc(la + lb + 2);
    if (!r) return NULL;
    memcpy(r, a, la);
    size_t p = la;
    if (p && r[p - 1] != '/') r[p++] = '/';
    memcpy(r + p, b, lb + 1);
    return r;
}

static int file_exists(const char *p)
{
    struct stat st;
    return stat(p, &st) == 0;
}

/* Core JRE libraries in DT_NEEDED order (each needs only ones above it). */
static const char *const k_preload[] = {
    "lib/libjava.so",  "lib/libjimage.so", "lib/libzip.so",    "lib/libnet.so",
    "lib/libnio.so",   "lib/libextnet.so", "lib/libverify.so", "lib/libmanagement.so",
    "lib/libmanagement_ext.so", "lib/libprefs.so", "lib/libsyslookup.so",
};

static void preload_jre_libs(const char *java_home)
{
    for (size_t i = 0; i < sizeof k_preload / sizeof k_preload[0]; i++) {
        char *p = path_join(java_home, k_preload[i]);
        if (!p) continue;
        if (file_exists(p)) {
            void *h = dlopen(p, RTLD_NOW | RTLD_LOCAL);
            if (!h) nlboot_log(1, "preload %s: %s", k_preload[i], dlerror());
        }
        free(p);
    }
}

static void to_slashes(char *s)
{
    for (; *s; s++)
        if (*s == '.') *s = '/';
}

static int run_java(struct boot_state *st)
{
    void *h = dlopen(st->libjvm, RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        set_error("dlopen %s: %s", st->libjvm, dlerror());
        return NLBOOT_ERR_DLOPEN;
    }
    /* From the HotSpot handle, never the global scope: ART exports a
     * JNI_CreateJavaVM of its own. */
    create_vm_fn create = (create_vm_fn)dlsym(h, "JNI_CreateJavaVM");
    if (!create) {
        set_error("dlsym JNI_CreateJavaVM: %s", dlerror());
        return NLBOOT_ERR_DLSYM;
    }
    if (st->flags & NLBOOT_PRELOAD_JRE_LIBS) preload_jre_libs(st->java_home);

    int extra = 4; /* vfprintf, exit, abort, -Xrs */
    JavaVMOption *o = calloc((size_t)(st->n_opts + extra), sizeof *o);
    if (!o) return NLBOOT_ERR_ARGS;
    int n = 0;
    for (int i = 0; i < st->n_opts; i++) o[n++].optionString = st->opts[i];
    o[n].optionString = "vfprintf";
    o[n++].extraInfo = (void *)hook_vfprintf;
    o[n].optionString = "exit";
    o[n++].extraInfo = (void *)hook_exit;
    o[n].optionString = "abort";
    o[n++].extraInfo = (void *)hook_abort;
    if (st->flags & NLBOOT_REDUCE_SIGNALS) o[n++].optionString = "-Xrs";

    JavaVMInitArgs vmargs;
    memset(&vmargs, 0, sizeof vmargs);
    vmargs.version = JNI_VERSION_1_8;
    vmargs.nOptions = n;
    vmargs.options = o;
    vmargs.ignoreUnrecognized = JNI_FALSE;

    for (int i = 0; i < n; i++)
        if (o[i].optionString[0] == '-') nlboot_log(0, "jvm option: %s", o[i].optionString);

    JavaVM *vm = NULL;
    JNIEnv *env = NULL;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    jint rc = create(&vm, (void **)&env, &vmargs);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    free(o);
    if (rc != JNI_OK || !env) {
        set_error("JNI_CreateJavaVM failed: %d", (int)rc);
        return NLBOOT_ERR_CREATE_VM;
    }
    nlboot_log(0, "JVM created in %ld ms",
               (long)((t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000));

    int result = 0;
    char *cls_name = xstrdup(st->main_class);
    to_slashes(cls_name);
    jclass cls = (*env)->FindClass(env, cls_name);
    jmethodID mid = cls ? (*env)->GetStaticMethodID(env, cls, "main", "([Ljava/lang/String;)V") : NULL;
    if (!mid) {
        if ((*env)->ExceptionCheck(env)) (*env)->ExceptionDescribe(env);
        set_error("main class %s or its main(String[]) not found", st->main_class);
        result = NLBOOT_ERR_MAIN_CLASS;
    } else {
        jclass str_cls = (*env)->FindClass(env, "java/lang/String");
        jobjectArray jargs = (*env)->NewObjectArray(env, st->n_args, str_cls, NULL);
        for (int i = 0; jargs && i < st->n_args; i++) {
            jstring s = (*env)->NewStringUTF(env, st->args[i]);
            (*env)->SetObjectArrayElement(env, jargs, i, s);
            (*env)->DeleteLocalRef(env, s);
        }
        nlboot_log(0, "calling %s.main (%d args)", st->main_class, st->n_args);
        (*env)->CallStaticVoidMethod(env, cls, mid, jargs);
        if ((*env)->ExceptionCheck(env)) {
            (*env)->ExceptionDescribe(env);
            set_error("uncaught exception in %s.main", st->main_class);
            result = 1;
        }
    }
    free(cls_name);

    /* Same order as the standard launcher: detach, then DestroyJavaVM (which
     * waits for the remaining non-daemon threads). */
    if ((*vm)->DetachCurrentThread(vm) != JNI_OK) nlboot_log(1, "DetachCurrentThread failed");
    if (st->flags & NLBOOT_DESTROY_VM) {
        (*vm)->DestroyJavaVM(vm);
        nlboot_log(0, "JVM destroyed");
    }
    nlboot_log(0, "NLBOOT RESULT %d", result);
    return result;
}

static void *java_thread(void *arg)
{
    struct boot_state *st = arg;
#if defined(__ANDROID__) || defined(__GLIBC__)
    pthread_setname_np(pthread_self(), "mc-main");
#endif
    st->result = run_java(st);
    g_running = 0;
    return NULL;
}

static int copy_config(const nlboot_config *c)
{
    memset(&g_st, 0, sizeof g_st);
    g_st.java_home = xstrdup(c->java_home);
    g_st.libjvm = c->libjvm_path && *c->libjvm_path ? xstrdup(c->libjvm_path)
                                                    : path_join(c->java_home, "lib/server/libjvm.so");
    g_st.main_class = xstrdup(c->main_class);
    g_st.n_opts = c->n_jvm_options > 0 ? c->n_jvm_options : 0;
    g_st.n_args = c->n_args > 0 ? c->n_args : 0;
    g_st.opts = calloc((size_t)g_st.n_opts + 1, sizeof(char *));
    g_st.args = calloc((size_t)g_st.n_args + 1, sizeof(char *));
    if (!g_st.java_home || !g_st.libjvm || !g_st.main_class || !g_st.opts || !g_st.args) return -1;
    for (int i = 0; i < g_st.n_opts; i++) g_st.opts[i] = xstrdup(c->jvm_options[i]);
    for (int i = 0; i < g_st.n_args; i++) g_st.args[i] = xstrdup(c->args[i]);
    g_st.stack = c->stack_size ? c->stack_size : (size_t)16 << 20;
    g_st.flags = c->flags;
    return 0;
}

int nlboot_start(const nlboot_config *cfg)
{
    if (!cfg || !cfg->java_home || !cfg->main_class) {
        set_error("nlboot_start: java_home and main_class are required");
        return NLBOOT_ERR_ARGS;
    }
    pthread_mutex_lock(&g_state_lock);
    if (g_started) {
        pthread_mutex_unlock(&g_state_lock);
        set_error("JVM was already started in this process (one JVM per process)");
        return NLBOOT_ERR_ALREADY;
    }
    g_started = 1;
    pthread_mutex_unlock(&g_state_lock);

    if (cfg->log_tag && *cfg->log_tag) snprintf(g_tag, sizeof g_tag, "%s", cfg->log_tag);
    if (cfg->flags & NLBOOT_REDIRECT_STDIO) nlboot_redirect_stdio(cfg->log_path, cfg->log_tag);
    else open_log_file(cfg->log_path);

    if (copy_config(cfg) != 0) {
        set_error("out of memory");
        return NLBOOT_ERR_ARGS;
    }
    nlboot_log(0, "nlboot %s: java_home=%s main=%s stack=%zu KiB flags=0x%x", NLBOOT_VERSION, g_st.java_home,
               g_st.main_class, g_st.stack >> 10, g_st.flags);

    pthread_attr_t a;
    pthread_attr_init(&a);
    pthread_attr_setstacksize(&a, g_st.stack);
    g_running = 1;
    int rc = pthread_create(&g_st.thread, &a, java_thread, &g_st);
    pthread_attr_destroy(&a);
    if (rc != 0) {
        g_running = 0;
        set_error("pthread_create(mc-main): %s", strerror(rc));
        return NLBOOT_ERR_THREAD;
    }
    return 0;
}

int nlboot_wait(void)
{
    static pthread_mutex_t join_lock = PTHREAD_MUTEX_INITIALIZER;
    static int joined;
    if (!g_started) return NLBOOT_ERR_ARGS;
    pthread_mutex_lock(&join_lock);
    if (!joined) {
        pthread_join(g_st.thread, NULL);
        joined = 1;
    }
    pthread_mutex_unlock(&join_lock);
    return g_st.result;
}

int nlboot_running(void) { return g_running; }

int nlboot_run(const nlboot_config *cfg)
{
    int rc = nlboot_start(cfg);
    if (rc != 0) return rc;
    return nlboot_wait();
}
