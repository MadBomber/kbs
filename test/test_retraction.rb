# frozen_string_literal: true

require_relative 'test_helper'

# Retraction follows links recorded when the fact was matched, instead of
# searching the memories.
class TestRetraction < Minitest::Test
  def setup
    @engine = KBS::Engine.new
    @fired = []
    fired = @fired
    @engine.add_rule(KBS::Rule.new(
                       "paid",
                       conditions: [
                         KBS::Condition.new(:order, { id: :id? }),
                         KBS::Condition.new(:payment, { order_id: :id? })
                       ],
                       action: ->(facts) { fired << facts.map(&:type) }
                     ))
  end

  def production
    @engine.production_nodes["paid"]
  end

  def test_engine_records_the_alpha_memories_of_a_fact
    order = @engine.add_fact(:order, id: 1)
    other = @engine.add_fact(:unrelated, id: 1)

    assert_equal [{ id: :id?, type: :order }], @engine.alpha_memories_for(order).map(&:pattern)
    assert_empty @engine.alpha_memories_for(other)
  end

  def test_removing_a_fact_forgets_its_alpha_memories
    order = @engine.add_fact(:order, id: 1)

    @engine.remove_fact(order)

    assert_empty @engine.alpha_memories_for(order)
    assert(@engine.alpha_memories.each_value.all? { |memory| memory.items.empty? })
  end

  def test_removing_the_right_fact_removes_its_matches
    @engine.add_fact(:order, id: 1)
    payment = @engine.add_fact(:payment, order_id: 1)
    assert_equal 1, production.tokens.size

    @engine.remove_fact(payment)

    assert_empty production.tokens
    assert @engine.agenda.empty?
  end

  def test_removing_the_left_fact_removes_its_matches
    order = @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)

    @engine.remove_fact(order)

    assert_empty production.tokens
    assert @engine.agenda.empty?
  end

  def test_removing_one_fact_keeps_the_other_matches
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:order, id: 2)
    first = @engine.add_fact(:payment, order_id: 1)
    @engine.add_fact(:payment, order_id: 2)

    @engine.remove_fact(first)

    assert_equal([[2, 2]], production.tokens.map { |token| [token.facts[0][:id], token.facts[1][:order_id]] })
  end

  def test_fact_joined_with_several_tokens
    3.times { @engine.add_fact(:order, id: 1) }
    payment = @engine.add_fact(:payment, order_id: 1)
    assert_equal 3, production.tokens.size

    @engine.remove_fact(payment)

    assert_empty production.tokens
  end

  def test_removal_works_after_the_fact_was_changed
    @engine.add_fact(:order, id: 1)
    payment = @engine.add_fact(:payment, order_id: 1)
    payment[:order_id] = 99

    @engine.remove_fact(payment)

    assert_empty production.tokens
    assert_equal 0, @engine.run
  end

  def test_removing_a_fact_twice_is_harmless
    @engine.add_fact(:order, id: 1)
    payment = @engine.add_fact(:payment, order_id: 1)

    2.times { @engine.remove_fact(payment) }

    assert_empty production.tokens
  end

  def test_removing_a_fact_that_was_never_added_is_harmless
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)

    @engine.remove_fact(KBS::Fact.new(:payment, order_id: 1))

    assert_equal 1, production.tokens.size
  end

  def test_fact_can_be_added_again_after_removal
    @engine.add_fact(:order, id: 1)
    payment = @engine.add_fact(:payment, order_id: 1)
    @engine.remove_fact(payment)
    @engine.add_fact(:payment, order_id: 1)

    assert_equal 1, @engine.run
  end

  def test_three_condition_chain_unwinds_from_the_middle
    fired = @fired
    @engine.add_rule(KBS::Rule.new(
                       "shipped",
                       conditions: [
                         KBS::Condition.new(:order, { id: :id? }),
                         KBS::Condition.new(:payment, { order_id: :id? }),
                         KBS::Condition.new(:shipment, { order_id: :id? })
                       ],
                       action: ->(_facts) { fired << :shipped }
                     ))
    @engine.add_fact(:order, id: 1)
    payment = @engine.add_fact(:payment, order_id: 1)
    @engine.add_fact(:shipment, order_id: 1)
    assert_equal 1, @engine.production_nodes["shipped"].tokens.size

    @engine.remove_fact(payment)

    assert_empty @engine.production_nodes["shipped"].tokens
    assert_empty production.tokens
  end

  def test_late_rule_facts_are_recorded_for_retraction
    order = @engine.add_fact(:order, id: 1)
    @engine.add_rule(KBS::Rule.new("big", conditions: [KBS::Condition.new(:order, { id: 1 })]))
    assert_equal 1, @engine.production_nodes["big"].tokens.size

    @engine.remove_fact(order)

    assert_empty @engine.production_nodes["big"].tokens
  end

  def test_reset_forgets_fact_memories_and_join_links
    order = @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)

    @engine.reset

    assert_empty @engine.alpha_memories_for(order)
    @engine.add_fact(:payment, order_id: 1)
    assert_equal 0, @engine.run
  end

  def test_blackboard_engine_retracts_by_uuid
    engine = KBS::Blackboard::Engine.new
    engine.add_rule(KBS::Rule.new(
                      "paid",
                      conditions: [
                        KBS::Condition.new(:order, { id: :id? }),
                        KBS::Condition.new(:payment, { order_id: :id? })
                      ]
                    ))
    engine.add_fact(:order, id: 1)
    payment = engine.add_fact(:payment, order_id: 1)
    assert_equal 1, engine.production_nodes["paid"].tokens.size

    engine.remove_fact(payment.uuid)

    assert_empty engine.production_nodes["paid"].tokens
  ensure
    engine&.close
  end
