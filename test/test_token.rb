# frozen_string_literal: true

require_relative 'test_helper'

class TestToken < Minitest::Test
  def setup
    @fact1 = KBS::Fact.new(:person, name: "Alice")
    @fact2 = KBS::Fact.new(:person, name: "Bob")
  end

  def test_initialization
    token = KBS::Token.new(nil, @fact1, nil)

    assert_nil token.parent
    assert_equal @fact1, token.fact
    assert_nil token.node
    assert_empty token.children
  end

  def test_facts_with_single_fact
    token = KBS::Token.new(nil, @fact1, nil)
    facts = token.facts

    assert_equal 1, facts.length
    assert_equal @fact1, facts[0]
  end

  def test_facts_with_parent_chain
    token1 = KBS::Token.new(nil, @fact1, nil)
    token2 = KBS::Token.new(token1, @fact2, nil)

    facts = token2.facts
    assert_equal 2, facts.length
    assert_equal @fact1, facts[0]
    assert_equal @fact2, facts[1]
  end

  def test_facts_with_nil_fact_in_chain
    # Dummy token (used by RETE for initial state)
    dummy = KBS::Token.new(nil, nil, nil)
    token = KBS::Token.new(dummy, @fact1, nil)

    facts = token.facts
    assert_equal 1, facts.length
    assert_equal @fact1, facts[0]
  end

  def test_fact_at_returns_the_fact_for_a_condition_position
    token1 = KBS::Token.new(nil, @fact1, nil)
    token2 = KBS::Token.new(token1, @fact2, nil)

    assert_equal @fact1, token2.fact_at(0)
    assert_equal @fact2, token2.fact_at(1)
    assert_nil token2.fact_at(2)
  end

  def test_fact_at_skips_the_root_dummy_token
    dummy = KBS::Token.new(nil, nil, nil)
    token = KBS::Token.new(dummy, @fact1, nil)

    assert_equal @fact1, token.fact_at(0)
  end

  def test_fact_at_keeps_the_position_of_a_negated_condition
    token1 = KBS::Token.new(KBS::Token.new(nil, nil, nil), @fact1, nil)
    negated = KBS::Token.new(token1, nil, :negation_node)
    token3 = KBS::Token.new(negated, @fact2, nil)

    assert_equal @fact1, token3.fact_at(0)
    assert_nil token3.fact_at(1)
    assert_equal @fact2, token3.fact_at(2)
    assert_equal [@fact1, @fact2], token3.facts
  end

  def test_children_management
    parent = KBS::Token.new(nil, @fact1, nil)
    child = KBS::Token.new(parent, @fact2, nil)

    assert_empty parent.children

    parent.add_child(child)
    assert_equal 1, parent.children.size
    assert_equal child, parent.children.first
  end

  def test_children_are_empty_and_frozen_until_a_child_is_added
    token = KBS::Token.new(nil, @fact1, nil)

    assert_empty token.children
    assert_predicate token.children, :frozen?
  end

  def test_remove_child_and_clear_children
    parent = KBS::Token.new(nil, @fact1, nil)
    first = KBS::Token.new(parent, @fact2, nil)
    second = KBS::Token.new(parent, @fact2, nil)
    parent.remove_child(first)
    [first, second].each { |child| parent.add_child(child) }

    parent.remove_child(first)
    assert_equal [second], parent.children.to_a

    parent.clear_children
    assert_empty parent.children
  end

  # A lone child is kept without a Set; the second one makes a Set.
  def test_children_move_between_one_and_many
    parent = KBS::Token.new(nil, @fact1, nil)
    first = KBS::Token.new(parent, @fact2, nil)
    second = KBS::Token.new(parent, @fact2, nil)

    parent.add_child(first)
    parent.add_child(first)
    assert_equal [first], parent.children.to_a
    parent.remove_child(second)
    assert_equal [first], parent.children.to_a

    parent.add_child(second)
    assert_equal [first, second], parent.children.to_a
    parent.remove_child(first)
    parent.remove_child(second)
    assert_empty parent.children

    lone = KBS::Token.new(nil, @fact1, nil)
    lone.add_child(first)
    lone.remove_child(first)
    assert_empty lone.children
    assert_predicate lone.children, :frozen?
  end

  def test_to_s
    token1 = KBS::Token.new(nil, @fact1, nil)
    token2 = KBS::Token.new(token1, @fact2, nil)

    result = token2.to_s
    assert_includes result, "Token"
  end

  def test_deep_chain
    tokens = [KBS::Token.new(nil, @fact1, nil)]
    5.times do |i|
      fact = KBS::Fact.new(:num, value: i)
      tokens << KBS::Token.new(tokens.last, fact, nil)
    end

    facts = tokens.last.facts
    assert_equal 6, facts.length
  end
end
