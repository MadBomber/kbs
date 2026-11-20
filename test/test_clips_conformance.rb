# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# Cases taken from the CLIPS 6.4.2 feature tests (exists.bat,
# firstjoin.bat, conres.clp and the logical tests). Each runs the same
# sequence of assertions and retractions as the CLIPS batch file with
# facts and activations watched, and compares the trace with what CLIPS
# prints for it, written in this gem's trace format.
#
# CLIPS cases that need features this gem does not have are not here:
# (not (and ...)), (exists) over several patterns, (test) conditions
# with no pattern, and the simplicity, complexity, lex and mea
# strategies.
class TestClipsConformance < Minitest::Test
  def setup
    @engine = KBS::Engine.new
    @out = StringIO.new
    @engine.trace_output = @out
    @fired = []
  end

  def condition(type, pattern = {}, **)
    KBS::Condition.new(type, pattern, **)
  end

  def rule(name, conditions, priority: 0, &action)
    fired = @fired
    action ||= ->(facts) { fired << [name, *facts.map { |fact| fact[:v] }] }
    @engine.add_rule(KBS::Rule.new(name, conditions: conditions, priority: priority, action: action))
  end

  def assert_trace(expected)
    assert_equal expected, @out.string
  end

  # exists.bat, first rule: (defrule test (exists (a ?)) =>)
  def test_exists_activates_once_however_many_facts_match
    rule("test", [condition(:a, {}, exists: true)])
    @engine.watch(:facts, :activations)

    a1 = @engine.add_fact(:a, v: 1)
    a2 = @engine.add_fact(:a, v: 2)
    a3 = @engine.add_fact(:a, v: 3)
    @engine.remove_fact(a1)
    @engine.remove_fact(a3)
    @engine.remove_fact(a2)
    @engine.add_fact(:a, v: 4)

    assert_trace <<~TRACE
      ==> fact :a, v: 1
      ==> Activation 0 test: *
      ==> fact :a, v: 2
      ==> fact :a, v: 3
      <== fact :a, v: 1
      <== fact :a, v: 3
      <== fact :a, v: 2
      <== Activation 0 test: *
      ==> fact :a, v: 4
      ==> Activation 0 test: *
    TRACE
  end

  # exists.bat, second rule: (defrule test (a ?x) (exists (b ?x ?)) =>)
  def test_exists_joined_to_an_earlier_pattern
    rule("test", [condition(:a, { x: :x? }), condition(:b, { x: :x? }, exists: true)])
    @engine.watch(:facts, :activations)

    f1 = @engine.add_fact(:b, x: 1, y: 1)
    f2 = @engine.add_fact(:b, x: 1, y: 2)
    f3 = @engine.add_fact(:a, x: 1)
    @engine.add_fact(:a, x: 2)
    @engine.remove_fact(f1)
    @engine.remove_fact(f2)
    f5 = @engine.add_fact(:b, x: 2, y: 2)
    @engine.add_fact(:b, x: 1, y: 2)
    f7 = @engine.add_fact(:b, x: 2, y: 3)
    @engine.add_fact(:b, x: 1, y: 3)
    @engine.remove_fact(f7)
    @engine.remove_fact(f5)
    @engine.remove_fact(f3)

    assert_trace <<~TRACE
      ==> fact :b, x: 1, y: 1
      ==> fact :b, x: 1, y: 2
      ==> fact :a, x: 1
      ==> Activation 0 test: fact :a, x: 1; *
      ==> fact :a, x: 2
      <== fact :b, x: 1, y: 1
      <== fact :b, x: 1, y: 2
      <== Activation 0 test: fact :a, x: 1; *
      ==> fact :b, x: 2, y: 2
      ==> Activation 0 test: fact :a, x: 2; *
      ==> fact :b, x: 1, y: 2
      ==> Activation 0 test: fact :a, x: 1; *
      ==> fact :b, x: 2, y: 3
      ==> fact :b, x: 1, y: 3
      <== fact :b, x: 2, y: 3
      <== fact :b, x: 2, y: 2
      <== Activation 0 test: fact :a, x: 2; *
      <== fact :a, x: 1
      <== Activation 0 test: fact :a, x: 1; *
    TRACE
  end

  # exists.bat, "6.3 Issue": (defrule detect (b ?b) (exists (a)) (test (eq ?b 2)) => ...)
  # The rule fires only for (b 2), whichever fact comes first.
  def test_exists_with_a_test_on_an_earlier_variable
    [[[:a, {}], [:b, { v: 1 }], 0], [[:b, { v: 1 }], [:a, {}], 0],
     [[:a, {}], [:b, { v: 2 }], 1], [[:b, { v: 2 }], [:a, {}], 1]].each do |first, second, expected|
      engine = KBS::Engine.new
      engine.add_rule(KBS::Rule.new("detect", conditions: [condition(:b, { v: ->(v) { v == 2 } }),
                                                           condition(:a, {}, exists: true)]))
      engine.add_fact(*first)
      engine.add_fact(*second)

      assert_equal expected, engine.run, "#{first.inspect} then #{second.inspect}"
    end
  end

  # firstjoin.bat: (defrule foo (not (a)) =>)
  def test_rule_whose_first_condition_is_negated
    @engine.watch(:activations)
    rule("foo", [condition(:a, {}, negated: true)])

    a = @engine.add_fact(:a, {})
    @engine.remove_fact(a)
    @engine.add_fact(:a, {})

    assert_trace <<~TRACE
      ==> Activation 0 foo: *
      <== Activation 0 foo: *
      ==> Activation 0 foo: *
      <== Activation 0 foo: *
    TRACE
  end

  # firstjoin.bat: (defrule foo (logical (not (a))) => (assert (b)))
  def test_logical_support_from_a_negated_first_condition
    engine = @engine
    rule("foo", [condition(:a, {}, negated: true, logical: true)]) { |_facts| engine.add_fact(:b, {}) }
    @engine.watch(:facts)

    @engine.run
    @engine.add_fact(:a, {})

    assert_trace <<~TRACE
      ==> fact :b
      ==> fact :a
      <== fact :b
    TRACE
  end

  # Basic programming guide, logical CE: a derived fact follows its
  # support, and facts derived from it follow in turn.
  def test_logical_chain_unwinds_in_order
    engine = @engine
    rule("r1", [condition(:a, {}, logical: true)]) { |_facts| engine.add_fact(:b, {}) }
    rule("r2", [condition(:b, {}, logical: true)]) { |_facts| engine.add_fact(:c, {}) }
    a = @engine.add_fact(:a, {})
    @engine.run
    @engine.watch(:facts)

    @engine.remove_fact(a)

    assert_trace <<~TRACE
      <== fact :a
      <== fact :b
      <== fact :c
    TRACE
  end

  # A join over three patterns on one variable: nothing is activated
  # until every pattern has a fact, and losing one withdraws it.
  def test_three_way_join
    rule("join", [condition(:a, { v: :x? }), condition(:b, { v: :x? }), condition(:c, { v: :x? })])
    @engine.watch(:activations)

    @engine.add_fact(:a, v: 1)
    @engine.add_fact(:c, v: 1)
    @engine.add_fact(:b, v: 2)
    b = @engine.add_fact(:b, v: 1)
    @engine.remove_fact(b)

    assert_trace <<~TRACE
      ==> Activation 0 join: fact :a, v: 1; fact :b, v: 1; fact :c, v: 1
      <== Activation 0 join: fact :a, v: 1; fact :b, v: 1; fact :c, v: 1
    TRACE
  end

  # conres.clp, salience: the higher salience fires first under every
  # strategy.
  def test_salience_orders_the_agenda_under_every_strategy
    %i[definition depth breadth].each do |strategy|
      @fired.clear
      @engine = KBS::Engine.new(strategy: strategy)
      rule("low", [condition(:go)], priority: -10)
      rule("high", [condition(:go)], priority: 10)
      rule("middle", [condition(:go)])
      @engine.add_fact(:go, v: 1)

      @engine.run

      assert_equal %w[high middle low], @fired.map(&:first), strategy
    end
  end

  # conres.clp, depth: among equal salience the newest activation fires
  # first.
  def test_depth_strategy_fires_the_newest_activation_first
    @engine.strategy = :depth
    rule("r", [condition(:n)])
    3.times { |i| @engine.add_fact(:n, v: i) }

    @engine.run

    assert_equal [["r", 2], ["r", 1], ["r", 0]], @fired
  end

  # conres.clp, breadth: among equal salience the oldest activation
  # fires first.
  def test_breadth_strategy_fires_the_oldest_activation_first
    @engine.strategy = :breadth
    rule("r", [condition(:n)])
    3.times { |i| @engine.add_fact(:n, v: i) }

    @engine.run

    assert_equal [["r", 0], ["r", 1], ["r", 2]], @fired
  end

  # Refraction: a rule fires once for a match, and again only for a new
  # match.
  def test_refraction
    rule("r", [condition(:n)])
    fact = @engine.add_fact(:n, v: 1)

    assert_equal 1, @engine.run
    assert_equal 0, @engine.run

    @engine.modify(fact, v: 2)

    assert_equal 1, @engine.run
    assert_equal [["r", 1], ["r", 2]], @fired
  end

  # A fact asserted by a firing rule is matched before the next rule
  # fires, so a higher salience rule it activates goes first.
  def test_agenda_is_reordered_while_running
    engine = @engine
    rule("start", [condition(:go)]) do |_facts|
      @fired << ["start"]
      engine.add_fact(:urgent, v: 1)
    end
    rule("later", [condition(:go)], priority: -1)
    rule("urgent", [condition(:urgent)], priority: 5)
    @engine.add_fact(:go, v: 0)

    @engine.run

    assert_equal %w[start urgent later], @fired.map(&:first)
  end

  # An activation whose fact is retracted by an earlier firing never
  # fires.
  def test_retracting_a_fact_cancels_its_pending_activation
    engine = @engine
    rule("first", [condition(:n)], priority: 1) do |facts|
      @fired << ["first"]
      engine.remove_fact(facts.first)
    end
    rule("second", [condition(:n)])
    @engine.add_fact(:n, v: 1)

    assert_equal 1, @engine.run
    assert_equal [["first"]], @fired
  end
end
