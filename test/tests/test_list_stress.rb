require 'test_helper'

# Basic correctness coverage for sort()/all_members() (previously entirely
# untested), plus a concurrent stress scenario for hunting the emptylist
# refcounting bandaid (see the comment at the top of src/list.cc). sort()
# and all_members() are the only two builtins that run list-refcounting
# code on a real background OS thread (src/background.cc) while the main
# interpreter loop keeps running other tasks concurrently, so hammering
# them alongside ordinary list construction is the best chance of
# reproducing a genuine cross-thread race, on top of whatever a soak of
# the rest of the suite already exercises single-threaded.
class TestListStress < Test::Unit::TestCase

  def setup
    run_test_as('wizard') do
      command(%Q|; for t in (queued_tasks()); kill_task(t[1]); endfor;|)
    end
  end

  def test_that_sort_orders_a_list_correctly
    run_test_as('programmer') do
      assert_equal [1, 2, 3, 4, 5], simplify(command("; return sort({3, 1, 4, 5, 2});"))
      assert_equal [], simplify(command("; return sort({});"))
      assert_equal ["a", "b", "c"], simplify(command(%Q|; return sort({"c", "a", "b"});|))
    end
  end

  def test_that_sort_supports_keys_natural_and_reverse
    run_test_as('programmer') do
      # sort by a parallel key list rather than the values themselves
      assert_equal ["c", "a", "b"], simplify(command(%Q|; return sort({"a", "b", "c"}, {2, 3, 1});|))
      # reverse flag
      assert_equal [5, 4, 3, 2, 1], simplify(command("; return sort({3, 1, 4, 5, 2}, {}, 0, 1);"))
    end
  end

  def test_that_sort_rejects_mismatched_types
    run_test_as('programmer') do
      assert_equal E_TYPE, simplify(command(%Q|; return sort({1, "two", 3});|))
    end
  end

  def test_that_all_members_finds_matching_indices
    run_test_as('programmer') do
      assert_equal [2, 4], simplify(command("; return all_members(1, {0, 1, 0, 1, 0});"))
      assert_equal [], simplify(command("; return all_members(1, {});"))
      assert_equal [1, 2, 3], simplify(command(%Q|; return all_members("x", {"x", "x", "x"});|))
    end
  end

  # Supplementary stress scenario, not the primary reproduction vehicle for
  # the emptylist bug (see the plan this test was added under) -- the bug
  # predates background threading entirely, so an organic soak of the
  # whole test suite matters more than this. This is here mainly to close
  # the sort()/all_members() coverage gap under concurrent load, and to
  # generate list-heavy traffic across many forked tasks while sort()/
  # all_members() run on real background threads (src/background.cc),
  # for an instrumented (TRACE_REFCOUNT) build to capture in its trace log.
  #
  # Note: debug_emptylist_refcount() can NOT be asserted to return to a
  # pre-test baseline here -- the existing bandaid (src/list.cc) makes
  # emptylist's refcount monotonically increase by design (real delref()
  # never fires on it), so it necessarily grows across this test and any
  # other list-heavy code. The only meaningful automated checks are that
  # this doesn't crash the server and, when the debug builtin is present,
  # that the count is a sane positive integer that didn't decrease.
  def test_that_concurrent_list_stress_does_not_crash_the_server
    run_test_as('wizard') do
      before = simplify(command(%Q{; ok = eval("return debug_emptylist_refcount();"); return ok[1] ? ok[2] | -1;}))

      a = create(:object)
      add_verb(a, ['player', 'xd', 'hammer'], ['this', 'none', 'this'])
      set_verb_code(a, 'hammer') do |vc|
        lines = <<-EOF
          l = {};
          for i in [1..50];
              l = listappend(l, i);
              l = listinsert(l, i, 1);
              x = {};
              y = sort(l);
              z = all_members(i, l);
          endfor;
          l = listdelete(l, 1);
          return 1;
        EOF
        lines.split("\n").each { |line| vc << line }
      end

      simplify(command(%Q|; for i in [1..10]; fork (0); #{a}:hammer(); endfork; endfor; return 1;|))

      for _ in 1..100
        simplify(command(";; suspend(0); return 1;"))
      end

      if before >= 0
        after = simplify(command(%Q{; ok = eval("return debug_emptylist_refcount();"); return ok[1] ? ok[2] | -1;}))
        assert after >= before, "emptylist refcount decreased (#{before} -> #{after}), contradicting the bandaid's own monotonic-increase behavior -- investigate"
      end
    end
  end
end
