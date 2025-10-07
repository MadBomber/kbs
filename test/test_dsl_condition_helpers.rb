# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs/dsl'

class TestDSLConditionHelpers < Minitest::Test
  include KBS::DSL::ConditionHelpers

  def test_less_than
    pred = less_than(100)

    assert pred.call(50)
    refute pred.call(100)
    refute pred.call(150)
  end

  def test_greater_than
    pred = greater_than(100)

    refute pred.call(50)
    refute pred.call(100)
    assert pred.call(150)
  end

  def test_between
    pred = between(10, 20)

    refute pred.call(5)
    assert pred.call(10)
    assert pred.call(15)
    assert pred.call(20)
    refute pred.call(25)
  end

  def test_one_of
    pred = one_of(:red, :blue, :green)

    assert pred.call(:red)
    assert pred.call(:blue)
    assert pred.call(:green)
    refute pred.call(:yellow)
  end

  def test_matches_regexp
    pred = matches(/^\d{3}-\d{4}$/)

    assert pred.call("123-4567")
    refute pred.call("abc-defg")
    refute pred.call("12-345")
  end

  def test_range_helper
    pred = range(1..10)

    refute pred.call(0)
    assert pred.call(1)
    assert pred.call(5)
    assert pred.call(10)
    refute pred.call(11)
  end

  def test_any_helper
    pred = any

    assert pred.call(nil)
    assert pred.call(0)
    assert pred.call("")
    assert pred.call(:symbol)
    assert pred.call([])
  end

  def test_helpers_in_rule
    kb = KBS::DSL::KnowledgeBase.new
    result = []

    kb.rule 'fast_car' do
      on :car, speed: greater_than(100)
      perform { |facts| result << facts.first[:speed] }
    end

    kb.fact(:car, speed: 50)
    kb.fact(:car, speed: 150)
    kb.run

    assert_equal 1, result.size
    assert_equal 150, result.first
  end

  def test_between_in_rule
    kb = KBS::DSL::KnowledgeBase.new
    result = []

    kb.rule 'young_driver' do
      on :driver, age: between(18, 25)
      perform { |facts| result << facts.first[:age] }
    end

    kb.fact(:driver, age: 17)
    kb.fact(:driver, age: 20)
    kb.fact(:driver, age: 30)
    kb.run

    assert_equal 1, result.size
    assert_equal 20, result.first
  end

  def test_one_of_in_rule
    kb = KBS::DSL::KnowledgeBase.new
    result = []

    kb.rule 'primary_color' do
      on :car, color: one_of(:red, :blue, :yellow)
      perform { |facts| result << facts.first[:color] }
    end

    kb.fact(:car, color: :red)
    kb.fact(:car, color: :green)
    kb.fact(:car, color: :blue)
    kb.run

    assert_equal 2, result.size
    assert_includes result, :red
    assert_includes result, :blue
  end
end
