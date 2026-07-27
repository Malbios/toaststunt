// Link-satisfying stubs for symbols the server .cc files under test
// reference from code paths this unit-test suite never actually exercises
// (the bf_* built-in-function wrappers in list.cc/collection.cc/log.cc,
// and a couple of DB/pattern/option-cache dependencies pulled in only
// because a whole .cc file compiles as one unit - there's no way to
// compile just the pure functions we actually test out of it). None of
// these bodies matter; they only need to exist so the linker is satisfied.
// Growing this file is the deliberate, cheaper alternative to pulling in
// real implementations that would themselves cascade into needing a live
// object DB/VM/network stack - exactly what this test suite exists to
// avoid.
#include "config.h"
#include "structures.h"
#include "functions.h"
#include "map.h"
#include "pattern.h"
#include "server.h"
#include "unparse.h"
#include "db.h"
#include "quota.h"
#include "garbage.h"
#include "waif.h"
#include "background.h"
#include "sosemanuk.h"

#include <cstdio>
#include <cstdlib>

void panic_moo(const char *message) {
    std::fprintf(stderr, "panic_moo (unit-test stub): %s\n", message);
    std::abort();
}

// `nothing`/`clear` are normally defined in objects.cc (see structures.h's
// own comment); `zero` in numbers.cc, which IS linked here for real, so
// only these two need a stub definition. Plain field assignment rather
// than aggregate-init - Var's union's first member isn't numeric, so a
// `{ TYPE_OBJ, { -1 } }` brace-init tries (and fails) to initialize that
// member instead of `.v.obj`.
static Var make_nothing_var() {
    Var v;
    v.type = TYPE_OBJ;
    v.v.obj = -1;
    return v;
}
Var nothing = make_nothing_var();

static Var make_clear_var() {
    Var v;
    v.type = TYPE_CLEAR;
    return v;
}
Var clear = make_clear_var();

// --- map.h: no test here constructs a TYPE_MAP Var, so these are
// never actually reached at runtime, only linked. ---
void destroy_map(Var) {}
Var map_dup(Var map) { return map; }
const rbnode *maplookup(Var, Var, Var *, int) { return nullptr; }
int mapequal(Var, Var, int) { return 0; }
Num maplength(Var) { return 0; }
int mapempty(Var) { return 1; }
int map_sizeof(rbtree *) { return 0; }
void destroy_iter(Var) {}
Var iter_dup(Var iter) { return iter; }

// --- waif.h: no test here constructs a TYPE_WAIF Var. ---
std::unordered_map<Waif *, bool> destroyed_waifs;
Waif *dup_waif(Waif *w) { return w; }
int waif_bytes(Waif *) { return 0; }

// --- db.h/quota.h: object-DB accessors - none of the functions under
// test here need real object state (get_system_property/anonymizing_var_ref
// and complex_free_var's ANON/general branches are explicitly excluded
// from this test suite's scope, per the plan's candidate survey). ---
int valid(Objid) { return 0; }
db_prop_handle db_find_property(Var, const char *, Var *) { return db_prop_handle(); }
int db_is_property_built_in(db_prop_handle) { return 0; }
Objid db_object_owner2(Var) { return -1; }
int db_object_has_flag2(Var, db_object_flag) { return 0; }
void db_destroy_anonymous_object(void *) {}
void incr_quota(Objid) {}

// --- garbage.h: no test here constructs a TYPE_ANON Var. ---
void gc_possible_root(Var) {}
void queue_anonymous_object(Var) {}

// --- background.h: no test here calls a bf_* builtin wrapper directly. ---
package background_thread(void (*)(Var, Var *, void *), Var *, void *, void (*)(void *)) {
    package p;
    p.kind = package::BI_RETURN;
    p.u.ret = Var::new_int(0);
    return p;
}

// --- sosemanuk.h: bf_random_bytes' PRNG - no test here calls that builtin. ---
void sosemanuk_prng(sosemanuk_run_context *, unsigned char *out, size_t out_len) {
    for (size_t i = 0; i < out_len; i++)
        out[i] = 0;
}

package make_error_pack(enum error err) {
    package p;
    p.kind = package::BI_RAISE;
    p.u.raise.code.type = TYPE_ERR;
    p.u.raise.code.v.err = err;
    p.u.raise.msg = "";
    p.u.raise.value = Var::new_int(0);
    return p;
}

package make_abort_pack(enum abort_reason) {
    package p;
    p.kind = package::BI_KILL;
    return p;
}

package make_var_pack(Var v) {
    package p;
    p.kind = package::BI_RETURN;
    p.u.ret = v;
    return p;
}

package no_var_pack(void) {
    package p;
    p.kind = package::BI_RETURN;
    p.u.ret = Var::new_int(0);
    return p;
}

package make_float_pack(double v) {
    package p;
    p.kind = package::BI_RETURN;
    p.u.ret = Var::new_float(v);
    return p;
}

package make_raise_pack(enum error err, const char *msg, Var value) {
    package p;
    p.kind = package::BI_RAISE;
    p.u.raise.code.type = TYPE_ERR;
    p.u.raise.code.v.err = err;
    p.u.raise.msg = msg;
    p.u.raise.value = value;
    return p;
}

Num _server_int_option_cache[SVO__CACHE_SIZE];

int mapforeach(Var, mapfunc, void *) {
    return 0; // no map support needed - none of these tests construct a TYPE_MAP Var
}

const char *error_name(enum error) {
    return "";
}

const char *unparse_error(enum error) {
    return "";
}

Pattern new_pattern(const char *, int) {
    Pattern p;
    p.ptr = nullptr;
    return p;
}

Match_Result match_pattern(Pattern, const char *, Match_Indices *, int) {
    return MATCH_FAILED;
}

void free_pattern(Pattern) {
}

unsigned register_function(const char *, int, int, bf_type, ...) {
    return 0;
}

int is_wizard(Objid) {
    return 0;
}
