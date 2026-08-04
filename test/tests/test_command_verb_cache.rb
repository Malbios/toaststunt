require 'test_helper'

# Regression coverage for db_find_command_verb()'s new cache (db_verbs.cc),
# used for ordinary player command dispatch. Modeled on test_verb_cache.rb,
# which covers the sibling db_find_callable_verb() cache -- but exercised
# via real typed commands (command()), since db_find_command_verb() is only
# reachable through command dispatch, not through :verb() calls.
class TestCommandVerbCache < Test::Unit::TestCase

  # The correctness-critical case this cache design exists for: unlike
  # db_find_callable_verb()'s cache (keyed only on object+name, fine since
  # a :verb() call has no arg-spec disambiguation), the same object can
  # define several same-named verbs distinguished only by dobj/prep/iobj.
  # A cache keyed only on (object, name) would silently return whichever
  # verbdef got cached first regardless of the command's actual arg shape.
  # Run each command shape twice to prove a warm cache doesn't corrupt the
  # second dispatch.
  def test_that_command_verb_dispatch_with_different_arg_specs_is_not_confused_by_the_cache
    run_test_with_prefix_and_suffix_as('wizard') do
      bare_idx = add_verb(player, [player, 'xd', 'zzzcvcargspec'], ['none', 'none', 'none'])
      set_verb_code(player, bare_idx) do |vc|
        vc << 'notify(player, "bare");'
      end
      prep_idx = add_verb(player, [player, 'xd', 'zzzcvcargspec'], ['any', 'at/to', 'any'])
      set_verb_code(player, prep_idx) do |vc|
        vc << 'notify(player, "prep");'
      end

      begin
        2.times do
          assert_equal 'bare', command('zzzcvcargspec')
          assert_equal 'prep', command('zzzcvcargspec something at me')
        end
      ensure
        delete_verb(player, prep_idx)
        delete_verb(player, bare_idx)
      end
    end
  end

  # If recycle()'s invalidation didn't reach this cache, a cached entry
  # keyed on the recycled object's C++ Object* could point at a verbdef
  # freed out from under it, or (if a new object reuses that pointer slot)
  # silently dispatch to the wrong object's verb -- not just wrong output,
  # a real dangling-pointer hazard.
  #
  # Dispatches via the command's direct object (a raw #N reference, which
  # find_verb_on() checks directly) rather than the player's location, so
  # this doesn't need move() -- moving into a freshly created room turns
  # out to trigger its own asynchronous room-entry output, arriving with
  # unpredictable delay and desyncing whatever command()/eval call comes
  # next on that connection (a pre-existing test-harness quirk, unrelated
  # to this cache; every other passing test in this codebase avoids it by
  # simply never relying on a fresh room's location for verb dispatch).
  def test_that_recycling_clears_the_command_verb_cache
    run_test_with_prefix_and_suffix_as('wizard') do
      a = create(:nothing)
      add_verb(a, [player, 'xd', 'zzzcvcrecycle'], ['any', 'none', 'none'])
      set_verb_code(a, 'zzzcvcrecycle') do |vc|
        vc << 'notify(player, "from-a");'
      end

      assert_equal 'from-a', command("zzzcvcrecycle #{a}") # warm the cache

      recycle(a)

      b = create(:nothing)
      add_verb(b, [player, 'xd', 'zzzcvcrecycle'], ['any', 'none', 'none'])
      set_verb_code(b, 'zzzcvcrecycle') do |vc|
        vc << 'notify(player, "from-b");'
      end

      assert_equal 'from-b', command("zzzcvcrecycle #{b}")
    end
  end

  # Same hazard as above, without recycle(): add_verb()/delete_verb() on
  # the *same* still-live object must also invalidate both a stale negative
  # (miss) entry and a stale positive one pointing at freed Verbdef memory.
  def test_that_add_verb_and_delete_verb_invalidate_the_command_verb_cache
    run_test_with_prefix_and_suffix_as('wizard') do
      command('zzzcvcaddtest') # no such verb yet: populates a negative cache entry

      add_verb(player, [player, 'xd', 'zzzcvcaddtest'], ['none', 'none', 'none'])
      begin
        set_verb_code(player, 'zzzcvcaddtest') do |vc|
          vc << 'notify(player, "added");'
        end

        assert_equal 'added', command('zzzcvcaddtest')

        delete_verb(player, 'zzzcvcaddtest')

        assert_not_equal 'added', command('zzzcvcaddtest')
      ensure
        evaluate(%q{`delete_verb(player, "zzzcvcaddtest") ! ANY => 0'})
      end
    end
  end

end
