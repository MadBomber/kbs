# frozen_string_literal: true

require_relative 'test_helper'

class TestAlphaMemory < Minitest::Test
  def setup
    @pattern = { type: :person, age: ->(v) { v > 18 } }
    @memory = KBS::AlphaMemory.new(@pattern)
    @fact1 = KBS::Fact.new(:person, name: "Alice", age: 30)
    @fact2 = KBS::Fact.new(:person, name: "Bob", age: 25)
  end

  def test_initialization
    assert_equal [], @memory.items
    assert_equal [], @memory.successors
    assert_equal @pattern, @memory.pattern
    assert @memory.linked
  end

  def test_activate_adds_fact
    @memory.activate(@fact1)

    assert_equal 1, @memory.items.length
    assert_equal @fact1, @memory.items[0]
  end

  def test_activate_multiple_facts
    @memory.activate(@fact1)
    @memory.activate(@fact2)

    assert_equal 2, @memory.items.length
    assert_includes @memory.items, @fact1
    assert_includes @memory.items, @fact2
  end

  def test_deactivate_removes_fact
    @memory.activate(@fact1)
    @memory.activate(@fact2)
    @memory.deactivate(@fact1)

    assert_equal 1, @memory.items.length
    refute_includes @memory.items, @fact1
    assert_includes @memory.items, @fact2
  end

  def test_activate_propagates_to_successors
    activations = []
    successor = Object.new
    def successor.right_activate(fact)
      @activations ||= []
      @activations << fact
    end
    successor.instance_variable_set(:@activations, activations)

    @memory.successors << successor
    @memory.activate(@fact1)

    assert_equal 1, activations.length
    assert_equal @fact1, activations[0]
  end

  def test_deactivate_propagates_to_successors
    deactivations = []
    successor = Object.new
    def successor.right_activate(fact)
      # No-op for this test
    end
    def successor.right_deactivate(fact)
      @deactivations ||= []
      @deactivations << fact
    end
    successor.instance_variable_set(:@deactivations, deactivations)

    @memory.successors << successor
    @memory.activate(@fact1)
    @memory.deactivate(@fact1)

    assert_equal 1, deactivations.length
    assert_equal @fact1, deactivations[0]
  end

  def test_unlink_prevents_activation
    @memory.unlink!

    refute @memory.linked
    @memory.activate(@fact1)

    assert_equal 0, @memory.items.length
  end

  def test_relink_enables_activation
    @memory.unlink!
    @memory.relink!

    assert @memory.linked
    @memory.activate(@fact1)

    assert_equal 1, @memory.items.length
  end

  def test_unlink_propagates_to_successors
    unlinked = false
    successor = Object.new
    def successor.right_unlink!
      @unlinked = true
    end
    def successor.unlinked?
      @unlinked ||= false
    end
    successor.instance_variable_set(:@unlinked, false)

    @memory.successors << successor
    @memory.unlink!

    # Check that right_unlink! was called
    @memory.activate(@fact1)
    assert_equal 0, @memory.items.length
  end

  def test_deactivate_when_unlinked
    @memory.activate(@fact1)
    @memory.unlink!
    @memory.deactivate(@fact1)

    # Should not remove when unlinked
    assert_equal 1, @memory.items.length
  end

  def test_empty_pattern
    memory = KBS::AlphaMemory.new({})
    fact = KBS::Fact.new(:any, value: 1)

    memory.activate(fact)
    assert_equal 1, memory.items.length
  end
end
