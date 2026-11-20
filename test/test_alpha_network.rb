# frozen_string_literal: true

require_relative 'test_helper'

class TestAlphaNetwork < Minitest::Test
  def setup
    @network = KBS::AlphaNetwork.new
  end

  def patterns(memories)
    memories.map(&:pattern)
  end

  def test_selector_is_the_first_constant_attribute
    assert_equal [:code, 5], KBS::AlphaNetwork.selector({ type: :event, code: 5, level: "high" })
    assert_equal [:level, "high"], KBS::AlphaNetwork.selector({ type: :event, code: :c?, level: "high" })
  end

  def test_selector_skips_type_variables_and_procs
    assert_nil KBS::AlphaNetwork.selector({ type: :event })
    assert_nil KBS::AlphaNetwork.selector({ type: :event, code: :c?, level: ->(v) { v > 1 } })
  end

  def test_selector_normalizes_numbers
    assert KBS::AlphaNetwork.selector({ type: :event, code: 5.0 }).last.eql?(5)
  end

  def test_selector_accepts_nil_as_a_constant
    assert_equal [:code, nil], KBS::AlphaNetwork.selector({ type: :event, code: nil })
  end

  def test_fetch_creates_one_memory_per_pattern
    first = @network.fetch({ type: :event, code: 1 })
    again = @network.fetch({ type: :event, code: 1 })

    assert_same first, again
    assert_equal 1, @network.memories.size
    assert_same first, @network.memories[{ type: :event, code: 1 }]
  end

  def test_fetch_yields_only_a_new_memory
    yielded = []
    2.times { @network.fetch({ type: :event }) { |memory| yielded << memory } }

    assert_equal 1, yielded.size
  end

  def test_candidates_are_limited_to_the_fact_type
    @network.fetch({ type: :event })
    @network.fetch({ type: :order })

    candidates = @network.candidates_for(KBS::Fact.new(:event, code: 1))

    assert_equal [{ type: :event }], patterns(candidates)
  end

  def test_candidates_are_limited_to_the_matching_constant
    100.times { |code| @network.fetch({ type: :event, code: code }) }

    candidates = @network.candidates_for(KBS::Fact.new(:event, code: 42))

    assert_equal [{ type: :event, code: 42 }], patterns(candidates)
  end

  def test_candidates_include_memories_without_a_constant
    @network.fetch({ type: :event, code: 1 })
    @network.fetch({ type: :event, level: ->(v) { v > 3 } })
    @network.fetch({ type: :event, code: :c? })

    candidates = @network.candidates_for(KBS::Fact.new(:event, code: 2, level: 9))

    assert_equal 2, candidates.size
    refute_includes patterns(candidates), { type: :event, code: 1 }
  end

  def test_candidates_cover_every_selector_attribute
    @network.fetch({ type: :event, code: 1 })
    @network.fetch({ type: :event, level: "high" })

    candidates = @network.candidates_for(KBS::Fact.new(:event, code: 1, level: "high"))

    assert_equal 2, candidates.size
  end

  def test_no_candidates_for_an_unknown_type
    @network.fetch({ type: :event })

    assert_empty @network.candidates_for(KBS::Fact.new(:other))
  end

  def test_memories_for_checks_the_rest_of_the_pattern
    @network.fetch({ type: :event, code: 1, level: "high" })

    assert_empty @network.memories_for(KBS::Fact.new(:event, code: 1, level: "low"))
    assert_equal 1, @network.memories_for(KBS::Fact.new(:event, code: 1, level: "high")).size
  end

  def test_memories_for_come_back_in_creation_order
    @network.fetch({ type: :event, level: "high" })
    @network.fetch({ type: :event })
    @network.fetch({ type: :event, code: 1 })

    memories = @network.memories_for(KBS::Fact.new(:event, code: 1, level: "high"))

    assert_equal [{ type: :event, level: "high" }, { type: :event }, { type: :event, code: 1 }], patterns(memories)
  end

  def test_constant_matches_an_equal_number_of_another_class
    @network.fetch({ type: :event, code: 1 })

    assert_equal 1, @network.memories_for(KBS::Fact.new(:event, code: 1.0)).size
  end

  def test_nil_constant_matches_a_fact_without_the_attribute
    @network.fetch({ type: :event, code: nil })

    assert_equal 1, @network.memories_for(KBS::Fact.new(:event)).size
    assert_empty @network.memories_for(KBS::Fact.new(:event, code: 1))
  end

  def test_untyped_pattern_is_a_candidate_for_every_fact
    @network.fetch({ code: 1 })

    assert_equal 1, @network.memories_for(KBS::Fact.new(:event, code: 1)).size
    assert_equal 1, @network.memories_for(KBS::Fact.new(:order, code: 1)).size
    assert_empty @network.memories_for(KBS::Fact.new(:order, code: 2))
  end
end

class TestEngineAlphaNetwork < Minitest::Test
  def setup
    @engine = KBS::Engine.new
    @fired = []
  end

  def add_rule(name, pattern)
    fired = @fired
    @engine.add_rule(KBS::Rule.new(name, conditions: [KBS::Condition.new(:event, pattern)],
                                         action: ->(_facts) { fired << name }))
  end

  def test_fact_fires_only_the_rules_for_its_constant
    50.times { |code| add_rule("code_#{code}", { code: code }) }

    @engine.add_fact(:event, code: 7)
    @engine.run

    assert_equal ["code_7"], @fired
  end

  def test_constant_predicate_and_variable_rules_together
    add_rule("constant", { code: 7 })
    add_rule("predicate", { code: ->(v) { v > 5 } })
    add_rule("variable", { code: :code? })
    add_rule("any", {})

    @engine.add_fact(:event, code: 7)
    @engine.run

    assert_equal %w[constant predicate variable any], @fired
  end

  def test_alpha_memories_reader_still_lists_every_memory
    add_rule("a", { code: 1 })
    add_rule("b", { code: 2 })

    assert_equal [{ code: 1, type: :event }, { code: 2, type: :event }], @engine.alpha_memories.keys
  end

  def test_user_attribute_named_type_still_matches
    fired = @fired
    @engine.add_rule(KBS::Rule.new("temp", conditions: [KBS::Condition.new(:sensor, { type: "temperature" })],
                                           action: ->(_facts) { fired << "temp" }))

    @engine.add_fact(:sensor, type: "temperature")
    @engine.add_fact(:sensor, type: "humidity")
    @engine.run

    assert_equal ["temp"], @fired
  end

  def test_late_rule_with_a_constant_sees_existing_facts
    @engine.add_fact(:event, code: 3)
    add_rule("late", { code: 3 })

    @engine.run

    assert_equal ["late"], @fired
  end
end
