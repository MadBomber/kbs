# frozen_string_literal: true

require_relative 'test_helper'

class TestProductionNode < Minitest::Test
  def setup
    @rule = KBS::Rule.new(
      "test_rule",
      conditions: [],
      action: ->(facts, bindings) { @fired = true; @fired_facts = facts }
    )
    @production_node = KBS::ProductionNode.new(@rule)
  end

  def test_initialization
    assert_equal @rule, @production_node.rule
    assert_equal [], @production_node.tokens
  end

  def test_activate_adds_token_and_fires_rule
    fact1 = KBS::Fact.new(:person, name: "Alice")
    fact2 = KBS::Fact.new(:person, name: "Bob")

    token1 = KBS::Token.new(nil, fact1, nil)
    token2 = KBS::Token.new(token1, fact2, nil)

    @fired = false
    @production_node.activate(token2)
    @production_node.fire_rule(token2)

    assert_equal 1, @production_node.tokens.length
    assert_equal token2, @production_node.tokens[0]
    assert @fired, "Rule should have fired"
  end

  def test_deactivate_removes_token
    fact = KBS::Fact.new(:person, name: "Alice")
    token = KBS::Token.new(nil, fact, nil)

    @production_node.activate(token)
    @production_node.deactivate(token)

    assert_equal 0, @production_node.tokens.length
  end

  def test_activate_fires_with_correct_facts
    fact1 = KBS::Fact.new(:person, name: "Alice")
    fact2 = KBS::Fact.new(:company, name: "Acme")

    token1 = KBS::Token.new(nil, fact1, nil)
    token2 = KBS::Token.new(token1, fact2, nil)

    @production_node.activate(token2)
    @production_node.fire_rule(token2)

    assert_equal [fact1, fact2], @fired_facts
  end

  def test_multiple_activations
    fact1 = KBS::Fact.new(:person, name: "Alice")
    fact2 = KBS::Fact.new(:person, name: "Bob")

    token1 = KBS::Token.new(nil, fact1, nil)
    token2 = KBS::Token.new(nil, fact2, nil)

    @production_node.activate(token1)
    @production_node.activate(token2)

    assert_equal 2, @production_node.tokens.length
  end

  def test_rule_with_no_action
    rule = KBS::Rule.new("no_action_rule", conditions: [], action: nil)
    node = KBS::ProductionNode.new(rule)

    fact = KBS::Fact.new(:person, name: "Alice")
    token = KBS::Token.new(nil, fact, nil)

    # Should not raise error
    node.activate(token)
    assert_equal 1, node.tokens.length
  end

  def test_rule_fires_multiple_times
    fired_count = 0
    rule = KBS::Rule.new(
      "counting_rule",
      conditions: [],
      action: ->(facts, bindings) { fired_count += 1 }
    )
    node = KBS::ProductionNode.new(rule)

    # Create three different tokens (realistic RETE behavior)
    fact1 = KBS::Fact.new(:event, id: 1)
    fact2 = KBS::Fact.new(:event, id: 2)
    fact3 = KBS::Fact.new(:event, id: 3)

    token1 = KBS::Token.new(nil, fact1, nil)
    token2 = KBS::Token.new(nil, fact2, nil)
    token3 = KBS::Token.new(nil, fact3, nil)

    node.activate(token1)
    node.activate(token2)
    node.activate(token3)

    # Fire all tokens
    node.tokens.each { |token| node.fire_rule(token) }

    assert_equal 3, fired_count
  end
end
