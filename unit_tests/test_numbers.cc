// Unit tests for the pure/near-pure free functions in src/numbers.cc -
// number parsing and MOO arithmetic semantics (strict, no int/float
// coercion - see the file's own comment above do_equals).
#include "catch_amalgamated.hpp"
#include "structures.h"
#include "numbers.h"

// Declared in sqlite.h (an odd home for it) rather than numbers.h - avoid
// pulling in <sqlite3.h> (an optional system dependency) just for this one
// prototype; the real definition lives in src/numbers.cc regardless.
extern int parse_float(const char *str, double *result);

TEST_CASE("parse_number parses a plain integer", "[parse_number]") {
    Num result = 0;
    REQUIRE(parse_number("42", &result, 0) == 1);
    REQUIRE(result == 42);
}

TEST_CASE("parse_number rejects trailing garbage", "[parse_number]") {
    Num result = 0;
    REQUIRE(parse_number("42x", &result, 0) == 0);
}

TEST_CASE("parse_number falls back to floating point when asked and the input isn't a plain int", "[parse_number]") {
    Num result = 0;
    REQUIRE(parse_number("3.14", &result, 1) == 1);
    REQUIRE(result == 3); // truncated through the Num cast, same as the real function's own behavior
}

TEST_CASE("parse_number rejects a float-looking input when try_floating_point is off", "[parse_number]") {
    // "3." fails strtoimax outright (p == str), so this must fail rather
    // than silently parsing "3".
    Num result = -1;
    REQUIRE(parse_number("3.", &result, 0) == 0);
}

TEST_CASE("parse_float parses a plain float", "[parse_float]") {
    double result = 0.0;
    REQUIRE(parse_float("3.5", &result) == 1);
    REQUIRE(result == Catch::Approx(3.5));
}

TEST_CASE("parse_float handles a leading sign and leading spaces", "[parse_float]") {
    double result = 0.0;
    REQUIRE(parse_float("  -2.5", &result) == 1);
    REQUIRE(result == Catch::Approx(-2.5));
}

TEST_CASE("parse_float rejects trailing garbage", "[parse_float]") {
    double result = 0.0;
    REQUIRE(parse_float("3.5x", &result) == 0);
}

TEST_CASE("compare_integers orders numerically", "[compare_integers]") {
    REQUIRE(compare_integers(1, 2) < 0);
    REQUIRE(compare_integers(2, 1) > 0);
    REQUIRE(compare_integers(5, 5) == 0);
}

TEST_CASE("compare_numbers orders two ints", "[compare_numbers]") {
    Var result = compare_numbers(Var::new_int(1), Var::new_int(2));
    REQUIRE(result.type == TYPE_INT);
    REQUIRE(result.v.num == -1);
}

TEST_CASE("compare_numbers rejects mismatched types", "[compare_numbers]") {
    Var result = compare_numbers(Var::new_int(1), Var::new_float(1.0));
    REQUIRE(result.type == TYPE_ERR);
    REQUIRE(result.v.err == E_TYPE);
}

TEST_CASE("do_equals compares two floats bitwise", "[do_equals]") {
    REQUIRE(do_equals(Var::new_float(1.5), Var::new_float(1.5)) == 1);
    REQUIRE(do_equals(Var::new_float(1.5), Var::new_float(2.5)) == 0);
}

TEST_CASE("do_add adds two integers", "[do_add]") {
    Var result = do_add(Var::new_int(2), Var::new_int(3));
    REQUIRE(result.type == TYPE_INT);
    REQUIRE(result.v.num == 5);
}

TEST_CASE("do_add adds two floats", "[do_add]") {
    Var result = do_add(Var::new_float(1.5), Var::new_float(2.5));
    REQUIRE(result.type == TYPE_FLOAT);
    REQUIRE(result.v.fnum == Catch::Approx(4.0));
}

TEST_CASE("do_add rejects mismatched types (no int/float coercion)", "[do_add]") {
    Var result = do_add(Var::new_int(1), Var::new_float(1.0));
    REQUIRE(result.type == TYPE_ERR);
    REQUIRE(result.v.err == E_TYPE);
}

TEST_CASE("do_subtract and do_multiply on integers", "[do_subtract][do_multiply]") {
    REQUIRE(do_subtract(Var::new_int(5), Var::new_int(3)).v.num == 2);
    REQUIRE(do_multiply(Var::new_int(4), Var::new_int(3)).v.num == 12);
}