end

class TestJoinNodeTokenLinks < Minitest::Test
  def setup
    @alpha = KBS::AlphaMemory.new(type: :payment)
    @beta = KBS::BetaMemory.new
    @node = KBS::JoinNode.new(@alpha, @beta, [])
    @removed = []
    removed = @removed
    successor = Object.new
    successor.define_singleton_method(:activate) { |_token| nil }
    successor.define_singleton_method(:deactivate) { |token| removed << token }
    @node.successors << successor
  end

  def test_tokens_built_from_a_fact
    2.times { @beta.add_token(KBS::Token.new(nil, KBS::Fact.new(:order), nil)) }
    fact = KBS::Fact.new(:payment)

    assert_empty @node.tokens_built_from(fact)
    @alpha.activate(fact)

    assert_equal 2, @node.tokens_built_from(fact).size
    assert(@node.tokens_built_from(fact).all? { |token| token.fact.equal?(fact) })
  end

  def test_right_deactivate_removes_exactly_the_tokens_of_that_fact
    parent = KBS::Token.new(nil, KBS::Fact.new(:order), nil)
    @beta.add_token(parent)
    gone = KBS::Fact.new(:payment)
    kept = KBS::Fact.new(:payment)
    [gone, kept].each { |fact| @alpha.activate(fact) }

    @alpha.deactivate(gone)

    assert_equal [gone], @removed.map(&:fact)
    assert_equal [kept], parent.children.map(&:fact)
    assert_empty @node.tokens_built_from(gone)
    assert_equal 1, @node.tokens_built_from(kept).size
  end

  def test_left_deactivate_removes_the_children_this_node_built
    parent = KBS::Token.new(nil, KBS::Fact.new(:order), nil)
    @beta.add_token(parent)
    fact = KBS::Fact.new(:payment)
    @alpha.activate(fact)
    foreign = KBS::Token.new(parent, KBS::Fact.new(:other), :another_node)
    parent.add_child(foreign)

    @beta.deactivate(parent)

    assert_equal [fact], @removed.map(&:fact)
    assert_equal [foreign], parent.children.to_a
    assert_empty @node.tokens_built_from(fact)
  end

  def test_reset_forgets_the_links
    @beta.add_token(KBS::Token.new(nil, KBS::Fact.new(:order), nil))
    fact = KBS::Fact.new(:payment)
    @alpha.activate(fact)

    @node.reset

    assert_empty @node.tokens_built_from(fact)
  end
end
