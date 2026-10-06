/*
 * Copyright (c) 2026 NLauncher
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * je_free_sized / je_free_aligned_sized for jemalloc 5.3.0.
 *
 * LWJGL 3.3.3 (org.lwjgl.system.jemalloc.JEmalloc) resolves these two symbols
 * eagerly. They exist in jemalloc's development branch (C23 free_sized and
 * free_aligned_sized) but not in the 5.3.0 release, so we provide them on top
 * of je_sdallocx(), which has the same contract: the size (and alignment) must
 * be the ones the memory was allocated with.
 */
#include <stddef.h>
#include <jemalloc/jemalloc.h>

JEMALLOC_EXPORT void je_free_sized(void *ptr, size_t size)
{
    if (ptr != NULL) {
        je_sdallocx(ptr, size, 0);
    }
}

JEMALLOC_EXPORT void je_free_aligned_sized(void *ptr, size_t alignment, size_t size)
{
    if (ptr != NULL) {
        je_sdallocx(ptr, size, MALLOCX_ALIGN(alignment));
    }
}
