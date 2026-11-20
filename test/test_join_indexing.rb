# frozen_string_literal: true

require_relative 'test_helper'

class TestJoinIndexing < Minitest::Test
  EQ = { token_field_index: 0, token_field: :id, fact_field: :order_id, operation: :eq }.freeze
  NE = { token_field_index: 0, token_field: :region, fact_field: :region, operation: :ne }.freeze

  def setup
    @alpha = KBS::AlphaMemory.new(type: :payment)
    @beta = KBS::BetaMemory.new
  end

  def order_token(attributes)
    KBS::Token.new(nil, KBS::Fact.new(:order, attributes), nil)
  end

  def test_indexable_tests
    assert KBS::JoinIndexing.indexable?(EQ)
    refute KBS::JoinIndexing.indexable?(NE)
    refute KBS::JoinIndexing.indexable?(EQ.merge(expected_value: 1))
    refute KBS::JoinIndexing.indexable?({ fact_field: :a, other_fact_field: :b, operation: :eq })
  end

  def test_node_without_equality_tests_is_not_indexed
    node = KBS::JoinNode.new(@alpha, @beta, [NE])

    refute node.indexed?
    assert_equal [NE], node.residual_tests
  end

  def test_node_with_an_equality_test_is_indexed
    node = KBS::JoinNode.new(@alpha, @beta, [EQ, NE])

    assert node.indexed?
    assert_equal [NE], node.residual_tests
  end

  def test_node_without_both_memories_is_not_indexed
    refute KBS::JoinNode.new(@alpha, nil, [EQ]).indexed?
    refute KBS::JoinNode.new(nil, @beta, [EQ]).indexed?
  end

  def test_candidate_facts_come_from_the_matching_bucket
    node = KBS::JoinNode.new(@alpha, @beta, [EQ])
    match = KBS::Fact.new(:payment, order_id: 1)
    other = KBS::Fact.new(:payment, order_id: 2)
    [match, other].each { |fact| @alpha.add_item(fact) }

    assert_equal [match], node.candidate_facts(order_token(id: 1)).to_a
    assert_empty node.candidate_facts(order_token(id: 3))
  end

  def test_candidate_tokens_come_from_the_matching_bucket
    node = KBS::JoinNode.new(@alpha, @beta, [EQ])
    match = order_token(id: 1)
    other = order_token(id: 2)
    [match, other].each { |token| @beta.add_token(token) }

    assert_equal [match], node.candidate_tokens(KBS::Fact.new(:payment, order_id: 1)).to_a
  end

  def test_unindexed_node_scans_its_memories
    node = KBS::JoinNode.new(@alpha, @beta, [])
    fact = KBS::Fact.new(:payment, order_id: 1)
    token = order_token(id: 9)
    @alpha.add_item(fact)
    @beta.add_token(token)

    assert_equal [fact], node.candidate_facts(token).to_a
    assert_equal [token], node.candidate_tokens(fact).to_a
  end

  def test_matching_facts_apply_the_residual_tests
    node = KBS::JoinNode.new(@alpha, @beta, [EQ, NE])
    same_region = KBS::Fact.new(:payment, order_id: 1, region: "eu")
    other_region = KBS::Fact.new(:payment, order_id: 1, region: "us")
    [same_region, other_region].each { |fact| @alpha.add_item(fact) }

    assert_equal [other_region], node.matching_facts(order_token(id: 1, region: "eu"))
  end

  def test_matching_tokens_apply_the_residual_tests
    node = KBS::JoinNode.new(@alpha, @beta, [EQ, NE])
    eu = order_token(id: 1, region: "eu")
    us = order_token(id: 1, region: "us")
    [eu, us].each { |token| @beta.add_token(token) }

    assert_equal [us], node.matching_tokens(KBS::Fact.new(:payment, order_id: 1, region: "eu"))
  end

  def test_index_includes_items_already_in_the_memories
    fact = KBS::Fact.new(:payment, order_id: 1)
    token = order_token(id: 1)
    @alpha.add_item(fact)
    @beta.add_token(token)

    node = KBS::JoinNode.new(@alpha, @beta, [EQ])

    assert_equal [fact], node.candidate_facts(token).to_a
    assert_equal [token], node.candidate_tokens(fact).to_a
  end

  def test_setting_tests_rebuilds_the_index
    node = KBS::JoinNode.new(@alpha, @beta, [])
    @alpha.add_item(KBS::Fact.new(:payment, order_id: 2))

    node.tests = [EQ]

    assert node.indexed?
    assert_empty node.candidate_facts(order_token(id: 1))
  end

  def test_removed_items_leave_the_index
    node = KBS::JoinNode.new(@alpha, @beta, [EQ])
    fact = KBS::Fact.new(:payment, order_id: 1)
    token = order_token(id: 1)
    @alpha.add_item(fact)
    @beta.add_token(token)

    @alpha.remove_item(fact)
    @beta.remove_token(token)

    assert_empty node.candidate_facts(token)
    assert_empty node.candidate_tokens(fact)
  end

  def test_joins_with_the_same_key_share_an_index
    assert_same @alpha.index_on([:order_id]), @alpha.index_on([:order_id])
    refute_same @alpha.index_on([:order_id]), @alpha.index_on([:region])
    assert_same @beta.index_on([[0, :id]]), @beta.index_on([[0, :id]])
  end

  def test_memory_clear_empties_the_indexes
    index = @alpha.index_on([:order_id])
    token_index = @beta.index_on([[0, :id]])
    @alpha.add_item(KBS::Fact.new(:payment, order_id: 1))
    @beta.add_token(order_token(id: 1))

    @alpha.clear
    @beta.clear

    assert_equal 0, index.size
    assert_equal 0, token_index.size
    assert_empty @alpha.items
    assert_empty @beta.tokens
  end

  def test_negation_node_is_indexed_too
    node = KBS::NegationNode.new(@alpha, @beta, [EQ])
    blocker = KBS::Fact.new(:payment, order_id: 1)
    @alpha.add_item(blocker)

    assert node.indexed?
    assert_equal [blocker], node.matching_facts(order_token(id: 1))
    assert_empty node.matching_facts(order_token(id: 2))
  end
