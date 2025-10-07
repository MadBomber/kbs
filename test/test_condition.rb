# frozen_string_literal: true

require_relative 'test_helper'

class TestCondition < Minitest::Test
  def test_initialization
    condition = KBS::Condition.new(:person, { name: "Alice", age: 30 })

    assert_equal :person, condition.type
    assert_equal({ name: "Alice", age: 30 }, condition.pattern)
    refute condition.negated
  end

  def test_initialization_with_negation
    condition = KBS::Condition.new(:alarm, { active: true }, negated: true)

    assert_equal :alarm, condition.type
    assert condition.negated
  end

  def test_variable_binding_extraction
    condition = KBS::Condition.new(:person, { name: :'?name', age: :'?age' })

    assert_equal 2, condition.variable_bindings.size
    assert_equal :name, condition.variable_bindings[:'?name']
    assert_equal :age, condition.variable_bindings[:'?age']
  end

  def test_no_variable_bindings
    condition = KBS::Condition.new(:person, { name: "Alice", age: 30 })

    assert_equal 0, condition.variable_bindings.size
  end

  def test_mixed_variables_and_constants
    condition = KBS::Condition.new(:person, { name: :'?name', age: 30, city: "NYC" })

    assert_equal 1, condition.variable_bindings.size
    assert_equal :name, condition.variable_bindings[:'?name']
  end

  def test_variable_with_proc_pattern
    condition = KBS::Condition.new(:person, { age: ->(v) { v > 18 }, name: :'?name' })

    assert_equal 1, condition.variable_bindings.size
    assert_equal :name, condition.variable_bindings[:'?name']
  end

  def test_empty_pattern
    condition = KBS::Condition.new(:event, {})

    assert_equal({}, condition.pattern)
    assert_equal 0, condition.variable_bindings.size
  end

  def test_non_variable_symbols
    # Symbols that don't start with ? should not be treated as variables
    condition = KBS::Condition.new(:person, { status: :active, name: :'?name' })

    assert_equal 1, condition.variable_bindings.size
    assert_equal :name, condition.variable_bindings[:'?name']
  end
end
