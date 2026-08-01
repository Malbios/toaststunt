require 'open3'
require 'timeout'

require 'test_helper'

class TestCliOptions < Test::Unit::TestCase

  private

  # Launches ./moo with the given command-line arguments and collects stderr
  # log lines until one of them matches `until_line`, or `timeout` seconds
  # pass. The server is then killed (it has no reason to exit on its own
  # here) and its lines returned.
  def start_and_capture_log(args, until_line:, timeout: 5)
    _, _, stderr, wait = Open3.popen3 %[./moo #{args}]
    lines = []
    begin
      Timeout.timeout(timeout) do
        while (line = stderr.gets)
          lines << line.chomp
          break if lines.last =~ until_line
        end
      end
    rescue Timeout::Error
      # Fall through with whatever was captured; the assertions below will
      # report it as a failure.
    ensure
      Process.kill('TERM', wait.pid) rescue nil
      wait.value
    end
    lines
  end

  public

  # Regression test for upstream issue #95: the long_options entry for
  # --tls-port was declared no_argument while its handler read optarg, so
  # `--tls-port 12399` left "12399" unconsumed. getopt_long then permuted it
  # to the end of argv, where it was picked up as the *input* database
  # filename instead of "Test.db" -- shifting every other positional
  # argument along with it. Confirmed by checking the log for the actual
  # effect of that misparse (a "Cannot open input database file: 12399"
  # failure) rather than just asserting a port number appears in the log.
  def test_that_tls_port_consumes_its_argument
    out_db = '/tmp/test_tls_port_out.db'
    File.delete(out_db) if File.exist?(out_db)

    lines = start_and_capture_log(
      "--tls-port 12399 Test.db #{out_db} 9900",
      until_line: /CMDLINE: Initial TLS port|Cannot open input database file/
    )

    assert lines.any? { |l| l =~ /CMDLINE: Initial TLS ports? = .*12399/ },
           "expected the server to log the parsed TLS port; got:\n#{lines.join("\n")}"
    assert lines.none? { |l| l =~ /Cannot open input database file/ },
           "the TLS port number leaked into positional argument parsing; got:\n#{lines.join("\n")}"
  ensure
    File.delete(out_db) if File.exist?(out_db)
  end

end
