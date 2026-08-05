/******************************************************************************
  Copyright (c) 1992, 1995, 1996 Xerox Corporation.  All rights reserved.
  Portions of this code were written by Stephen White, aka ghond.
  Use and copying of this software and preparation of derivative works based
  upon this software are permitted.  Any distribution of this software or
  derivative works must comply with all applicable United States export
  control laws.  This software is made available AS IS, and Xerox Corporation
  makes no warranty about the software, its performance or its conformity to
  any specification.  Any person obtaining a copy of this software is requested
  to send their name and post office or electronic mail address to:
    Pavel Curtis
    Xerox PARC
    3333 Coyote Hill Rd.
    Palo Alto, CA 94304
    Pavel@Xerox.Com
 *****************************************************************************/

#include <stdlib.h>
#include <string.h>
#include <mutex>

#include "config.h"
#include "list.h"
#include "options.h"
#include "server.h"
#include "storage.h"
#include "structures.h"
#include "utils.h"

#ifdef TRACE_REFCOUNT
#include <cstdio>
#include <execinfo.h>
#include <pthread.h>

#ifndef TRACE_REFCOUNT_MAX_EVENTS
#define TRACE_REFCOUNT_MAX_EVENTS 200000
#endif

/* Investigation-only (see options.h): backtrace-logging tracer for every
 * refcount change to the emptylist/emptymap singleton payloads. Targets are
 * set once by new_list()/new_map() right after each singleton is created. */
const void *g_refcount_trace_target = nullptr;
const void *g_refcount_trace_target2 = nullptr;

void
trace_refcount_event(const void *ptr, const char *op, uint32_t new_value)
{
    static std::atomic<unsigned long> event_count{0};
    static std::once_flag log_init;
    static FILE *log_file = nullptr;
    static std::mutex log_mutex;

    void *frames[32];
    int n_frames = backtrace(frames, 32);

    std::call_once(log_init, []() {
        log_file = fopen("refcount_trace.log", "w");
        if (log_file)
            setvbuf(log_file, nullptr, _IOLBF, 0);
    });

    if (!log_file)
        return;

    unsigned long seq = event_count.fetch_add(1);
    if (seq > TRACE_REFCOUNT_MAX_EVENTS)
        return;

    std::lock_guard<std::mutex> lock(log_mutex);

    if (seq == TRACE_REFCOUNT_MAX_EVENTS) {
        fprintf(log_file, "CAPPED at %d events, no further refcount events will be logged\n",
                TRACE_REFCOUNT_MAX_EVENTS);
        return;
    }

    fprintf(log_file, "%lu thread=%lu ptr=%p op=%s refcount=%u", seq,
            (unsigned long) pthread_self(), ptr, op, new_value);
    for (int i = 0; i < n_frames; i++)
        fprintf(log_file, " %p", frames[i]);
    fprintf(log_file, "\n");
}
#endif /* TRACE_REFCOUNT */

static inline int
refcount_overhead(Memory_Type type)
{
    /* These are the only allocation types that are addref()'d.
     * As long as we're living on the wild side, avoid getting the
     * refcount slot for allocations that won't need it.
     */
    int total = 0;
    switch (type) {
        /* deal with systems with picky alignment issues */
        case M_LIST:
        case M_TREE:
        case M_TRAV:
        case M_ANON:
        case M_WAIF:
        case M_STRING:
            total = sizeof(var_metadata);
            break;
        default:
            total = 0;
    }

    return total;
}

void *
mymalloc(unsigned size, Memory_Type type)
{
    char *memptr;
    char msg[100];
    int offs;

    if (size == 0)      /* For queasy systems */
        size = 1;

    offs = refcount_overhead(type);
    memptr = (char *) malloc(offs + size);
    if (!memptr) {
        sprintf(msg, "memory allocation (size %u) failed!", size);
        panic_moo(msg);
    }

    if (offs) {
        memptr += offs;
        var_metadata *metadata = (var_metadata *)(memptr - sizeof(var_metadata));

        metadata->refcount = 1;

#ifdef ENABLE_GC
        if (type == M_LIST || type == M_TREE || type == M_ANON) {
            metadata->buffered = 0;
            metadata->color = (type == M_ANON) ? GC_BLACK : GC_GREEN;
        }
#endif /* ENABLE_GC */

#ifdef MEMO_SIZE
        if (type == M_STRING)
            metadata->size = size - 1;
#endif /* MEMO_SIZE */

#ifdef MEMO_SIZE
        if (type == M_LIST || type == M_TREE)
            metadata->size = 0;
#endif /* MEMO_SIZE */

    }
    return memptr;
}

/* Bandaid mirroring the emptylist/emptymap one (see the comment at the top
 * of list.cc): exposing this as a global lets free_str() (storage.h) skip
 * freeing it if its refcount would otherwise hit zero. Its refcount is
 * pinned at the value mymalloc() gives it at creation and never adjusted
 * again in either direction -- str_dup() and str_ref() below, and
 * complex_var_ref()'s TYPE_STR case (utils.cc), all skip the addref that
 * would otherwise apply. Without that, the count would climb forever
 * (nothing ever brought it back down even before this fix) and eventually
 * overflow and wrap back through zero, reproducing the exact premature-free
 * crash this guards against -- the same failure mode already fixed for
 * emptylist/emptymap. */
const char *emptystring;

const char *
str_ref(const char *s)
{
    if (s != emptystring)
        addref(s);
    return s;
}

char *
str_dup(const char *s)
{
    char *r;

    if (s == nullptr || *s == '\0') {
        static std::once_flag emptystring_init;

        std::call_once(emptystring_init, []() {
            char *ptr = (char *) mymalloc(1, M_STRING);
            *ptr = '\0';
            emptystring = ptr;
        });
        return (char *) emptystring;
    } else {
        r = (char *) mymalloc(strlen(s) + 1, M_STRING); /* NO MEMO HERE */
        strcpy(r, s);
    }
    return r;
}

void *
myrealloc(void *ptr, unsigned size, Memory_Type type)
{
    int offs = refcount_overhead(type);
    static char msg[100];

    ptr = realloc((char *) ptr - offs, size + offs);
    if (!ptr) {
        sprintf(msg, "memory re-allocation (size %u) failed!", size);
        panic_moo(msg);
    }

    return (char *) ptr + offs;
}

void
myfree(void *ptr, Memory_Type type)
{
    free((char *) ptr - refcount_overhead(type));
}
