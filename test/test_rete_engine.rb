# frozen_string_literal: true

require_relative 'test_helper'

class TestEngine < Minitest::Test
  def setup
    @engine = KBS::Engine.new
  end

  def test_initialization
    assert_instance_of KBS::Engine, @engine
    assert_instance_of KBS::WorkingMemory, @engine.working_memory
  end

  def test_add_fact
    fact = @engine.add_fact(:car, { color: :red, speed: 100 })

    assert_instance_of KBS::Fact, fact
    assert_equal :car, fact.type
    assert_equal :red, fact[:color]
    assert_equal 100, fact[:speed]
    assert_includes @engine.working_memory.facts, fact
  end

  def test_remove_fact
    fact = @engine.add_fact(:car, { color: :blue })
    @engine.remove_fact(fact)

    refute_includes @engine.working_memory.facts, fact
  end

  def test_add_rule
    rule = KBS::Rule.new('test_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.action = ->(facts) { :rule_fired }
    end

    @engine.add_rule(rule)

    assert @engine.instance_variable_get(:@rules).include?(rule)
  end

  def test_alpha_network_creation
    condition = KBS::Condition.new(:car, { color: :red })
    pattern = condition.pattern.merge(type: condition.type)
    @engine.send(:get_or_create_alpha_memory, pattern)

    alpha_memories = @engine.instance_variable_get(:@alpha_memories)
    assert alpha_memories.key?(pattern)
  end

  def test_rule_compilation_single_condition
    rule = KBS::Rule.new('simple_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.action = ->(facts) { :fired }
    end

    @engine.add_rule(rule)

    production_nodes = @engine.instance_variable_get(:@production_nodes)
    assert production_nodes.key?(rule.name)
  end

  def test_rule_compilation_multiple_conditions
    rule = KBS::Rule.new('complex_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.conditions << KBS::Condition.new(:driver, { age: 25 })
      r.action = ->(facts) { :fired }
    end

    @engine.add_rule(rule)

    production_nodes = @engine.instance_variable_get(:@production_nodes)
    assert production_nodes.key?(rule.name)
  end

  def test_rule_compilation_with_negation
    rule = KBS::Rule.new('negation_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.conditions << KBS::Condition.new(:problem, {}, negated: true)
      r.action = ->(facts) { :fired }
    end

    @engine.add_rule(rule)

    production_nodes = @engine.instance_variable_get(:@production_nodes)
    assert production_nodes.key?(rule.name)
  end

  def test_simple_inference
    fired = false

    rule = KBS::Rule.new('red_car_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.action = ->(facts) { fired = true }
    end

    @engine.add_rule(rule)
    @engine.add_fact(:car, { color: :red, speed: 100 })
    @engine.run

    assert fired, "Rule should have fired"
  end

  def test_multi_condition_inference
    result = []

    rule = KBS::Rule.new('young_driver_rule') do |r|
      r.conditions << KBS::Condition.new(:driver, { age: 20 })
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.action = ->(facts) { result << facts }
    end

    @engine.add_rule(rule)
    @engine.add_fact(:driver, { age: 20 })
    @engine.add_fact(:car, { color: :red })
    @engine.run

    assert_equal 1, result.size
    assert_equal 2, result.first.size
  end

  def test_negation_inference
    result = []

    rule = KBS::Rule.new('no_problem_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.conditions << KBS::Condition.new(:problem, {}, negated: true)
      r.action = ->(facts) { result << :fired }
    end

    @engine.add_rule(rule)
    @engine.add_fact(:car, { color: :red })
    @engine.run

    assert_equal 1, result.size
  end

  def test_negation_blocks_rule
    result = []

    rule = KBS::Rule.new('no_problem_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.conditions << KBS::Condition.new(:problem, {}, negated: true)
      r.action = ->(facts) { result << :fired }
    end

    @engine.add_rule(rule)
    @engine.add_fact(:car, { color: :red })
    @engine.add_fact(:problem, { type: :engine })
    @engine.run

    assert_empty result, "Rule should not fire when negated fact exists"
  end

  def test_pattern_matching_with_proc
    result = []

    rule = KBS::Rule.new('fast_car_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { speed: ->(s) { s > 100 } })
      r.action = ->(facts) { result << facts.first[:speed] }
    end

    @engine.add_rule(rule)
    @engine.add_fact(:car, { speed: 50 })
    @engine.add_fact(:car, { speed: 150 })
    @engine.run

    assert_equal 1, result.size
    assert_equal 150, result.first
  end

  def test_multiple_rules_fire
    results = []

    rule1 = KBS::Rule.new('rule1') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.action = ->(facts) { results << :rule1 }
    end

    rule2 = KBS::Rule.new('rule2') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.action = ->(facts) { results << :rule2 }
    end

    @engine.add_rule(rule1)
    @engine.add_rule(rule2)
    @engine.add_fact(:car, { color: :red })
    @engine.run

    assert_equal 2, results.size
    assert_includes results, :rule1
    assert_includes results, :rule2
  end

  def test_fact_removal_invalidates_tokens
    result = []

    rule = KBS::Rule.new('test_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.action = ->(facts) { result << :fired }
    end

    @engine.add_rule(rule)
    fact = @engine.add_fact(:car, { color: :red })
    @engine.run

    assert_equal 1, result.size
    result.clear

    @engine.remove_fact(fact)
    @engine.run

    assert_empty result, "Rule should not fire after fact removed"
  end

  def test_observer_pattern
    observer = Object.new
    def observer.update(action, fact)
      @called = true
      @action = action
      @fact = fact
    end

    class << observer
      attr_reader :called, :action, :fact
    end

    @engine.working_memory.add_observer(observer)
    @engine.add_fact(:car, { color: :red })

    assert observer.called
    assert_equal :add, observer.action
  end

  def test_complex_join_network
    result = []

    rule = KBS::Rule.new('complex_rule') do |r|
      r.conditions << KBS::Condition.new(:driver, { name: "John" })
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.conditions << KBS::Condition.new(:license, { valid: true })
      r.action = ->(facts) { result << facts.map(&:type) }
    end

    @engine.add_rule(rule)
    @engine.add_fact(:driver, { name: "John" })
    @engine.add_fact(:car, { color: :red })
    @engine.add_fact(:license, { valid: true })
    @engine.run

    assert_equal 1, result.size
    assert_equal [:driver, :car, :license], result.first
  end

  def test_no_matching_facts
    result = []

    rule = KBS::Rule.new('test_rule') do |r|
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.action = ->(facts) { result << :fired }
    end

    @engine.add_rule(rule)
    @engine.add_fact(:car, { color: :blue })
    @engine.run

    assert_empty result
  end

  def test_partial_matches
    result = []

    rule = KBS::Rule.new('two_condition_rule') do |r|
      r.conditions << KBS::Condition.new(:driver, { age: 25 })
      r.conditions << KBS::Condition.new(:car, { color: :red })
      r.action = ->(facts) { result << :fired }
    end

    @engine.add_rule(rule)
    @engine.add_fact(:driver, { age: 25 })
    @engine.run

    assert_empty result, "Rule should not fire with only partial match"
  end
end
