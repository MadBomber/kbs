# frozen_string_literal: true

require_relative 'test_helper'

class TestRule < Minitest::Test
  def test_initialization
    condition = KBS::Condition.new(:person, { name: "Alice" })
    action = ->(facts, bindings) { puts "Hello" }
    rule = KBS::Rule.new("greet", conditions: [condition], action: action, priority: 10)

    assert_equal "greet", rule.name
    assert_equal 1, rule.conditions.length
    assert_equal action, rule.action
    assert_equal 10, rule.priority
  end

  def test_default_priority
    rule = KBS::Rule.new("test", conditions: [], action: nil)

    assert_equal 0, rule.priority
  end

  def test_fire_executes_action
    fired = false
    action = ->(facts, bindings) { fired = true }
    rule = KBS::Rule.new("test", conditions: [], action: action)

    fact = KBS::Fact.new(:person, name: "Alice")
    rule.fire([fact])

    assert fired
  end

  def test_fire_extracts_bindings
    extracted_bindings = nil
    action = ->(facts, bindings) { extracted_bindings = bindings }

    condition = KBS::Condition.new(:person, { name: :name?, age: :age? })
    rule = KBS::Rule.new("test", conditions: [condition], action: action)

    fact = KBS::Fact.new(:person, name: "Alice", age: 30)
    rule.fire([fact])

    assert_equal "Alice", extracted_bindings[:name?]
    assert_equal 30, extracted_bindings[:age?]
  end

  def test_fire_with_multiple_facts
    extracted_facts = nil
    action = ->(facts, bindings) { extracted_facts = facts }

    condition1 = KBS::Condition.new(:person, {})
    condition2 = KBS::Condition.new(:company, {})
    rule = KBS::Rule.new("test", conditions: [condition1, condition2], action: action)

    fact1 = KBS::Fact.new(:person, name: "Alice")
    fact2 = KBS::Fact.new(:company, name: "Acme")

    rule.fire([fact1, fact2])

    assert_equal 2, extracted_facts.length
    assert_equal fact1, extracted_facts[0]
    assert_equal fact2, extracted_facts[1]
  end

  def test_fire_with_negated_condition
    extracted_bindings = nil
    action = ->(facts, bindings) { extracted_bindings = bindings }

    condition1 = KBS::Condition.new(:sensor, { temp: :temp? })
    condition2 = KBS::Condition.new(:alarm, { active: true }, negated: true)
    rule = KBS::Rule.new("test", conditions: [condition1, condition2], action: action)

    fact1 = KBS::Fact.new(:sensor, temp: 100)

    rule.fire([fact1])

    # Should only extract bindings from non-negated conditions
    assert_equal 100, extracted_bindings[:temp?]
    assert_equal 1, extracted_bindings.size
  end

  def test_fire_without_action
    rule = KBS::Rule.new("test", conditions: [], action: nil)
    fact = KBS::Fact.new(:person, name: "Alice")

    # Should not raise error
    rule.fire([fact])
  end

  def test_fire_tracks_count
    rule = KBS::Rule.new("test", conditions: [], action: ->(f, b) {})
    fact = KBS::Fact.new(:event, id: 1)

    3.times { rule.fire([fact]) }

    # The fired_count is private, but we can verify the action was called
    # by using a counter in the action itself
    counter = 0
    rule = KBS::Rule.new("counter", conditions: [], action: ->(f, b) { counter += 1 })

    3.times { rule.fire([fact]) }
    assert_equal 3, counter
  end

  def test_bindings_from_multiple_conditions
    extracted_bindings = nil
    action = ->(facts, bindings) { extracted_bindings = bindings }

    condition1 = KBS::Condition.new(:person, { name: :person_name? })
    condition2 = KBS::Condition.new(:company, { name: :company_name? })
    rule = KBS::Rule.new("test", conditions: [condition1, condition2], action: action)

    fact1 = KBS::Fact.new(:person, name: "Alice")
    fact2 = KBS::Fact.new(:company, name: "Acme")

    rule.fire([fact1, fact2])

    assert_equal "Alice", extracted_bindings[:person_name?]
    assert_equal "Acme", extracted_bindings[:company_name?]
  end
end
