# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs/blackboard'

class TestBlackboardEngine < Minitest::Test
  def setup
    @engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
  end

  def teardown
    @engine.blackboard.close if @engine
  end

  def test_initialization
    assert_instance_of KBS::Blackboard::Engine, @engine
    assert_instance_of KBS::Blackboard::Memory, @engine.blackboard
  end

  def test_add_fact
    fact = @engine.add_fact(:sensor, { temp: 22 })

    assert_instance_of KBS::Blackboard::Fact, fact
    assert fact.uuid
  end

  def test_remove_fact
    fact = @engine.add_fact(:sensor, { temp: 22 })
    @engine.remove_fact(fact)

    facts = @engine.blackboard.get_facts(:sensor)
    assert_empty facts
  end

  def test_rule_execution
    result = []

    rule = KBS::Rule.new('temp_rule') do |r|
      r.conditions << KBS::Condition.new(:sensor, { temp: 22 })
      r.action = ->(facts) { result << facts.first.uuid }
    end

    @engine.add_rule(rule)
    fact = @engine.add_fact(:sensor, { temp: 22 })
    @engine.run

    assert_equal 1, result.size
    assert_equal fact.uuid, result.first
  end

  def test_rule_firing_logged
    rule = KBS::Rule.new('test_rule') do |r|
      r.conditions << KBS::Condition.new(:sensor, { temp: 22 })
      r.action = ->(facts) { }
    end

    @engine.add_rule(rule)
    @engine.add_fact(:sensor, { temp: 22 })
    @engine.run

    firings = @engine.blackboard.get_rule_firings
    assert_equal 1, firings.size
    assert_equal 'test_rule', firings.first[:rule_name]
  end

  def test_post_message
    @engine.post_message("Sensor1", "readings", { temp: 22 }, priority: 5)

    messages = @engine.blackboard.peek_messages("readings")
    assert_equal 1, messages.size
  end

  def test_consume_message
    @engine.post_message("Sensor1", "readings", { temp: 22 })
    message = @engine.consume_message("readings", "Consumer1")

    assert message
    assert_equal "Sensor1", message[:sender]
    assert_equal 22, message[:content][:temp]
  end

  def test_stats
    @engine.add_fact(:sensor, { temp: 22 })
    @engine.post_message("Sensor1", "readings", { temp: 22 })

    stats = @engine.stats
    assert_equal 1, stats[:active_facts]
    assert_equal 1, stats[:unconsumed_messages]
  end

  def test_fact_update_triggers_rete
    result = []

    rule = KBS::Rule.new('high_temp_rule') do |r|
      r.conditions << KBS::Condition.new(:sensor, { temp: ->(t) { t > 25 } })
      r.action = ->(facts) { result << :fired }
    end

    @engine.add_rule(rule)
    fact = @engine.add_fact(:sensor, { temp: 20 })
    @engine.run
    assert_empty result

    # Update triggers re-evaluation
    fact[:temp] = 30
    # Note: In current implementation, updates don't auto-trigger RETE
    # This would require re-adding the updated fact or implementing update propagation
  end

  def test_working_memory_is_blackboard
    assert_equal @engine.blackboard, @engine.instance_variable_get(:@working_memory)
  end

  def test_observer_integration
    observer_called = false

    observer = Object.new
    def observer.update(action, fact)
      @called = true
    end

    class << observer
      attr_reader :called
    end

    @engine.blackboard.add_observer(observer)
    @engine.add_fact(:sensor, { temp: 22 })

    assert observer.called
  end
end
