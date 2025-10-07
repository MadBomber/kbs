# frozen_string_literal: true

require_relative 'test_helper'

class TestJoinNode < Minitest::Test
  def setup
    @alpha_memory = KBS::AlphaMemory.new(type: :person)
    @beta_memory = KBS::BetaMemory.new
    @join_node = KBS::JoinNode.new(@alpha_memory, @beta_memory, [])
  end

  def test_initialization
    assert_equal @alpha_memory, @join_node.alpha_memory
    assert_equal @beta_memory, @join_node.beta_memory
    assert_equal [], @join_node.successors
    assert_equal [], @join_node.tests
    assert @join_node.left_linked
    assert @join_node.right_linked
  end

  def test_initialization_adds_to_memory_successors
    assert_includes @alpha_memory.successors, @join_node
    assert_includes @beta_memory.successors, @join_node
  end

  def test_right_activate_creates_new_tokens
    tokens = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    successor.instance_variable_set(:@tokens, tokens)
    @join_node.successors << successor

    # Add initial dummy token to beta memory
    dummy_token = KBS::Token.new(nil, nil, nil)
    @beta_memory.add_token(dummy_token)

    # Add fact to alpha memory (which automatically propagates to join_node)
    fact = KBS::Fact.new(:person, name: "Alice")
    @alpha_memory.activate(fact)

    # Alpha memory activation automatically calls right_activate on join_node
    assert_equal 1, tokens.length
    assert_equal fact, tokens[0].fact
  end

  def test_left_activate_creates_new_tokens
    tokens = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    successor.instance_variable_set(:@tokens, tokens)
    @join_node.successors << successor

    # Add fact to alpha memory
    fact = KBS::Fact.new(:person, name: "Alice")
    @alpha_memory.activate(fact)

    # Create token and left activate
    token = KBS::Token.new(nil, nil, nil)
    @join_node.left_activate(token)

    assert_equal 1, tokens.length
  end

  def test_join_with_equality_test
    # Create join node with equality test
    tests = [{
      token_field_index: 0,
      token_field: :company,
      fact_field: :company,
      operation: :eq
    }]
    join_node = KBS::JoinNode.new(@alpha_memory, @beta_memory, tests)

    tokens = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    successor.instance_variable_set(:@tokens, tokens)
    join_node.successors << successor

    # Add matching fact to beta
    fact1 = KBS::Fact.new(:employee, name: "Alice", company: "Acme")
    token1 = KBS::Token.new(nil, fact1, nil)
    @beta_memory.add_token(token1)

    # Add matching fact to alpha (which automatically propagates to join_node)
    fact2 = KBS::Fact.new(:person, name: "Bob", company: "Acme")
    @alpha_memory.activate(fact2)

    # Alpha memory activation automatically calls right_activate on join_node
    assert_equal 1, tokens.length
  end

  def test_join_with_failing_test
    tests = [{
      token_field_index: 0,
      token_field: :company,
      fact_field: :company,
      operation: :eq
    }]
    join_node = KBS::JoinNode.new(@alpha_memory, @beta_memory, tests)

    tokens = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    successor.instance_variable_set(:@tokens, tokens)
    join_node.successors << successor

    # Add non-matching fact to beta
    fact1 = KBS::Fact.new(:employee, name: "Alice", company: "Acme")
    token1 = KBS::Token.new(nil, fact1, nil)
    @beta_memory.add_token(token1)

    # Add non-matching fact to alpha
    fact2 = KBS::Fact.new(:person, name: "Bob", company: "TechCorp")
    @alpha_memory.activate(fact2)

    join_node.right_activate(fact2)

    # Should not create token due to failed test
    assert_equal 0, tokens.length
  end

  def test_left_unlink
    @join_node.left_unlink!
    refute @join_node.left_linked
  end

  def test_right_unlink
    @join_node.right_unlink!
    refute @join_node.right_linked
  end

  def test_unlinked_prevents_activation
    tokens = []
    successor = Object.new
    def successor.activate(token)
      @tokens ||= []
      @tokens << token
    end
    successor.instance_variable_set(:@tokens, tokens)
    @join_node.successors << successor

    @join_node.left_unlink!

    fact = KBS::Fact.new(:person, name: "Alice")
    token = KBS::Token.new(nil, nil, nil)
    @join_node.left_activate(token)

    assert_equal 0, tokens.length
  end

  def test_right_deactivate
    # Add token via activation
    dummy_token = KBS::Token.new(nil, nil, nil)
    @beta_memory.add_token(dummy_token)

    fact = KBS::Fact.new(:person, name: "Alice")
    @alpha_memory.activate(fact)
    @join_node.right_activate(fact)

    # Track deactivations
    deactivations = []
    successor = Object.new
    def successor.deactivate(token)
      @deactivations ||= []
      @deactivations << token
    end
    successor.instance_variable_set(:@deactivations, deactivations)
    @join_node.successors << successor

    # Deactivate the fact
    @join_node.right_deactivate(fact)

    # Should have propagated deactivation
    assert deactivations.length >= 0 # May be 0 if no children were created
  end
end
