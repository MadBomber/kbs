# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# watch, matches, join_activity and network_stats, on both engines.
module IntrospectionTests
  def order_rule(name = "paid")
    KBS::Rule.new(name, conditions: [
                    KBS::Condition.new(:order, { id: :id? }),
                    KBS::Condition.new(:payment, { order_id: :id? }),
                    KBS::Condition.new(:hold, { order_id: :id? }, negated: true)
                  ])
  end

  def test_watch_returns_the_engine_and_is_off_by_default
    out = StringIO.new
    @engine.trace_output = out
    @engine.add_fact(:order, id: 1)

    assert_empty out.string
    assert_same @engine, @engine.watch(:facts)
    assert_same @engine, @engine.unwatch
    assert_same out, @engine.trace_output
  end

  def test_watching_rules_and_activations
    out = StringIO.new
    @engine.trace_output = out
    @engine.add_rule(order_rule)
    @engine.watch(:activations, :rules)
    @engine.add_fact(:order, id: 1)
    payment = @engine.add_fact(:payment, order_id: 1)
    @engine.run
    @engine.remove_fact(payment)
    @engine.add_fact(:payment, order_id: 1)
    @engine.add_fact(:hold, order_id: 1)

    lines = out.string.lines.map { |line| line[/\A(==> Activation|<== Activation|FIRE \d+)/, 1] }
    assert_equal ["==> Activation", "FIRE 1", "==> Activation", "<== Activation"], lines
  end

  def test_watching_facts
    out = StringIO.new
    @engine.trace_output = out
    @engine.watch(:facts)
    fact = @engine.add_fact(:order, id: 1)
    @engine.remove_fact(fact)

    assert_equal %w[==> <==], out.string.lines.map { |line| line[0, 3] }
  end

  def test_matches_shows_where_a_rule_stops
    @engine.add_rule(order_rule)
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:order, id: 2)
    @engine.add_fact(:payment, order_id: 3)

    report = @engine.matches("paid")

    assert_equal "paid", report[:rule]
    assert_equal [
      { keyword: "on", type: :order, alpha_matches: 2, partial_matches: 2 },
      { keyword: "on", type: :payment, alpha_matches: 1, partial_matches: 0 },
      { keyword: "without", type: :hold, alpha_matches: 0, partial_matches: 0 }
    ], report[:conditions]
    assert_equal 0, report[:matches]
    assert_equal 0, report[:activations]
  end

  def test_matches_counts_complete_matches_and_pending_activations
    @engine.add_rule(order_rule)
    2.times do |i|
      @engine.add_fact(:order, id: i)
      @engine.add_fact(:payment, order_id: i)
    end
    @engine.run(1)

    report = @engine.matches("paid")

    assert_equal [2, 2, 2], report[:conditions].map { |condition| condition[:partial_matches] }
    assert_equal 2, report[:matches]
    assert_equal 1, report[:activations]
  end

  def test_matches_for_an_unknown_rule
    assert_nil @engine.matches("nope")
    assert_nil @engine.join_activity("nope")
  end

  def test_join_activity_counts_the_work_of_each_condition
    @engine.add_rule(order_rule)
    3.times { |i| @engine.add_fact(:order, id: i) }
    @engine.add_fact(:payment, order_id: 1)

    first, second, third = @engine.join_activity("paid")

    assert_equal :order, first[:type]
    assert_equal 3, first[:right_activations]
    assert_equal 3, first[:matches]
    assert second[:indexed]
    assert_equal 3, second[:left_activations]
    assert_equal 1, second[:right_activations]
    assert_equal 1, second[:comparisons]
    assert_equal 1, second[:matches]
    assert_equal "without", third[:keyword]
  end

  def test_an_unindexed_join_compares_every_candidate
    @engine.add_rule(KBS::Rule.new("cross", conditions: [KBS::Condition.new(:a, {}), KBS::Condition.new(:b, {})]))
    3.times { |i| @engine.add_fact(:a, id: i) }
    2.times { |i| @engine.add_fact(:b, id: i) }

    second = @engine.join_activity("cross").last

    refute second[:indexed]
    assert_equal 6, second[:comparisons]
    assert_equal 6, second[:matches]
  end

  def test_reset_join_activity
    @engine.add_rule(order_rule)
    @engine.add_fact(:order, id: 1)

    @engine.reset_join_activity

    assert(@engine.join_activity("paid").all? { |step| step[:right_activations].zero? && step[:matches].zero? })
  end

  def test_rules_that_share_a_node_report_the_same_counts
    @engine.add_rule(order_rule("a"))
    @engine.add_rule(order_rule("b"))
    @engine.add_fact(:order, id: 1)

    assert_equal @engine.join_activity("a"), @engine.join_activity("b")
  end

  def test_network_stats
    @engine.add_rule(order_rule("a"))
    @engine.add_rule(order_rule("b"))
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)

    assert_equal({ rules: 2, facts: 2, alpha_memories: 3, beta_nodes: 3, conditions: 6,
                   partial_matches: 3, activations: 2 }, @engine.network_stats)
  end
