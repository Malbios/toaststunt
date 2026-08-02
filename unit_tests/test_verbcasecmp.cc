// Unit tests for verbcasecmp (src/utils.cc:76-110) - the verb-name matcher
// backing verb_code()/set_verb_code()/verb_info()/verb_args() (via
// db_find_defined_verb, src/db_verbs.cc). Seeded specifically to pin down
// its star-abbreviation matching and its pointer-identity fast path - both
// discovered live, the hard way, while tracking down a real bug where
// `l*ook` (a verb whose *only* declared name uses the `*` abbreviation
// marker) could not be opened through $vcs:ide_fetch/ide_save. See the
// project plan's "Open follow-ups" section for the full writeup.
#include "catch_amalgamated.hpp"
#include "utils.h"

TEST_CASE("verbcasecmp matches the full verb name", "[verbcasecmp]") {
    REQUIRE(verbcasecmp("look", "look") == 1);
}

TEST_CASE("verbcasecmp is case-insensitive", "[verbcasecmp]") {
    REQUIRE(verbcasecmp("Look", "LOOK") == 1);
    REQUIRE(verbcasecmp("look", "Look") == 1);
}

TEST_CASE("verbcasecmp rejects a word the verb name doesn't start with", "[verbcasecmp]") {
    REQUIRE(verbcasecmp("look", "took") == 0);
    REQUIRE(verbcasecmp("look", "lookx") == 0);
}

TEST_CASE("verbcasecmp * abbreviation matches every prefix from the minimum to the full word", "[verbcasecmp][star]") {
    // "l*ook" means "l", "lo", "loo", and "look" are all valid abbreviations.
    REQUIRE(verbcasecmp("l*ook", "l") == 1);
    REQUIRE(verbcasecmp("l*ook", "lo") == 1);
    REQUIRE(verbcasecmp("l*ook", "loo") == 1);
    REQUIRE(verbcasecmp("l*ook", "look") == 1);
}

TEST_CASE("verbcasecmp * abbreviation rejects a prefix shorter than the minimum", "[verbcasecmp][star]") {
    // The minimum abbreviation for "l*ook" is "l" - there's nothing shorter
    // to reject in this specific case, but a word that doesn't even match
    // the minimum prefix must fail.
    REQUIRE(verbcasecmp("l*ook", "x") == 0);
}

TEST_CASE("verbcasecmp * abbreviation rejects a word past the full form", "[verbcasecmp][star]") {
    REQUIRE(verbcasecmp("l*ook", "looks") == 0);
}

TEST_CASE("verbcasecmp checks every space-separated alternative in the declared name", "[verbcasecmp][multi-name]") {
    // A verb declared as "look l*ook" (two names for the same verb, one
    // plain and one star-abbreviated) must match a search word against
    // *either* alternative.
    REQUIRE(verbcasecmp("look l*ook", "look") == 1);
    REQUIRE(verbcasecmp("look l*ook", "l") == 1);
    REQUIRE(verbcasecmp("look l*ook", "loo") == 1);
    REQUIRE(verbcasecmp("look l*ook", "took") == 0);
}

TEST_CASE("verbcasecmp fails when the search word itself contains a literal star", "[verbcasecmp][star][regression]") {
    // THE BUG. A verb whose *only* declared name uses the `*` marker (e.g.
    // "l*ook", with no separate plain "look" alias) naturally gets passed
    // back into verb_code()/verb_info()/etc. as its own search word by any
    // code that iterates verbs() and echoes the name back (exactly what
    // $vcs:ide_fetch/ide_save/capture_verb/export_metadata all did before
    // being fixed - see the project plan's "Open follow-ups"). One would
    // expect a verb to always be found by its own exact declared name, but
    // it is not: two freshly-allocated (non-pointer-identical) copies of
    // the literal string "l*ook" do NOT match each other here. This is the
    // real, current behavior of this function - not the desired behavior,
    // but what it actually does - confirmed against a live ToastStunt
    // instance during that investigation, not just by reading this test's
    // own assertion. If this test ever starts failing (i.e. this line
    // suddenly returns 1), the star-handling logic changed and every one
    // of the $vcs call sites that now explicitly strips `*` before calling
    // verb_code()/verb_info() should be re-examined - they may no longer
    // need the workaround, or worse, may now be double-stripping a name
    // that would have matched correctly on its own.
    char verb[] = "l*ook";
    char word[] = "l*ook";
    REQUIRE(verb != word); // guard: these must be two distinct allocations, not the same pointer
    REQUIRE(verbcasecmp(verb, word) == 0);
}

TEST_CASE("verbcasecmp's pointer-identity fast path returns a match regardless of content", "[verbcasecmp][pointer-identity][regression]") {
    // `if (verb == word) return 1;` (utils.cc:85-87) runs before any of the
    // real star-matching logic. When the exact same pointer is passed for
    // both arguments, this masks the bug above entirely - which is exactly
    // why iterating verbs() and passing its own returned string straight
    // back into a lookup can *appear* to work for a single-name star verb
    // (verbs() returns a reference-counted alias of the verbdef's own name,
    // not a copy) while being fundamentally broken the moment any string
    // operation (even a harmless-looking `+ ""`) forces a fresh allocation.
    // This test pins that fast path down explicitly so a future change to
    // verbcasecmp can't silently remove it without a test noticing.
    const char *same = "l*ook";
    REQUIRE(verbcasecmp(same, same) == 1);
}
