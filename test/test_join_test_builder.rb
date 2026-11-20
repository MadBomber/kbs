# frozen_string_literal: true

require_relative 'test_helper'

class TestJoinTestBuilder < Minitest::Test
  def tests_for(*conditions)
    KBS::JoinTestBuilder.new(conditions).tests
  end

  def test_variable_predicate
    assert KBS::JoinTestBuilder.variable?(:id?)
    refute KBS::JoinTestBuilder.variable?(:id)
    refute KBS::JoinTestBuilder.variable?("id?")
  end

  def test_no_tests_without_shared_variables
    tests = tests_for(
      KBS::Condition.new(:a, { x: :x? }),
      KBS::Condition.new(:b, { y: :y? })
    )

    assert_equal [[], []], tests
  end

  def test_shared_variable_joins_to_the_binding_condition
    tests = tests_for(
      KBS::Condition.new(:sensor, { id: :id? }),
      KBS::Condition.new(:threshold, { sensor_id: :id? })
    )

    assert_equal [], tests[0]
    assert_equal [{ token_field_index: 0, token_field: :id, fact_field: :sensor_id, operation: :eq }], tests[1]
  end

  def test_variable_joins_to_its_first_binding
    tests = tests_for(
      KBS::Condition.new(:a, { x: :v? }),
      KBS::Condition.new(:b, { y: :v? }),
      KBS::Condition.new(:c, { z: :v? })
    )

    assert_equal 0, tests[2].first[:token_field_index]
    assert_equal :x, tests[2].first[:token_field]
  end

  def test_token_index_counts_negated_conditions
    tests = tests_for(
      KBS::Condition.new(:a, { x: :x? }),
      KBS::Condition.new(:block, {}, negated: true),
      KBS::Condition.new(:c, { y: :y? }),
      KBS::Condition.new(:d, { y: :y? })
    )

    assert_equal 2, tests[3].first[:token_field_index]
  end

  def test_negated_condition_joins_on_bound_variable
    tests = tests_for(
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:payment, { order_id: :id? }, negated: true)
    )

    assert_equal [{ token_field_index: 0, token_field: :id, fact_field: :order_id, operation: :eq }], tests[1]
  end

  def test_variable_first_seen_in_negated_condition_binds_nothing
    tests = tests_for(
      KBS::Condition.new(:a, {}),
      KBS::Condition.new(:b, { x: :v? }, negated: true),
      KBS::Condition.new(:c, { x: :v? })
    )

    assert_equal [[], [], []], tests
  end

  def test_variable_repeated_in_one_condition_compares_fact_fields
    tests = tests_for(KBS::Condition.new(:pair, { left: :v?, right: :v? }))

    assert_equal [[{ fact_field: :right, other_fact_field: :left, operation: :eq }]], tests
  end

  def test_constant_user_type_attribute_is_tested
    tests = tests_for(KBS::Condition.new(:sensor, { type: "temperature" }))

    assert_equal "temperature", tests[0].first[:expected_value]
    assert_equal :type, tests[0].first[:fact_field]
  end

  def test_variable_user_type_attribute_needs_no_constant_test
    tests = tests_for(KBS::Condition.new(:sensor, { type: :kind? }))

    assert_equal [[]], tests
  end
end
