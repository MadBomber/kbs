# frozen_string_literal: true

require_relative 'test_helper'

class TestDecompiler < Minitest::Test
  include KBS::DSL::ConditionHelpers

  limit = 7
  CLASS_BODY_LAMBDA = ->(v) { v < limit }

  class DecompilerFixtures
    def nested_capture
      [1].map { |offset| ->(v) { v < offset } }.first
    end
  end


  # Its local table matches the nested block's locals, which must not fool
  # the decompiler into reading the block's slot from this method.
  class DecompilerFixturesChild < DecompilerFixtures
    def nested_capture(offset = nil)
      super() unless offset
    end
  end


  def test_renders_value_captured_by_greater_than
    assert_equal '->(v) { v > 80 }', decompile(greater_than(80))
  end


  def test_renders_values_captured_by_between
    source = decompile(between(1, 9))

    assert_includes source, 'v >= 1'
    assert_includes source, 'v <= 9'
    refute_includes source, 'getlocal'
  end


  def test_renders_value_captured_from_method_with_keyword_args
    assert_equal '->(v) { v < 2 }', decompile(keyword_capture(2, flag: true))
  end


  def test_nested_block_capture_falls_back_to_comment
    assert_equal '->(v) { v < /* getlocal_WC_1 */ }', decompile(DecompilerFixtures.new.nested_capture)
  end


  def test_nested_block_capture_in_overridden_method_falls_back_to_comment
    assert_equal '->(v) { v < /* getlocal_WC_1 */ }',
                 decompile(DecompilerFixturesChild.new.nested_capture)
  end


  def test_class_body_lambda_falls_back_to_comment
    assert_equal '->(v) { v < /* getlocal_WC_1 */ }', decompile(CLASS_BODY_LAMBDA)
  end


  def test_value_without_literal_form_falls_back_to_comment
    [Object.new, 1/3r, Float::INFINITY, [1], 1..5, "\xFF".b, Class.new(String).new('s')].each do |value|
      assert_equal '->(v) { v == /* getlocal_WC_1 */ }', decompile(equality_capture(value))
    end
  end


  def test_renders_scalar_literal_values
    [5, 2.5, :c, 'x', nil, true].each do |value|
      assert_equal "->(v) { v == #{value.inspect} }", decompile(equality_capture(value))
    end
  end


  def test_renders_not_equal
    assert_equal '->(v) { v != 5 }', decompile(not_equal(5))
  end


  def test_block_inside_lambda_names_the_lambda_local
    assert_equal '->(v) { v.any? { |x| x > v } }', decompile(inner_block_lambda)
  end

  private


  def keyword_capture(limit, flag:)
    ->(v) { v < limit } if flag
  end


  def equality_capture(target)
    ->(v) { v == target }
  end


  def inner_block_lambda
    marker = 99
    ->(v) { v.any? { |x| x > v } } if marker
  end


  def decompile(proc_obj)
    KBS::Decompiler.new(proc_obj).decompile
  end
end
