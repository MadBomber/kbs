# frozen_string_literal: true

require_relative 'test_helper'

class TestRuleSource < Minitest::Test
  def source(conditions: [], **)
    KBS::RuleSource.new(name: "r", conditions: conditions, **)
  end

  def test_empty_rule
    assert_equal %(rule "r" do\nend), source.to_s
  end

  def test_header_lines
    assert_empty source.header_lines
    assert_equal ['  desc "why"', "  priority 5"], source(description: "why", priority: 5).header_lines
  end

  def test_condition_lines_without_logical_conditions
    conditions = [KBS::Condition.new(:a, { id: 1 }), KBS::Condition.new(:b, {}, negated: true)]

    assert_equal ["  on :a, id: 1", "  without :b"], source(conditions: conditions).condition_lines
  end

  def test_condition_lines_wrap_the_logical_conditions
    conditions = [KBS::Condition.new(:a, {}, logical: true), KBS::Condition.new(:b)]

    assert_equal ["  logical do", "    on :a", "  end", "  on :b"], source(conditions: conditions).condition_lines
  end

  def test_action_lines
    assert_empty source.action_lines
    assert_equal ["  perform { |n| n + 1 }"], source(action: ->(n) { n + 1 }).action_lines
  end

  def test_condition_line
    condition = KBS::Condition.new(:a, { id: 1 }, exists: true)

    assert_equal "    exists :a, id: 1", KBS::RuleSource.condition_line(condition, "    ")
  end

  def test_pattern_source
    assert_equal "", KBS::RuleSource.pattern_source({})
    assert_equal "id: 1, name: \"x\"", KBS::RuleSource.pattern_source({ id: 1, name: "x" })
  end

  def test_value_source
    assert_equal ":x?", KBS::RuleSource.value_source(:x?)
    assert_equal "->(v) { v > 1 }", KBS::RuleSource.value_source(->(v) { v > 1 })
    assert_match(/\A<decompilation failed: .+>\z/, KBS::RuleSource.value_source(:even?.to_proc))
  end

  def test_block_source
    assert_equal "{ |n| n + 1 }", KBS::RuleSource.block_source(->(n) { n + 1 })
    assert_match(/\A\{ <decompilation failed: .+> \}\z/, KBS::RuleSource.block_source(:even?.to_proc))
  end
end
