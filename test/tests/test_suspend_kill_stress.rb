require 'test_helper'

# Stress coverage for the "emptylist bandaid" refcount investigation
# (see the "Emptylist bandaid refcounting bug" tracking card). These tests
# target suspend_task()/resume_from_previous_vm() (src/execute.cc) and the
# sibling do_forked_task path (src/tasks.cc), which transplant activation-
# stack contents (which can hold {}) via plain struct assignment -- correct
# only by a hand-enforced "weak"/"strong" free convention, not the type
# system, and with no assertion. The likeliest place for that convention to
# be violated is an edge case combining suspend()/fork() with abnormal
# termination (kill_task()) -- ordinary suspend/resume was traced separately
# and looks sound.
#
# Independent of whether this ever turns up the historical bug, these are
# new regression tests for previously-untested lifecycle edge cases.
class TestSuspendKillStress < Test::Unit::TestCase

  def setup
    run_test_as('wizard') do
      command(%Q|; for t in (queued_tasks()); kill_task(t[1]); endfor;|)
    end
  end

  def test_that_killing_a_suspended_task_with_emptylist_locals_is_clean
    run_test_as('wizard') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'holder'], ['this', 'none', 'this'])
      set_verb_code(o, 'holder') do |vc|
        vc << %Q|fork t (0)|
        vc << %Q|  x = {};|
        vc << %Q|  y = {1, 2, {}};|
        vc << %Q|  z = ["a" -> {}, "b" -> 2];|
        vc << %Q|  suspend();|
        vc << %Q|  return {x, y, z};|
        vc << %Q|endfork|
        vc << %Q|return t;|
      end

      begin
        t = simplify(command(%Q|; return #{o}:holder();|))
        assert_equal 0, kill_task(t)

        # Hammer emptylist from many subsequent operations, raising the
        # odds that any corruption from the kill above surfaces as a crash
        # (under the investigation's LeakCheck+tripwire build) rather than
        # landing silently in unrelated memory.
        100.times { simplify(command('; z = {}; y = []; return {z, y};')) }

        if has_function?('debug_emptylist_refcount')
          rc = simplify(command('; return debug_emptylist_refcount();'))
          assert rc.is_a?(Integer) && rc > 0, "emptylist refcount corrupted or wrapped: #{rc.inspect}"
        end
      ensure
        recycle(o)
      end
    end
  end

  def test_that_killing_a_forked_then_suspended_task_with_emptylist_locals_is_clean
    run_test_as('wizard') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'chain'], ['this', 'none', 'this'])
      set_verb_code(o, 'chain') do |vc|
        # A task that is first FORKED (exercising do_forked_task's own
        # var_ref/program_ref-based deep copy), then -- once actually
        # running -- suspends itself, transitioning to the shallow-copy
        # activation-stack convention partway through its life.
        vc << %Q|fork t (0)|
        vc << %Q|  x = {};|
        vc << %Q|  y = {{}, {}, {}};|
        vc << %Q|  suspend();|
        vc << %Q|  return x;|
        vc << %Q|endfork|
        vc << %Q|return t;|
      end

      begin
        t = simplify(command(%Q|; return #{o}:chain();|))
        # A second round-trip command to let the forked task actually run
        # to its suspend() point before we kill it (the scheduler runs
        # ready tasks between commands on this connection).
        simplify(command('; return 1;'))
        assert_equal 0, kill_task(t)

        100.times { simplify(command('; z = {}; y = []; return {z, y};')) }

        if has_function?('debug_emptylist_refcount')
          rc = simplify(command('; return debug_emptylist_refcount();'))
          assert rc.is_a?(Integer) && rc > 0, "emptylist refcount corrupted or wrapped: #{rc.inspect}"
        end
      ensure
        recycle(o)
      end
    end
  end

end
