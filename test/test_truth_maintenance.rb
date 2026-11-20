# frozen_string_literal: true

require_relative 'test_helper'

class TestTruthMaintenance < Minitest::Test
  def setup
    @tms = KBS::TruthMaintenance.new
    @sensor = KBS::Fact.new(:sensor, id: 1)
    @token = KBS::Token.new(nil, @sensor, nil)
    @other_token = KBS::Token.new(nil, KBS::Fact.new(:sensor, id: 2), nil)
    @fact = KBS::Fact.new(:overheating, id: 1)
  end

  def test_fact_without_support_is_unconditional
    refute @tms.supported?(@fact)
    assert_empty @tms.supports_of(@fact)
    assert_equal 0, @tms.size
  end

  def test_support_links_fact_and_token
    @tms.support(@fact, @token)

    assert @tms.supported?(@fact)
    assert_equal [@token], @tms.supports_of(@fact)
    assert_equal [@fact], @tms.dependents_of(@token)
    assert_equal 1, @tms.size
  end

  def test_withdrawing_the_only_support_returns_the_fact
    @tms.support(@fact, @token)

    assert_equal [@fact], @tms.withdraw(@token)
    refute @tms.supported?(@fact)
    assert_empty @tms.dependents_of(@token)
  end

  def test_withdrawing_one_of_two_supports_keeps_the_fact
    @tms.support(@fact, @token)
    @tms.support(@fact, @other_token)

    assert_empty @tms.withdraw(@token)
    assert @tms.supported?(@fact)
    assert_equal [@fact], @tms.withdraw(@other_token)
  end

  def test_withdrawing_an_unknown_token
    assert_empty @tms.withdraw(@token)
  end

  def test_token_supporting_several_facts
    second = KBS::Fact.new(:alarm, id: 1)
    @tms.support(@fact, @token)
    @tms.support(second, @token)

    assert_equal [@fact, second], @tms.withdraw(@token)
  end

  def test_release_makes_a_fact_unconditional
    @tms.support(@fact, @token)

    @tms.release(@fact)

    refute @tms.supported?(@fact)
    assert_empty @tms.withdraw(@token)
  end

  def test_release_of_an_unsupported_fact_is_ignored
    @tms.release(@fact)

    assert_equal 0, @tms.size
  end

  def test_facts_depending_on_a_fact
    @tms.support(@fact, @token)
    @tms.support(KBS::Fact.new(:alarm), @other_token)

    assert_equal [@fact], @tms.facts_depending_on(@sensor)
    assert_empty @tms.facts_depending_on(@fact)
  end

  def test_clear
    @tms.support(@fact, @token)
    @tms.clear

    assert_equal 0, @tms.size
    assert_empty @tms.dependents_of(@token)
  end
end

