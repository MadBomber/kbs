# frozen_string_literal: true

require_relative 'test_helper'

class TestAgenda < Minitest::Test
  def node(name, priority = 0)
    KBS::ProductionNode.new(KBS::Rule.new(name, priority: priority))
  end

  def token
    KBS::Token.new(nil, KBS::Fact.new(:x), nil)
  end

  def names(agenda)
    names = []
    while (activation = agenda.pop)
      names << activation.rule.name
    end
    names
  end

  def test_starts_empty
    agenda = KBS::Agenda.new

    assert agenda.empty?
    assert_equal 0, agenda.size
    assert_nil agenda.pop
    assert_nil agenda.peek
    assert_equal :definition, agenda.strategy
  end

  def test_unknown_strategy_raises
    assert_raises(ArgumentError) { KBS::Agenda.new(strategy: :nope) }
    assert_raises(ArgumentError) { KBS::Agenda.new.strategy = :nope }
  end

  def test_add_returns_the_activation
    agenda = KBS::Agenda.new
    rule_node = node("a", 7)
    match = token

    activation = agenda.add(rule_node, match, rule_order: 3)

    assert_same rule_node, activation.node
    assert_same match, activation.token
    assert_equal 7, activation.salience
    assert_equal 3, activation.rule_order
    assert_equal 1, agenda.size
    refute agenda.empty?
  end

  def test_higher_salience_pops_first
    agenda = KBS::Agenda.new
    agenda.add(node("low", 1), token)
    agenda.add(node("high", 10), token)
    agenda.add(node("mid", 5), token)

    assert_equal %w[high mid low], names(agenda)
  end

  def test_definition_strategy_orders_by_rule_then_age
    agenda = KBS::Agenda.new(strategy: :definition)
    second = node("second")
    first = node("first")
    agenda.add(second, token, rule_order: 1)
    agenda.add(first, token, rule_order: 0)
    agenda.add(second, token, rule_order: 1)

    assert_equal %w[first second second], names(agenda)
  end

  def test_depth_strategy_pops_newest_first
    agenda = KBS::Agenda.new(strategy: :depth)
    %w[a b c].each_with_index { |name, i| agenda.add(node(name), token, rule_order: i) }

    assert_equal %w[c b a], names(agenda)
  end

  def test_breadth_strategy_pops_oldest_first
    agenda = KBS::Agenda.new(strategy: :breadth)
    %w[c a b].each_with_index { |name, i| agenda.add(node(name), token, rule_order: 2 - i) }

    assert_equal %w[c a b], names(agenda)
  end

  def test_salience_wins_over_strategy
    agenda = KBS::Agenda.new(strategy: :depth)
    agenda.add(node("high", 5), token)
    agenda.add(node("newest", 0), token)

    assert_equal %w[high newest], names(agenda)
  end

  def test_remove_takes_an_activation_off_the_agenda
    agenda = KBS::Agenda.new
    agenda.add(node("a"), token, rule_order: 0)
    gone = agenda.add(node("b"), token, rule_order: 1)
    agenda.add(node("c"), token, rule_order: 2)

    agenda.remove(gone)

    assert_equal 2, agenda.size
    assert_equal %w[a c], names(agenda)
  end

  def test_remove_is_safe_to_repeat_and_accepts_nil
    agenda = KBS::Agenda.new
    activation = agenda.add(node("a"), token)

    agenda.remove(activation)
    agenda.remove(activation)
    agenda.remove(nil)

    assert_equal 0, agenda.size
    assert_nil agenda.pop
  end

  def test_removing_a_popped_activation_does_not_change_the_size
    agenda = KBS::Agenda.new
    agenda.add(node("a"), token)
    agenda.add(node("b"), token, rule_order: 1)
    popped = agenda.pop

    agenda.remove(popped)

    assert_equal 1, agenda.size
  end

  def test_peek_does_not_remove
    agenda = KBS::Agenda.new
    agenda.add(node("a"), token)

    assert_equal "a", agenda.peek.rule.name
    assert_equal 1, agenda.size
  end

  def test_peek_skips_removed_activations
    agenda = KBS::Agenda.new
    first = agenda.add(node("a"), token, rule_order: 0)
    agenda.add(node("b"), token, rule_order: 1)
    agenda.remove(first)

    assert_equal "b", agenda.peek.rule.name
  end

  def test_to_a_lists_pending_activations_in_firing_order
    agenda = KBS::Agenda.new
    agenda.add(node("low", 1), token)
    removed = agenda.add(node("gone", 9), token)
    agenda.add(node("high", 5), token)
    agenda.remove(removed)

    assert_equal(%w[high low], agenda.to_a.map { |activation| activation.rule.name })
    assert_equal 2, agenda.size
  end

  def test_changing_strategy_reorders_pending_activations
    agenda = KBS::Agenda.new(strategy: :breadth)
    %w[a b c].each_with_index { |name, i| agenda.add(node(name), token, rule_order: i) }

    agenda.strategy = :depth

    assert_equal :depth, agenda.strategy
    assert_equal 3, agenda.size
    assert_equal %w[c b a], names(agenda)
  end

  def test_clear
    agenda = KBS::Agenda.new
    activation = agenda.add(node("a"), token)

    agenda.clear

    assert agenda.empty?
    assert_nil agenda.pop
    assert activation.cancelled?
  end

  def test_many_activations_pop_in_order
    agenda = KBS::Agenda.new(strategy: :breadth)
    saliences = (1..200).map { |i| (i * 37) % 11 }
    saliences.each_with_index { |salience, i| agenda.add(node("r#{i}", salience), token) }

    popped = []
    while (activation = agenda.pop)
      popped << [activation.salience, activation.timetag]
    end

    assert_equal 200, popped.size
    assert_equal popped.sort_by { |salience, timetag| [-salience, timetag] }, popped
  end

  def test_activation_to_s
    agenda = KBS::Agenda.new
    activation = agenda.add(node("alert", 3), KBS::Token.new(nil, KBS::Fact.new(:sensor, id: 1), nil))

    assert_equal "3 alert: fact :sensor, id: 1", activation.to_s
  end
end
