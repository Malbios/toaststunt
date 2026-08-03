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

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "db.h"
#include "functions.h"
#include "list.h"
#include "structures.h"
#include "match.h"
#include "parse_cmd.h"
#include "storage.h"
#include "unparse.h"
#include "utils.h"

static Var *
aliases(Objid oid)
{
    Var value;
    db_prop_handle h;

    h = db_find_property(Var::new_obj(oid), "aliases", &value);
    if (!h.ptr || value.type != TYPE_LIST) {
        /* Simulate a pointer to an empty list */
        return &zero;
    } else
        return value.v.list;
}

struct match_data {
    int lname;
    const char *name;
    Objid exact, partial;
};

static int
match_proc(void *data, Objid oid)
{
    struct match_data *d = (struct match_data *)data;
    Var *names = aliases(oid);
    int i;
    const char *name;

    for (i = 0; i <= names[0].v.num; i++) {
        if (i == 0)
            name = db_object_name(oid);
        else if (names[i].type != TYPE_STR)
            continue;
        else
            name = names[i].v.str;

        if (!strncasecmp(name, d->name, d->lname)) {
            if (name[d->lname] == '\0') {   /* exact match */
                if (d->exact == NOTHING || d->exact == oid)
                    d->exact = oid;
                else
                    return 1;
            } else {        /* partial match */
                if (d->partial == FAILED_MATCH || d->partial == oid)
                    d->partial = oid;
                else
                    d->partial = AMBIGUOUS;
            }
        }
    }

    return 0;
}

static Objid
match_contents(Objid player, const char *name)
{
    Objid loc;
    int step;
    Objid oid;
    struct match_data d;

    d.lname = strlen(name);
    d.name = name;
    d.exact = NOTHING;
    d.partial = FAILED_MATCH;

    if (!valid(player))
        return FAILED_MATCH;
    loc = db_object_location(player);

    for (oid = player, step = 0; step < 2; oid = loc, step++) {
        if (!valid(oid))
            continue;
        if (db_for_all_contents(oid, match_proc, &d))
            /* We only abort the enumeration for exact ambiguous matches... */
            return AMBIGUOUS;
    }

    if (d.exact != NOTHING)
        return d.exact;
    else
        return d.partial;
}

Objid
match_object(Objid player, const char *name)
{
    if (name[0] == '\0')
        return NOTHING;
    if (name[0] == '#') {
        char *p;
        Objid r = strtol(name + 1, &p, 10);

        if (*p != '\0' || !valid(r))
            return FAILED_MATCH;
        return r;
    }
    if (!valid(player))
        return FAILED_MATCH;
    if (!strcasecmp(name, "me"))
        return player;
    if (!strcasecmp(name, "here"))
        return db_object_location(player);
    return match_contents(player, name);
}

struct ordinal_word {
    const char *name;
    int value;
};

/* first..ninth; also doubles as the second half of a compound tens ordinal
 * ("twenty-third" -> TENS_CARDINALS["twenty"] + ONES_ORDINALS["third"]). */
static const struct ordinal_word ONES_ORDINALS[] = {
    {"first", 1}, {"second", 2}, {"third", 3}, {"fourth", 4}, {"fifth", 5},
    {"sixth", 6}, {"seventh", 7}, {"eighth", 8}, {"ninth", 9},
};

static const struct ordinal_word TEENS_ORDINALS[] = {
    {"tenth", 10}, {"eleventh", 11}, {"twelfth", 12}, {"thirteenth", 13},
    {"fourteenth", 14}, {"fifteenth", 15}, {"sixteenth", 16},
    {"seventeenth", 17}, {"eighteenth", 18}, {"nineteenth", 19},
};

/* Exact multiples of ten as ordinals ("twentieth"), distinct from the
 * cardinal spelling ("twenty") used in a compound like "twenty-first". */