end

class TestEngineIntrospection < Minitest::Test
  include IntrospectionTests

  def setup
    @engine = KBS::Engine.new
  end

  def test_trace_lines_in_full
    out = StringIO.new
    @engine.trace_output = out
    @engine.add_rule(KBS::Rule.new("hot", priority: 3, conditions: [KBS::Condition.new(:sensor, {})]))
    @engine.watch
    fact = @engine.add_fact(:sensor, id: 1)
    @engine.run
    @engine.remove_fact(fact)

    assert_equal <<~TRACE, out.string
      ==> fact :sensor, id: 1
      ==> Activation 3 hot: fact :sensor, id: 1
      FIRE 1 hot: fact :sensor, id: 1
      <== fact :sensor, id: 1
    TRACE
  end
end

class TestBlackboardEngineIntrospection < Minitest::Test
  include IntrospectionTests

  def setup
    @engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
  end

  def teardown
    @engine.close
  end
end

class TestKnowledgeBaseIntrospection < Minitest::Test
  def test_watch_and_matches_are_forwarded
    kb = KBS.knowledge_base
    out = StringIO.new
    kb.engine.trace_output = out
    kb.rule("hot") { on :sensor }

    assert_same kb, kb.watch(:facts)
    kb.assert(:sensor, id: 1)
    assert_same kb, kb.unwatch
    kb.assert(:sensor, id: 2)

    assert_equal "==> fact :sensor, id: 1\n", out.string
    assert_equal 2, kb.matches("hot")[:matches]
  end
end

class TestJoinActivity < Minitest::Test
  def test_node_counts_and_resets_its_activity
    alpha = KBS::AlphaMemory.new
    beta = KBS::BetaMemory.new
    beta.add_token(KBS::Token.new(nil, nil, nil))
    node = KBS::JoinNode.new(alpha, beta, [])
    assert_equal [0, 0, 0, 0], node.activity.to_a

    node.right_activate(KBS::Fact.new(:a))
    assert_equal [0, 1, 1, 1], node.activity.to_a

    node.reset_activity
    assert_equal [0, 0, 0, 0], node.activity.to_a
  end

  def test_agenda_listens_only_while_activations_are_watched
    engine = KBS::Engine.new
    assert_nil engine.agenda.listener

    engine.watch(:facts)
    assert_nil engine.agenda.listener

    engine.watch(:activations)
    assert_same engine.tracer, engine.agenda.listener

    engine.unwatch
    assert_nil engine.agenda.listener
  end

  def test_token_slots_are_frozen
    token = KBS::Token.new(KBS::Token.new(nil, KBS::Fact.new(:a), nil), nil, nil)

    assert_equal 2, token.slots.size
    assert_nil token.slots.last
    assert token.slots.frozen?
  end
end
