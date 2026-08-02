// Unit tests for src/collection.cc's ismember (list case only - the map
// case delegates to mapforeach/map.cc, out of scope for this pass).
#include "catch_amalgamated.hpp"
#include "structures.h"
#include "list.h"
#include "collection.h"

TEST_CASE("ismember finds a present value and reports its 1-based position", "[ismember]") {
    Var list = new_list(3);
    list.v.list[1] = Var::new_int(10);
    list.v.list[2] = Var::new_int(20);
    list.v.list[3] = Var::new_int(30);

    REQUIRE(ismember(Var::new_int(20), list, 1) == 2);
}

TEST_CASE("ismember returns 0 when the value isn't present", "[ismember]") {
    Var list = new_list(2);
    list.v.list[1] = Var::new_int(10);
    list.v.list[2] = Var::new_int(20);

    REQUIRE(ismember(Var::new_int(99), list, 1) == 0);
}
