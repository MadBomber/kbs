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
    assert_equal [], token.children
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

  def test_children_management
    parent = KBS::Token.new(nil, @fact1, nil)
    child = KBS::Token.new(parent, @fact2, nil)

    assert_equal [], parent.children

    parent.children << child
    assert_equal 1, parent.children.length
    assert_equal child, parent.children[0]
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
