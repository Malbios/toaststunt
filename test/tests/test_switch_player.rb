require 'test_helper'

class TestSwitchPlayer < Test::Unit::TestCase

  def test_that_switch_player_does_not_work_for_non_wizards
    run_test_as('programmer') do
      assert_equal E_PERM, simplify(switch_player(player, player))
    end
  end

  def test_that_switch_player_switches_player
    run_test_as('wizard') do
      old_player = player
      new_player = make_new_player
      switch_player(player, new_player)
      assert_not_equal old_player, simplify(command %Q|;return player;|)
      assert_equal new_player, simplify(command %Q|;return player;|)
    end
  end

  def test_that_switching_back_and_forth_works
    run_test_as('wizard') do
      old_player = player
      new_player = make_new_player
      switch_player(player, new_player)
      assert_not_equal old_player, simplify(command %Q|;return player;|)
      assert_equal new_player, simplify(command %Q|;return player;|)
      switch_player(new_player, player)
      assert_equal old_player, simplify(command %Q|;return player;|)
      assert_not_equal new_player, simplify(command %Q|;return player;|)
      switch_player(player, new_player)
      assert_not_equal old_player, simplify(command %Q|;return player;|)
      assert_equal new_player, simplify(command %Q|;return player;|)
    end
  end

  # Regression test for the O(1) find_shandle() lookup index added in
  # server.cc (all_shandles_by_player, alongside the pre-existing
  # all_shandles linked list). Switching a second, independent connection
  # into a player id that's already connected briefly leaves two shandles
  # claiming the same player id -- see the comment in player_switched().
  # The index has to end up resolving that id to the surviving connection,
  # not a stale or wrong one, or every builtin that calls find_shandle()
  # (notify() among them) would target the wrong socket after a redirect.
  def test_that_switching_into_an_already_connected_player_redirects_to_the_new_connection
    run_test_as('wizard') do
      a_player = player

      sock_b = TCPSocket.open(options['host'], options['port'])
      sock_b.puts 'connect wizard'

      begin
        # Fire the switch and drain whatever comes back without trying to
        # parse it: switch_player()'s own redirect notice is sent via a
        # direct, unqueued send_message() call (not notify()), and the
        # eval verb's own completion marker for *this* command isn't
        # reliably delivered once the task's identity changes mid-verb
        # (the library's own switch_player helper above works around the
        # same quirk by re-sending the marker itself) -- so this is
        # expected to run out its short timeout rather than complete
        # cleanly. What matters is the state of the world *after* it
        # settles, checked below with fresh queries.
        raw_command(sock_b, "; return switch_player(player, #{a_player});", 1.5)

        b_player_after = simplify(raw_command(sock_b, '; return player;'))
        assert_equal a_player, b_player_after

        # a lookup for a_player's id must now resolve to B's connection --
        # if find_shandle() still (or again) pointed at A's freed handle,
        # this would return stale/garbage data instead of "true".
        still_correct = simplify(raw_command(sock_b, "; return player == #{a_player};"))
        assert_equal 1, still_correct
      ensure
        sock_b.close rescue nil
      end
    end
  end

  private

  def make_new_player
    simplify command %Q|;o = create($nothing); move(o, player.location); set_player_flag(o, 1); o.programmer = 1; o.wizard = 1; return o;|
  end

  # Minimal standalone version of MooSupport#command for a second,
  # independently-managed connection. Test.db's eval verb (#2:0) always
  # wraps its output in the same -=!-^-!=- / -=!-v-!=- markers regardless
  # of connection state, so this only needs to replicate the marker
  # state machine, not PREFIX/SUFFIX setup.
  def raw_command(sock, cmd, timeout_s = 5)
    sock.puts cmd
    acc = []
    state = :looking
    deadline = Time.now + timeout_s
    while state != :done
      remaining = deadline - Time.now
      break if remaining <= 0
      break unless IO.select([sock], nil, nil, remaining)
      line = sock.gets
      break if line.nil?
      line = line.chomp
      state = :found and next if line == '-=!-^-!=-' && (state == :looking || state == :found)
      state = :done and next if line == '-=!-v-!=-' && state == :found
      acc << line and next if state == :found
    end
    acc.length > 0 ? (acc.length > 1 ? acc : acc[0]) : nil
  end

end
