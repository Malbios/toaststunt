require 'test_helper'

# Regression coverage for the telnet IAC state machine (network.cc,
# process_telnet_byte()) added by the earlier "telnet state-machine refactor"
# backport. That state machine lives on the persistent connection handle
# (h->telnet_state / h->command_stream), so it must correctly resume parsing
# an IAC sequence whose bytes arrive across separate TCP reads, not just
# within a single buffer. These tests deliberately split IAC sequences
# across multiple socket writes (with a short sleep in between to force
# separate server-side read() calls) and assert the reassembly is correct.
#
# Extracted IAC commands are delivered out-of-band to #0:do_out_of_band_command
# with the raw bytes MOO-binary-encoded (control/non-graphic bytes become
# "~XX" hex, see stream_add_raw_bytes_to_binary() in utils.cc). Ordinary
# in-band bytes surrounding an IAC sequence stay in the normal input line
# and, since they don't match any verb, reach a "huh" catch-all verb on the
# player's room, which notify()s back the unmatched verb word so it can be
# read directly as the response to that command (command()'s own approach,
# see test_huh.rb).
class TestTelnetIac < Test::Unit::TestCase

  def teardown
    run_test_as('wizard') do
      evaluate(%q{`delete_verb($system, "do_out_of_band_command") ! ANY => 0'})
      evaluate(%q{`delete_property($system, "oob_capture") ! ANY => 0'})
    end
  end

  private

  # A raw-injected in-band command line is still a normal typed command as
  # far as the connection's PREFIX/SUFFIX framing is concerned, so it gets
  # its own wrapped response -- exactly like every command() call does.
  # Since it wasn't sent via command(), nothing has read that response yet.
  # This mirrors command()'s own read loop (minus the send_string half) so
  # a raw-injected command's response can be read directly, the same way
  # test_huh.rb reads a "huh" verb's notify() output via command()'s return
  # value -- avoids any property-polling race against PREFIX/SUFFIX framing.
  def drain_marker_response
    acc = []
    state = :looking
    while (state != :done)
      line = @sock.gets.chomp
      state = :found and next if line == '-=!-^-!=-' and (state == :looking or state == :found)
      state = :done and next if line == '-=!-v-!=-' and state == :found
      acc << line and next if state == :found
    end
    acc.length > 0 ? acc.length > 1 ? acc : acc[0] : nil
  end

  def poll_until(timeout = 3.0)
    elapsed = 0.0
    result = nil
    while elapsed < timeout
      result = yield
      break if result
      sleep(0.1)
      elapsed += 0.1
    end
    result
  end

  # The test harness's expression parser unwraps a single-element MOO list
  # into its bare element (e.g. `{"x"}` parses as `"x"`, not `["x"]"`) --
  # only the empty-list case (nothing captured yet) is distinguishable as an
  # actual empty Ruby Array. This project's capture properties here only
  # ever accumulate exactly one entry per test, so callers assert against
  # the bare captured value, not a one-element array.
  def captured?(value)
    !(value.is_a?(Array) && value.empty?)
  end

  def setup_oob_capture
    add_property(:system, 'oob_capture', [], [player, ''])
    add_verb(:system, [player, 'xd', 'do_out_of_band_command'], ['this', 'none', 'this'])
    set_verb_code(SYSTEM, 'do_out_of_band_command') do |vc|
      vc << 'this.oob_capture = {@this.oob_capture, argstr};'
    end
  end

  def poll_oob_capture
    poll_until do
      arr = get(:system, 'oob_capture')
      captured?(arr) ? arr : nil
    end
  end

  # move() into a fresh room triggers its own room-entry output (e.g. a
  # look/description side effect) independently of the eval command's own
  # {1, ...} return value -- observed in practice as a stray, unpaired
  # "-=!-v-!=-" suffix line with no preceding prefix, arriving after
  # move()'s own command() call has already returned. Left alone, it would
  # desync the next command() call's marker pairing (and feeding it through
  # drain_marker_response's paired state machine would just hang forever
  # waiting for a prefix that will never come). Discard any such raw stray
  # lines directly, bounded by a short non-blocking wait so this is a no-op
  # once the connection is actually idle.
  def drain_stray_output
    sleep(1.0)
    while IO.select([@sock], nil, nil, 0.3)
      @sock.gets
    end
  end

  def make_huh_room
    room = create(:nothing)
    add_verb(room, [player, 'xd', 'accept'], ['this', 'none', 'this'])
    set_verb_code(room, 'accept') do |vc|
      vc << 'return 1;'
    end
    add_verb(room, [player, 'xd', 'huh'], ['this', 'none', 'this'])
    set_verb_code(room, 'huh') do |vc|
      vc << 'notify(player, verb);'
    end
    move(player, room)
    drain_stray_output
    room
  end

  public

  # IAC IAC is not currently reinjected as a literal 0xFF data byte -- both
  # bytes are consumed by the state machine with no output (see
  # TELNET_STATE_IAC's `c == TN_IAC` branch in network.cc). This locks in
  # that today's actual (swallowing) behavior survives when the two IAC
  # bytes are split across separate reads, rather than assuming RFC-854
  # semantics that this codebase doesn't implement.
  def test_that_split_iac_iac_escape_works
    run_test_with_prefix_and_suffix_as('wizard') do
      make_huh_room

      @sock.write("\xFF")
      @sock.flush
      sleep(0.1)
      @sock.write("\xFF" + "zzztelnetiac1\r\n")
      @sock.flush

      assert_equal 'zzztelnetiac1', drain_marker_response
    end
  end

  # IAC DO ECHO (a 3-byte WILL/WONT/DO/DONT command) split across all three
  # of its own bytes, each in a separate write/read.
  def test_that_split_three_byte_do_command_works
    run_test_with_prefix_and_suffix_as('wizard') do
      setup_oob_capture

      @sock.write("\xFF")
      @sock.flush
      sleep(0.1)
      @sock.write("\xFD")
      @sock.flush
      sleep(0.1)
      @sock.write("\x01")
      @sock.flush

      captured = poll_oob_capture
      assert_equal '~FF~FD~01', captured
    end
  end

  # IAC SB TERMINAL-TYPE 0 "xterm" IAC SE, split mid-payload.
  def test_that_split_subnegotiation_payload_works
    run_test_with_prefix_and_suffix_as('wizard') do
      setup_oob_capture

      @sock.write("\xFF\xFA\x18")
      @sock.flush
      sleep(0.1)
      @sock.write("\x00xterm")
      @sock.flush
      sleep(0.1)
      @sock.write("\xFF\xF0")
      @sock.flush

      captured = poll_oob_capture
      assert_equal '~FF~FA~18~00xterm~FF~F0', captured
    end
  end

  # Regression target for the historical "boundary issue extracting telnet
  # IAC sequences from the middle of input" bug class: the terminating
  # IAC SE split exactly at the IAC/SE boundary, across two separate reads.
  def test_that_iac_se_boundary_split_works
    run_test_with_prefix_and_suffix_as('wizard') do
      setup_oob_capture

      @sock.write("\xFF\xFA\x18\x00xterm")
      @sock.flush
      sleep(0.1)
      @sock.write("\xFF")
      @sock.flush
      sleep(0.1)
      @sock.write("\xF0")
      @sock.flush

      captured = poll_oob_capture
      assert_equal '~FF~FA~18~00xterm~FF~F0', captured
    end
  end

  # Regression target for the historical "IAC sequences mixed with in-band
  # data" bug class: ordinary command bytes before and after an IAC command,
  # all in the same write/read. The IAC command must still be extracted and
  # delivered out-of-band correctly, and the connection must remain healthy
  # afterward (not desynced/hung by the interleaved in-band bytes around
  # it) -- verified here via a plain eval on the same connection once the
  # OOB capture confirms the command was processed.
  def test_that_iac_mixed_with_inband_data_in_one_segment_works
    run_test_as('wizard') do
      setup_oob_capture

      @sock.write("zzzfoo\xFF\xFD\x01zzzbar\r\n")
      @sock.flush

      oob_captured = poll_oob_capture
      assert_equal '~FF~FD~01', oob_captured

      assert_equal 2, evaluate('1 + 1')
    end
  end

  # Worst-case granularity: every byte of a full IAC SB ... IAC SE sequence
  # arrives in its own separate write/read.
  def test_that_byte_at_a_time_subnegotiation_works
    run_test_with_prefix_and_suffix_as('wizard') do
      setup_oob_capture

      "\xFF\xFA\x01\xFF\xF0".each_byte do |b|
        @sock.write(b.chr)
        @sock.flush
        sleep(0.02)
      end

      captured = poll_oob_capture
      assert_equal '~FF~FA~01~FF~F0', captured
    end
  end

end
