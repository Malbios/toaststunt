// Unit tests for the pure list-manipulation core in src/list.cc (as
// opposed to the bf_* built-in-function wrappers in the second half of
// that file, which aren't in scope here).
#include "catch_amalgamated.hpp"
#include "structures.h"
#include "list.h"

extern int invalid_pair(int num1, int num2, int max); // list.cc:1359, not declared in any header

static Var int_list(std::initializer_list<Num> values) {
    Var list = new_list((int)values.size());
    int i = 1;
    for (Num v : values)
        list.v.list[i++] = Var::new_int(v);
    return list;
}

TEST_CASE("new_list of size 0 reports length 0", "[list]") {
    Var list = new_list(0);
    REQUIRE(list.type == TYPE_LIST);
    REQUIRE(list.v.list[0].v.num == 0);
}

TEST_CASE("new_list of size n reports length n", "[list]") {
    Var list = new_list(3);
    REQUIRE(list.v.list[0].v.num == 3);
}

TEST_CASE("listappend grows the list by one and preserves order", "[list]") {
    Var list = int_list({1, 2});
    list = listappend(list, Var::new_int(3));
    REQUIRE(list.v.list[0].v.num == 3);
    REQUIRE(list.v.list[1].v.num == 1);
    REQUIRE(list.v.list[2].v.num == 2);
    REQUIRE(list.v.list[3].v.num == 3);
}

TEST_CASE("listinsert places a value at the given 1-based position", "[list]") {
    Var list = int_list({1, 3});
    list = listinsert(list, Var::new_int(2), 2);
    REQUIRE(list.v.list[0].v.num == 3);
    REQUIRE(list.v.list[1].v.num == 1);
    REQUIRE(list.v.list[2].v.num == 2);
    REQUIRE(list.v.list[3].v.num == 3);
}

TEST_CASE("listdelete removes the element at the given position", "[list]") {
    Var list = int_list({1, 2, 3});
    list = listdelete(list, 2);
    REQUIRE(list.v.list[0].v.num == 2);
    REQUIRE(list.v.list[1].v.num == 1);
    REQUIRE(list.v.list[2].v.num == 3);
}

TEST_CASE("listset replaces the element at the given position", "[list]") {
    Var list = int_list({1, 2, 3});
    list = listset(list, Var::new_int(99), 2);
    REQUIRE(list.v.list[2].v.num == 99);
}

TEST_CASE("listconcat concatenates two lists in order", "[list]") {
    Var a = int_list({1, 2});
    Var b = int_list({3, 4});
    Var result = listconcat(a, b);
    REQUIRE(result.v.list[0].v.num == 4);
    REQUIRE(result.v.list[1].v.num == 1);
    REQUIRE(result.v.list[2].v.num == 2);
    REQUIRE(result.v.list[3].v.num == 3);
    REQUIRE(result.v.list[4].v.num == 4);
}

TEST_CASE("sublist extracts an inclusive 1-based range", "[list]") {
    Var list = int_list({10, 20, 30, 40});
    Var result = sublist(list, 2, 3);
    REQUIRE(result.v.list[0].v.num == 2);
    REQUIRE(result.v.list[1].v.num == 20);
    REQUIRE(result.v.list[2].v.num == 30);
}

TEST_CASE("listrangeset replaces an inclusive range with another list's contents", "[list]") {
    // {1,2,3,4,5}, positions 2-4 ({2,3,4}, 3 elements) replaced with {8,9}
    // (2 elements) -> net length 5 - 3 + 2 = 4: {1,8,9,5}.
    Var base = int_list({1, 2, 3, 4, 5});
    Var value = int_list({8, 9});
    Var result = listrangeset(base, 2, 4, value);
    REQUIRE(result.v.list[0].v.num == 4);
    REQUIRE(result.v.list[1].v.num == 1);
    REQUIRE(result.v.list[2].v.num == 8);
    REQUIRE(result.v.list[3].v.num == 9);
    REQUIRE(result.v.list[4].v.num == 5);
}

TEST_CASE("listequal compares element-by-element", "[list]") {
    Var a = int_list({1, 2, 3});
    Var b = int_list({1, 2, 3});
    Var c = int_list({1, 2, 4});
    REQUIRE(listequal(a, b, 1) == 1);
    REQUIRE(listequal(a, c, 1) == 0);
}

TEST_CASE("setadd only appends a value not already present", "[list]") {
    Var list = int_list({1, 2});
    list = setadd(list, Var::new_int(2)); // already present
    REQUIRE(list.v.list[0].v.num == 2);
    list = setadd(list, Var::new_int(3)); // new
    REQUIRE(list.v.list[0].v.num == 3);
    REQUIRE(list.v.list[3].v.num == 3);
}

TEST_CASE("setremove removes a present value and is a no-op otherwise", "[list]") {
    Var list = int_list({1, 2, 3});
    list = setremove(list, Var::new_int(2));
    REQUIRE(list.v.list[0].v.num == 2);
    REQUIRE(list.v.list[1].v.num == 1);
    REQUIRE(list.v.list[2].v.num == 3);

    Var list2 = int_list({1, 2});
    Var unchanged = setremove(list2, Var::new_int(99));
    REQUIRE(unchanged.v.list[0].v.num == 2);
}

TEST_CASE("invalid_pair rejects an out-of-range or malformed substitution pair", "[list][invalid_pair]") {
    // Used by the %<n> substitution machinery to sanity-check a {from, to}
    // pair before use - `max` is the highest valid index.
    REQUIRE(invalid_pair(0, -1, 5) == 0);  // the documented "empty" sentinel pair
    REQUIRE(invalid_pair(1, 3, 5) == 0);   // a normal, in-range pair
    REQUIRE(invalid_pair(1, 10, 5) != 0);  // past max
}
