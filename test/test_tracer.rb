# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

class TestTracer < Minitest::Test
  def setup
    @out = StringIO.new
    @tracer = KBS::Tracer.new(@out)
    @fact = KBS::Fact.new(:sensor, id: 1)
    @node = KBS::ProductionNode.new(KBS::Rule.new("hot", priority: 5))
    @agenda = KBS::Agenda.new
    @activation = @agenda.add(@node, KBS::Token.new(nil, @fact, nil), rule_order: 0)
  end

  def test_nothing_is_watched_at_first
    assert_empty @tracer.watched
    @tracer.fact_added(@fact)
    @tracer.activation_added(@activation)
    @tracer.rule_fired(@activation)

    assert_empty @out.string
  end

  def test_watch_without_arguments_watches_everything
    assert_same @tracer, @tracer.watch

    assert_equal %i[facts activations rules], @tracer.watched
  end

  def test_watch_and_unwatch_single_items
    @tracer.watch(:facts, :rules)
    @tracer.unwatch(:facts)

    assert_equal %i[rules], @tracer.watched
    assert @tracer.watching?(:rules)
    refute @tracer.watching?(:facts)
  end

  def test_unwatch_without_arguments_stops_everything
    @tracer.watch.unwatch

    assert_empty @tracer.watched
  end

  def test_unknown_item_is_rejected
    error = assert_raises(ArgumentError) { @tracer.watch(:globals) }

    assert_match(/cannot watch \[:globals\]/, error.message)
  end

  def test_fact_lines
    @tracer.watch(:facts)
    @tracer.fact_added(@fact)
    @tracer.fact_removed(@fact)

    assert_equal "==> fact :sensor, id: 1\n<== fact :sensor, id: 1\n", @out.string
  end

  def test_activation_lines
    @tracer.watch(:activations)
    @tracer.activation_added(@activation)
    @tracer.activation_removed(@activation)

    assert_equal "==> Activation 5 hot: fact :sensor, id: 1\n<== Activation 5 hot: fact :sensor, id: 1\n", @out.string
  end

  def test_rule_lines_count_firings_even_when_not_watched
    @tracer.rule_fired(@activation)
    @tracer.watch(:rules)
    @tracer.rule_fired(@activation)

    assert_equal "FIRE 2 hot: fact :sensor, id: 1\n", @out.string
  end

  def test_output_can_be_replaced
    other = StringIO.new
    @tracer.output = other
    @tracer.watch(:facts)
    @tracer.fact_added(@fact)

    assert_empty @out.string
    refute_empty other.string
  end

  def test_activation_description_marks_conditions_without_a_fact
    token = KBS::Token.new(KBS::Token.new(nil, @fact, nil), nil, nil)
    activation = @agenda.add(@node, token, rule_order: 0)

    assert_equal "hot: fact :sensor, id: 1; *", activation.description
    assert_equal "5 hot: fact :sensor, id: 1; *", activation.to_s
  end
end

class TestAgendaListener < Minitest::Test
  def setup
    @events = []
    events = @events
    listener = Object.new
    listener.define_singleton_method(:activation_added) { |activation| events << [:added, activation] }
    listener.define_singleton_method(:activation_removed) { |activation| events << [:removed, activation] }
    @agenda = KBS::Agenda.new
    @agenda.listener = listener
    @node = KBS::ProductionNode.new(KBS::Rule.new("r"))
    @token = KBS::Token.new(nil, KBS::Fact.new(:a), nil)
  end

  def test_listener_hears_about_added_and_removed_activations
    activation = @agenda.add(@node, @token, rule_order: 0)
    @agenda.remove(activation)

    assert_equal [[:added, activation], [:removed, activation]], @events
  end

  def test_popping_an_activation_is_not_a_removal
    activation = @agenda.add(@node, @token, rule_order: 0)
    @agenda.pop

    assert_equal [[:added, activation]], @events
  end
end
