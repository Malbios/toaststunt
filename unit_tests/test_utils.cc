// Unit tests for the pure/near-pure free functions in src/utils.cc (aside
// from verbcasecmp, which has its own dedicated test_verbcasecmp.cc).
#include <cstring>

#include "catch_amalgamated.hpp"
#include "structures.h"
#include "streams.h"
#include "utils.h"

TEST_CASE("str_hash is deterministic for the same input", "[str_hash]") {
    REQUIRE(str_hash("hello") == str_hash("hello"));
}

TEST_CASE("str_hash differs for different input", "[str_hash]") {
    // Not a mathematical guarantee for an arbitrary hash function, but any
    // hash worth using shouldn't collide on two short, very different
    // strings - if this ever fails, str_hash's algorithm changed in a way
    // worth a second look.
    REQUIRE(str_hash("hello") != str_hash("goodbye"));
}

TEST_CASE("strindex finds a substring and reports its 1-based position", "[strindex]") {
    const char *source = "hello world";
    REQUIRE(strindex(source, (int)strlen(source), "world", 5, 1) == 7);
}

TEST_CASE("strindex returns 0 when the substring isn't present", "[strindex]") {
    const char *source = "hello world";
    REQUIRE(strindex(source, (int)strlen(source), "xyz", 3, 1) == 0);
}

TEST_CASE("strindex is case-insensitive when case_counts is false", "[strindex]") {
    const char *source = "hello WORLD";
    REQUIRE(strindex(source, (int)strlen(source), "world", 5, 0) == 7);
    REQUIRE(strindex(source, (int)strlen(source), "world", 5, 1) == 0);
}

TEST_CASE("strrindex finds the last occurrence of a substring", "[strrindex]") {
    const char *source = "abcabc";
    REQUIRE(strrindex(source, (int)strlen(source), "abc", 3, 1) == 4);
}

TEST_CASE("strrindex returns 0 when the substring isn't present", "[strrindex]") {
    const char *source = "abcabc";
    REQUIRE(strrindex(source, (int)strlen(source), "xyz", 3, 1) == 0);
}

TEST_CASE("clean_to_raw_bytes is a pass-through that reports the string's length", "[clean_to_raw_bytes]") {
    int len = -1;
    const char *result = clean_to_raw_bytes("hello", &len);
    REQUIRE(len == 5);
    REQUIRE(strcmp(result, "hello") == 0);
}

TEST_CASE("raw_bytes_to_binary/binary_to_raw_bytes round-trip arbitrary bytes", "[binary]") {
    const char raw[] = { 'a', '\0', 'b', (char)0xFF, 'c' };
    const char *encoded = raw_bytes_to_binary(raw, sizeof(raw));
    REQUIRE(encoded != nullptr);

    int decodedLen = -1;
    const char *decoded = binary_to_raw_bytes(encoded, &decodedLen);
    REQUIRE(decoded != nullptr);
    REQUIRE(decodedLen == (int)sizeof(raw));
    REQUIRE(memcmp(decoded, raw, sizeof(raw)) == 0);
}

TEST_CASE("binary_to_raw_bytes rejects a malformed ~-escape", "[binary]") {
    // This format isn't "the whole string is hex" - printable bytes pass
    // through literally, and only `~XX` sequences are hex-decoded (see
    // stream_add_raw_bytes_to_binary, the encoder side, which only escapes
    // non-printable bytes and literal `~`). So a plain string like "abc"
    // with no `~` at all is valid input, not malformed - malformed means a
    // `~` followed by something that isn't 2 hex digits.
    int len = -1;
    REQUIRE(binary_to_raw_bytes("~G0", &len) == nullptr);
}

TEST_CASE("strtr translates matching characters", "[strtr]") {
    const char *source = "hello";
    const char *result = strtr(source, (int)strlen(source), "el", 2, "ip", 2, 1);
    REQUIRE(strcmp(result, "hippo") == 0);
}

TEST_CASE("stream_add_strsub replaces every occurrence of a substring", "[stream_add_strsub]") {
    Stream *s = new_stream(32);
    stream_add_strsub(s, "the cat sat on the mat", "at", "og", 1);
    REQUIRE(strcmp(stream_contents(s), "the cog sog on the mog") == 0);
    free_stream(s);
}

TEST_CASE("is_true reflects each type's own notion of truthiness", "[is_true]") {
    REQUIRE(is_true(Var::new_int(1)) == 1);
    REQUIRE(is_true(Var::new_int(0)) == 0);
    REQUIRE(is_true(Var::new_float(1.5)) == 1);
    REQUIRE(is_true(Var::new_float(0.0)) == 0);
    REQUIRE(is_true(str_dup_to_var("")) == 0);
    REQUIRE(is_true(str_dup_to_var("x")) == 1);
}

TEST_CASE("compare orders integers numerically", "[compare]") {
    REQUIRE(compare(Var::new_int(1), Var::new_int(2), 1) < 0);
    REQUIRE(compare(Var::new_int(2), Var::new_int(1), 1) > 0);
    REQUIRE(compare(Var::new_int(2), Var::new_int(2), 1) == 0);
}

TEST_CASE("compare respects case_matters for strings", "[compare]") {
    Var a = str_dup_to_var("abc");
    Var b = str_dup_to_var("ABC");
    REQUIRE(compare(a, b, 1) != 0);
    REQUIRE(compare(a, b, 0) == 0);
}

TEST_CASE("equality treats a bool and an equal int as equal", "[equality]") {
    // compare()'s doc comment explicitly carves out this cross-type case.
    REQUIRE(equality(Var::new_bool(true), Var::new_int(1), 1) == 1);
    REQUIRE(equality(Var::new_int(0), Var::new_bool(false), 1) == 1);
    REQUIRE(equality(Var::new_bool(true), Var::new_int(0), 1) == 0);
}

TEST_CASE("equality is case-insensitive for strings when asked", "[equality]") {
    Var a = str_dup_to_var("abc");
    Var b = str_dup_to_var("ABC");
    REQUIRE(equality(a, b, 0) == 1);
    REQUIRE(equality(a, b, 1) == 0);
}
