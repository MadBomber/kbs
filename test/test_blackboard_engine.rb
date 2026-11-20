# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs/blackboard'
require 'tmpdir'
require 'fileutils'

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

  def test_dsl_with_blackboard_engine
    readings = []

    kb = KBS.knowledge_base(engine: @engine) do
      rule 'temperature_monitor' do
        on :sensor, value: greater_than(25)
        perform { |facts| readings << facts.first[:value] }
      end

      fact :sensor, value: 22
      fact :sensor, value: 28
      run
    end

    assert_same @engine, kb.engine
    assert_equal [28], readings
    assert_equal([22, 28], @engine.blackboard.get_facts(:sensor).map { |fact| fact[:value] })
    assert_equal 'temperature_monitor', @engine.blackboard.get_rule_firings.first[:rule_name]
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
      r.action = ->(facts) {}
    end

    @engine.add_rule(rule)
    @engine.add_fact(:sensor, { temp: 22 })
    @engine.run

    firings = @engine.blackboard.get_rule_firings
    assert_equal 1, firings.size
    assert_equal 'test_rule', firings.first[:rule_name]
  end

  def test_rule_firing_logs_bindings_after_negated_condition
    conditions = [
      KBS::Condition.new(:a, { v: :x? }),
      KBS::Condition.new(:blocker, {}, negated: true),
      KBS::Condition.new(:b, { v: :y? }),
      KBS::Condition.new(:c, { v: :z? })
    ]
    @engine.add_rule(KBS::Rule.new('negation_in_middle', conditions: conditions))
    { a: 'A', b: 'B', c: 'C' }.each { |type, value| @engine.add_fact(type, { v: value }) }
    @engine.run

    assert_equal([{ x?: 'A', y?: 'B', z?: 'C' }], @engine.blackboard.get_rule_firings.map { |f| f[:bindings] })
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

  # Issue #64: the docs call engine.facts and engine.close.
  def test_facts_and_close
    @engine.add_fact(:sensor, { temp: 22 })
    assert_equal([22], @engine.facts.map { |f| f[:temp] })

    @engine.close
    assert @engine.blackboard.store.db.closed?
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
      r.action = ->(_facts) { result << :fired }
    end

    @engine.add_rule(rule)
    fact = @engine.add_fact(:sensor, { temp: 20 })
    @engine.run
    assert_empty result

    # Update triggers re-evaluation
    fact[:temp] = 30
    # NOTE: In current implementation, updates don't auto-trigger RETE
    # This would require re-adding the updated fact or implementing update propagation
  end

  def test_working_memory_is_blackboard
    assert_equal @engine.blackboard, @engine.instance_variable_get(:@working_memory)
  end

  def test_observer_integration
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

  # Issue #42: remove_fact must retract the fact from the Rete network,
  # so a rule negated on it fires afterwards.
  def test_remove_fact_retracts_negated_fact_from_network
    fired = 0
    @engine.add_rule(KBS::Rule.new('a_without_b',
                                   conditions: [KBS::Condition.new(:a, {}), KBS::Condition.new(:b, {}, negated: true)],
                                   action: ->(_facts) { fired += 1 }))
    @engine.add_fact(:a, {})
    b = @engine.add_fact(:b, {})
    @engine.remove_fact(b)
    @engine.run

    assert_equal 1, fired
    assert_empty @engine.alpha_memories[{ type: :b }].items
  end

  def test_remove_fact_retracts_positive_match
    fired = 0
    @engine.add_rule(KBS::Rule.new('a_and_b',
                                   conditions: [KBS::Condition.new(:a, {}), KBS::Condition.new(:b, {})],
                                   action: ->(_facts) { fired += 1 }))
    @engine.add_fact(:a, {})
    b = @engine.add_fact(:b, {})
    @engine.remove_fact(b)
    @engine.run

    assert_equal 0, fired
    assert_empty @engine.production_nodes['a_and_b'].tokens
  end

  # Contract: blackboard/symbol-rule-name-is-audited
  # Bug: a rule with a Symbol name raised "can't prepare Symbol" when it fired on the SQLite store
  def test_rule_with_symbol_name_fires_and_is_audited
    fired = 0
    @engine.add_rule(KBS::Rule.new(:symbol_rule,
                                   conditions: [KBS::Condition.new(:sensor, {})],
                                   action: ->(_facts) { fired += 1 }))
    @engine.add_fact(:sensor, { temp: 22 })
    @engine.run

    assert_equal 1, fired
    assert_equal(['symbol_rule'], @engine.blackboard.get_rule_firings(:symbol_rule).map { |f| f[:rule_name] })
  end

  # Contract: blackboard/remove-fact-returns-fact
  # Bug: Blackboard::Engine#remove_fact returned the observer array instead of the fact
  def test_remove_fact_returns_the_fact
    fact = @engine.add_fact(:sensor, { temp: 22 })

    assert_equal fact, @engine.remove_fact(fact)
  end

  # Contract: blackboard/transaction-rollback-withdraws-added-facts
  # Bug: facts added in a rolled-back transaction stayed in the RETE network and their rules still fired
  def test_rolled_back_fact_is_withdrawn_from_the_network
    fired = 0
    @engine.add_rule(KBS::Rule.new('order_rule',
                                   conditions: [KBS::Condition.new(:order, {})],
                                   action: ->(_facts) { fired += 1 }))

    assert_raises(RuntimeError) do
      @engine.blackboard.transaction do
        @engine.add_fact(:order, { id: 1 })
        raise 'validation failed'
      end
    end
    @engine.run

    assert_equal 0, fired
    assert_empty @engine.facts
    assert_empty @engine.alpha_memories[{ type: :order }].items
  end

  def test_rolled_back_nested_transaction_withdraws_facts_from_both_levels
    @engine.add_rule(KBS::Rule.new('order_rule', conditions: [KBS::Condition.new(:order, {})], action: ->(_f) {}))

    assert_raises(RuntimeError) do
      @engine.blackboard.transaction do
        @engine.add_fact(:order, { id: 1 })
        @engine.blackboard.transaction { @engine.add_fact(:order, { id: 2 }) }
        raise 'validation failed'
      end
    end

    assert_equal 0, @engine.run
    assert_empty @engine.alpha_memories[{ type: :order }].items
  end

  def test_committed_transaction_keeps_its_facts
    @engine.blackboard.transaction { @engine.add_fact(:order, { id: 1 }) }

    assert_equal 1, @engine.facts.size
  end

  def test_fact_removed_inside_a_rolled_back_transaction_is_withdrawn_once
    removals = []
    observer = Object.new
    observer.define_singleton_method(:update) { |action, fact| removals << fact.uuid if action == :remove }
    @engine.blackboard.add_observer(observer)

    assert_raises(RuntimeError) do
      @engine.blackboard.transaction do
        fact = @engine.add_fact(:order, { id: 1 })
        @engine.remove_fact(fact)
        raise 'validation failed'
      end
    end

    assert_equal 1, removals.size
  end
