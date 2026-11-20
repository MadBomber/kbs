# frozen_string_literal: true

require_relative 'test_helper'

# Duplicate rejection, modify, and the guard against changing facts while
# one is being matched. Run against both engines.
module FactLifecycleTests
  def count_rule(name, type, pattern = {})
    fired = (@fired ||= [])
    @engine.add_rule(KBS::Rule.new(name, conditions: [KBS::Condition.new(type, pattern)],
                                         action: ->(facts) { fired << [name, facts.first[:temp]] }))
  end

  # --- duplicates ---

  def test_duplicates_are_allowed_by_default
    count_rule("any", :sensor)

    first = @engine.add_fact(:sensor, id: 1)
    second = @engine.add_fact(:sensor, id: 1)

    assert @engine.fact_duplication
    refute_same first, second
    assert_equal 2, @engine.run
  end

  def test_duplicate_is_refused_when_duplication_is_off
    @engine.fact_duplication = false
    count_rule("any", :sensor)

    first = @engine.add_fact(:sensor, id: 1, temp: 20)
    second = @engine.add_fact(:sensor, id: 1, temp: 20)

    assert_equal first, second
    assert_equal 1, @engine.facts.size
    assert_equal 1, @engine.run
  end

  def test_different_facts_are_both_kept
    @engine.fact_duplication = false

    @engine.add_fact(:sensor, id: 1)
    @engine.add_fact(:sensor, id: 2)
    @engine.add_fact(:alarm, id: 1)

    assert_equal 3, @engine.facts.size
  end

  def test_fact_can_be_added_again_after_it_was_removed
    @engine.fact_duplication = false
    first = @engine.add_fact(:sensor, id: 1)
    @engine.remove_fact(first)

    @engine.add_fact(:sensor, id: 1)

    assert_equal 1, @engine.facts.size
  end

  def test_turning_duplication_off_registers_existing_facts
    existing = @engine.add_fact(:sensor, id: 1)

    @engine.fact_duplication = false

    assert_equal existing, @engine.add_fact(:sensor, id: 1)
    assert_equal existing, @engine.duplicate_of(:sensor, { id: 1 })
  end

  def test_duplicate_of_is_nil_while_duplication_is_on
    @engine.add_fact(:sensor, id: 1)

    assert_nil @engine.duplicate_of(:sensor, { id: 1 })
  end

  def test_reset_forgets_registered_facts
    skip "reset does not clear a blackboard store" if @engine.is_a?(KBS::Blackboard::Engine)
    @engine.fact_duplication = false
    @engine.add_fact(:sensor, id: 1)

    @engine.reset

    assert_nil @engine.duplicate_of(:sensor, { id: 1 })
  end

  # --- modify ---

  def test_modify_matches_the_new_values
    count_rule("hot", :sensor, { temp: ->(t) { t > 30 } })
    fact = @engine.add_fact(:sensor, id: 1, temp: 20)
    assert_equal 0, @engine.run

    modified = @engine.modify(fact, temp: 40)

    assert_equal 40, modified[:temp]
    assert_equal 1, modified[:id]
    assert_equal 1, @engine.run
    assert_equal [["hot", 40]], @fired
  end

  def test_modify_removes_matches_on_the_old_values
    count_rule("hot", :sensor, { temp: ->(t) { t > 30 } })
    fact = @engine.add_fact(:sensor, id: 1, temp: 40)

    @engine.modify(fact, temp: 10)

    assert @engine.agenda.empty?
    assert_equal 0, @engine.run
  end

  def test_modify_reactivates_a_rule_that_already_fired
    count_rule("any", :sensor)
    fact = @engine.add_fact(:sensor, id: 1, temp: 20)
    @engine.run

    @engine.modify(fact, temp: 21)

    assert_equal 1, @engine.run
    assert_equal [["any", 20], ["any", 21]], @fired
  end

  def test_modify_keeps_one_fact_in_working_memory
    fact = @engine.add_fact(:sensor, id: 1, temp: 20)

    @engine.modify(fact, temp: 21)

    assert_equal 1, @engine.facts.size
    assert_equal 21, @engine.facts.first[:temp]
  end

  def test_modify_updates_joins
    fired = []
    @engine.add_rule(KBS::Rule.new(
      "paid",
      conditions: [
        KBS::Condition.new(:order, { id: :id? }),
        KBS::Condition.new(:payment, { order_id: :id? })
      ],
      action: ->(facts) { fired << facts.last[:order_id] }
    ))
    @engine.add_fact(:order, id: 1)
    @engine.add_fact(:order, id: 2)
    payment = @engine.add_fact(:payment, order_id: 9)

    payment = @engine.modify(payment, order_id: 2)
    @engine.run
    @engine.modify(payment, order_id: 1)
    @engine.run

    assert_equal [2, 1], fired
  end

  def test_modify_of_a_fact_not_in_working_memory_returns_nil
    fact = @engine.add_fact(:sensor, id: 1)
    @engine.remove_fact(fact)

    assert_nil @engine.modify(fact, temp: 5)
    assert_empty @engine.facts
  end

  def test_modify_into_a_duplicate_removes_the_fact
    @engine.fact_duplication = false
    kept = @engine.add_fact(:sensor, id: 1, temp: 20)
    changed = @engine.add_fact(:sensor, id: 1, temp: 30)

    result = @engine.modify(changed, temp: 20)

    assert_equal kept, result
    assert_equal 1, @engine.facts.size
  end

  def test_modify_without_a_real_change_is_not_a_duplicate_of_itself
    @engine.fact_duplication = false
    fact = @engine.add_fact(:sensor, id: 1, temp: 20)

    result = @engine.modify(fact, temp: 20)

    assert_equal fact, result
    assert_equal 1, @engine.facts.size
  end

  # --- guard ---

  def test_not_matching_between_operations
    @engine.add_fact(:sensor, id: 1)

    refute @engine.matching?
  end

  def test_adding_a_fact_from_a_pattern_predicate_raises
    engine = @engine
    count_rule("bad", :sensor, { temp: ->(_t) { engine.add_fact(:alarm, {}) } })

    assert_raises(KBS::MatchInProgressError) { @engine.add_fact(:sensor, temp: 1) }
    refute @engine.matching?
  end

  def test_removing_a_fact_from_a_pattern_predicate_raises
    engine = @engine
    other = @engine.add_fact(:other, {})
    count_rule("bad", :sensor, { temp: ->(_t) { engine.remove_fact(other) } })

    assert_raises(KBS::MatchInProgressError) { @engine.add_fact(:sensor, temp: 1) }
  end

  def test_modifying_a_fact_from_a_pattern_predicate_raises
    engine = @engine
    other = @engine.add_fact(:other, {})
    count_rule("bad", :sensor, { temp: ->(_t) { engine.modify(other, x: 1) } })

    assert_raises(KBS::MatchInProgressError) { @engine.add_fact(:sensor, temp: 1) }
  end

  def test_engine_works_again_after_the_guard_raised
    engine = @engine
    armed = true
    count_rule("bad", :sensor, { temp: ->(_t) { engine.add_fact(:alarm, {}) if armed; true } })
    assert_raises(KBS::MatchInProgressError) { @engine.add_fact(:sensor, temp: 1) }

    armed = false
    @engine.add_fact(:sensor, temp: 2)

    assert_operator @engine.run, :>=, 1
  end

  def test_rule_actions_may_change_facts
    engine = @engine
    @engine.add_rule(KBS::Rule.new("react", conditions: [KBS::Condition.new(:sensor, {})],
                                            action: ->(facts) { engine.add_fact(:alarm, {}); engine.remove_fact(facts.first) }))
    @engine.add_fact(:sensor, id: 1)

    assert_equal 1, @engine.run
    assert_equal [:alarm], @engine.facts.map(&:type)
  end

  def test_error_is_a_kbs_error
    assert_operator KBS::MatchInProgressError, :<, KBS::Error
    assert_match(/while a fact is being matched/, KBS::MatchInProgressError.new.message)
  end