static const struct ordinal_word TENS_ORDINALS[] = {
    {"twentieth", 20}, {"thirtieth", 30}, {"fortieth", 40}, {"fiftieth", 50},
    {"sixtieth", 60}, {"seventieth", 70}, {"eightieth", 80}, {"ninetieth", 90},
};

static const struct ordinal_word TENS_CARDINALS[] = {
    {"twenty", 20}, {"thirty", 30}, {"forty", 40}, {"fifty", 50},
    {"sixty", 60}, {"seventy", 70}, {"eighty", 80}, {"ninety", 90},
};

#define TABLE_LEN(t) (sizeof(t) / sizeof((t)[0]))

static int
lookup_ordinal_word(const char *word, size_t len, const struct ordinal_word *table, size_t table_len)
{
    for (size_t i = 0; i < table_len; i++)
        if (strlen(table[i].name) == len && !strncasecmp(word, table[i].name, len))
            return table[i].value;
    return 0;
}

/* Splits a leading ordinal -- numeric ("2nd", lenient about digit/suffix
 * agreement) or spelled out ("third", "twenty-third", up to "ninety-ninth"
 * -- larger word-form scales like "hundredth" aren't handled) -- off the
 * front of a string. Returns {ordinal-or-0, remainder}; 0 means no leading
 * ordinal was found and remainder is the input unchanged. */
static package
bf_parse_ordinal(Var arglist, Byte next, void *vdata, Objid progr)
{   /* (str) */
    const char *str = arglist.v.list[1].v.str;
    const char *p = str;
    int value = 0;
    const char *rest = str;

    if (isdigit((unsigned char)*p)) {
        const char *digits_end = p;
        while (isdigit((unsigned char)*digits_end))
            digits_end++;
        char c0 = tolower((unsigned char)digits_end[0]);
        char c1 = tolower((unsigned char)digits_end[1]);
        if ((c0 == 's' && c1 == 't') || (c0 == 'n' && c1 == 'd')
                || (c0 == 'r' && c1 == 'd') || (c0 == 't' && c1 == 'h')) {
            value = atoi(p);
            rest = digits_end + 2;
        }
    }

    if (value == 0) {
        const char *word_end = p;
        while (isalpha((unsigned char)*word_end) || *word_end == '-')
            word_end++;
        size_t word_len = word_end - p;

        if (word_len > 0) {
            int v = lookup_ordinal_word(p, word_len, ONES_ORDINALS, TABLE_LEN(ONES_ORDINALS));
            if (!v)
                v = lookup_ordinal_word(p, word_len, TEENS_ORDINALS, TABLE_LEN(TEENS_ORDINALS));
            if (!v)
                v = lookup_ordinal_word(p, word_len, TENS_ORDINALS, TABLE_LEN(TENS_ORDINALS));
            if (!v) {
                const char *dash = (const char *)memchr(p, '-', word_len);
                if (dash) {
                    size_t left_len = dash - p;
                    size_t right_len = word_end - (dash + 1);
                    int tens = lookup_ordinal_word(p, left_len, TENS_CARDINALS, TABLE_LEN(TENS_CARDINALS));
                    int ones = lookup_ordinal_word(dash + 1, right_len, ONES_ORDINALS, TABLE_LEN(ONES_ORDINALS));
                    if (tens && ones)
                        v = tens + ones;
                }
            }
            if (v) {
                value = v;
                rest = word_end;
            }
        }
    }

    if (value != 0) {
        while (*rest == ' ' || *rest == '\t')
            rest++;
    } else {
        rest = str;
    }

    Var result = new_list(2);
    result.v.list[1].type = TYPE_INT;
    result.v.list[1].v.num = value;
    result.v.list[2].type = TYPE_STR;
    result.v.list[2].v.str = str_dup(rest);

    free_var(arglist);
    return make_var_pack(result);
}

void
register_match(void)
{
    register_function("parse_ordinal", 1, 1, bf_parse_ordinal, TYPE_STR);
}
