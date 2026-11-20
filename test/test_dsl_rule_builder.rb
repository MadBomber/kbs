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
    builder.perform { |_facts| fired = true }

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
      perform { |_facts| :action }
    end

    rule = builder.build
    assert_equal 3, rule.conditions.size
    assert rule.conditions.last.negated
    assert_instance_of Proc, rule.action
  end

  def test_perform_with_zero_argument_method
    receiver = Object.new
    builder = KBS::DSL::RuleBuilder.new('test_rule')
    builder.perform(&receiver.method(:object_id))

    assert_equal receiver.object_id, builder.build.fire([])
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
    builder.then { |_facts| :action }
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
    assert_empty(rule.conditions.first.pattern.except(:type))
  end

  # Contract: dsl/block-pattern-variables
  # Bug: a bare name used as a value in a block pattern stayed a DSL::Variable and never matched
  def test_bare_name_in_block_pattern_binds_a_variable
    builder = KBS::DSL::RuleBuilder.new('r')
    builder.on(:temperature) { location loc }

    assert_equal({ location: :loc? }, builder.conditions.first.pattern)
    assert_equal({ loc?: :location }, builder.conditions.first.variable_bindings)
  end

  # Contract: dsl/block-pattern-variables
  # Bug: two block conditions sharing a bare-name variable never joined
  def test_bare_name_variables_join_conditions
    fired = []
    kb = KBS.knowledge_base do
      rule "join" do
        on(:temperature) { location loc }
        on(:alarm) { location loc }
        perform { |_facts, bindings| fired << bindings[:loc?] }
      end
      fact :temperature, location: "lab"
      fact :alarm, location: "lab"
      fact :alarm, location: "attic"
    end

    kb.run

    assert_equal ["lab"], fired
  end

  # Each comparison in a pattern block records a predicate, so none is void.
  # rubocop:disable Lint/Void
  # Contract: dsl/block-pattern-operators
  # Bug: `value > 80` in a block pattern raised NoMethodError
  def test_comparison_operators_in_block_pattern_build_predicates
    builder = KBS::DSL::RuleBuilder.new('r')
    builder.on(:t) do
      high > 80
      low < 10
      at_least >= 5
      at_most <= 5
      code != 3
      exact == 7
    end
    pattern = builder.conditions.first.pattern

    assert_equal %i[high low at_least at_most code exact], pattern.keys
    assert_equal 7, pattern[:exact]
    assert [pattern[:high].call(81), !pattern[:high].call(80)].all?
    assert [pattern[:low].call(9), !pattern[:low].call(10)].all?
    assert [pattern[:at_least].call(5), !pattern[:at_least].call(4)].all?
    assert [pattern[:at_most].call(5), !pattern[:at_most].call(6)].all?
    assert [pattern[:code].call(4), !pattern[:code].call(3)].all?
  end

  # Contract: dsl/block-pattern-operators
  # Bug: a rule written with `value > 80` in a block pattern never fired
  def test_rule_with_operator_block_pattern_fires
    fired = []
    kb = KBS.knowledge_base do
      rule "hot" do
        on(:t) { value > 80 }
        perform { |facts| fired << facts.first[:value] }
      end
      fact :t, value: 95
      fact :t, value: 50
    end

    kb.run

    assert_equal [95], fired
  end
  # rubocop:enable Lint/Void
end
