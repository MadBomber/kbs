# frozen_string_literal: true

require_relative 'test_helper'

# Engine#run fires from the agenda until it is empty.
module EngineRunTests
  def rule(name, *types, priority: 0, &action)
    conditions = types.map { |type| KBS::Condition.new(type, {}) }
    @engine.add_rule(KBS::Rule.new(name, conditions: conditions, action: action, priority: priority))
  end

  def test_run_returns_the_number_of_rules_fired
    rule("a", :go) { nil }
    rule("b", :go) { nil }
    @engine.add_fact(:go)

    assert_equal 2, @engine.run
    assert_equal 0, @engine.run
  end

  def test_fact_asserted_by_an_action_fires_an_earlier_rule_in_the_same_run
    fired = []
    engine = @engine
    rule("consume", :b) { fired << :consume }
    rule("produce", :a) do
      fired << :produce
      engine.add_fact(:b)
    end
    @engine.add_fact(:a)

    @engine.run

    assert_equal %i[produce consume], fired
  end

  def test_rules_chain_through_several_steps
    fired = []
    engine = @engine
    rule("third", :c) { fired << 3 }
    rule("second", :b) do
      fired << 2
      engine.add_fact(:c)
    end
    rule("first", :a) do
      fired << 1
      engine.add_fact(:b)
    end
    @engine.add_fact(:a)

    assert_equal 3, @engine.run
    assert_equal [1, 2, 3], fired
  end

  def test_higher_priority_activation_created_during_a_run_fires_next
    fired = []
    engine = @engine
    rule("low", :go) { fired << :low }
    rule("urgent", :alarm, priority: 10) { fired << :urgent }
    rule("trigger", :go, priority: 5) do
      fired << :trigger
      engine.add_fact(:alarm)
    end
    @engine.add_fact(:go)

    @engine.run

    assert_equal %i[trigger urgent low], fired
  end

  def test_retraction_by_an_action_removes_a_pending_activation
    fired = []
    engine = @engine
    victim = nil
    rule("low", :b) { fired << :low }
    rule("high", :a, priority: 5) do
      fired << :high
      engine.remove_fact(victim)
    end
    victim = @engine.add_fact(:b)
    @engine.add_fact(:a)

    assert_equal 1, @engine.run
    assert_equal %i[high], fired
    assert @engine.agenda.empty?
  end

  def test_an_activation_fires_once_across_runs
    fired = 0
    rule("once", :go) { fired += 1 }
    @engine.add_fact(:go)

    3.times { @engine.run }

    assert_equal 1, fired
  end

  def test_run_limit_stops_after_that_many_firings
    fired = []
    %w[a b c].each { |name| rule(name, :go) { fired << name } }
    @engine.add_fact(:go)

    assert_equal 2, @engine.run(2)
    assert_equal %w[a b], fired
    assert_equal 1, @engine.agenda.size

    assert_equal 1, @engine.run
    assert_equal %w[a b c], fired
  end

  def test_run_limit_of_zero_fires_nothing
    rule("a", :go) { flunk "must not fire" }
    @engine.add_fact(:go)

    assert_equal 0, @engine.run(0)
  end

  def test_halt_stops_the_run_after_the_firing_rule
    fired = []
    engine = @engine
    rule("a", :go) do
      fired << "a"
      engine.halt
    end
    rule("b", :go) { fired << "b" }
    @engine.add_fact(:go)

    assert_equal 1, @engine.run
    assert_equal %w[a], fired

    assert_equal 1, @engine.run
    assert_equal %w[a b], fired
  end

  def test_run_limit_bounds_a_rule_that_feeds_itself
    engine = @engine
    count = 0
    rule("loop", :tick) do
      count += 1
      engine.add_fact(:tick)
    end
    @engine.add_fact(:tick)

    assert_equal 25, @engine.run(25)
    assert_equal 25, count
  end

  def test_agenda_holds_matches_until_run
    rule("a", :go) { nil }
    @engine.add_fact(:go)
    @engine.add_fact(:go)

    assert_equal 2, @engine.agenda.size
    @engine.run
    assert @engine.agenda.empty?
  end

  def test_reset_clears_the_agenda
    rule("a", :go) { flunk "must not fire" }
    @engine.add_fact(:go)

    @engine.reset

    assert @engine.agenda.empty?
    assert_equal 0, @engine.run
  end

  def test_depth_strategy_fires_newest_match_first
    fired = []
    @engine.strategy = :depth
    @engine.add_rule(KBS::Rule.new("r", conditions: [KBS::Condition.new(:item, {})],
                                        action: ->(facts) { fired << facts.first[:n] }))
    3.times { |n| @engine.add_fact(:item, n: n) }

    @engine.run

    assert_equal [2, 1, 0], fired
    assert_equal :depth, @engine.strategy
  end

  def test_breadth_strategy_fires_oldest_match_first_across_rules
    fired = []
    @engine.strategy = :breadth
    rule("b_rule", :b) { fired << :b }
    rule("a_rule", :a) { fired << :a }
    @engine.add_fact(:a)
    @engine.add_fact(:b)

    @engine.run

    assert_equal %i[a b], fired
  end
end

class TestEngineRun < Minitest::Test
  include EngineRunTests

  def setup
    @engine = KBS::Engine.new
  end

  def test_strategy_keyword
    assert_equal :depth, KBS::Engine.new(strategy: :depth).strategy
    assert_raises(ArgumentError) { KBS::Engine.new(strategy: :nope) }
  end
end

class TestBlackboardEngineRun < Minitest::Test
  include EngineRunTests

  def setup
    @engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
  end

  def teardown
    @engine.close
  end

  def test_strategy_keyword
    engine = KBS::Blackboard::Engine.new(strategy: :breadth)

    assert_equal :breadth, engine.strategy
  ensure
    engine&.close
  end

  def test_each_firing_is_logged_once
    rule("chain_a", :a) { @engine.add_fact(:b) }
    rule("chain_b", :b) { nil }
    @engine.add_fact(:a)

    @engine.run
    @engine.run

    names = @engine.blackboard.get_rule_firings.map { |firing| firing[:rule_name] }
    assert_equal %w[chain_a chain_b], names.sort
  end
end

class TestKnowledgeBaseRun < Minitest::Test
  def test_run_passes_the_limit_and_returns_the_count
    kb = KBS.knowledge_base do
      rule("a") { on :go; perform { nil } }
      rule("b") { on :go; perform { nil } }
    end
    kb.assert(:go)

    assert_equal 1, kb.run(1)
    assert_equal 1, kb.run
  end

  def test_halt
    kb = KBS.knowledge_base
    fired = []
    kb.rule("a") { on :go; perform { fired << "a"; kb.halt } }
    kb.rule("b") { on :go; perform { fired << "b" } }
    kb.assert(:go)

    kb.run

    assert_equal %w[a], fired
  end
end