end

class TestBlackboardEngineReopen < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, 'bb.db')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Contract: blackboard/stored-facts-registered-on-reopen
  # Bug: with fact_duplication: false, a reopened blackboard accepted a duplicate of a stored fact
  def test_reopened_blackboard_rejects_duplicate_of_stored_fact
    first = KBS::Blackboard::Engine.new(db_path: @path, fact_duplication: false)
    stored = first.add_fact(:sensor, { temp: 22 })
    first.close

    reopened = KBS::Blackboard::Engine.new(db_path: @path, fact_duplication: false)

    assert_equal stored, reopened.add_fact(:sensor, { temp: 22 })
    assert_equal 1, reopened.blackboard.get_facts(:sensor).size
  ensure
    reopened&.close
  end
end

class TestBlackboardFactEquality < Minitest::Test
  def test_facts_with_the_same_uuid_are_equal
    a = KBS::Blackboard::Fact.new('u-1', :a, { x: 1 })
    b = KBS::Blackboard::Fact.new('u-1', :a, { x: 2 })

    assert_equal a, b
    assert a.eql?(b)
    assert_equal a.hash, b.hash
    assert_equal 1, [a, b].uniq.size
  end

  def test_facts_with_different_uuids_are_not_equal
    a = KBS::Blackboard::Fact.new('u-1', :a, { x: 1 })
    b = KBS::Blackboard::Fact.new('u-2', :a, { x: 1 })

    refute_equal a, b
    refute a.eql?(b)
  end

  def test_fact_is_not_equal_to_other_objects
    fact = KBS::Blackboard::Fact.new('u-1', :a, {})

    refute_equal fact, 'u-1'
    refute_equal fact, KBS::Fact.new(:a, {})
  end
end

require_relative 'late_rule_addition_tests'

class TestBlackboardEngineLateRuleAddition < Minitest::Test
  include LateRuleAdditionTests

  def setup
    @engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
  end

  def teardown
    @engine.blackboard.close
  end
end
