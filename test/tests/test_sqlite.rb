require 'test_helper'

class TestSqlite < Test::Unit::TestCase

  def test_that_sqlite_open_requires_wizard_permissions
    run_test_as('programmer') do
      assert_equal E_PERM, simplify(command %Q|; return sqlite_open(":memory:");|)
    end
  end

  # Regression test for the sqlite_execute() statement cache: prepared
  # statements are now reused across calls (keyed by query text) instead
  # of being re-prepared/finalized every time. Running the same query text
  # twice with different bound parameters, then a third time repeating the
  # first parameter, exercises the cache-hit path and confirms reset +
  # clear_bindings between uses doesn't leak state from a prior bind.
  def test_that_cached_prepared_statements_rebind_correctly_and_close_cleanly
    # sqlite_execute() is a threaded builtin that implicitly suspends the
    # calling verb, and eval() (which the ";" test command runs through)
    # doesn't carry a suspend across cleanly -- set_thread_mode(0) forces
    # it to run synchronously within this eval instead, per-command since
    # each ";" is its own temporary verb invocation.
    run_test_as('wizard') do
      db = simplify(command %Q|; set_thread_mode(0); return sqlite_open(":memory:");|)

      command %Q|; set_thread_mode(0); sqlite_execute(#{db}, "CREATE TABLE t (a INTEGER, b TEXT);", {});|
      command %Q|; set_thread_mode(0); sqlite_execute(#{db}, "INSERT INTO t VALUES (?, ?);", {1, "one"});|
      command %Q|; set_thread_mode(0); sqlite_execute(#{db}, "INSERT INTO t VALUES (?, ?);", {2, "two"});|

      r1 = simplify(command %Q|; set_thread_mode(0); return sqlite_execute(#{db}, "SELECT b FROM t WHERE a = ?;", {1});|)
      r2 = simplify(command %Q|; set_thread_mode(0); return sqlite_execute(#{db}, "SELECT b FROM t WHERE a = ?;", {2});|)
      r3 = simplify(command %Q|; set_thread_mode(0); return sqlite_execute(#{db}, "SELECT b FROM t WHERE a = ?;", {1});|)

      # a 1-row, 1-column result collapses all the way to a bare scalar
      # under this suite's list-parsing rules (a genuine MOO-value shape,
      # not a bug).
      assert_equal 'one', r1
      assert_equal 'two', r2
      assert_equal r1, r3

      # a distinct query text against the same connection, returning
      # multiple rows/columns, to check the cache is keyed correctly per
      # query rather than colliding with the single-column query above
      r_all = simplify(command %Q|; set_thread_mode(0); return sqlite_execute(#{db}, "SELECT a, b FROM t ORDER BY a;", {});|)
      assert_equal [[1, 'one'], [2, 'two']], r_all

      # sqlite3_close() fails (SQLITE_BUSY) while any prepared statement on
      # the connection remains unfinalized -- closing here only succeeds
      # cleanly if the cached statement above was finalized first.
      assert_equal 0, simplify(command %Q|; set_thread_mode(0); return sqlite_close(#{db});|)
    end
  end

end
