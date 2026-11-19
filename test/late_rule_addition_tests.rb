# frozen_string_literal: true


# Regression tests for issue #34: adding a rule after facts exist must not
# replay those facts into alpha memories that already hold them.
module LateRuleAdditionTests
  def counting_rule(name, conditions, counts)
    KBS::Rule.new(name, conditions: conditions, action: ->(_facts) { counts[name] += 1 })
  end

  def test_late_rule_does_not_refire_earlier_rule
    counts = Hash.new(0)
    @engine.add_rule(counting_rule('a', [KBS::Condition.new(:t, {})], counts))
    @engine.add_fact(:t, {})
    @engine.add_rule(counting_rule('b', [KBS::Condition.new(:u, {})], counts))
    @engine.run

    assert_equal 1, counts['a']
    assert_equal 0, counts['b']
    assert_equal 1, @engine.alpha_memories[{ type: :t }].items.size
  end

  def test_late_rule_sharing_an_alpha_memory_fires_once_for_existing_fact
    counts = Hash.new(0)
    @engine.add_rule(counting_rule('a', [KBS::Condition.new(:t, {})], counts))
    @engine.add_fact(:t, {})
    @engine.add_rule(counting_rule('b', [KBS::Condition.new(:t, {})], counts))
    @engine.run

    assert_equal({ 'a' => 1, 'b' => 1 }, counts)
  end

  def test_late_multi_condition_rule_matches_existing_facts_once
    counts = Hash.new(0)
    @engine.add_rule(counting_rule('a', [KBS::Condition.new(:t, {})], counts))
    @engine.add_fact(:t, {})
    @engine.add_fact(:u, {})
    @engine.add_rule(counting_rule('tu', [KBS::Condition.new(:t, {}), KBS::Condition.new(:u, {})], counts))
    @engine.run

    assert_equal({ 'a' => 1, 'tu' => 1 }, counts)
  end

  def test_late_negated_rule_sees_existing_facts
    counts = Hash.new(0)
    @engine.add_fact(:t, {})
    @engine.add_fact(:u, {})
    @engine.add_rule(counting_rule('t_without_u', [KBS::Condition.new(:t, {}), KBS::Condition.new(:u, {}, negated: true)], counts))
    @engine.run

    assert_equal 0, counts['t_without_u']
  end
end
