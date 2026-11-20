# frozen_string_literal: true

require_relative 'test_helper'

# KBS::RuleStep reports one condition of a rule as built into the network.
class TestRuleStep < Minitest::Test
  # A stand-in for a join node: just the parts a step reads.
  Node = Struct.new(:indexed?, :activity)

  def step(node: Node.new(true, KBS::JoinIndexing::Activity.new(1, 2, 3, 4)))
    alpha = KBS::AlphaMemory.new({ type: :order })
    alpha.add_item(KBS::Fact.new(:order, id: 1))
    beta = KBS::BetaMemory.new
    KBS::RuleStep.new(KBS::Condition.new(:order, { id: :id? }), alpha, node, beta)
  end

  def test_matches_reports_the_condition_and_memory_sizes
    assert_equal({ keyword: "on", type: :order, alpha_matches: 1, partial_matches: 0 }, step.matches)
  end

  def test_activity_reports_the_condition_and_node_counts
    expected = { keyword: "on", type: :order, indexed: true,
                 left_activations: 1, right_activations: 2, comparisons: 3, matches: 4 }

    assert_equal expected, step.activity
  end
end

# KBS::Tracer.validated checks the items given to watch and unwatch.
class TestTracerValidated < Minitest::Test
  def test_no_items_means_every_item
    assert_equal KBS::Tracer::ITEMS, KBS::Tracer.validated([])
  end

  def test_known_items_are_returned
    assert_equal %i[facts rules], KBS::Tracer.validated(%i[facts rules])
  end

  def test_unknown_item_raises
    error = assert_raises(ArgumentError) { KBS::Tracer.validated(%i[facts bogus]) }

    assert_includes error.message, ":bogus"
  end
end
