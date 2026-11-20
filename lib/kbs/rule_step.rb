# frozen_string_literal: true

module KBS
  # One condition of a rule as built into the network: the condition, the
  # alpha memory of the facts that fit it, the node that joins it, and the
  # beta memory of the partial matches up to and including it. The engine
  # keeps one per condition of each rule for Engine#matches and
  # Engine#join_activity.
  RuleStep = Data.define(:condition, :alpha_memory, :node, :beta_memory) do
    # How far the rule has matched at this condition.
    def matches
      { **label, alpha_matches: alpha_memory.size, partial_matches: beta_memory.size }
    end

    # The work this condition's node has done. Rules that share the node
    # report the same counts.
    def activity
      { **label, indexed: node.indexed?, **node.activity.to_h }
    end

    private

    def label
      { keyword: condition.keyword, type: condition.type }
    end
  end
end
