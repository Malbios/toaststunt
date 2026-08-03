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

#include <algorithm>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <vector>

#include "config.h"
#include "db.h"
#include "functions.h"
#include "list.h"
#include "structures.h"
#include "match.h"
#include "parse_cmd.h"
#include "server.h"
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
 * front of `str`. Returns the ordinal value (0 if none was found) and sets
 * `*rest_out` to the remainder after the ordinal and any following
 * whitespace, or to `str` unchanged if no ordinal was found. Shared by the
 * `parse_ordinal` builtin and complex_match()'s ordinal disambiguation
 * below, so there's only one ordinal parser in the codebase rather than two
 * independent ones. */
static int
parse_leading_ordinal(const char *str, const char **rest_out)
{
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

    *rest_out = rest;
    return value;
}

/* Combines an object's real name and its `.aliases` property into a single
 * flat list of candidate-matching keys, for complex_match()'s per-candidate
 * key-list comparison below (unlike match_proc()'s name-then-each-alias
 * loop, complex_match() wants one flat list per candidate). */
static Var
name_and_aliases(Objid oid)
{
    Var *names = aliases(oid);
    int n = names[0].v.num;
    Var result = new_list(n + 1);

    result.v.list[1] = str_dup_to_var(db_object_name(oid));
    for (int i = 1; i <= n; i++)
        result.v.list[i + 1] = var_ref(names[i]);

    return result;
}

struct complex_match_data {
    Var targets;    /* list of Objid Vars, parallel to `keys` */
    Var keys;       /* list of name_and_aliases() lists, one per candidate */
};

static int
complex_match_collect(void *data, Objid oid)
{
    struct complex_match_data *d = (struct complex_match_data *)data;

    d->targets = listappend(d->targets, Var::new_obj(oid));
    d->keys = listappend(d->keys, name_and_aliases(oid));

    return 0;
}

static void
push_if_not_exists(std::vector<int> &vec, int value)
{
    if (std::find(vec.begin(), vec.end(), value) == vec.end())
        vec.push_back(value);
}

/* Three-tier object matching: exact (case-insensitive equality), starts-with,
 * and contains-anywhere, checked against every name/alias key of every
 * candidate. A leading ordinal word ("2nd", "twenty-third") is stripped from
 * `input` first and used to select the Nth candidate within whichever tier
 * has that many entries, rather than requiring an exact/unique match.
 * Returns the (1-based-into-`keys`) indices of the matching candidates:
 * empty for no match, one element for a unique or ordinal-selected match,
 * more than one for an ambiguous match. */
static std::vector<int>
complex_match(const char *input, Var *keys)
{
    if (keys->v.list[0].v.num <= 0)
        return {};

    const char *rest;
    int ordinal = parse_leading_ordinal(input, &rest);
    const char *subject = (ordinal > 0) ? rest : input;

    if (*subject == '\0')
        return {};

    int subject_len = (int) strlen(subject);
    std::vector<int> exact_matches, start_matches, contain_matches;

    for (int i = 1; i <= keys->v.list[0].v.num; i++) {
        Var *candidate_keys = keys->v.list[i].v.list;
        for (int j = 1; j <= candidate_keys[0].v.num; j++) {
            if (candidate_keys[j].type != TYPE_STR)
                continue;
            const char *key = candidate_keys[j].v.str;
            int key_len = (int) memo_strlen(key);

            if (!strcasecmp(subject, key))
                push_if_not_exists(exact_matches, i);
            if (strindex(key, key_len, subject, subject_len, 0) == 1)
                push_if_not_exists(start_matches, i);
            if (strindex(key, key_len, subject, subject_len, 0) >= 1)
                push_if_not_exists(contain_matches, i);
        }
    }

    if (ordinal > 0) {
        if ((size_t) ordinal <= exact_matches.size())
            return { exact_matches[ordinal - 1] };
        if ((size_t) ordinal <= start_matches.size())
            return { start_matches[ordinal - 1] };
        if ((size_t) ordinal <= contain_matches.size())
            return { contain_matches[ordinal - 1] };
        return {};
    }

    if (!exact_matches.empty())
        return exact_matches;
    if (!start_matches.empty())
        return start_matches;
    return contain_matches;
}

Objid
match_object(Objid player, const char *name)
{
    if (name[0] == '\0')
        return NOTHING;
    if (name[0] == '#') {
        /* Referencing an object by raw number bypasses name/alias matching
         * entirely, so it's restricted to wizards and programmers rather
         * than left open to any player. */
        if (!is_wizard(player) && !is_programmer(player))
            return FAILED_MATCH;

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
    if (!server_flag_option_cached(SVO_MATCH_MODE))
        return match_contents(player, name);

    Objid loc;
    int step;
    Objid oid;
    struct complex_match_data d = { new_list(0), new_list(0) };

    loc = db_object_location(player);
    for (oid = player, step = 0; step < 2; oid = loc, step++) {
        if (!valid(oid))
            continue;
        db_for_all_contents(oid, complex_match_collect, &d);
    }

    std::vector<int> matches = complex_match(name, &d.keys);
    Objid result;
    if (matches.empty())
        result = FAILED_MATCH;
    else if (matches.size() == 1)
        result = d.targets.v.list[matches[0]].v.obj;
    else
        result = AMBIGUOUS;

    free_var(d.targets);
    free_var(d.keys);
    return result;
}

static package
bf_parse_ordinal(Var arglist, Byte next, void *vdata, Objid progr)
{   /* (str) */
    const char *str = arglist.v.list[1].v.str;
    const char *rest;
    int value = parse_leading_ordinal(str, &rest);

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
