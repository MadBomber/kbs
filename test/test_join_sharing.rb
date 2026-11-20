# frozen_string_literal: true

require_relative 'test_helper'

# Rules that start with the same conditions share the nodes for them.
module JoinSharingTests
  def order
    KBS::Condition.new(:order, { id: :id? })
  end

  def payment
    KBS::Condition.new(:payment, { order_id: :id? })
  end

  def add_rule(name, conditions, priority: 0)
    fired = (@fired ||= [])
    @engine.add_rule(KBS::Rule.new(name, conditions: conditions, priority: priority,
                                         action: ->(_facts) { fired << name }))
  end

  def test_rules_with_the_same_conditions_share_every_node
    add_rule("a", [order, payment])
    add_rule("b", [order, payment])

    assert_equal 2, @engine.beta_nodes.size
  end

  def test_rules_share_only_their_common_prefix
    add_rule("a", [order, payment, KBS::Condition.new(:shipment, { order_id: :id? })])
    add_rule("b", [order, payment, KBS::Condition.new(:refund, { order_id: :id? })])

    assert_equal 4, @engine.beta_nodes.size
  end

  def test_no_sharing_when_the_first_condition_differs
    add_rule("a", [order, payment])
    add_rule("b", [KBS::Condition.new(:order, { id: :id?, rush: true }), payment])

    assert_equal 4, @engine.beta_nodes.size
  end

  # A pattern includes its variable names, so these are two alpha
  # memories and nothing below them is shared.
  def test_patterns_that_differ_only_in_variable_names_are_not_shared
    add_rule("a", [order, payment])
    add_rule("b", [KBS::Condition.new(:order, { id: :other? }), payment])

    assert_equal 4, @engine.beta_nodes.size
  end

  def test_no_sharing_between_a_positive_and_a_negated_condition
    add_rule("a", [order, payment])
    add_rule("b", [order, KBS::Condition.new(:payment, { order_id: :id? }, negated: true)])

    assert_equal 3, @engine.beta_nodes.size
    assert_equal [KBS::JoinNode, KBS::JoinNode, KBS::NegationNode], @engine.beta_nodes.map(&:class)
  end

  def test_conditions_in_another_order_are_not_shared
    add_rule("a", [order, payment])
    add_rule("b", [KBS::Condition.new(:payment, { order_id: :id? }), KBS::Condition.new(:order, { id: :id? })])

    assert_equal 4, @engine.beta_nodes.size
  end

  def test_rules_sharing_every_node_each_fire_once
    add_rule("a", [order, payment])
    add_rule("b", [order, payment])
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)

    assert_equal 2, @engine.run
    assert_equal %w[a b], @fired
    assert_equal 0, @engine.run
  end

  def test_shared_rules_respect_priority
    add_rule("low", [order, payment], priority: 1)
    add_rule("high", [order, payment], priority: 9)
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)

    @engine.run

    assert_equal %w[high low], @fired
  end

  def test_rules_sharing_a_prefix_fire_for_their_own_tail
    add_rule("shipped", [order, payment, KBS::Condition.new(:shipment, { order_id: :id? })])
    add_rule("refunded", [order, payment, KBS::Condition.new(:refund, { order_id: :id? })])
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)
    @engine.add_fact(:refund, order_id: 1)

    @engine.run

    assert_equal %w[refunded], @fired
  end

  def test_shorter_rule_shares_the_prefix_of_a_longer_one
    add_rule("long", [order, payment, KBS::Condition.new(:shipment, { order_id: :id? })])
    add_rule("short", [order, payment])
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)

    @engine.run

    assert_equal 3, @engine.beta_nodes.size
    assert_equal %w[short], @fired
  end

  def test_late_rule_sharing_a_prefix_sees_the_existing_matches
    add_rule("a", [order, payment])
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)
    @engine.run

    add_rule("b", [order, payment])
    add_rule("c", [order, payment, KBS::Condition.new(:shipment, { order_id: :id? })])
    @engine.add_fact(:shipment, order_id: 1)

    assert_equal 2, @engine.run
    assert_equal %w[a b c], @fired
  end

  def test_retraction_reaches_every_rule_on_a_shared_node
    add_rule("a", [order, payment])
    add_rule("b", [order, payment])
    @engine.add_fact(:order, id: 1)
    fact = @engine.add_fact(:payment, order_id: 1)

    @engine.remove_fact(fact)

    assert @engine.agenda.empty?
    assert_equal 0, @engine.run
  end

  def test_shared_negation_node
    negated = -> { KBS::Condition.new(:hold, {}, negated: true) }
    add_rule("a", [order, negated.call])
    add_rule("b", [order, negated.call])
    @engine.add_fact(:order, id: 1)
    assert_equal 2, @engine.beta_nodes.size
    assert_equal 2, @engine.agenda.size

    @engine.add_fact(:hold, {})

    assert @engine.agenda.empty?
  end

  def test_logical_rule_sharing_a_prefix_with_a_plain_rule
    engine = @engine
    @engine.add_rule(KBS::Rule.new("plain", conditions: [KBS::Condition.new(:sensor, {})]))
    @engine.add_rule(KBS::Rule.new("derive",
                                   conditions: [KBS::Condition.new(:sensor, {}, logical: true)],
                                   action: ->(_facts) { engine.add_fact(:overheating, {}) }))
    sensor = @engine.add_fact(:sensor, {})
    @engine.run
    assert_equal 1, @engine.beta_nodes.size

    @engine.remove_fact(sensor)

    assert_empty @engine.facts
  end
