# frozen_string_literal: true

require_relative 'test_helper'

class TestFact < Minitest::Test
  def test_initialization
    fact = KBS::Fact.new(:person, name: "Alice", age: 30)

    assert_equal :person, fact.type
    assert_equal({ name: "Alice", age: 30 }, fact.attributes)
    refute_nil fact.id
  end

  def test_id_is_unique
    fact1 = KBS::Fact.new(:person, name: "Alice")
    fact2 = KBS::Fact.new(:person, name: "Bob")

    refute_equal fact1.id, fact2.id
  end

  def test_attribute_accessor
    fact = KBS::Fact.new(:person, name: "Alice", age: 30)

    assert_equal "Alice", fact[:name]
    assert_equal 30, fact[:age]
    assert_nil fact[:unknown]
  end

  def test_matches_with_exact_type
    fact = KBS::Fact.new(:person, name: "Alice", age: 30)

    assert fact.matches?(type: :person)
    refute fact.matches?(type: :employee)
  end

  def test_matches_with_exact_attributes
    fact = KBS::Fact.new(:person, name: "Alice", age: 30)

    assert fact.matches?(type: :person, name: "Alice")
    assert fact.matches?(type: :person, age: 30)
    refute fact.matches?(type: :person, name: "Bob")
  end

  def test_matches_with_proc_condition
    fact = KBS::Fact.new(:person, name: "Alice", age: 30)

    assert fact.matches?(type: :person, age: ->(v) { v > 18 })
    assert fact.matches?(type: :person, age: ->(v) { v == 30 })
    refute fact.matches?(type: :person, age: ->(v) { v < 18 })
  end

  def test_matches_with_variable_binding
    fact = KBS::Fact.new(:person, name: "Alice", age: 30)

    # Variables (symbols ending with ?) should match anything
    assert fact.matches?(type: :person, name: :name?)
    assert fact.matches?(type: :person, age: :age?)
  end

  def test_matches_with_missing_attribute
    fact = KBS::Fact.new(:person, name: "Alice")

    refute fact.matches?(type: :person, age: 30)
  end

  def test_matches_with_proc_on_missing_attribute
    fact = KBS::Fact.new(:person, name: "Alice")

    refute fact.matches?(type: :person, age: ->(v) { v > 18 })
  end

  def test_matches_without_type_in_pattern
    fact = KBS::Fact.new(:person, name: "Alice", age: 30)

    assert fact.matches?(name: "Alice")
    refute fact.matches?(name: "Bob")
  end

  def test_to_s
    fact = KBS::Fact.new(:person, name: "Alice", age: 30)
    result = fact.to_s

    assert_includes result, "person"
    assert_includes result, "name"
    assert_includes result, "Alice"
  end

  def test_empty_attributes
    fact = KBS::Fact.new(:event)

    assert_equal({}, fact.attributes)
    assert fact.matches?(type: :event)
  end
end
