require 'test_helper'

# Exercises the new `$server_options.match_mode` object-matching upgrade
# (src/match.cc's complex_match()) via real player commands, since
# match_object() is only reachable through command parsing, not as a MOO
# builtin. Each test defines a catch-all "zzmatch" verb on the connected
# player (arg spec `any any any`, so it fires regardless of whether the
# direct object matches) that echoes back `tostr(dobj)` -- #-3 means
# FAILED_MATCH, #-2 means AMBIGUOUS, anything else is the matched object.
class TestComplexMatch < Test::Unit::TestCase

  FAILED = '#-3'
  AMBIGUOUS = '#-2'

  def teardown
    run_test_with_prefix_and_suffix_as('wizard') do
      set_match_mode(0)
    end
  end

  def set_match_mode(mode)
    command(%Q|; \`add_property($server_options, "match_mode", #{mode}, {player, ""}) ! E_INVARG => ($server_options.match_mode = #{mode})'; load_server_options(); return 1;|)
  end

  def setup_match_verb
    add_verb(player, [player, 'xd', 'zzmatch'], ['any', 'any', 'any'])
    set_verb_code(player, 'zzmatch') do |vc|
      vc << 'notify(player, tostr(dobj));'
    end
  end

  def make_candidate(name, aliases = [])
    o = create(:nothing)
    alias_literal = '{' + aliases.map { |a| a.inspect }.join(', ') + '}'
    command(%Q|; #{o}.name = #{name.inspect}; add_property(#{o}, "aliases", #{alias_literal}, {player, ""}); move(#{o}, player); return 1;|)
    o
  end

  def recycle_all(*objs)
    objs.each { |o| command(%Q|; recycle(#{o}); return 1;|) }
  end

  def test_that_legacy_mode_only_matches_a_name_prefix
    run_test_with_prefix_and_suffix_as('wizard') do
      setup_match_verb
      apple = make_candidate('Golden Apple')
      set_match_mode(0)
      # "apple" is not a *prefix* of "Golden Apple", so legacy matching
      # (today's unchanged default behavior) fails to find it.
      assert_equal FAILED, command('zzmatch apple')
      recycle_all(apple)
    end
  end

  def test_that_complex_mode_matches_via_contains_when_nothing_else_fits
    run_test_with_prefix_and_suffix_as('wizard') do
      setup_match_verb
      apple = make_candidate('Golden Apple')
      set_match_mode(1)
      # Same setup as above, but complex mode's contains-anywhere tier
      # finds it where legacy prefix matching couldn't.
      assert_equal "#{apple}", command('zzmatch apple')
      recycle_all(apple)
    end
  end

  def test_that_complex_mode_prefers_exact_over_starts_with_over_contains
    run_test_with_prefix_and_suffix_as('wizard') do
      setup_match_verb
      exact = make_candidate('Apple')
      starts_with = make_candidate('Apple Pie')
      contains = make_candidate('Pineapple')
      set_match_mode(1)
      # All three are candidates at some tier, but the exact match is
      # unique and wins outright rather than being ambiguous with the
      # other two.
      assert_equal "#{exact}", command('zzmatch apple')
      recycle_all(exact, starts_with, contains)
    end
  end

  def test_that_complex_mode_is_ambiguous_across_multiple_equal_tier_matches
    run_test_with_prefix_and_suffix_as('wizard') do
      setup_match_verb
      a = make_candidate('Red Apple')
      b = make_candidate('Green Apple')
      set_match_mode(1)
      assert_equal AMBIGUOUS, command('zzmatch apple')
      recycle_all(a, b)
    end
  end

  def test_that_a_leading_ordinal_disambiguates_between_equal_tier_matches
    run_test_with_prefix_and_suffix_as('wizard') do
      setup_match_verb
      a = make_candidate('Red Apple')
      b = make_candidate('Green Apple')
      set_match_mode(1)

      first = command('zzmatch 1st apple')
      second = command('zzmatch 2nd apple')
      candidates = ["#{a}", "#{b}"]

      assert_not_equal first, second
      assert candidates.include?(first), "expected #{first} to be one of #{candidates}"
      assert candidates.include?(second), "expected #{second} to be one of #{candidates}"

      # Only two candidates exist -- asking for the 3rd must fail rather
      # than silently falling back to an unordered/ambiguous match.
      assert_equal FAILED, command('zzmatch 3rd apple')

      # A spelled-out compound ordinal works the same way as the numeric
      # form, reusing the same parse_leading_ordinal() as parse_ordinal() --
      # still out of range with only two candidates.
      assert_equal FAILED, command('zzmatch twenty-third apple')

      recycle_all(a, b)
    end
  end

  def test_that_hash_n_syntax_works_for_wizards_and_programmers
    run_test_with_prefix_and_suffix_as('wizard') do
      target = create(:nothing)
      setup_match_verb
      assert_equal "#{target}", command("zzmatch #{target}")
      recycle_all(target)
    end
    run_test_with_prefix_and_suffix_as('programmer') do
      target = create(:nothing)
      setup_match_verb
      assert_equal "#{target}", command("zzmatch #{target}")
      recycle_all(target)
    end
  end

  def test_that_hash_n_syntax_is_denied_to_a_plain_player
    run_test_with_prefix_and_suffix_as('wizard') do
      target = create(:nothing)
      plain_player = simplify(command(%Q|; o = create($nothing); move(o, player.location); set_player_flag(o, 1); return o;|))
      add_verb(plain_player, [plain_player, 'xd', 'zzmatch'], ['any', 'any', 'any'])
      set_verb_code(plain_player, 'zzmatch') do |vc|
        vc << 'notify(player, tostr(dobj));'
      end
      switch_player(player, plain_player)
      assert_equal FAILED, command("zzmatch #{target}")
      recycle_all(target, plain_player)
    end
  end

end
