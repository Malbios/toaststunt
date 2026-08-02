// Unit tests for src/str_intern.cc's public API - a self-contained
// module-static hash table, no DB/network/VM dependency. Needs an
// open/close pair around each test (module-global state).
#include <cstring>

#include "catch_amalgamated.hpp"
#include "str_intern.h"

TEST_CASE("str_intern returns the same pointer for two equal strings while the table is open", "[str_intern]") {
    str_intern_open(0);
    const char *a = str_intern("hello");
    const char *b = str_intern("hello");
    REQUIRE(a == b); // interned - genuinely the same allocation, not just equal content
    str_intern_close();
}

TEST_CASE("str_intern returns distinct content for different strings", "[str_intern]") {
    str_intern_open(0);
    const char *a = str_intern("hello");
    const char *b = str_intern("goodbye");
    REQUIRE(a != b);
    REQUIRE(strcmp(a, "hello") == 0);
    REQUIRE(strcmp(b, "goodbye") == 0);
    str_intern_close();
}
