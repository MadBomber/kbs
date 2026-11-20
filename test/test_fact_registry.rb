# frozen_string_literal: true

require_relative 'test_helper'

class TestFactRegistry < Minitest::Test
  def setup
    @registry = KBS::FactRegistry.new
    @fact = KBS::Fact.new(:sensor, id: 1, temp: 20)
  end

  def test_find_returns_nil_when_empty
    assert_nil @registry.find(:sensor, { id: 1, temp: 20 })
    assert_equal 0, @registry.size
  end

  def test_add_then_find_by_type_and_attributes
    assert @registry.add(@fact)

    assert_same @fact, @registry.find(:sensor, { id: 1, temp: 20 })
    assert_same @fact, @registry.find(:sensor, { temp: 20, id: 1 })
    assert_nil @registry.find(:sensor, { id: 1 })
    assert_nil @registry.find(:other, { id: 1, temp: 20 })
  end

  def test_add_refuses_an_equal_fact
    @registry.add(@fact)

    refute @registry.add(KBS::Fact.new(:sensor, id: 1, temp: 20))
    assert_equal 1, @registry.size
    assert_same @fact, @registry.find(:sensor, { id: 1, temp: 20 })
  end

  def test_remove
    @registry.add(@fact)
    @registry.remove(@fact)

    assert_nil @registry.find(:sensor, { id: 1, temp: 20 })
    assert_equal 0, @registry.size
  end

  def test_remove_of_an_unfiled_fact_keeps_the_filed_one
    @registry.add(@fact)
    @registry.remove(KBS::Fact.new(:sensor, id: 1, temp: 20))

    assert_same @fact, @registry.find(:sensor, { id: 1, temp: 20 })
  end

  def test_fact_is_filed_under_its_attributes_at_the_time
    @registry.add(@fact)
    @fact[:temp] = 99

    assert_same @fact, @registry.find(:sensor, { id: 1, temp: 20 })
    @registry.remove(@fact)
    assert_equal 0, @registry.size
  end

  def test_clear
    @registry.add(@fact)
    @registry.clear

    assert_equal 0, @registry.size
  end
end