# Facts asserted by a rule with logical conditions follow the match of
# those conditions. Run against both engines.
module LogicalSupportTests
  def logical(type, pattern = {}, **)
    KBS::Condition.new(type, pattern, logical: true, **)
  end

  def derive_rule(name, conditions, derived_type)
    engine = @engine
    @engine.add_rule(KBS::Rule.new(name, conditions: conditions,
                                         action: ->(facts) { engine.add_fact(derived_type, id: facts.first[:id]) }))
  end

  def types
    @engine.facts.map(&:type).sort
  end

  def test_derived_fact_is_retracted_with_its_support
    derive_rule("hot", [logical(:sensor, { temp: ->(t) { t > 90 } })], :overheating)
    sensor = @engine.add_fact(:sensor, id: 1, temp: 95)
    @engine.run
    assert_equal %i[overheating sensor], types

    @engine.remove_fact(sensor)

    assert_empty @engine.facts
  end

  def test_derived_fact_is_reported_as_supported
    derive_rule("hot", [logical(:sensor)], :overheating)
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run
    derived = @engine.facts.find { |fact| fact.type == :overheating }

    assert @engine.logically_supported?(derived)
    refute @engine.logically_supported?(sensor)
    assert_equal [[sensor]], @engine.dependencies(derived)
    assert_equal [derived], @engine.dependents(sensor)
    assert_empty @engine.dependencies(sensor)
  end

  def test_fact_from_a_rule_without_logical_conditions_stays
    derive_rule("hot", [KBS::Condition.new(:sensor)], :overheating)
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run

    @engine.remove_fact(sensor)

    assert_equal %i[overheating], types
  end

  def test_fact_asserted_outside_a_rule_stays
    derive_rule("hot", [logical(:sensor)], :overheating)
    manual = @engine.add_fact(:overheating, id: 7)
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run

    @engine.remove_fact(sensor)

    assert_equal [manual], @engine.facts
  end

  def test_modify_that_breaks_the_match_retracts_the_derived_fact
    derive_rule("hot", [logical(:sensor, { temp: ->(t) { t > 90 } })], :overheating)
    sensor = @engine.add_fact(:sensor, id: 1, temp: 95)
    @engine.run

    @engine.modify(sensor, temp: 20)

    assert_equal %i[sensor], types
  end

  def test_only_the_logical_conditions_carry_the_support
    derive_rule("hot", [logical(:sensor), KBS::Condition.new(:trigger)], :overheating)
    @engine.add_fact(:sensor, id: 1)
    trigger = @engine.add_fact(:trigger, id: 1)
    @engine.run

    @engine.remove_fact(trigger)

    assert_equal %i[overheating sensor], types
  end

  def test_support_through_a_negated_logical_condition
    derive_rule("unpaid", [logical(:order, { id: :id? }), logical(:payment, { order_id: :id? }, negated: true)], :overdue)
    @engine.add_fact(:order, id: 1)
    @engine.run
    assert_equal %i[order overdue], types

    @engine.add_fact(:payment, order_id: 1)

    assert_equal %i[order payment], types
  end

  def test_derived_facts_cascade
    derive_rule("hot", [logical(:sensor)], :overheating)
    derive_rule("alarm", [logical(:overheating)], :alarm)
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run
    assert_equal %i[alarm overheating sensor], types

    @engine.remove_fact(sensor)

    assert_empty @engine.facts
  end

  def test_one_match_supports_several_facts
    engine = @engine
    @engine.add_rule(KBS::Rule.new("two", conditions: [logical(:sensor)],
                                          action: lambda { |_facts|
                                            engine.add_fact(:a, {})
                                            engine.add_fact(:b, {})
                                          }))
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run

    @engine.remove_fact(sensor)

    assert_empty @engine.facts
  end

  def test_explicitly_retracting_a_derived_fact_forgets_its_support
    derive_rule("hot", [logical(:sensor)], :overheating)
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run
    derived = @engine.facts.find { |fact| fact.type == :overheating }

    @engine.remove_fact(derived)
    @engine.remove_fact(sensor)

    assert_empty @engine.facts
    assert_empty @engine.dependents(sensor)
  end

  def test_with_duplication_off_a_fact_needs_every_support_gone
    @engine.fact_duplication = false
    engine = @engine
    @engine.add_rule(KBS::Rule.new("hot", conditions: [logical(:sensor)],
                                          action: ->(_facts) { engine.add_fact(:alert, level: 1) }))
    first = @engine.add_fact(:sensor, id: 1)
    second = @engine.add_fact(:sensor, id: 2)
    @engine.run
    alert = @engine.facts.find { |fact| fact.type == :alert }
    assert_equal 2, @engine.dependencies(alert).size

    @engine.remove_fact(first)
    assert_includes types, :alert

    @engine.remove_fact(second)
    refute_includes types, :alert
  end

  def test_asserting_a_supported_fact_outside_a_rule_makes_it_unconditional
    @engine.fact_duplication = false
    engine = @engine
    @engine.add_rule(KBS::Rule.new("hot", conditions: [logical(:sensor)],
                                          action: ->(_facts) { engine.add_fact(:alert, level: 1) }))
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run

    alert = @engine.add_fact(:alert, level: 1)
    @engine.remove_fact(sensor)

    refute @engine.logically_supported?(alert)
    assert_equal %i[alert], types
  end

  def test_logical_rule_does_not_take_over_an_unconditional_fact
    @engine.fact_duplication = false
    engine = @engine
    @engine.add_rule(KBS::Rule.new("hot", conditions: [logical(:sensor)],
                                          action: ->(_facts) { engine.add_fact(:alert, level: 1) }))
    @engine.add_fact(:alert, level: 1)
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run

    @engine.remove_fact(sensor)

    assert_equal %i[alert], types
  end

  def test_fact_is_not_asserted_once_the_action_removed_its_own_support
    engine = @engine
    results = []
    @engine.add_rule(KBS::Rule.new("self", conditions: [logical(:sensor)],
                                           action: lambda { |facts|
                                             engine.remove_fact(facts.first)
                                             results << engine.add_fact(:overheating, {})
                                           }))
    @engine.add_fact(:sensor, id: 1)

    @engine.run

    assert_equal [nil], results
    assert_empty @engine.facts
  end

  def test_fact_that_defeats_its_own_support_goes_straight_back_out
    engine = @engine
    @engine.add_rule(KBS::Rule.new("flip", conditions: [logical(:go), logical(:done, {}, negated: true)],
                                           action: ->(_facts) { engine.add_fact(:done, {}) }))
    @engine.add_fact(:go, {})

    assert_equal 5, @engine.run(5)
    assert_equal %i[go], types
  end

  def test_logical_condition_after_a_plain_one_is_rejected
    rule = KBS::Rule.new("bad", conditions: [KBS::Condition.new(:a), logical(:b)])

    error = assert_raises(ArgumentError) { @engine.add_rule(rule) }
    assert_match(/logical conditions must come before/, error.message)
    assert_empty @engine.rules
  end

  def test_reset_forgets_supports
    skip "reset does not clear a blackboard store" if @engine.is_a?(KBS::Blackboard::Engine)
    derive_rule("hot", [logical(:sensor)], :overheating)
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run

    @engine.reset

    assert_empty @engine.dependents(sensor)
    assert_empty @engine.facts
  end
