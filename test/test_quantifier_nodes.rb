# frozen_string_literal: true

require_relative 'test_helper'

# NegationNode and ExistsNode share the token/fact links in QuantifierNode.
class TestQuantifierNodes < Minitest::Test
  JOIN = { token_field_index: 0, token_field: :id, fact_field: :order_id, operation: :eq }.freeze

  def setup
    @alpha = KBS::AlphaMemory.new(type: :payment)
    @beta = KBS::BetaMemory.new
    @passed = []
    @retracted = []
  end

  def build(node_class, tests = [JOIN])
    node = node_class.new(@alpha, @beta, tests)
    passed = @passed
    retracted = @retracted
    successor = Object.new
    successor.define_singleton_method(:activate) { |token| passed << token }
    successor.define_singleton_method(:deactivate) { |token| retracted << token }
    node.successors << successor
    node
  end

  def order(id)
    KBS::Token.new(nil, KBS::Fact.new(:order, id: id), nil)
  end

  def payment(order_id)
    KBS::Fact.new(:payment, order_id: order_id)
  end

  def test_base_class_needs_a_subclass
    node = KBS::QuantifierNode.new(@alpha, @beta, [])

    assert_raises(NotImplementedError) { node.left_activate(order(1)) }
  end

  def test_negation_passes_a_token_with_no_match
    node = build(KBS::NegationNode)
    token = order(1)
    @alpha.activate(payment(2))

    @beta.activate(token)

    assert_equal 1, @passed.size
    assert_same token, @passed.first.parent
    assert_nil @passed.first.fact
    refute node.matched?(token)
  end

  def test_negation_blocks_a_token_with_a_match
    node = build(KBS::NegationNode)
    token = order(1)
    blocker = payment(1)
    @alpha.activate(blocker)

    @beta.activate(token)

    assert_empty @passed
    assert node.matched?(token)
    assert_equal [blocker], node.facts_matching(token)
    assert_equal [token], node.tokens_matched_by(blocker)
  end

  def test_negation_first_blocker_retracts_the_passed_token
    build(KBS::NegationNode)
    @beta.activate(order(1))

    @alpha.activate(payment(1))

    assert_equal @passed, @retracted
  end

  def test_negation_second_blocker_changes_nothing
    build(KBS::NegationNode)
    @beta.activate(order(1))
    @alpha.activate(payment(1))

    @alpha.activate(payment(1))

    assert_equal 1, @retracted.size
  end

  def test_negation_passes_again_only_when_the_last_blocker_goes
    node = build(KBS::NegationNode)
    token = order(1)
    first = payment(1)
    second = payment(1)
    [first, second].each { |fact| @alpha.activate(fact) }
    @beta.activate(token)

    @alpha.deactivate(first)
    assert_empty @passed
    assert_equal [second], node.facts_matching(token)

    @alpha.deactivate(second)
    assert_equal 1, @passed.size
    refute node.matched?(token)
    assert_empty node.tokens_matched_by(second)
  end

  def test_blocker_only_affects_the_tokens_it_matches
    build(KBS::NegationNode)
    @beta.activate(order(1))
    @beta.activate(order(2))

    @alpha.activate(payment(1))

    assert_equal [1], @retracted.map { |token| token.parent.fact[:id] }
  end

  def test_negation_removing_a_blocked_token_drops_its_links
    node = build(KBS::NegationNode)
    token = order(1)
    blocker = payment(1)
    @alpha.activate(blocker)
    @beta.activate(token)

    @beta.deactivate(token)

    refute node.matched?(token)
    assert_empty node.tokens_matched_by(blocker)
    @alpha.deactivate(blocker)
    assert_empty @passed
  end

  def test_negation_removing_a_passed_token_retracts_its_output
    build(KBS::NegationNode)
    token = order(1)
    @beta.activate(token)

    @beta.deactivate(token)

    assert_equal @passed, @retracted
    assert_empty token.children
  end

  def test_exists_passes_once_however_many_facts_match
    node = build(KBS::ExistsNode)
    token = order(1)
    3.times { @alpha.activate(payment(1)) }

    @beta.activate(token)

    assert_equal 1, @passed.size
    assert_nil @passed.first.fact
    assert_equal 3, node.facts_matching(token).size
  end

  def test_exists_does_not_pass_without_a_match
    build(KBS::ExistsNode)
    @alpha.activate(payment(2))

    @beta.activate(order(1))

    assert_empty @passed
  end

  def test_exists_passes_when_the_first_match_arrives
    build(KBS::ExistsNode)
    @beta.activate(order(1))

    @alpha.activate(payment(1))
    @alpha.activate(payment(1))

    assert_equal 1, @passed.size
  end

  def test_exists_retracts_only_when_the_last_match_goes
    build(KBS::ExistsNode)
    first = payment(1)
    second = payment(1)
    [first, second].each { |fact| @alpha.activate(fact) }
    @beta.activate(order(1))

    @alpha.deactivate(first)
    assert_empty @retracted

    @alpha.deactivate(second)
    assert_equal @passed, @retracted
  end

  def test_exists_passes_again_after_a_new_match
    build(KBS::ExistsNode)
    fact = payment(1)
    @alpha.activate(fact)
    @beta.activate(order(1))
    @alpha.deactivate(fact)

    @alpha.activate(payment(1))

    assert_equal 2, @passed.size
  end

  def test_reset_forgets_the_links
    node = build(KBS::NegationNode)
    token = order(1)
    blocker = payment(1)
    @alpha.activate(blocker)
    @beta.activate(token)

    node.reset

    refute node.matched?(token)
    assert_empty node.tokens_matched_by(blocker)
  end

  def test_unindexed_node_matches_every_fact
    node = build(KBS::NegationNode, [])
    token = order(1)
    @alpha.activate(payment(99))

    @beta.activate(token)

    refute node.indexed?
    assert_empty @passed
  end