end

# The index must agree with the == comparison the join tests use.
class TestIndexedJoinSemantics < Minitest::Test
  def setup
    @engine = KBS::Engine.new
    @fired = []
    fired = @fired
    @engine.add_rule(KBS::Rule.new(
      "paid",
      conditions: [
        KBS::Condition.new(:order, { id: :id?, region: :region? }),
        KBS::Condition.new(:payment, { order_id: :id?, region: :region? })
      ],
      action: ->(facts) { fired << facts.map { |fact| fact[:id] || fact[:order_id] } }
    ))
  end

  def test_join_on_two_variables
    @engine.add_fact(:order, id: 1, region: "eu")
    @engine.add_fact(:payment, order_id: 1, region: "eu")
    @engine.add_fact(:payment, order_id: 1, region: "us")

    assert_equal 1, @engine.run
  end

  def test_integer_joins_with_an_equal_float
    @engine.add_fact(:order, id: 1, region: "eu")
    @engine.add_fact(:payment, order_id: 1.0, region: "eu")

    assert_equal 1, @engine.run
  end

  def test_string_does_not_join_with_a_symbol
    @engine.add_fact(:order, id: 1, region: "eu")
    @engine.add_fact(:payment, order_id: 1, region: :eu)

    assert_equal 0, @engine.run
  end

  def test_late_rule_sees_facts_through_the_index
    @engine.add_fact(:order, id: 5, region: "eu")
    @engine.add_fact(:refund, order_id: 5)
    fired = @fired
    @engine.add_rule(KBS::Rule.new(
      "refunded",
      conditions: [
        KBS::Condition.new(:order, { id: :id? }),
        KBS::Condition.new(:refund, { order_id: :id? })
      ],
      action: ->(_facts) { fired << :refunded }
    ))

    @engine.run

    assert_equal [:refunded], @fired
  end

  def test_reset_empties_the_indexes
    @engine.add_fact(:order, id: 1, region: "eu")
    @engine.reset
    @engine.add_fact(:payment, order_id: 1, region: "eu")

    assert_equal 0, @engine.run
  end
end
