# frozen_string_literal: true

module KBS
  # What the engine can tell about itself while it runs, as CLIPS `watch`
  # and `matches` do. Included in KBS::Engine, whose tracer, agenda, rule
  # paths and network it reads.
  module Introspection
    # Starts writing a line for each change to the watched items, or to
    # every item when none is given: :facts, :activations, :rules. Lines
    # go to #trace_output, $stdout by default. See KBS::Tracer.
    def watch(*items)
      @tracer.watch(*items)
      listen_to_agenda
      self
    end

    def unwatch(*items)
      @tracer.unwatch(*items)
      listen_to_agenda
      self
    end

    # The agenda reports to the tracer only while activations are
    # watched, so an unwatched engine pays nothing for it.
    def listen_to_agenda
      @agenda.listener = @tracer.watching?(:activations) ? @tracer : nil
    end

    def trace_output
      @tracer.output
    end

    def trace_output=(output)
      @tracer.output = output
    end

    # How far each condition of a rule has matched: the facts that fit
    # the condition on its own, and the partial matches of the rule up to
    # and including it. The first condition whose partial_matches is zero
    # is the one that keeps the rule from firing.
    #
    # @return [Hash, nil] { rule:, conditions: [{ keyword:, type:,
    #   alpha_matches:, partial_matches: }], matches:, activations: };
    #   nil for an unknown rule
    def matches(rule_name)
      path = @rule_paths[rule_name]
      return nil unless path

      node = @production_nodes[rule_name]
      tokens = node.tokens
      {
        rule: rule_name,
        conditions: path.map(&:matches),
        matches: tokens.size,
        activations: tokens.count { |token| !node.fired?(token) }
      }
    end

    # The work each condition of a rule has cost so far. See
    # KBS::JoinIndexing::Activity. Rules that share a node report the
    # same counts for it.
    #
    # @return [Array<Hash>, nil] one Hash per condition; nil for an
    #   unknown rule
    def join_activity(rule_name)
      @rule_paths[rule_name]&.map(&:activity)
    end

    def reset_join_activity
      @beta_nodes.each(&:reset_activity)
    end

    # The size of the network and of what it holds.
    def network_stats
      {
        rules: @rules.size,
        facts: @working_memory.facts.size,
        alpha_memories: @alpha_memories.size,
        beta_nodes: @beta_nodes.size,
        conditions: @rules.sum { |rule| rule.conditions.size },
        partial_matches: @beta_nodes.sum { |node| node.successors.grep(BetaMemory).sum(&:size) },
        activations: @agenda.size
      }
    end

    # Every join, negation and exists node in the network. Rules that
    # start with the same conditions share nodes, so there can be fewer
    # nodes than conditions.
    def beta_nodes
      @beta_nodes.dup
    end
  end
end