end

class TestEngineJoinSharing < Minitest::Test
  include JoinSharingTests

  def setup
    @engine = KBS::Engine.new
  end

  def test_reset_clears_shared_memories_once
    add_rule("a", [order, payment])
    add_rule("b", [order, payment])
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)

    @engine.reset
    @engine.add_fact(:order, id: 2)
    @engine.add_fact(:payment, order_id: 2)

    assert_equal 2, @engine.run
  end

  def test_beta_nodes_is_a_copy
    add_rule("a", [order])

    @engine.beta_nodes.clear

    assert_equal 1, @engine.beta_nodes.size
  end
end

class TestBlackboardEngineJoinSharing < Minitest::Test
  include JoinSharingTests

  def setup
    @engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
  end

  def teardown
    @engine.close
  end

  def test_each_shared_rule_is_logged
    add_rule("a", [order, payment])
    add_rule("b", [order, payment])
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)

    @engine.run

    names = @engine.blackboard.get_rule_firings.map { |firing| firing[:rule_name] }
    assert_equal %w[a b], names.sort
  end
end

class TestProductionNodeFiredRecord < Minitest::Test
  def test_two_rules_fire_for_one_shared_token
    fired = []
    first = KBS::ProductionNode.new(KBS::Rule.new("a", action: ->(_facts) { fired << "a" }))
    second = KBS::ProductionNode.new(KBS::Rule.new("b", action: ->(_facts) { fired << "b" }))
    token = KBS::Token.new(nil, KBS::Fact.new(:x), nil)
    [first, second].each { |node| node.activate(token) }

    2.times { [first, second].each { |node| node.fire_rule(token) } }

    assert_equal %w[a b], fired
    assert first.fired?(token)
    assert second.fired?(token)
  end

  def test_deactivate_and_reset_forget_the_fired_record
    node = KBS::ProductionNode.new(KBS::Rule.new("a"))
    token = KBS::Token.new(nil, KBS::Fact.new(:x), nil)
    other = KBS::Token.new(nil, KBS::Fact.new(:x), nil)
    [token, other].each do |each_token|
      node.activate(each_token)
      node.fire_rule(each_token)
    end

    node.deactivate(token)
    refute node.fired?(token)

    node.reset
    refute node.fired?(other)
  end
end
