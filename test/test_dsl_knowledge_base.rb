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

  # Issue #64: the docs call kb.close.
  def test_close_closes_a_blackboard_engine
    engine = KBS::Blackboard::Engine.new
    KBS.knowledge_base(engine: engine).close
    assert engine.blackboard.store.db.closed?

    KBS.knowledge_base.close
  end

  # Issue #58: print_rules used to show helpers as raw Proc objects.
  def test_print_rules_renders_condition_helpers
    kb = KBS.knowledge_base do
      rule 'hot' do
        on :temperature, value: greater_than(80), location: "lab"
        perform {}
      end
    end

    assert_output(/1\. temperature\(value: ->\(v\) \{ v > 80 \}, location: "lab"\)$/) { kb.print_rules }
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
      perform { |_facts| fired = true }
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
      perform { |_facts| results << :rule1 }
    end

    kb.rule 'rule2' do
      on :car, color: :red
      perform { |_facts| results << :rule2 }
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
    assert_equal %i[signal no_problem], results

    kb.retract(kb.query(:signal).first)
    assert_empty kb.engine.production_nodes['has_signal'].tokens

    results.clear
    kb.reset
    kb.run
    assert_equal %i[no_critical no_problem], results
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

    KBS.knowledge_base do
      rule 'test' do
        on :car, color: :red
        perform { |_facts| result << :fired }
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
      perform { |_facts| result << :fired }
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
      perform do |_facts|
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
    builder.perform { |_facts| puts "alert" }
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

  # Issue #65: a helper or ?variable on a user attribute named `type`
  # never matched, and a negated one never blocked.
  def test_helper_and_variable_on_type_attribute
    fired = []
    KBS.knowledge_base do
      rule('helper') do
        on :sensor, type: one_of('temperature')
        perform { |f| fired << [:helper, f.first[:type]] }
      end
      rule('variable') do
        on :sensor, type: :t?
        perform { |_f, b| fired << [:variable, b[:t?]] }
      end
      rule('blocked') do
        on :go
        without :sensor, type: one_of('temperature')
        perform { fired << :blocked }
      end
      rule('literal') do
        on :sensor, type: 'humidity'
        perform { fired << :literal }
      end
      fact :go
      fact :sensor, type: 'temperature'
      run
    end

    assert_equal [[:helper, 'temperature'], [:variable, 'temperature']], fired.sort
  end

  # Contract: dsl/perform-working-memory-calls
  # Bug: bare `fact`/`retract`/`modify` in perform added a condition or raised NoMethodError, not changing working memory
  def test_bare_working_memory_calls_in_perform_change_working_memory
    kb = KBS.knowledge_base do
      rule "triage" do
        on :reading, value: :v?
        on :stale
        perform do |facts|
          reading, stale = facts
          fact :alert, level: reading[:value]
          modify reading, value: 0
          retract stale
        end
      end
      fact :reading, value: 99
      fact :stale
    end

    kb.run

    assert_equal [[:alert, { level: 99 }], [:reading, { value: 0 }]], kb.facts.map { [it.type, it.attributes] }.sort_by(&:first)
    assert_equal 2, kb.rules["triage"].conditions.size
  end

  # Contract: dsl/perform-working-memory-calls
  # Bug: a bare `assert` or `query` in a perform block raised NoMethodError
  def test_bare_assert_and_query_in_perform_reach_the_knowledge_base
    kb = KBS.knowledge_base do
      rule "count" do
        on :go
        perform { assert :counted, n: query(:item).size }
      end
      fact :item
      fact :item
      fact :go
    end

    kb.run

    assert_equal [{ n: 2 }], kb.query(:counted).map(&:attributes)
  end

  # Contract: dsl/perform-working-memory-calls
  # Bug: a bare `assert` in a logical rule's perform block raised NoMethodError, so it got no logical support
  def test_bare_assert_in_perform_gets_logical_support
    kb = KBS.knowledge_base do
      rule "overheating" do
        logical { on :sensor, temp: greater_than(90) }
        perform { assert :overheating }
      end
    end
    sensor = kb.fact(:sensor, temp: 95)
    kb.run
    overheating = kb.query(:overheating).first

    assert kb.engine.logically_supported?(overheating)
    kb.retract(sensor)
    assert_empty kb.query(:overheating)
  end

  # Contract: dsl/perform-working-memory-calls
  # Bug: `kb.fact` from an action must keep working alongside the bare forms
  def test_kb_fact_from_perform_still_works
    kb = KBS.knowledge_base do
      kb = self
      rule("derive") do
        on(:a)
        perform { kb.fact :b }
      end
      fact :a
    end

    kb.run

    assert_equal 1, kb.query(:b).size
  end

  # Contract: dsl/rule-built-guard
  # Bug: a condition keyword called after the rule was built silently changed the builder and never the rule
  def test_condition_keywords_after_build_raise
    kb = KBS::DSL::KnowledgeBase.new
    builder = kb.rule("r") { on :a }

    %i[on given matches without exists absent missing lacks].each do |keyword|
      assert_raises(KBS::RuleBuiltError, keyword.to_s) { builder.public_send(keyword, :b) }
    end
    assert_raises(KBS::RuleBuiltError) { builder.logical { on :b } }
    assert_raises(KBS::RuleBuiltError) { builder.perform { nil } }
    assert_equal 1, kb.rules["r"].conditions.size
  end

  # Contract: dsl/rule-built-guard
  # Bug: `on` inside a perform block silently added a condition to the built rule
  def test_condition_keyword_inside_perform_raises_during_run
    kb = KBS.knowledge_base do
      rule("r") do
        on(:a)
        perform { on :b }
      end
      fact :a
    end

    error = assert_raises(KBS::RuleBuiltError) { kb.run }
    assert_match(/"r"/, error.message)
  end

  # Contract: dsl/perform-working-memory-calls
  # Bug: a working-memory call on a builder with no knowledge base raised NoMethodError
  def test_working_memory_call_without_knowledge_base_raises_clear_error
    builder = KBS::DSL::RuleBuilder.new("r")
    builder.on(:a)
    builder.build

    assert_raises(KBS::NoKnowledgeBaseError) { builder.fact(:b) }
    assert_raises(KBS::NoKnowledgeBaseError) { builder.assert(:b) }
  end

  # Contract: dsl/knowledge-base-condition-helpers
  # Bug: KnowledgeBase did not include ConditionHelpers, so kb.query(:t, value: greater_than(80)) raised NoMethodError
  def test_query_accepts_condition_helpers
    kb = KBS.knowledge_base do
      fact :t, value: 95
      fact :t, value: 50
    end

    assert_equal([95], kb.query(:t, value: kb.greater_than(80)).map { it[:value] })
    assert_equal([50], kb.instance_eval { query(:t, value: between(40, 60)) }.map { it[:value] })
  end

  # Contract: dsl/knowledge-base-condition-helpers
  # Bug: query must apply a lambda pattern value as a predicate
  def test_query_applies_lambda_values
    kb = KBS::DSL::KnowledgeBase.new
    kb.fact(:t, value: 95)
    kb.fact(:t, value: 50)

    assert_equal([50], kb.query(:t, value: ->(v) { v < 60 }).map { it[:value] })
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
