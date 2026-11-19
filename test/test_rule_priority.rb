# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs/blackboard'

# Regression tests for issue #35: higher-priority rules fire first.
module RulePriorityTests
  def ordered_rule(name, priority, fired)
    KBS::Rule.new(name, conditions: [KBS::Condition.new(:go, {})],
                        action: ->(_facts) { fired << name }, priority: priority)
  end

  def test_higher_priority_rule_fires_first
    fired = []
    @engine.add_rule(ordered_rule('low', 1, fired))
    @engine.add_rule(ordered_rule('high', 100, fired))
    @engine.add_fact(:go, {})
    @engine.run

    assert_equal %w[high low], fired
  end

  def test_equal_priorities_keep_definition_order
    fired = []
    %w[first second third].each { |name| @engine.add_rule(ordered_rule(name, 0, fired)) }
    @engine.add_rule(ordered_rule('urgent', 5, fired))
    @engine.add_fact(:go, {})
    @engine.run

    assert_equal %w[urgent first second third], fired
  end

  def test_prioritized_production_nodes_sorts_by_descending_priority
    fired = []
    @engine.add_rule(ordered_rule('a', 0, fired))
    @engine.add_rule(ordered_rule('b', -1, fired))
    @engine.add_rule(ordered_rule('c', 10, fired))
    @engine.add_rule(ordered_rule('d', 0, fired))

    assert_equal %w[c a d b], @engine.prioritized_production_nodes.map { |node| node.rule.name }
  end
end

class TestEngineRulePriority < Minitest::Test
  include RulePriorityTests

  def setup
    @engine = KBS::Engine.new
  end
end

class TestBlackboardEngineRulePriority < Minitest::Test
  include RulePriorityTests

  def setup
    @engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
  end

  def teardown
    @engine.blackboard.close
  end
end
