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

  # Regression tests for sanitize_string_for_moo()'s SQLITE_SANITIZE_STRINGS
  # handling: newlines become tabs on every string result, and
  # sqlite_execute()'s path used to sanitize the same string twice
  # (directly, then again inside string_to_moo_type()) -- harmless since
  # the substitution is idempotent, but confirms the dedup didn't change
  # the observable result.

  def test_that_sanitize_strings_replaces_newlines_with_tabs_via_sqlite_execute
    run_test_as('wizard') do
      # options = PARSE_TYPES(2) | PARSE_OBJECTS(4) | SANITIZE_STRINGS(8)
      db = simplify(command %Q|; set_thread_mode(0); return sqlite_open(":memory:", 14);|)
      command %Q|; set_thread_mode(0); sqlite_execute(#{db}, "CREATE TABLE t (a TEXT);", {});|
      command %Q|; set_thread_mode(0); sqlite_execute(#{db}, "INSERT INTO t VALUES (?);", {"line1" + chr(10) + "line2"});|

      assert_equal "line1\tline2", simplify(command %Q|; set_thread_mode(0); return sqlite_execute(#{db}, "SELECT a FROM t;", {});|)
      assert_equal 0, simplify(command %Q|; set_thread_mode(0); return sqlite_close(#{db});|)
    end
  end

  def test_that_sanitize_strings_replaces_newlines_with_tabs_via_sqlite_query
    run_test_as('wizard') do
      db = simplify(command %Q|; set_thread_mode(0); return sqlite_open(":memory:", 14);|)
      command %Q|; set_thread_mode(0); sqlite_execute(#{db}, "CREATE TABLE t (a TEXT);", {});|
      command %Q|; set_thread_mode(0); sqlite_execute(#{db}, "INSERT INTO t VALUES (?);", {"line1" + chr(10) + "line2"});|

      assert_equal "line1\tline2", simplify(command %Q|; return sqlite_query(#{db}, "SELECT a FROM t;");|)
      assert_equal 0, simplify(command %Q|; set_thread_mode(0); return sqlite_close(#{db});|)
    end
  end

  def test_that_sanitize_strings_leaves_strings_without_newlines_unchanged
    run_test_as('wizard') do
      db = simplify(command %Q|; set_thread_mode(0); return sqlite_open(":memory:", 14);|)
      command %Q|; set_thread_mode(0); sqlite_execute(#{db}, "CREATE TABLE t (a TEXT);", {});|
      command %Q|; set_thread_mode(0); sqlite_execute(#{db}, "INSERT INTO t VALUES (?);", {"no newline here"});|

      assert_equal "no newline here", simplify(command %Q|; set_thread_mode(0); return sqlite_execute(#{db}, "SELECT a FROM t;", {});|)
      assert_equal "no newline here", simplify(command %Q|; return sqlite_query(#{db}, "SELECT a FROM t;");|)
      assert_equal 0, simplify(command %Q|; set_thread_mode(0); return sqlite_close(#{db});|)
    end
  end

end
