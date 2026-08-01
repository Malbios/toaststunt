require 'test_helper'

class TestSystemBuiltins < Test::Unit::TestCase

  def test_that_getenv_requires_wizperms
    run_test_as('wizard') do
      assert_not_equal E_PERM, getenv('PATH')
    end
    run_test_as('programmer') do
      assert_equal E_PERM, getenv('PATH')
    end
  end

  def test_that_getenv_fails_on_invalid_arguments
    run_test_as('wizard') do
      assert_equal E_ARGS, simplify(command(%Q|; getenv(); |))
      assert_equal E_TYPE, getenv(1)
      assert_equal E_TYPE, getenv(1.1)
    end
  end

  def test_that_getenv_returns_the_environment_variable_value
    run_test_as('wizard') do
      assert_equal ENV['PATH'], getenv('PATH')
      assert_equal ENV['USER'], getenv('USER')
    end
  end

  def test_that_getenv_returns_zero_if_the_environment_variable_does_not_exist
    run_test_as('wizard') do
      assert_equal 0, getenv('XYZZY')
    end
  end

  # Regression test for upstream issue #96: flush_input() used to dequeue
  # with DQ_FIRST, which removes whatever is at the front of the input
  # queue regardless of kind, so a pending out-of-band command queued
  # behind ordinary input got silently discarded along with it. It should
  # only ever discard in-band input.
  #
  # force_input()/flush_input() act on the queue synchronously, so both
  # calls below are guaranteed to run before the server's main loop gets a
  # chance to dequeue anything -- the queue is exactly {in-band, OOB} at
  # the moment flush_input() runs. The OOB command itself is dispatched
  # asynchronously afterwards (as #0:do_out_of_band_command), hence the
  # poll below rather than an immediate assertion.
  def test_that_flush_input_does_not_discard_out_of_band_commands
    run_test_as('wizard') do
      add_property(:system, 'oob_test_marker', 0, [player, ''])
      add_verb(:system, [player, 'xd', 'do_out_of_band_command'], ['this', 'none', 'this'])
      begin
        set_verb_code(SYSTEM, 'do_out_of_band_command') do |vc|
          vc << 'this.oob_test_marker = this.oob_test_marker + 1;'
        end

        command(%Q|; force_input(player, "this in-band line should be flushed"); force_input(player, "#$#keepalive-ping"); return flush_input(player);|)

        marker = 0
        10.times do
          marker = get(:system, 'oob_test_marker')
          break if marker == 1
          sleep(0.1)
        end

        assert_equal 1, marker
      ensure
        delete_verb(:system, 'do_out_of_band_command')
        delete_property(:system, 'oob_test_marker')
      end
    end
  end

end
