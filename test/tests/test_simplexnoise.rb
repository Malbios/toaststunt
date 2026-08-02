require 'test_helper'

class TestSimplexnoise < Test::Unit::TestCase

  # simplex_noise() is deterministic (no seeding, a fixed perm[512] table),
  # so a spread of sample points across 1D-4D should always stay within the
  # documented [-1, 1] output range.
  def test_that_simplex_noise_stays_within_range_across_dimensions
    run_test_as('programmer') do
      samples = [
        [0.0],
        [0.37, 1.0],
        [1.5, -2.25, 0.1],
        [3.3, -0.7, 2.2, -1.9],
        [10.0],
        [-5.5, 5.5],
        [100.25, -100.25, 50.5],
        [0.001, 0.002, 0.003, 0.004],
      ]

      samples.each do |point|
        args = point.map { |n| n.to_s }.join(', ')
        result = simplify(command %Q|; return simplex_noise({#{args}});|)
        assert result.is_a?(Float), "expected a float for simplex_noise({#{args}}), got #{result.inspect}"
        assert result >= -1.0 && result <= 1.0, "simplex_noise({#{args}}) = #{result} is outside [-1, 1]"
      end
    end
  end

  # simplex_noise() rejects anything other than a list of 1 to 4 floats.
  def test_that_simplex_noise_rejects_bad_arguments
    run_test_as('programmer') do
      assert_equal E_TYPE, simplify(command %Q|; return simplex_noise({1, 2, 3, 4, 5});|)
      assert_equal E_TYPE, simplify(command %Q|; return simplex_noise({1});|)
      assert_equal E_TYPE, simplify(command %Q|; return simplex_noise({1.0, "two"});|)
    end
  end

  # Regression test for the 2D scale factor fix (40.0 -> 70.0, matching
  # Stefan Gustavson's later corrected reference implementation): fixed
  # input/output snapshots to catch any future accidental regression back
  # to the old placeholder constant, which would silently shrink every 2D
  # result by a factor of ~1.75.
  def test_that_2d_simplex_noise_matches_known_values
    run_test_as('programmer') do
      assert_in_delta(-0.219909865884995, simplify(command %Q|; return simplex_noise({0.37, 1.0});|), 0.0001)
      assert_in_delta(0.741765249238095, simplify(command %Q|; return simplex_noise({1.5, -2.25});|), 0.0001)
      assert_in_delta(0.0, simplify(command %Q|; return simplex_noise({0.0, 0.0});|), 0.0001)
    end
  end

end
