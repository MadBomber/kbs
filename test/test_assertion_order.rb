# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs/blackboard'

# Regression tests for issue #41: a multi-condition rule fires once per
# match whatever order its facts arrive in.
module AssertionOrderTests
  def fire_count(types, order)
    fired = 0
    conditions = types.map { |type| KBS::Condition.new(type, {}) }
    @engine.add_rule(KBS::Rule.new('rule', conditions: conditions, action: ->(_facts) { fired += 1 }))
    order.each { |type| @engine.add_fact(type, {}) }
    @engine.run
    [fired, @engine.production_nodes['rule'].tokens.size]
  end

  def test_two_conditions_in_condition_order
    assert_equal [1, 1], fire_count(%i[a b], %i[a b])
  end

  def test_two_conditions_in_reverse_order
    assert_equal [1, 1], fire_count(%i[a b], %i[b a])
  end

  def test_three_conditions_in_every_order
    %i[a b c].permutation.each do |order|
      setup
      assert_equal [1, 1], fire_count(%i[a b c], order), "order #{order.inspect}"
    end
  end
end

class TestEngineAssertionOrder < Minitest::Test
  include AssertionOrderTests

  def setup
    @engine = KBS::Engine.new
  end
end

class TestBlackboardEngineAssertionOrder < Minitest::Test
  include AssertionOrderTests

  def setup
    @engine&.blackboard&.close
    @engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
  end

  def teardown
    @engine.blackboard.close
  end

  def test_reverse_order_writes_one_audit_row
    fire_count(%i[a b], %i[b a])

    assert_equal 1, @engine.blackboard.get_rule_firings.size
  end
end