end

class TestEngineFactLifecycle < Minitest::Test
  include FactLifecycleTests

  def setup
    @engine = KBS::Engine.new
  end

  def test_fact_duplication_keyword
    refute KBS::Engine.new(fact_duplication: false).fact_duplication
  end

  def test_modify_keeps_the_same_fact_object
    fact = @engine.add_fact(:sensor, id: 1, temp: 20)

    assert_same fact, @engine.modify(fact, temp: 21)
  end

  def test_setting_an_attribute_directly_does_not_rematch
    count_rule("hot", :sensor, { temp: ->(t) { t > 30 } })
    fact = @engine.add_fact(:sensor, id: 1, temp: 20)

    fact[:temp] = 40

    assert_equal 0, @engine.run
  end
end

class TestBlackboardEngineFactLifecycle < Minitest::Test
  include FactLifecycleTests

  def setup
    @engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
  end

  def teardown
    @engine.close
  end

  def test_fact_duplication_keyword
    engine = KBS::Blackboard::Engine.new(fact_duplication: false)

    refute engine.fact_duplication
  ensure
    engine&.close
  end

  def test_duplicate_is_not_written_to_the_store
    @engine.fact_duplication = false
    2.times { @engine.add_fact(:sensor, id: 1) }

    assert_equal 1, @engine.blackboard.get_facts(:sensor).size
  end

  def test_modify_keeps_the_uuid_and_logs_an_update
    fact = @engine.add_fact(:sensor, id: 1, temp: 20)

    modified = @engine.modify(fact, temp: 21)

    assert_equal fact.uuid, modified.uuid
    assert_equal 21, @engine.blackboard.get_facts(:sensor).first[:temp]
    actions = @engine.blackboard.get_history(fact.uuid).map { |entry| entry[:action] }
    assert_includes actions, 'UPDATE'
  end

  def test_modify_accepts_a_uuid
    fact = @engine.add_fact(:sensor, id: 1, temp: 20)

    modified = @engine.modify(fact.uuid, temp: 21)

    assert_equal 21, modified[:temp]
  end

  def test_modify_keeps_symbol_values_that_json_would_change
    fired = []
    @engine.add_rule(KBS::Rule.new("open", conditions: [KBS::Condition.new(:ticket, { status: :open })],
                                           action: ->(facts) { fired << facts.first[:priority] }))
    fact = @engine.add_fact(:ticket, status: :open, priority: 1)
    @engine.run

    @engine.modify(fact, priority: 2)
    @engine.run

    assert_equal [1, 2], fired
  end

  def test_memory_find_fact
    fact = @engine.add_fact(:sensor, id: 1)

    assert_equal fact, @engine.blackboard.find_fact(fact)
    assert_equal fact, @engine.blackboard.find_fact(fact.uuid)
    assert_nil @engine.blackboard.find_fact("missing")
  end

  def test_memory_modify_fact_of_a_missing_fact
    assert_nil @engine.blackboard.modify_fact("missing", { a: 1 })
  end
end

class TestKnowledgeBaseModify < Minitest::Test
  def test_modify
    fired = []
    kb = KBS.knowledge_base do
      rule "hot" do
        on :sensor, temp: greater_than(30)
        perform { |facts| fired << facts.first[:temp] }
      end
    end
    fact = kb.assert(:sensor, temp: 20)

    kb.modify(fact, temp: 35)
    kb.run

    assert_equal [35], fired
  end
end
