/*
 * nljava — tiny `java`-like executable on top of nlboot.
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 NLauncher
 *
 * On Android it is packaged as lib/arm64-v8a/libnljava.so (the only place an
 * app may exec from) and used for the "separate native process" variant.
 * On a desktop host it is used by the tests.
 *
 * Usage:
 *   nljava [--java-home DIR] [--libjvm FILE] [--log FILE] [--xrs] [--preload]
 *          [--stack-mb N] [JVM options...] (-cp|-classpath|--class-path) CP
 *          MAINCLASS [args...]
 * JAVA_HOME is used when --java-home is absent.
 */
#include "nlboot.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int usage(void)
{
    fprintf(stderr, "usage: nljava [--java-home DIR] [--libjvm FILE] [--log FILE] [--xrs] [--preload] [--stack-mb N]\n"
                    "              [jvm options] -cp CLASSPATH MAINCLASS [args...]\n");
    return 2;
}

int main(int argc, char **argv)
{
    const char *home = getenv("JAVA_HOME");
    const char *libjvm = NULL, *log = NULL;
    unsigned flags = NLBOOT_DESTROY_VM;
    size_t stack = 0;
    const char **opts = calloc((size_t)argc + 2, sizeof(char *));
    char *cp_opt = NULL;
    int n_opts = 0, i = 1;
    if (!opts) return 1;

    for (; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "--java-home") && i + 1 < argc) home = argv[++i];
        else if (!strcmp(a, "--libjvm") && i + 1 < argc) libjvm = argv[++i];
        else if (!strcmp(a, "--log") && i + 1 < argc) { log = argv[++i]; flags |= NLBOOT_REDIRECT_STDIO; }
        else if (!strcmp(a, "--xrs")) flags |= NLBOOT_REDUCE_SIGNALS;
        else if (!strcmp(a, "--preload")) flags |= NLBOOT_PRELOAD_JRE_LIBS;
        else if (!strcmp(a, "--stack-mb") && i + 1 < argc) stack = (size_t)atoi(argv[++i]) << 20;
        else if ((!strcmp(a, "-cp") || !strcmp(a, "-classpath") || !strcmp(a, "--class-path")) && i + 1 < argc) {
            const char *cp = argv[++i];
            cp_opt = malloc(strlen(cp) + 32);
            if (!cp_opt) return 1;
            sprintf(cp_opt, "-Djava.class.path=%s", cp);
            opts[n_opts++] = cp_opt;
        } else if (a[0] == '-') opts[n_opts++] = a;
        else break;
    }
    if (i >= argc || !home) return usage();

    nlboot_config c;
    memset(&c, 0, sizeof c);
    c.java_home = home;
    c.libjvm_path = libjvm;
    c.jvm_options = opts;
    c.n_jvm_options = n_opts;
    c.main_class = argv[i];
    c.args = (const char *const *)(argv + i + 1);
    c.n_args = argc - i - 1;
    c.stack_size = stack;
    c.log_path = log;
    c.log_tag = "nljava";
    c.flags = flags;
    int rc = nlboot_run(&c);
    free(cp_opt);
    free(opts);
    if (rc < 0) {
        fprintf(stderr, "nljava: %s\n", nlboot_last_error());
        return 100 - rc; /* 101.. for nlboot errors */
    }
    return rc;
}
