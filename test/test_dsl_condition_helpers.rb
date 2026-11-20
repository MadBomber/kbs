# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs'

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

  # Issue #67: a value of the wrong type used to raise from add_fact and
  # leave the fact half added.
  def test_wrong_type_value_does_not_match
    refute greater_than(5).call("7")
    refute less_than(5).call("3")
    refute between(1, 9).call("5")
    refute range(1..9).call("5")
    refute matches(/1/).call(1)

    kb = KBS::DSL::KnowledgeBase.new
    fired = []

    kb.rule 'big' do
      on :s, v: greater_than(5)
      perform { fired << :big }
    end
    kb.rule 'digit' do
      on :s, v: matches(/1/)
      perform { fired << :digit }
    end

    kb.fact(:s, v: "7")
    kb.fact(:s, v: 1)
    kb.run

    assert_empty fired
  end

  # Issue #40: helpers inside the block form of `on` used to be recorded
  # as pattern keys of their own, so the rule never fired.
  def test_helpers_in_block_form_on_are_conditions_not_keys
    kb = KBS::DSL::KnowledgeBase.new
    fired = []

    kb.rule('big')  do
      on(:stock) { volume greater_than(500_000) }
      perform { fired << :big }
    end
    kb.rule('soon') do
      on(:earnings) { days_until(satisfies { |d| d <= 3 }) }
      perform { fired << :soon }
    end
    kb.rule('hot')  do
      on(:stock) { sector one_of(:tech, :energy) }
      perform { fired << :hot }
    end
    kb.rule('low')  do
      on(:stock) { rsi less_than(30) }
      perform { fired << :low }
    end
    kb.rule('flat') do
      on(:stock) { change not_equal(0) }
      perform { fired << :flat }
    end
    kb.rule('mid')  do
      on(:stock) { rsi range(20..40) }
      perform { fired << :mid }
    end
    kb.rule('ex')   do
      on(:stock) { exchange equals(:nyse) }
      perform { fired << :ex }
    end

    assert_equal([[:volume], [:days_until], [:sector], [:rsi], [:change], [:rsi], [:exchange]],
                 kb.rules.values.map { |rule| rule.conditions.first.pattern.keys })

    kb.fact :stock, volume: 900_000, sector: :tech, rsi: 25, change: 1, exchange: :nyse
    kb.fact :earnings, days_until: 2
    kb.run

    assert_equal %i[big soon hot low flat mid ex], fired
  end
end
