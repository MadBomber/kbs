# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs'

class TestDSLRuleBuilder < Minitest::Test
  def test_initialization
    builder = KBS::DSL::RuleBuilder.new('test_rule')

    assert_instance_of KBS::DSL::RuleBuilder, builder
    assert_equal 'test_rule', builder.name
  end

  def test_single_condition
    builder = KBS::DSL::RuleBuilder.new('test_rule')
    builder.on(:car, color: :red)

    rule = builder.build
    assert_equal 1, rule.conditions.size
    assert_equal :car, rule.conditions.first.type
  end

  def test_multiple_conditions
    builder = KBS::DSL::RuleBuilder.new('test_rule')
    builder.on(:car, color: :red)
    builder.on(:driver, age: 25)

    rule = builder.build
    assert_equal 2, rule.conditions.size
  end

  def test_negated_condition
    builder = KBS::DSL::RuleBuilder.new('test_rule')
    builder.on(:car, color: :red)
    builder.without(:problem)

    rule = builder.build
    assert_equal 2, rule.conditions.size
    assert rule.conditions.last.negated
  end

  def test_action
    fired = false
    builder = KBS::DSL::RuleBuilder.new('test_rule')
    builder.on(:car, color: :red)
    builder.perform { |facts| fired = true }

    rule = builder.build
    assert_instance_of Proc, rule.action
    rule.action.call([])
    assert fired
  end

  def test_dsl_block_evaluation
    builder = KBS::DSL::RuleBuilder.new('test_rule')

    builder.instance_eval do
      on :car, color: :red
      on :driver, age: 25
      without :problem
      perform { |facts| :action }
    end

    rule = builder.build
    assert_equal 3, rule.conditions.size
    assert rule.conditions.last.negated
    assert_instance_of Proc, rule.action
  end

  def test_aliases
    builder = KBS::DSL::RuleBuilder.new('test_rule')

    # Test 'given' alias for 'on'
    builder.given(:car, color: :red)
    assert_equal 1, builder.instance_variable_get(:@conditions).size

    # Test 'matches' alias for 'on'
    builder.matches(:driver, age: 25)
    assert_equal 2, builder.instance_variable_get(:@conditions).size

    # Test 'then' alias for 'perform'
    builder.then { |facts| :action }
    assert_instance_of Proc, builder.instance_variable_get(:@action_block)
  end

  def test_condition_with_proc
    builder = KBS::DSL::RuleBuilder.new('test_rule')
    builder.on(:car, speed: ->(s) { s > 100 })

    rule = builder.build
    condition = rule.conditions.first

    assert condition.pattern[:speed].is_a?(Proc)
  end

  def test_empty_pattern
    builder = KBS::DSL::RuleBuilder.new('test_rule')
    builder.on(:car)

    rule = builder.build
    assert_equal :car, rule.conditions.first.type
    assert_empty rule.conditions.first.pattern.reject { |k, _| k == :type }
  end
end
