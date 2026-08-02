require 'test_helper'

class TestMoocodeParsing < Test::Unit::TestCase

  def test_that_expression_exception_syntax_works
    run_test_as('programmer') do
      assert_equal [], simplify(command("; return `args ! ANY => 0';"))
    end
  end

  def test_that_greater_than_syntax_works
    run_test_as('programmer') do
      assert_equal 1, simplify(command("; return 3 > 2;"))
    end
  end

  def test_that_greater_than_or_equal_to_syntax_works
    run_test_as('programmer') do
      assert_equal 1, simplify(command("; return 3 >= 2;"))
    end
  end

  def test_that_less_than_syntax_works
    run_test_as('programmer') do
      assert_equal 1, simplify(command("; return 2 < 3;"))
    end
  end

  def test_that_less_than_or_equal_to_syntax_works
    run_test_as('programmer') do
      assert_equal 1, simplify(command("; return 2 <= 3;"))
    end
  end

  def test_that_and_syntax_works
    run_test_as('programmer') do
      assert_equal 3, simplify(command("; return 2 && 3;"))
    end
  end

  def test_that_or_syntax_works
    run_test_as('programmer') do
      assert_equal 2, simplify(command("; return 2 || 3;"))
    end
  end

  def test_that_caret_collection_syntax_works
    run_test_as('programmer') do
      assert_equal 1, simplify(command("; return {1, 2, 3}[^];"))
      assert_equal [1, 2], simplify(command("; return {1, 2, 3}[^ .. ^ + 1];"))
      assert_equal [1, 2], simplify(command("; return {1, 2, 3}[^..^ + 1];"))
    end
  end

  def test_that_dollar_sign_collection_syntax_works
    run_test_as('programmer') do
      assert_equal 3, simplify(command("; return {1, 2, 3}[$];"))
      assert_equal [2, 3], simplify(command("; return {1, 2, 3}[-1 + $ .. $];"))
      assert_equal [2, 3], simplify(command("; return {1, 2, 3}[-1 + $..$];"))
    end
  end

  def test_that_bitwise_and_works
    run_test_as('programmer') do
      assert_equal 0, simplify(command('; return 1 &. 2;'))
    end
  end

  def test_that_disassembling_bitwise_and_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'and'], ['this', 'none', 'this'])
      set_verb_code(o, 'and', ['1 &. 2;'])
      assert disassemble(o, 'and').detect { |line| line =~ /BITAND/ }
    end
  end

  def test_that_decompiling_bitwise_and_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'and'], ['this', 'none', 'this'])
      set_verb_code(o, 'and', ['1 &. 2;'])
      assert_equal '1 &. 2;', verb_code(o, 'and')
    end
  end

  def test_that_bitwise_or_works
    run_test_as('programmer') do
      assert_equal 3, simplify(command('; return 1 |. 2;'))
    end
  end

  def test_that_disassembling_bitwise_or_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'or'], ['this', 'none', 'this'])
      set_verb_code(o, 'or', ['1 |. 2;'])
      assert disassemble(o, 'or').detect { |line| line =~ /BITOR/ }
    end
  end

  def test_that_decompiling_bitwise_or_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'or'], ['this', 'none', 'this'])
      set_verb_code(o, 'or', ['1 |. 2;'])
      assert_equal '1 |. 2;', verb_code(o, 'or')
    end
  end

  def test_that_bitwise_xor_works
    run_test_as('programmer') do
      assert_equal 2, simplify(command('; return 1 ^. 3;'))
    end
  end

  def test_that_disassembling_bitwise_xor_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'xor'], ['this', 'none', 'this'])
      set_verb_code(o, 'xor', ['1 ^. 2;'])
      assert disassemble(o, 'xor').detect { |line| line =~ /BITXOR/ }
    end
  end

  def test_that_decompiling_bitwise_xor_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'xor'], ['this', 'none', 'this'])
      set_verb_code(o, 'xor', ['1 ^. 2;'])
      assert_equal '1 ^. 2;', verb_code(o, 'xor')
    end
  end

  def test_that_bitwise_complement_works
    run_test_as('programmer') do
      assert_equal -1, simplify(command('; return ~0;'))
    end
  end

  def test_that_disassembling_bitwise_complement_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'complement'], ['this', 'none', 'this'])
      set_verb_code(o, 'complement', ['~123;'])
      assert disassemble(o, 'complement').detect { |line| line =~ /COMPLEMENT/ }
    end
  end

  def test_that_decompiling_bitwise_complement_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'complement'], ['this', 'none', 'this'])
      set_verb_code(o, 'complement', ['~123;'])
      assert_equal '~123;', verb_code(o, 'complement')
    end
  end

  def test_that_bit_shift_left_works
    run_test_as('programmer') do
      assert_equal 4, simplify(command('; return 1 << 2;'))
    end
  end

  def test_that_disassembling_bit_shift_left_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'shift_left'], ['this', 'none', 'this'])
      set_verb_code(o, 'shift_left', ['1 << 2;'])
      assert disassemble(o, 'shift_left').detect { |line| line =~ /BITSHL/ }
    end
  end

  def test_that_decompiling_bit_shift_left_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'shift_left'], ['this', 'none', 'this'])
      set_verb_code(o, 'shift_left', ['1 << 2;'])
      assert_equal '1 << 2;', verb_code(o, 'shift_left')
    end
  end

  def test_that_bit_shift_right_works
    run_test_as('programmer') do
      assert_equal 2, simplify(command('; return 8 >> 2;'))
    end
  end

  def test_that_disassembling_bit_shift_right_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'shift_right'], ['this', 'none', 'this'])
      set_verb_code(o, 'shift_right', ['1 >> 2;'])
      assert disassemble(o, 'shift_right').detect { |line| line =~ /BITSHR/ }
    end
  end

  def test_that_decompiling_bit_shift_right_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'shift_right'], ['this', 'none', 'this'])
      set_verb_code(o, 'shift_right', ['1 >> 2;'])
      assert_equal '1 >> 2;', verb_code(o, 'shift_right')
    end
  end

  def test_specific_left_shift_edge_cases
    run_test_as('programmer') do
        if @@options['64bit']
            lmb = simplify(command('; return -9223372036854775808;'))
            rmb = simplify(command('; return 1;'))
            all = simplify(command('; return ~0;'))

            assert_equal E_INVARG, simplify(command('; return 0 << -1;'))
            assert_equal E_INVARG, simplify(command('; return 0 << 65;'))

            assert_equal rmb, simplify(command("; return #{rmb} << 0;"))
            assert_equal lmb, simplify(command("; return #{rmb} << 63;"))
            assert_equal lmb, simplify(command("; return #{all} << 63;"))
            assert_equal 0, simplify(command("; return #{rmb} << 64;"))
        else
            lmb = simplify(command('; return -2147483648;'))
            rmb = simplify(command('; return 1;'))
            all = simplify(command('; return ~0;'))

            assert_equal E_INVARG, simplify(command('; return 0 << -1;'))
            assert_equal E_INVARG, simplify(command('; return 0 << 33;'))

            assert_equal rmb, simplify(command("; return #{rmb} << 0;"))
            assert_equal lmb, simplify(command("; return #{rmb} << 31;"))
            assert_equal lmb, simplify(command("; return #{all} << 31;"))
            assert_equal 0, simplify(command("; return #{rmb} << 32;"))
        end
    end
  end

  def test_specific_right_shift_edge_cases
    run_test_as('programmer') do
        if @@options['64bit']
            lmb = simplify(command('; return -9223372036854775807;'))
            rmb = simplify(command('; return 1;'))
            all = simplify(command('; return ~0;'))

            assert_equal E_INVARG, simplify(command('; return 0 >> -1;'))
            assert_equal E_INVARG, simplify(command('; return 0 >> 65;'))

            assert_equal lmb, simplify(command("; return #{lmb} >> 0;"))
            assert_equal rmb, simplify(command("; return #{lmb} >> 63;"))
            assert_equal rmb, simplify(command("; return #{all} >> 63;"))
            assert_equal 0, simplify(command("; return #{lmb} >> 64;"))
        else
            lmb = simplify(command('; return -2147483648;'))
            rmb = simplify(command('; return 1;'))
            all = simplify(command('; return ~0;'))

            assert_equal E_INVARG, simplify(command('; return 0 >> -1;'))
            assert_equal E_INVARG, simplify(command('; return 0 >> 33;'))

            assert_equal lmb, simplify(command("; return #{lmb} >> 0;"))
            assert_equal rmb, simplify(command("; return #{lmb} >> 31;"))
            assert_equal rmb, simplify(command("; return #{all} >> 31;"))
            assert_equal 0, simplify(command("; return #{lmb} >> 32;"))
        end
    end
  end

  def test_shift_left_shift_right
      run_test_as('programmer') do
          if @@options['64bit']
              (1..63).each do |i|
                  assert_equal -9223372036854775808, simplify(command("; return (-9223372036854775807 >> #{i % 64}) << #{i % 64};"))
                  assert_equal 1, simplify(command("; return (1 << #{i % 64}) >> #{i % 64};"))
              end
          else
              32.times do |i|
                  assert_equal -2147483648, simplify(command("; return (-2147483648 >> #{i % 32}) << #{i % 32};"))
                  assert_equal 1, simplify(command("; return (1 << #{i % 32}) >> #{i % 32};"))
              end
          end
      end
  end

  def test_precedence
    run_test_as('programmer') do
      assert_equal 2, simplify(command('; return 1 << 3 >> 2;'))
      if @@options['64bit']
          assert_equal 9223372036854775807, simplify(command('; return ~0 >> 1;'))
      else
          assert_equal 2147483647, simplify(command('; return ~0 >> 1;'))
      end
      assert_equal 2, simplify(command('; return 1 << 1 &. 2;'))
      assert_equal 1, simplify(command('; return 4 >> 2 &. 1;'))
    end
  end

  # The trailing semicolon on the last statement in a block is optional when
  # immediately followed by a block-closing keyword (or end of program) --
  # the closer itself already unambiguously ends the block, so requiring a
  # semicolon there too is redundant. Decompiled output always normalizes
  # the semicolon back in, since the AST is identical either way.

  def test_that_decompiling_if_without_trailing_semicolon_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'v'], ['this', 'none', 'this'])
      assert_equal [], set_verb_code(o, 'v', ['if (1) return 5 endif'])
      assert_equal ['if (1)', '  return 5;', 'endif'], verb_code(o, 'v')
    end
  end

  def test_that_decompiling_if_else_without_trailing_semicolon_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'v'], ['this', 'none', 'this'])
      assert_equal [], set_verb_code(o, 'v', ['if (0) return 1 else return 2 endif'])
      assert_equal ['if (0)', '  return 1;', 'else', '  return 2;', 'endif'], verb_code(o, 'v')
    end
  end

  def test_that_decompiling_for_without_trailing_semicolon_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'v'], ['this', 'none', 'this'])
      assert_equal [], set_verb_code(o, 'v', ['for i in [1..3] break endfor'])
      assert_equal ['for i in [1..3]', '  break;', 'endfor'], verb_code(o, 'v')
    end
  end

  def test_that_decompiling_while_without_trailing_semicolon_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'v'], ['this', 'none', 'this'])
      assert_equal [], set_verb_code(o, 'v', ['x = 0; while (x < 1) x = x + 1; continue endwhile return x;'])
      assert_equal ['x = 0;', 'while (x < 1)', '  x = x + 1;', '  continue;', 'endwhile', 'return x;'], verb_code(o, 'v')
    end
  end

  def test_that_decompiling_try_except_without_trailing_semicolon_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'v'], ['this', 'none', 'this'])
      assert_equal [], set_verb_code(o, 'v', ['try return 1 except e (ANY) return 2 endtry'])
      assert_equal ['try', '  return 1;', 'except e (ANY)', '  return 2;', 'endtry'], verb_code(o, 'v')
    end
  end

  def test_that_decompiling_try_finally_without_trailing_semicolon_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'v'], ['this', 'none', 'this'])
      assert_equal [], set_verb_code(o, 'v', ['x = 0; try x = 1 finally x = x + 1 endtry return x;'])
      assert_equal ['x = 0;', 'try', '  x = 1;', 'finally', '  x = x + 1;', 'endtry', 'return x;'], verb_code(o, 'v')
    end
  end

  def test_that_decompiling_final_program_statement_without_trailing_semicolon_works
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'v'], ['this', 'none', 'this'])
      assert_equal [], set_verb_code(o, 'v', ['return 42'])
      assert_equal 'return 42;', verb_code(o, 'v')
    end
  end

  def test_that_semicolon_is_still_required_between_non_final_statements
    run_test_as('programmer') do
      o = create(:nothing)
      add_verb(o, [player, 'xd', 'v'], ['this', 'none', 'this'])
      assert_not_equal [], set_verb_code(o, 'v', ['x = 1 y = 2;'])
    end
  end

end
