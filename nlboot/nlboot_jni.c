/*
 * nlboot JNI bridge for the Android app (ART side).
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 NLauncher
 *
 * Kotlin counterpart (class name configurable with -DNLBOOT_JNI_CLASS=...):
 *
 *   object NativeBoot {
 *     @JvmStatic external fun start(javaHome: String, libjvm: String?, jvmOptions: Array<String>,
 *                                   mainClass: String, args: Array<String>, logPath: String?,
 *                                   flags: Int, stackSize: Long): Int
 *     @JvmStatic external fun waitFor(): Int
 *     @JvmStatic external fun running(): Boolean
 *     @JvmStatic external fun redirectStdio(logPath: String?, tag: String?): Int
 *     @JvmStatic external fun lastError(): String
 *     @JvmStatic external fun version(): String
 *     @JvmStatic external fun setenv(name: String, value: String): Int
 *   }
 *
 * Rule: HotSpot threads never call into ART. This file only runs on ART
 * threads (the Kotlin caller); the JVM itself lives on the "mc-main" thread.
 */
#include "nlboot.h"

#include <jni.h>
#include <stdlib.h>
#include <string.h>

#ifndef NLBOOT_JNI_CLASS
#define NLBOOT_JNI_CLASS "net/nlauncher/game/boot/NativeBoot"
#endif

static char *dup_jstring(JNIEnv *env, jstring s)
{
    if (!s) return NULL;
    const char *c = (*env)->GetStringUTFChars(env, s, NULL);
    if (!c) return NULL;
    char *r = strdup(c);
    (*env)->ReleaseStringUTFChars(env, s, c);
    return r;
}

static char **dup_jarray(JNIEnv *env, jobjectArray a, int *count)
{
    *count = a ? (*env)->GetArrayLength(env, a) : 0;
    char **r = calloc((size_t)*count + 1, sizeof(char *));
    for (int i = 0; r && i < *count; i++) {
        jstring s = (jstring)(*env)->GetObjectArrayElement(env, a, i);
        r[i] = dup_jstring(env, s);
        if (!r[i]) r[i] = strdup("");
        (*env)->DeleteLocalRef(env, s);
    }
    return r;
}

static void free_array(char **a, int n)
{
    if (!a) return;
    for (int i = 0; i < n; i++) free(a[i]);
    free(a);
}

static jint JNICALL n_start(JNIEnv *env, jclass cls, jstring java_home, jstring libjvm, jobjectArray jvm_opts,
                            jstring main_class, jobjectArray args, jstring log_path, jint flags, jlong stack)
{
    (void)cls;
    nlboot_config c;
    memset(&c, 0, sizeof c);
    char *home = dup_jstring(env, java_home);
    char *jvm = dup_jstring(env, libjvm);
    char *main = dup_jstring(env, main_class);
    char *log = dup_jstring(env, log_path);
    int n_opts = 0, n_args = 0;
    char **opts = dup_jarray(env, jvm_opts, &n_opts);
    char **argv = dup_jarray(env, args, &n_args);
    c.java_home = home;
    c.libjvm_path = jvm;
    c.jvm_options = (const char *const *)opts;
    c.n_jvm_options = n_opts;
    c.main_class = main;
    c.args = (const char *const *)argv;
    c.n_args = n_args;
    c.stack_size = stack > 0 ? (size_t)stack : 0;
    c.log_path = log;
    c.log_tag = "nlgame";
    c.flags = (unsigned)flags;
    int rc = nlboot_start(&c); /* copies everything it keeps */
    free(home);
    free(jvm);
    free(main);
    free(log);
    free_array(opts, n_opts);
    free_array(argv, n_args);
    return rc;
}

static jint JNICALL n_wait(JNIEnv *env, jclass cls)
{
    (void)env;
    (void)cls;
    return nlboot_wait();
}

static jboolean JNICALL n_running(JNIEnv *env, jclass cls)
{
    (void)env;
    (void)cls;
    return nlboot_running() ? JNI_TRUE : JNI_FALSE;
}

static jint JNICALL n_redirect(JNIEnv *env, jclass cls, jstring log_path, jstring tag)
{
    (void)cls;
    char *log = dup_jstring(env, log_path);
    char *t = dup_jstring(env, tag);
    int rc = nlboot_redirect_stdio(log, t);
    free(log);
    free(t);
    return rc;
}

static jstring JNICALL n_last_error(JNIEnv *env, jclass cls)
{
    (void)cls;
    return (*env)->NewStringUTF(env, nlboot_last_error());
}

static jstring JNICALL n_version(JNIEnv *env, jclass cls)
{
    (void)cls;
    return (*env)->NewStringUTF(env, NLBOOT_VERSION);
}

static jint JNICALL n_setenv(JNIEnv *env, jclass cls, jstring name, jstring value)
{
    (void)cls;
    char *k = dup_jstring(env, name);
    char *v = dup_jstring(env, value);
    int rc = (k && v) ? setenv(k, v, 1) : -1;
    free(k);
    free(v);
    return rc;
}

static const JNINativeMethod k_methods[] = {
    {"start",
     "(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;"
     "Ljava/lang/String;IJ)I",
     (void *)n_start},
    {"waitFor", "()I", (void *)n_wait},
    {"running", "()Z", (void *)n_running},
    {"redirectStdio", "(Ljava/lang/String;Ljava/lang/String;)I", (void *)n_redirect},
    {"lastError", "()Ljava/lang/String;", (void *)n_last_error},
    {"version", "()Ljava/lang/String;", (void *)n_version},
    {"setenv", "(Ljava/lang/String;Ljava/lang/String;)I", (void *)n_setenv},
};

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved)
{
    (void)reserved;
    JNIEnv *env = NULL;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    jclass cls = (*env)->FindClass(env, NLBOOT_JNI_CLASS);
    if (!cls) return JNI_ERR;
    if ((*env)->RegisterNatives(env, cls, k_methods, (jint)(sizeof k_methods / sizeof k_methods[0])) != 0)
        return JNI_ERR;
    return JNI_VERSION_1_6;
}
