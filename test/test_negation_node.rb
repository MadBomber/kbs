# frozen_string_literal: true

require_relative 'test_helper'

class TestNegationNode < Minitest::Test
  def setup
    @alpha_memory = KBS::AlphaMemory.new(type: :alarm)
    @beta_memory = KBS::BetaMemory.new
    @negation_node = KBS::NegationNode.new(@alpha_memory, @beta_memory, [])
  end

  def test_initialization
    assert_equal @alpha_memory, @negation_node.alpha_memory
    assert_equal @beta_memory, @negation_node.beta_memory
    assert_equal [], @negation_node.successors
    assert_equal [], @negation_node.tests
  end

  def test_left_activate_with_no_matches
    # When there are no matching facts in alpha, token should be created
    tokens = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    successor.instance_variable_set(:@tokens, tokens)
    @negation_node.successors << successor

    fact = KBS::Fact.new(:sensor, temp: 100)
    token = KBS::Token.new(nil, fact, nil)

    @negation_node.left_activate(token)

    assert_equal 1, tokens.length
    assert_equal token, tokens[0].parent
  end

  def test_left_activate_with_matches
    # When there are matching facts, no token should be created
    tokens = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    successor.instance_variable_set(:@tokens, tokens)
    @negation_node.successors << successor

    # Add matching fact to alpha
    alarm_fact = KBS::Fact.new(:alarm, active: true)
    @alpha_memory.activate(alarm_fact)

    # Try to activate with token
    sensor_fact = KBS::Fact.new(:sensor, temp: 100)
    token = KBS::Token.new(nil, sensor_fact, nil)

    @negation_node.left_activate(token)

    # Should not create token because match exists
    assert_equal 0, tokens.length
  end

  def test_right_activate_removes_existing_tokens
    # Setup: create token via left activation (no matches)
    deactivations = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    def successor.deactivate(token)
      @deactivations ||= []
      @deactivations << token
    end
    successor.instance_variable_set(:@deactivations, deactivations)
    @negation_node.successors << successor

    sensor_fact = KBS::Fact.new(:sensor, temp: 100)
    token = KBS::Token.new(nil, sensor_fact, nil)
    @beta_memory.add_token(token)

    @negation_node.left_activate(token)

    # Now add matching fact (should remove token)
    alarm_fact = KBS::Fact.new(:alarm, active: true)
    @negation_node.right_activate(alarm_fact)

    # Token should have been removed
    assert_equal 1, deactivations.length
  end

  def test_right_deactivate_creates_tokens
    # Setup: add matching fact first (prevents token creation)
    alarm_fact = KBS::Fact.new(:alarm, active: true)
    @alpha_memory.activate(alarm_fact)

    sensor_fact = KBS::Fact.new(:sensor, temp: 100)
    token = KBS::Token.new(nil, sensor_fact, nil)
    @beta_memory.add_token(token)

    @negation_node.left_activate(token)

    # Now track activations
    activations = []
    successor = Object.new
    def successor.activate(token)
      @activations ||= []
      @activations << token
    end
    successor.instance_variable_set(:@activations, activations)
    @negation_node.successors << successor

    # Deactivate the blocking fact
    @negation_node.right_deactivate(alarm_fact)

    # Should now create token since match is gone
    assert_equal 1, activations.length
  end

  def test_negation_with_equality_test
    tests = [{
      token_field_index: 0,
      token_field: :location,
      fact_field: :location,
      operation: :eq
    }]
    negation_node = KBS::NegationNode.new(@alpha_memory, @beta_memory, tests)

    tokens = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    successor.instance_variable_set(:@tokens, tokens)
    negation_node.successors << successor

    # Add alarm for different location
    alarm_fact = KBS::Fact.new(:alarm, location: "reactor1")
    @alpha_memory.activate(alarm_fact)

    # Activate with token for different location
    sensor_fact = KBS::Fact.new(:sensor, temp: 100, location: "reactor2")
    token = KBS::Token.new(nil, sensor_fact, nil)

    negation_node.left_activate(token)

    # Should create token because locations don't match
    assert_equal 1, tokens.length
  end

  def test_multiple_blocking_facts
    alarm1 = KBS::Fact.new(:alarm, id: 1)
    alarm2 = KBS::Fact.new(:alarm, id: 2)

    @alpha_memory.activate(alarm1)
    @alpha_memory.activate(alarm2)

    tokens = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    successor.instance_variable_set(:@tokens, tokens)
    @negation_node.successors << successor

    sensor_fact = KBS::Fact.new(:sensor, temp: 100)
    token = KBS::Token.new(nil, sensor_fact, nil)

    @negation_node.left_activate(token)

    # Should not create token (multiple blocking facts)
    assert_equal 0, tokens.length
  end
end
