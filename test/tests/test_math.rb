require 'test_helper'

class TestMath < Test::Unit::TestCase

  def test_that_random_0_is_invalid
    run_test_as('programmer') do
      assert_equal E_INVARG, random(0)
    end
  end

  def test_that_random_1_returns_1
    run_test_as('programmer') do
      assert_equal 1, random(1)
    end
  end

  def test_that_random_returns_a_number_between_1_and_2147483647
    run_test_as('programmer') do
      1000.times do
        r = random
        if @@options['64bit']
            assert r > 0 && r <= 9223372036854775807
        else
            assert r > 0 && r <= 2147483647
        end
      end
    end
  end

  def test_that_random_requires_a_positive_integer
    run_test_as('programmer') do
      assert_equal E_INVARG, random(-1)
    end
  end

  def test_that_random_bytes_requires_a_non_negative_integer
    run_test_as('programmer') do
      assert_equal E_INVARG, random_bytes(-1)
    end
  end

  def test_that_random_bytes_0_is_the_empty_string
    run_test_as('programmer') do
      assert_equal '', random_bytes(0)
    end
  end

  def test_that_random_bytes_1_returns_one_byte
    run_test_as('programmer') do
      assert_equal 1, random_bytes(1).binary_string_to_binary.length
    end
  end

  def test_that_random_bytes_2_returns_two_bytes
    run_test_as('programmer') do
      assert_equal 2, random_bytes(2).binary_string_to_binary.length
    end
  end

  def test_that_random_bytes_returns_no_more_than_10000_bytes
    run_test_as('programmer') do
      assert_equal E_INVARG, random_bytes(10001)
    end
  end

  def test_that_division_by_zero_fails
    run_test_as('programmer') do
      assert_equal E_DIV, simplify(command(%Q|; 1.1 / 0.0; |))
      assert_equal E_DIV, simplify(command(%Q|; 1 / 0; |))
      assert_equal E_DIV, simplify(command(%Q|; 1.1 % 0.0; |))
      assert_equal E_DIV, simplify(command(%Q|; 1 % 0; |))
    end
  end

  def test_the_minint_edge_case
    run_test_as('programmer') do
        if @@options['64bit']
            assert_equal -9223372036854775807, simplify(command(%Q|; return -9223372036854775807 / -1; |))
            assert_equal 0, simplify(command(%Q|; return -9223372036854775807 % -1; |))
        else
            assert_equal -2147483648, simplify(command(%Q|; return -2147483648 / -1; |))
            assert_equal 0, simplify(command(%Q|; return -2147483648 % -1; |))
        end
    end
  end

  def test_division
    run_test_as('programmer') do
      assert_equal 5, simplify(command(%Q|; return -15 / -3; |))
      assert_equal -5, simplify(command(%Q|; return -15 / 3; |))
      assert_equal -5, simplify(command(%Q|; return 15 / -3; |))
      assert_equal 5, simplify(command(%Q|; return 15 / 3; |))
    end
    run_test_as('programmer') do
      assert_equal 5.0, simplify(command(%Q|; return -15.0 / -3.0; |))
      assert_equal -5.0, simplify(command(%Q|; return -15.0 / 3.0; |))
      assert_equal -5.0, simplify(command(%Q|; return 15.0 / -3.0; |))
      assert_equal 5.0, simplify(command(%Q|; return 15.0 / 3.0; |))
    end
  end

  def test_modulus
    run_test_as('programmer') do
      assert_equal -3, simplify(command(%Q|; return -15 % -4; |))
      assert_equal 1, simplify(command(%Q|; return -15 % 4; |))
      assert_equal -1, simplify(command(%Q|; return 15 % -4; |))
      assert_equal 3, simplify(command(%Q|; return 15 % 4; |))
    end
    run_test_as('programmer') do
      assert_equal -3.0, simplify(command(%Q|; return -15.0 % -4.0; |))
      assert_equal 1.0, simplify(command(%Q|; return -15.0 % 4.0; |))
      assert_equal -1.0, simplify(command(%Q|; return 15.0 % -4.0; |))
      assert_equal 3.0, simplify(command(%Q|; return 15.0 % 4.0; |))
    end
  end

  def test_that_format_time_uses_a_caller_supplied_strftime_format
    run_test_as('programmer') do
      # A fixed, arbitrary epoch time -- the exact wall-clock rendering is
      # timezone-dependent (format_time uses localtime()), so this only
      # checks that a custom format string is honored, not a specific value.
      assert_equal 5, simplify(command(%Q|; return length(format_time("%H:%M", 0));|))
    end
  end

  def test_that_format_time_defaults_to_the_current_time
    run_test_as('programmer') do
      assert_kind_of String, simplify(command('; return format_time();'))
    end
  end

  def test_that_parse_time_is_the_inverse_of_format_time
    run_test_as('programmer') do
      # Round-trip through both functions instead of asserting an absolute
      # value, so the test passes regardless of the server's timezone.
      assert_equal 1000000000, simplify(command(%Q|; return parse_time(format_time("%Y-%m-%d %H:%M:%S", 1000000000), "%Y-%m-%d %H:%M:%S");|))
    end
  end

  def test_that_parse_time_rejects_input_that_does_not_match_the_format
    run_test_as('programmer') do
      assert_equal E_INVARG, simplify(command(%Q|; return parse_time("not a date", "%Y-%m-%d");|))
    end
  end

end