end

class TestEngineLogicalSupport < Minitest::Test
  include LogicalSupportTests

  def setup
    @engine = KBS::Engine.new
  end
end

class TestBlackboardEngineLogicalSupport < Minitest::Test
  include LogicalSupportTests

  def setup
    @engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
  end

  def teardown
    @engine.close
  end

  def test_automatic_retraction_is_written_to_the_store
    derive_rule("hot", [logical(:sensor)], :overheating)
    sensor = @engine.add_fact(:sensor, id: 1)
    @engine.run

    @engine.remove_fact(sensor)

    assert_empty @engine.blackboard.get_facts(:overheating)
  end
end

class TestLogicalRule < Minitest::Test
  def logical(type)
    KBS::Condition.new(type, {}, logical: true)
  end

  def test_condition_flag
    assert KBS::Condition.new(:a, {}, logical: true).logical
    refute KBS::Condition.new(:a).logical
  end

  def test_logical_count_is_the_leading_run
    rule = KBS::Rule.new("r", conditions: [logical(:a), logical(:b), KBS::Condition.new(:c)])

    assert_equal 2, rule.logical_count
    assert rule.logical_conditions_first?
    assert_equal 0, KBS::Rule.new("plain", conditions: [KBS::Condition.new(:c)]).logical_count
  end

  def test_logical_conditions_first
    rule = KBS::Rule.new("r", conditions: [logical(:a), KBS::Condition.new(:b), logical(:c)])

    assert_equal 1, rule.logical_count
    refute rule.logical_conditions_first?
  end

  def test_to_s_wraps_logical_conditions
    rule = KBS::Rule.new("r", conditions: [logical(:a), KBS::Condition.new(:b)])

    assert_equal <<~SOURCE.chomp, rule.to_s
      rule "r" do
        logical do
          on :a
        end
        on :b
      end
    SOURCE
  end

  def test_to_s_when_every_condition_is_logical
    rule = KBS::Rule.new("r", conditions: [logical(:a)])

    assert_equal %(rule "r" do\n  logical do\n    on :a\n  end\nend), rule.to_s
  end

  def test_token_retracted_flag
    token = KBS::Token.new(nil, KBS::Fact.new(:a), nil)

    refute token.retracted?
    token.mark_retracted!
    assert token.retracted?
  end

  def test_beta_memory_tells_its_listener_about_removed_tokens
    memory = KBS::BetaMemory.new
    removed = []
    listener = Object.new
    listener.define_singleton_method(:token_removed) { |token| removed << token }
    memory.listener = listener
    token = KBS::Token.new(nil, KBS::Fact.new(:a), nil)
    memory.add_token(token)

    memory.remove_token(token)

    assert_equal [token], removed
  end
end

class TestLogicalDsl < Minitest::Test
  def test_logical_block_marks_its_conditions
    builder = KBS::DSL::RuleBuilder.new("r")
    builder.logical do
      on :sensor
      without :maintenance
      exists :operator
    end
    builder.on :trigger

    assert_equal [true, true, true, false], builder.conditions.map(&:logical)
    assert_equal 3, builder.build.logical_count
  end

  def test_dsl_rule_with_logical_support
    kb = KBS.knowledge_base
    kb.rule "overheating" do
      logical do
        on :sensor, temp: greater_than(90)
      end
      perform { kb.assert(:overheating) }
    end
    sensor = kb.assert(:sensor, temp: 95)
    kb.run
    assert_equal 2, kb.facts.size

    kb.retract(sensor)

    assert_empty kb.facts
  end

  def test_rule_source_shows_the_logical_block
    kb = KBS.knowledge_base
    kb.instance_eval("rule('r') { logical { on :sensor, id: 1 }; on :trigger }", "(eval)", 1)

    assert_equal <<~SOURCE.chomp, kb.rule_source("r")
      rule "r" do
        logical do
          on :sensor, id: 1
        end
        on :trigger
      end
    SOURCE
  end
end
