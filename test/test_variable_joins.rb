# frozen_string_literal: true

require_relative 'test_helper'

# A ?variable shared by two conditions joins them: both facts must hold
# the same value.
class TestVariableJoins < Minitest::Test
  def setup
    @engine = KBS::Engine.new
    @fired = []
  end

  def add_rule(*conditions)
    fired = @fired
    @engine.add_rule(KBS::Rule.new(:rule, conditions: conditions,
                                          action: ->(facts, bindings) { fired << [facts, bindings] }))
  end

  def test_shared_variable_matches_only_equal_values
    add_rule(
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:payment, { order_id: :id? })
    )
    3.times { |i| @engine.add_fact(:order, id: i) }
    3.times { |i| @engine.add_fact(:payment, order_id: i) }

    @engine.run

    assert_equal 3, @fired.size
    @fired.each { |facts, _| assert_equal facts[0][:id], facts[1][:order_id] }
  end

  def test_shared_variable_when_later_condition_facts_arrive_first
    add_rule(
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:payment, { order_id: :id? })
    )
    3.times { |i| @engine.add_fact(:payment, order_id: i) }
    3.times { |i| @engine.add_fact(:order, id: i) }

    @engine.run

    assert_equal 3, @fired.size
  end

  def test_bindings_hold_the_joined_value
    add_rule(
      KBS::Condition.new(:order, { id: :id?, total: :total? }),
      KBS::Condition.new(:payment, { order_id: :id?, amount: :amount? })
    )
    @engine.add_fact(:order, id: 7, total: 50)
    @engine.add_fact(:payment, order_id: 7, amount: 50)
    @engine.add_fact(:payment, order_id: 8, amount: 10)

    @engine.run

    assert_equal [{ id?: 7, total?: 50, amount?: 50 }], @fired.map(&:last)
  end

  def test_three_way_join
    add_rule(
      KBS::Condition.new(:a, { k: :k? }),
      KBS::Condition.new(:b, { k: :k? }),
      KBS::Condition.new(:c, { k: :k? })
    )
    [1, 2].each do |k|
      @engine.add_fact(:a, k: k)
      @engine.add_fact(:b, k: k)
      @engine.add_fact(:c, k: k)
    end

    @engine.run

    assert_equal 2, @fired.size
  end

  def test_negated_condition_joins_on_bound_variable
    add_rule(
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:payment, { order_id: :id? }, negated: true)
    )
    3.times { |i| @engine.add_fact(:order, id: i) }
    @engine.add_fact(:payment, order_id: 1)

    @engine.run

    assert_equal [0, 2], @fired.map { |facts, _| facts[0][:id] }
  end

  def test_join_after_a_negated_condition
    add_rule(
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:hold, {}, negated: true),
      KBS::Condition.new(:item, { sku: :sku? }),
      KBS::Condition.new(:stock, { sku: :sku? })
    )
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:item, sku: "a")
    @engine.add_fact(:item, sku: "b")
    @engine.add_fact(:stock, sku: "b")

    @engine.run

    assert_equal [{ id?: 1, sku?: "b" }], @fired.map(&:last)
  end

  def test_variable_repeated_in_one_condition
    add_rule(KBS::Condition.new(:pair, { left: :v?, right: :v? }))
    @engine.add_fact(:pair, left: 1, right: 1)
    @engine.add_fact(:pair, left: 1, right: 2)

    @engine.run

    assert_equal 1, @fired.size
  end

  def test_retracting_a_joined_fact_removes_the_match
    add_rule(
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:payment, { order_id: :id? })
    )
    @engine.add_fact(:order, id: 1)
    payment = @engine.add_fact(:payment, order_id: 1)
    @engine.remove_fact(payment)

    @engine.run

    assert_empty @fired
  end

  def test_different_variables_do_not_join
    add_rule(
      KBS::Condition.new(:order, { id: :order? }),
      KBS::Condition.new(:payment, { order_id: :payment? })
    )
    2.times { |i| @engine.add_fact(:order, id: i) }
    2.times { |i| @engine.add_fact(:payment, order_id: i) }

    @engine.run

    assert_equal 4, @fired.size
  end

  def test_dsl_rule_joins_on_shared_variable
    fired = []
    kb = KBS.knowledge_base do
      rule "paid" do
        on :order, id: :id?
        on :payment, order_id: :id?
        perform { |_facts, bindings| fired << bindings[:id?] }
      end
    end
    2.times { |i| kb.assert(:order, id: i) }
    kb.assert(:payment, order_id: 1)

    kb.run

    assert_equal [1], fired
  end

  def test_blackboard_engine_joins_on_shared_variable
    engine = KBS::Blackboard::Engine.new
    fired = @fired
    engine.add_rule(KBS::Rule.new("paid",
                                  conditions: [
                                    KBS::Condition.new(:order, { id: :id? }),
                                    KBS::Condition.new(:payment, { order_id: :id? })
                                  ],
                                  action: ->(facts) { fired << facts }))
    2.times { |i| engine.add_fact(:order, id: i) }
    engine.add_fact(:payment, order_id: 0)

    engine.run

    assert_equal 1, @fired.size
  ensure
    engine&.close
  end
end
