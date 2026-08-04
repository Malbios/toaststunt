require 'test_helper'

# Exercises the new $server_options.escape_sequences_in_strings option
# (src/parser.y's string lexer, src/list.cc's unparse_value()). Ruby
# single-quoted/%q{} source is used for MOO code throughout so Ruby
# doesn't itself interpret backslashes before they reach the socket.
class TestStringEscapes < Test::Unit::TestCase

  def teardown
    run_test_as('wizard') do
      set_escape_sequences(0)
    end
  end

  def set_escape_sequences(mode)
    command(%Q|; \`add_property($server_options, "escape_sequences_in_strings", #{mode}, {player, ""}) ! E_INVARG => ($server_options.escape_sequences_in_strings = #{mode})'; load_server_options(); return 1;|)
  end

  # Default (option absent/0): \n \t \r in a source literal silently drop
  # the backslash and keep the bare letter, exactly as before this feature
  # existed -- the whole point of gating this behind an opt-in option.
  def test_that_escape_sequences_are_off_by_default
    run_test_as('wizard') do
      assert_equal 'anbtcrd', simplify(command(%q|; return "a\nb\tc\rd";|))
    end
  end

  def test_that_escape_sequences_work_when_enabled
    run_test_as('wizard') do
      set_escape_sequences(1)
      assert_equal "a\nb\tc\rd", simplify(command(%q|; return "a\nb\tc\rd";|))
    end
  end

  # \" and \\ already worked before this feature existed and must stay
  # byte-identical in both option states.
  def test_that_backslash_quote_and_backslash_backslash_are_unaffected_by_the_option
    run_test_as('wizard') do
      set_escape_sequences(0)
      assert_equal 'a"b\c', simplify(command(%q|; return "a\"b\\\\c";|))
      set_escape_sequences(1)
      assert_equal 'a"b\c', simplify(command(%q|; return "a\"b\\\\c";|))
    end
  end

  # Any backslash followed by a character with no special meaning still
  # just drops the backslash and keeps the character, in both states.
  def test_that_unknown_escape_still_passes_through_the_following_character
    run_test_as('wizard') do
      set_escape_sequences(0)
      assert_equal 'azb', simplify(command(%q|; return "a\zb";|))
      set_escape_sequences(1)
      assert_equal 'azb', simplify(command(%q|; return "a\zb";|))
    end
  end

  # Round-trip via a runtime control character (chr(9), not a source-level
  # escape) rather than chr(10): a raw newline in the *response* would
  # split it across two socket lines regardless of this feature, an
  # unrelated transport concern this test isn't about.
  def test_that_unparse_round_trips_control_characters_when_escape_sequences_are_enabled
    run_test_as('wizard') do
      set_escape_sequences(1)
      literal = simplify(command(%q|; return toliteral(chr(9) + "x");|))
      assert_equal '"\tx"', literal
      recompiled = simplify(command("; return #{literal};"))
      assert_equal "\tx", recompiled
    end
  end

  # With the option off, unparse_value() never escapes control characters
  # -- today's existing, unfixed-by-this-card behavior stays unchanged.
  def test_that_unparse_does_not_change_when_escape_sequences_are_disabled
    run_test_as('wizard') do
      set_escape_sequences(0)
      literal = simplify(command(%q|; return toliteral(chr(9) + "x");|))
      assert_equal "\"\tx\"", literal
    end
  end

end
