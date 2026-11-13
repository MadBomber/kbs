# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs'

class TestDSLKnowledgeBase < Minitest::Test
  def test_initialization
    kb = KBS::DSL::KnowledgeBase.new

    assert_instance_of KBS::DSL::KnowledgeBase, kb
    assert_instance_of KBS::Engine, kb.engine
  end

  def test_knowledge_base_uses_passed_engine
    engine = KBS::Engine.new
    kb = KBS.knowledge_base(engine: engine)

    assert_same engine, kb.engine
  end

  def test_knowledge_base_with_blackboard_engine_fires_rules
    engine = KBS::Blackboard::Engine.new
    fired = []
    hot_sensor_knowledge_base(engine, fired).run

    assert_equal [28], fired
    assert_equal 2, engine.blackboard.get_facts(:sensor).size
  end

  def test_initialization_with_engine
    engine = KBS::Engine.new
    kb = KBS::DSL::KnowledgeBase.new(engine: engine)

    assert_same engine, kb.engine
  end

  def test_nil_engine_uses_default
    assert_instance_of KBS::Engine, KBS::DSL::KnowledgeBase.new(engine: nil).engine
    assert_instance_of KBS::Engine, KBS.knowledge_base(engine: nil).engine
  end

  def test_dsl_entry_point_without_block
    kb = KBS.knowledge_base

    assert_instance_of KBS::DSL::KnowledgeBase, kb
    assert_instance_of KBS::Engine, kb.engine
  end

  def test_rule_priority_keyword_sets_rule_priority
    kb = KBS::DSL::KnowledgeBase.new
    kb.rule("urgent", priority: 100) { on :alarm }

    assert_equal 100, kb.rules["urgent"].priority
  end

  def test_rule_priority_in_block_overrides_keyword
    kb = KBS::DSL::KnowledgeBase.new
    kb.rule("urgent", priority: 100) do
      priority 5
      on :alarm
    end

    assert_equal 5, kb.rules["urgent"].priority
  end

  def test_defrule_passes_priority_keyword
    kb = KBS::DSL::KnowledgeBase.new
    kb.defrule("urgent", priority: 50) { on :alarm }

    assert_equal 50, kb.rules["urgent"].priority
  end

  def test_rule_priority_keyword_inside_knowledge_base_block
    fired = []
    kb = KBS.knowledge_base do
      rule "urgent", priority: 100 do
        on :alarm
        perform { fired << :urgent }
      end
      fact :alarm
      run
    end

    assert_equal 100, kb.rules["urgent"].priority
    assert_equal [:urgent], fired
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

  def test_leading_negation_fires_once_on_empty_memory
    fired = 0
    kb = KBS.knowledge_base do
      rule 'no_critical' do
        without :alert, level: "critical"
        perform { fired += 1 }
      end
    end

    2.times { kb.run }

    assert_equal 1, fired
  end

  def test_leading_negation_is_blocked_by_matching_fact
    [true, false].each do |fact_before_rule|
      fired = 0
      kb = KBS::DSL::KnowledgeBase.new
      blocker = kb.fact(:alert, level: "critical") if fact_before_rule
      kb.rule 'no_critical' do
        without :alert, level: "critical"
        perform { fired += 1 }
      end
      blocker = kb.fact(:alert, level: "critical") unless fact_before_rule
      second_blocker = kb.fact(:alert, level: "critical")

      kb.run

      assert_equal 0, fired

      kb.retract(blocker)
      kb.run
      assert_equal 0, fired

      kb.retract(second_blocker)
      kb.run
      assert_equal 1, fired
    end
  end

  def test_leading_negation_followed_by_positive_condition
    result = []
    kb = KBS.knowledge_base do
      rule 'signal_without_critical' do
        without :alert, level: "critical"
        on :signal
        perform { |facts| result << facts.map(&:type) }
      end
    end

    kb.run
    assert_empty result

    kb.fact(:signal)
    kb.run
    assert_equal [[:signal]], result

    kb.reset
    kb.fact(:signal)
    kb.fact(:alert, level: "critical")
    kb.run
    assert_equal [[:signal]], result
  end

  def test_leading_negation_ignores_nonmatching_facts
    fired = 0
    kb = KBS.knowledge_base do
      fact :alert, level: "warning"
      rule 'no_critical' do
        without :alert, level: "critical"
        perform { fired += 1 }
      end
    end

    kb.run

    assert_equal 1, fired
  end

  def test_leading_negation_fires_again_after_reset
    fired = 0
    kb = KBS.knowledge_base do
      rule 'no_critical' do
        without :alert, level: "critical"
        perform { fired += 1 }
      end
    end

    kb.run
    assert_equal 1, fired

    2.times do
      kb.reset
      kb.fact(:alert, level: "critical")
      kb.run
      assert_equal 1, fired
    end

    kb.reset
    kb.run
    kb.run
    assert_equal 2, fired
  end

  def test_consecutive_leading_negations
    fired = 0
    kb = KBS.knowledge_base do
      rule 'no_alerts' do
        without :alert, level: "critical"
        without :problem
        perform { fired += 1 }
      end
    end

    kb.run
    assert_equal 1, fired

    kb.reset
    kb.fact(:alert, level: "critical")
    kb.run
    assert_equal 1, fired

    kb.reset
    kb.fact(:problem)
    kb.run
    assert_equal 1, fired

    kb.reset
    kb.run
    assert_equal 2, fired
  end

  def test_leading_negation_preserves_other_rule_tokens
    results = []
    kb = KBS.knowledge_base do
      rule 'has_signal' do
        on :signal
        perform { results << :signal }
      end
      rule 'no_critical' do
        without :alert, level: "critical"
        perform { results << :no_critical }
      end
      rule 'no_problem' do
        without :problem
        perform { results << :no_problem }
      end
      fact :signal
      fact :alert, level: "critical"
    end

    kb.run
    assert_equal [:signal, :no_problem], results

    kb.retract(kb.query(:signal).first)
    assert_empty kb.engine.production_nodes['has_signal'].tokens

    results.clear
    kb.reset
    kb.run
    assert_equal [:no_critical, :no_problem], results
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

  # =========================================================================
  # Dynamic rule reconstruction (no source file)
  # =========================================================================

  def test_dynamic_rule_reconstruction
    kb = KBS::DSL::KnowledgeBase.new

    # Build a rule programmatically (simulating dynamic creation)
    builder = KBS::DSL::RuleBuilder.new("dynamic_rule")
    builder.on :sensor, temp: :high
    builder.perform { |facts| puts "alert" }
    rule = builder.build
    kb.instance_variable_get(:@rule_builders)["dynamic_rule"] = builder
    kb.instance_variable_get(:@rules)["dynamic_rule"] = rule
    kb.engine.add_rule(rule)

    # No source_location stored — forces reconstruction
    source = kb.rule_source("dynamic_rule")
    assert_includes source, 'rule "dynamic_rule" do'
    assert_includes source, "on :sensor"
    assert_includes source, "temp: :high"
    assert_includes source, "perform"
  end

  def test_dynamic_rule_with_proc_condition
    kb = KBS::DSL::KnowledgeBase.new

    builder = KBS::DSL::RuleBuilder.new("threshold")
    builder.on :reading, value: ->(v) { v > 100 }
    builder.perform { |facts| }
    rule = builder.build
    kb.instance_variable_get(:@rule_builders)["threshold"] = builder
    kb.instance_variable_get(:@rules)["threshold"] = rule
    kb.engine.add_rule(rule)

    source = kb.rule_source("threshold")
    assert_includes source, "rule"
    assert_includes source, "value:"
    # The decompiler should reconstruct the lambda
    assert_includes source, "v > 100"
  end

  def test_dynamic_rule_with_negation
    kb = KBS::DSL::KnowledgeBase.new

    builder = KBS::DSL::RuleBuilder.new("safe_check")
    builder.on :system, status: :running
    builder.without :alert, level: :critical
    builder.perform { |facts| }
    rule = builder.build
    kb.instance_variable_get(:@rule_builders)["safe_check"] = builder
    kb.instance_variable_get(:@rules)["safe_check"] = rule
    kb.engine.add_rule(rule)

    source = kb.rule_source("safe_check")
    assert_includes source, "on :system"
    assert_includes source, "without :alert"
    assert_includes source, "level: :critical"
  end

  def test_dynamic_rule_with_description_and_priority
    kb = KBS::DSL::KnowledgeBase.new

    builder = KBS::DSL::RuleBuilder.new("important")
    builder.desc "A high-priority rule"
    builder.priority 10
    builder.on :event, kind: :urgent
    builder.perform { |facts| }
    rule = builder.build
    kb.instance_variable_get(:@rule_builders)["important"] = builder
    kb.instance_variable_get(:@rules)["important"] = rule
    kb.engine.add_rule(rule)

    source = kb.rule_source("important")
    assert_includes source, 'desc "A high-priority rule"'
    assert_includes source, "priority 10"
  end

  private

  def hot_sensor_knowledge_base(engine, fired)
    KBS.knowledge_base(engine: engine) do
      rule 'hot' do
        on :sensor, value: greater_than(25)
        perform { |facts| fired << facts.first[:value] }
      end
      fact :sensor, value: 22
      fact :sensor, value: 28
    end
  end
end
