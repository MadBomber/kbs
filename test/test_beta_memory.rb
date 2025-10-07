# frozen_string_literal: true

require_relative 'test_helper'

class TestBetaMemory < Minitest::Test
  def setup
    @memory = KBS::BetaMemory.new
    @fact = KBS::Fact.new(:person, name: "Alice")
    @token = KBS::Token.new(nil, @fact, nil)
  end

  def test_initialization
    assert_equal [], @memory.tokens
    assert_equal [], @memory.successors
    assert @memory.linked
  end

  def test_add_token
    @memory.add_token(@token)

    assert_equal 1, @memory.tokens.length
    assert_equal @token, @memory.tokens[0]
  end

  def test_remove_token
    @memory.add_token(@token)
    @memory.remove_token(@token)

    assert_equal 0, @memory.tokens.length
  end

  def test_activate_adds_and_propagates
    activations = []
    successor = Object.new
    def successor.left_activate(token)
      @activations ||= []
      @activations << token
    end
    successor.instance_variable_set(:@activations, activations)

    @memory.successors << successor
    @memory.activate(@token)

    assert_equal 1, @memory.tokens.length
    assert_equal 1, activations.length
    assert_equal @token, activations[0]
  end

  def test_activate_with_generic_activate_method
    activations = []
    successor = Object.new
    def successor.activate(token)
      @activations ||= []
      @activations << token
    end
    successor.instance_variable_set(:@activations, activations)

    @memory.successors << successor
    @memory.activate(@token)

    assert_equal 1, activations.length
  end

  def test_unlink_prevents_propagation
    calls = []
    successor = Object.new
    def successor.left_unlink!
      @calls ||= []
      @calls << :unlinked
    end
    successor.instance_variable_set(:@calls, calls)

    @memory.successors << successor
    @memory.unlink!

    refute @memory.linked
    assert_equal 1, calls.length
  end

  def test_relink_enables_propagation
    calls = []
    successor = Object.new
    def successor.left_relink!
      @calls ||= []
      @calls << :relinked
    end
    successor.instance_variable_set(:@calls, calls)

    @memory.successors << successor
    @memory.unlink!
    @memory.relink!

    assert @memory.linked
    assert_equal 1, calls.length
  end

  def test_add_token_relinks_when_first_token
    @memory.add_token(@token)

    # After adding first token, should be linked
    assert @memory.linked
  end

  def test_remove_token_unlinks_when_empty
    @memory.add_token(@token)
    @memory.remove_token(@token)

    # After removing last token, should unlink
    refute @memory.linked
  end

  def test_multiple_successors
    calls1 = []
    calls2 = []

    successor1 = Object.new
    def successor1.left_activate(token)
      @calls ||= []
      @calls << token
    end
    successor1.instance_variable_set(:@calls, calls1)

    successor2 = Object.new
    def successor2.activate(token)
      @calls ||= []
      @calls << token
    end
    successor2.instance_variable_set(:@calls, calls2)

    @memory.successors << successor1
    @memory.successors << successor2
    @memory.activate(@token)

    assert_equal 1, calls1.length
    assert_equal 1, calls2.length
  end
end
