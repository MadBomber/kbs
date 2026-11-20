# frozen_string_literal: true

require_relative 'test_helper'

class TestPatternMatching < Minitest::Test
  def test_value_matches_a_constant
    assert KBS::PatternMatching.value_matches?(1, 1)
    refute KBS::PatternMatching.value_matches?(1, 2)
  end

  def test_value_matches_a_predicate
    predicate = ->(value) { value > 5 }

    assert KBS::PatternMatching.value_matches?(9, predicate)
    refute KBS::PatternMatching.value_matches?(1, predicate)
    refute KBS::PatternMatching.value_matches?(nil, predicate)
  end

  def test_a_variable_matches_anything
    assert KBS::PatternMatching.value_matches?(nil, :x?)
    refute KBS::PatternMatching.value_matches?(:other, :x)
  end

  def test_both_kinds_of_fact_match_the_same_way
    pattern = { type: :sensor, temp: ->(temp) { temp > 90 }, id: :id? }
    plain = KBS::Fact.new(:sensor, temp: 95, id: 1)
    stored = KBS::Blackboard::Fact.new("uuid", :sensor, { temp: 95, id: 1 })

    assert plain.matches?(pattern)
    assert stored.matches?(pattern)
    refute plain.matches?(pattern.merge(type: :other))
    refute stored.matches?(pattern.merge(temp: 1))
  end
end

class TestNetworkNode < Minitest::Test
  # The smallest thing a memory can talk to.
  class Probe
    include KBS::NetworkNode

    attr_reader :successors

    def initialize(successors)
      @successors = successors
    end

    def pass_on(token) = activate_successors(token)
    def take_back(token) = deactivate_successors(token)
  end

  def test_unhandled_calls_do_nothing
    node = Probe.new([])

    assert_nil node.left_unlink!
    assert_nil node.left_relink!
    assert_nil node.right_unlink!
    assert_nil node.right_relink!
    assert_nil node.right_deactivate(KBS::Fact.new(:a))
  end

  def test_tokens_go_to_and_come_back_from_the_successors
    memory = KBS::BetaMemory.new
    node = Probe.new([memory])
    token = KBS::Token.new(nil, KBS::Fact.new(:a), nil)

    node.pass_on(token)
    assert_equal [token], memory.tokens.to_a

    node.take_back(token)
    assert_empty memory.tokens
  end

  def test_production_node_answers_a_beta_memory
    node = KBS::ProductionNode.new(KBS::Rule.new("r"))
    token = KBS::Token.new(nil, KBS::Fact.new(:a), nil)

    node.left_activate(token)
    assert_equal [token], node.tokens

    node.left_deactivate(token)
    assert_empty node.tokens
  end
end

class TestActivationOrdering < Minitest::Test
  def setup
    node = KBS::ProductionNode.new(KBS::Rule.new("r", priority: 7))
    @activation = KBS::Activation.new(node, KBS::Token.new(nil, KBS::Fact.new(:a), nil), rule_order: 3, timetag: 11)
  end

  def test_key_for_each_strategy
    assert_equal [-7, -11, 0], @activation.key_for(:depth)
    assert_equal [-7, 11, 0], @activation.key_for(:breadth)
    assert_equal [-7, 3, 11], @activation.key_for(:definition)
  end

  def test_withdraw_cancels_once
    assert @activation.withdraw
    assert @activation.cancelled?
    refute @activation.withdraw
  end
end

class TestListings < Minitest::Test
  def test_condition_summary
    assert_equal "sensor(id: 1)", KBS::Condition.new(:sensor, { id: 1 }).summary
    assert_equal "NOT hold()", KBS::Condition.new(:hold, {}, negated: true).summary
    assert_equal "EXISTS alarm(level: 3)", KBS::Condition.new(:alarm, { level: 3 }, exists: true).summary
  end

  def test_condition_bindings_from_a_fact
    condition = KBS::Condition.new(:order, { id: :id?, total: :total? })

    assert_equal({ id?: 4, total?: 9 }, condition.bindings_from(KBS::Fact.new(:order, id: 4, total: 9)))
  end

  def builder
    KBS::DSL::RuleBuilder.new("hot").tap do |rule|
      rule.desc "too warm"
      rule.priority 2
      rule.on :sensor, id: 1
      rule.without :hold
    end
  end

  def test_rule_builder_source
    assert_equal <<~SOURCE.chomp, builder.source
      rule "hot" do
        desc "too warm"
        priority 2
        on :sensor, id: 1
        without :hold
      end
    SOURCE
  end

  def test_rule_builder_summary_lines
    assert_equal ["Rule: hot", "  Description: too warm", "  Priority: 2", "  Conditions: 2",
                  "    1. sensor(id: 1)", "    2. NOT hold()", ""], builder.summary_lines
  end

  def test_print_facts_and_print_rules
    kb = KBS.knowledge_base
    kb.rule("hot") { on :sensor, id: 1 }
    kb.assert(:sensor, id: 1)
    line = "-" * 40

    assert_output("Working Memory Contents:\n#{line}\n1. fact :sensor, id: 1\n#{line}\n") { kb.print_facts }
    assert_output("Knowledge Base Rules:\n#{line}\nRule: hot\n  Priority: 0\n  Conditions: 1\n    " \
                  "1. sensor(id: 1)\n\n#{line}\n") { kb.print_rules }
  end

  def test_query_uses_the_same_matching_as_rules
    kb = KBS.knowledge_base
    kb.assert(:sensor, temp: 95)
    kb.assert(:sensor, temp: 20)
    kb.assert(:other, temp: 95)

    assert_equal([95], kb.query(:sensor, temp: ->(temp) { temp > 90 }).map { |fact| fact[:temp] })
    assert_equal 2, kb.query(:sensor).size
  end

  def test_rule_lines_and_rule_line_index
    kb = KBS.knowledge_base
    lines = ["x = 1\n", "  rule \"r\" do\n", "    on :a\n", "  end\n", "end\n"]

    assert_equal 1, kb.send(:rule_line_index, lines, 2)
    assert_equal 4, kb.send(:rule_line_index, lines, 4)
    assert_equal lines[1..3], kb.send(:rule_lines, lines.drop(1))
    assert_equal ["  rule \"r\" do\n"], kb.send(:rule_lines, ["  rule \"r\" do\n"])
  end

  def test_an_in_memory_engine_closes_without_effect
    assert_nil KBS::Engine.new.close
    assert_nil KBS.knowledge_base.close
  end
end