end

class TestExistsCondition < Minitest::Test
  def setup
    @engine = KBS::Engine.new
    @fired = []
  end

  def add_rule(*conditions)
    fired = @fired
    @engine.add_rule(KBS::Rule.new("rule", conditions: conditions,
                                           action: ->(facts, bindings) { fired << [facts.map(&:type), bindings] }))
  end

  def test_condition_flags
    condition = KBS::Condition.new(:alarm, {}, exists: true)

    assert condition.exists
    refute condition.negated
    refute condition.binds_fact?
    assert_equal "exists", condition.keyword
    assert_equal "without", KBS::Condition.new(:alarm, {}, negated: true).keyword
    assert_equal "on", KBS::Condition.new(:alarm).keyword
    assert KBS::Condition.new(:alarm).binds_fact?
    refute KBS::Condition.new(:alarm, {}, negated: true).binds_fact?
  end

  def test_condition_cannot_be_negated_and_exists
    assert_raises(ArgumentError) { KBS::Condition.new(:alarm, {}, negated: true, exists: true) }
  end

  def test_exists_fires_once_for_many_facts
    add_rule(KBS::Condition.new(:alarm, {}, exists: true))
    3.times { @engine.add_fact(:alarm) }

    assert_equal 1, @engine.run
    assert_equal [[[], {}]], @fired
  end

  def test_exists_does_not_fire_without_a_fact
    add_rule(KBS::Condition.new(:alarm, {}, exists: true))

    assert_equal 0, @engine.run
  end

  def test_exists_joins_on_a_bound_variable
    add_rule(
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:payment, { order_id: :id? }, exists: true)
    )
    2.times { |i| @engine.add_fact(:order, id: i) }
    2.times { @engine.add_fact(:payment, order_id: 1) }

    @engine.run

    assert_equal [[[:order], { id?: 1 }]], @fired
  end

  def test_exists_contributes_no_fact_and_keeps_later_bindings_aligned
    add_rule(
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:payment, { order_id: :id? }, exists: true),
      KBS::Condition.new(:customer, { name: :name? })
    )
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:payment, order_id: 1)
    @engine.add_fact(:customer, name: "Ada")

    @engine.run

    assert_equal [[%i[order customer], { id?: 1, name?: "Ada" }]], @fired
  end

  def test_variable_first_used_in_exists_is_not_bound_later
    add_rule(
      KBS::Condition.new(:payment, { order_id: :id? }, exists: true),
      KBS::Condition.new(:order, { id: :id? })
    )
    @engine.add_fact(:payment, order_id: 1)
    @engine.add_fact(:order, id: 2)

    assert_equal 1, @engine.run
  end

  def test_retracting_the_last_match_takes_the_activation_back
    add_rule(KBS::Condition.new(:alarm, {}, exists: true))
    first = @engine.add_fact(:alarm)
    second = @engine.add_fact(:alarm)

    @engine.remove_fact(first)
    assert_equal 1, @engine.agenda.size

    @engine.remove_fact(second)
    assert @engine.agenda.empty?
  end

  def test_exists_fires_again_after_the_facts_went_and_came_back
    add_rule(KBS::Condition.new(:alarm, {}, exists: true))
    alarm = @engine.add_fact(:alarm)
    @engine.run
    @engine.remove_fact(alarm)
    @engine.add_fact(:alarm)

    assert_equal 1, @engine.run
    assert_equal 2, @fired.size
  end

  def test_late_exists_rule_sees_existing_facts
    2.times { @engine.add_fact(:alarm) }
    add_rule(KBS::Condition.new(:alarm, {}, exists: true))

    assert_equal 1, @engine.run
  end

  def test_reset_clears_exists_matches
    add_rule(KBS::Condition.new(:alarm, {}, exists: true))
    @engine.add_fact(:alarm)

    @engine.reset

    assert_equal 0, @engine.run
    @engine.add_fact(:alarm)
    assert_equal 1, @engine.run
  end

  def test_rule_to_s_uses_the_exists_keyword
    rule = KBS::Rule.new("r", conditions: [KBS::Condition.new(:alarm, { level: 3 }, exists: true)])

    assert_includes rule.to_s, "  exists :alarm, level: 3"
  end
end

class TestExistsDsl < Minitest::Test
  def test_exists_keyword_builds_an_exists_condition
    builder = KBS::DSL::RuleBuilder.new("r")
    builder.exists(:alarm, level: 3)

    condition = builder.conditions.first
    assert condition.exists
    assert_equal({ level: 3 }, condition.pattern)
  end

  def test_exists_keyword_accepts_a_block
    builder = KBS::DSL::RuleBuilder.new("r")
    builder.exists(:alarm) { level 3 }

    assert_equal({ level: 3 }, builder.conditions.first.pattern)
  end

  def test_dsl_rule_fires_once
    fired = 0
    kb = KBS.knowledge_base do
      rule "any alarm" do
        exists :alarm
        perform { fired += 1 }
      end
    end
    3.times { kb.assert(:alarm) }

    kb.run

    assert_equal 1, fired
  end

  def test_rule_source_and_print_rules_show_exists
    kb = KBS.knowledge_base
    kb.instance_eval("rule('any alarm') { exists :alarm, level: 3 }", "(eval)", 1)

    assert_includes kb.rule_source("any alarm"), "exists :alarm, level: 3"
    assert_output(/1\. EXISTS alarm\(level: 3\)/) { kb.print_rules }
  end
end