TEST_CASE("do_modulus wraps to match the divisor's sign (Python-style, not C's)", "[do_modulus]") {
    Var result = do_modulus(Var::new_int(-7), Var::new_int(3));
    REQUIRE(result.type == TYPE_INT);
    REQUIRE(result.v.num == 2); // C's -7 % 3 is -1; MOO's wraps to 2
}

TEST_CASE("do_modulus by zero is a division error", "[do_modulus]") {
    Var result = do_modulus(Var::new_int(5), Var::new_int(0));
    REQUIRE(result.type == TYPE_ERR);
    REQUIRE(result.v.err == E_DIV);
}

TEST_CASE("do_divide divides two integers", "[do_divide]") {
    Var result = do_divide(Var::new_int(7), Var::new_int(2));
    REQUIRE(result.type == TYPE_INT);
    REQUIRE(result.v.num == 3);
}

TEST_CASE("do_divide by zero is a division error", "[do_divide]") {
    Var result = do_divide(Var::new_int(5), Var::new_int(0));
    REQUIRE(result.type == TYPE_ERR);
    REQUIRE(result.v.err == E_DIV);
}

TEST_CASE("do_divide guards the MININT / -1 overflow case", "[do_divide]") {
    // -MININT overflows Num's range - the real function special-cases this
    // rather than triggering undefined behavior.
    Var result = do_divide(Var::new_int(MININT), Var::new_int(-1));
    REQUIRE(result.type == TYPE_INT);
    REQUIRE(result.v.num == MININT);
}

TEST_CASE("do_power with a positive integer exponent", "[do_power]") {
    Var result = do_power(Var::new_int(2), Var::new_int(10));
    REQUIRE(result.type == TYPE_INT);
    REQUIRE(result.v.num == 1024);
}

TEST_CASE("do_power with a negative integer exponent - base cases", "[do_power]") {
    // POSSIBLE REAL BUG, not a typo in this test: numbers.cc's negative-
    // exponent switch for base -1 is `ans.v.num = (b & 1) ? 1 : -1;` - an
    // odd exponent (b & 1 true) yields 1, an even one yields -1. That's
    // backwards from (-1)^n (odd n should give -1, even n should give 1) -
    // asserted here as the function's actual, current behavior, not the
    // mathematically "correct" one, per this suite's own regression-test
    // convention (see test_verbcasecmp.cc). Flagged for the maintainers,
    // not fixed here - changing core arithmetic semantics is a bigger call
    // than adding test coverage.
    REQUIRE(do_power(Var::new_int(-1), Var::new_int(-3)).v.num == 1);  // odd negative exponent
    REQUIRE(do_power(Var::new_int(-1), Var::new_int(-4)).v.num == -1); // even negative exponent
    REQUIRE(do_power(Var::new_int(1), Var::new_int(-5)).v.num == 1);
    REQUIRE(do_power(Var::new_int(5), Var::new_int(-1)).v.num == 0); // truncates towards zero
}

TEST_CASE("do_power of 0 to a negative exponent is a division error", "[do_power]") {
    Var result = do_power(Var::new_int(0), Var::new_int(-1));
    REQUIRE(result.type == TYPE_ERR);
    REQUIRE(result.v.err == E_DIV);
}

TEST_CASE("do_power with a float base", "[do_power]") {
    Var result = do_power(Var::new_float(2.0), Var::new_int(3));
    REQUIRE(result.type == TYPE_FLOAT);
    REQUIRE(result.v.fnum == Catch::Approx(8.0));
}

TEST_CASE("become_integer converts a float with no fractional part", "[become_integer]") {
    Num result = 0;
    enum error e = become_integer(Var::new_float(42.0), &result, 0);
    REQUIRE(e == E_NONE);
    REQUIRE(result == 42);
}

TEST_CASE("become_integer rejects a non-finite float", "[become_integer]") {
    Num result = 0;
    enum error e = become_integer(Var::new_float(1.0 / 0.0), &result, 0);
    REQUIRE(e == E_FLOAT);
}

TEST_CASE("become_integer rejects a list", "[become_integer]") {
    Var in;
    in.type = TYPE_LIST;
    Num result = 0;
    enum error e = become_integer(in, &result, 0);
    REQUIRE(e == E_TYPE);
}
