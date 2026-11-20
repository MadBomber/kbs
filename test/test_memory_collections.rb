# frozen_string_literal: true

require_relative 'test_helper'

# The memories keep their contents in Sets and hand out copies.
class TestMemoryCollections < Minitest::Test
  def setup
    @fact = KBS::Fact.new(:person, name: "Alice")
    @other = KBS::Fact.new(:person, name: "Bob")
  end

  def test_working_memory_accessors
    memory = KBS::WorkingMemory.new
    memory.add_fact(@fact)
    memory.add_fact(@other)

    assert_equal 2, memory.size
    assert memory.include?(@fact)
    assert_equal [@fact, @other], memory.enum_for(:each_fact).to_a
  end

  def test_working_memory_facts_is_a_copy
    memory = KBS::WorkingMemory.new
    memory.add_fact(@fact)

    memory.facts.clear

    assert_equal [@fact], memory.facts
  end

  def test_working_memory_ignores_a_fact_added_twice
    memory = KBS::WorkingMemory.new
    2.times { memory.add_fact(@fact) }

    assert_equal 1, memory.size
  end

  def test_working_memory_clear_does_not_notify
    memory = KBS::WorkingMemory.new
    events = []
    observer = Object.new
    observer.define_singleton_method(:update) { |action, _fact| events << action }
    memory.add_observer(observer)
    memory.add_fact(@fact)

    memory.clear

    assert_equal 0, memory.size
    assert_equal [:add], events
  end

  def test_alpha_memory_accessors
    memory = KBS::AlphaMemory.new(type: :person)
    memory.add_item(@fact)
    memory.add_item(@other)

    assert_equal 2, memory.size
    assert memory.include?(@fact)
    assert_equal [@fact, @other], memory.enum_for(:each_item).to_a

    memory.remove_item(@fact)
    assert_equal [@other], memory.items
  end

  def test_alpha_memory_items_is_a_copy
    memory = KBS::AlphaMemory.new(type: :person)
    memory.add_item(@fact)

    memory.items << @other

    assert_equal [@fact], memory.items
  end

  def test_beta_memory_accessors
    memory = KBS::BetaMemory.new
    first = KBS::Token.new(nil, @fact, nil)
    second = KBS::Token.new(nil, @other, nil)
    memory.add_token(first)
    memory.add_token(second)

    assert_equal 2, memory.size
    assert memory.include?(first)
    assert_equal [first, second], memory.enum_for(:each_token).to_a

    memory.remove_token(first)
    assert_equal [second], memory.tokens
  end

  def test_beta_memory_tokens_is_a_copy
    memory = KBS::BetaMemory.new
    token = KBS::Token.new(nil, @fact, nil)
    memory.add_token(token)

    memory.tokens.clear

    assert_equal [token], memory.tokens
  end

  def test_production_node_tokens_is_a_copy
    node = KBS::ProductionNode.new(KBS::Rule.new("r"))
    token = KBS::Token.new(nil, @fact, nil)
    node.activate(token)

    node.tokens.clear

    assert_equal [token], node.tokens
  end
end
