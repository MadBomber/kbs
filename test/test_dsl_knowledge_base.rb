# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs'

class TestDSLKnowledgeBase < Minitest::Test
  def test_initialization
    kb = KBS::DSL::KnowledgeBase.new

    assert_instance_of KBS::DSL::KnowledgeBase, kb
    assert_instance_of KBS::Engine, kb.engine
  end

  def test_add_fact
    kb = KBS::DSL::KnowledgeBase.new
    kb.fact(:car, color: :red, speed: 100)

    facts = kb.engine.working_memory.facts
    assert_equal 1, facts.size
    assert_equal :car, facts.first.type
    assert_equal :red, facts.first[:color]
  end

  def test_rule_definition
    kb = KBS::DSL::KnowledgeBase.new
    fired = false

    kb.rule 'test_rule' do
      on :car, color: :red
      perform { |facts| fired = true }
    end

    kb.fact(:car, color: :red)
    kb.run

    assert fired
  end

  def test_multiple_rules
    kb = KBS::DSL::KnowledgeBase.new
    results = []

    kb.rule 'rule1' do
      on :car, color: :red
      perform { |facts| results << :rule1 }
    end

    kb.rule 'rule2' do
      on :car, color: :red
      perform { |facts| results << :rule2 }
    end

    kb.fact(:car, color: :red)
    kb.run

    assert_equal 2, results.size
    assert_includes results, :rule1
    assert_includes results, :rule2
  end

  def test_dsl_entry_point
    kb = KBS.knowledge_base do
      fact :car, color: :red
    end

    assert_instance_of KBS::DSL::KnowledgeBase, kb
    assert_equal 1, kb.engine.working_memory.facts.size
  end

  def test_block_dsl
    result = []

    kb = KBS.knowledge_base do
      rule 'test' do
        on :car, color: :red
        perform { |facts| result << :fired }
      end

      fact :car, color: :red
      run
    end

    assert_equal 1, result.size
  end

  def test_query_facts
    kb = KBS::DSL::KnowledgeBase.new
    kb.fact(:car, color: :red, speed: 100)
    kb.fact(:car, color: :blue, speed: 80)
    kb.fact(:driver, name: "John")

    cars = kb.query(:car)
    assert_equal 2, cars.size

    red_cars = kb.query(:car, color: :red)
    assert_equal 1, red_cars.size
    assert_equal :red, red_cars.first[:color]
  end

  def test_reset_clears_facts_and_state
    result = []

    kb = KBS::DSL::KnowledgeBase.new
    kb.rule 'test_rule' do
      on :car, color: :red
      perform { |facts| result << :fired }
    end

    kb.fact(:car, color: :red)
    kb.run
    assert_equal [:fired], result

    kb.reset
    assert_empty kb.facts, "Facts should be cleared after reset"

    # Rules should still work after reset
    result.clear
    kb.fact(:car, color: :red)
    kb.run
    assert_equal [:fired], result
  end

  def test_reset_prevents_stale_cross_cycle_matches
    result = []

    kb = KBS::DSL::KnowledgeBase.new
    kb.rule 'two_cond' do
      on :domain, name: "code"
      on :tool, name: "eval_tool"
      perform { |facts| result << facts[1][:name] }
    end

    # Cycle 1: both facts present
    kb.assert(:domain, name: "code")
    kb.assert(:tool, name: "eval_tool")
    kb.run
    assert_equal ["eval_tool"], result

    # Cycle 2: reset, assert only tool — should NOT match
    kb.reset
    result.clear

    kb.assert(:tool, name: "eval_tool")
    kb.run
    assert_empty result, "Rule should not fire without domain fact after reset"
  end

  # =========================================================================
  # rule_source / print_rule_source
  # =========================================================================

  def test_rule_source_returns_source_string
    kb = KBS::DSL::KnowledgeBase.new
    kb.rule 'simple' do
      on :car, color: :red
      perform { |facts| }
    end

    source = kb.rule_source('simple')
    assert_includes source, "rule"
    assert_includes source, "simple"
    assert_includes source, "on :car"
    assert_includes source, "perform"
  end

  def test_rule_source_returns_nil_for_unknown_rule
    kb = KBS::DSL::KnowledgeBase.new
    assert_nil kb.rule_source('nonexistent')
  end

  def test_rule_source_captures_negation
    kb = KBS::DSL::KnowledgeBase.new
    kb.rule 'with_negation' do
      on :car, color: :red
      without :alert, type: :warning
      perform { |facts| }
    end

    source = kb.rule_source('with_negation')
    assert_includes source, "without :alert"
  end

  def test_rule_source_captures_nested_blocks
    kb = KBS::DSL::KnowledgeBase.new
    kb.rule 'nested' do
      on :car, color: :red
      perform do |facts|
        puts "fired"
      end
    end

    source = kb.rule_source('nested')
    assert_includes source, "perform do"
    assert_includes source, "puts"
  end

  def test_rule_source_works_via_knowledge_base_block
    kb = KBS.knowledge_base do
      rule 'kb_rule' do
        on :sensor, temp: :high?
        perform { |facts| }
      end
    end

    source = kb.rule_source('kb_rule')
    assert_includes source, "rule"
    assert_includes source, "kb_rule"
    assert_includes source, "on :sensor"
  end

  def test_print_rule_source_outputs_to_stdout
    kb = KBS::DSL::KnowledgeBase.new
    kb.rule 'printable' do
      on :car, color: :red
      perform { |facts| }
    end

    output = capture_io { kb.print_rule_source('printable') }.first
    assert_includes output, "on :car"
  end

  def test_print_rule_source_shows_message_for_unknown_rule
    kb = KBS::DSL::KnowledgeBase.new

    output = capture_io { kb.print_rule_source('missing') }.first
    assert_includes output, "No source available for rule 'missing'"
  end
end
