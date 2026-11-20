# frozen_string_literal: true

module KBS
  class Engine
    attr_reader :working_memory, :rules, :alpha_memories, :production_nodes, :agenda

    # @param strategy [Symbol] conflict resolution strategy; see KBS::Agenda
    def initialize(strategy: :definition)
      @agenda = Agenda.new(strategy: strategy)
      @halted = false
      @working_memory = WorkingMemory.new
      @rules = []
      @alpha_network = AlphaNetwork.new
      @alpha_memories = @alpha_network.memories
      @fact_memories = {}
      @production_nodes = {}
      @root_beta_memory = BetaMemory.new

      # Add initial dummy token to root beta memory
      # This represents "no conditions matched yet" and allows the first condition to match
      @root_beta_memory.add_token(Token.new(nil, nil, nil))

      @working_memory.add_observer(self)
    end

    def add_rule(rule)
      @rules << rule
      build_network_for_rule(rule)
    end

    def add_fact(type, attributes = {})
      fact = Fact.new(type, attributes)
      @working_memory.add_fact(fact)
      fact
    end

    def remove_fact(fact)
      @working_memory.remove_fact(fact)
    end

    def facts
      @working_memory.facts
    end

    def update(action, fact)
      if action == :add
        match_fact(fact)
      elsif action == :remove
        unmatch_fact(fact)
      end
    end

    # Sends a new fact to every alpha memory whose pattern it matches,
    # and remembers which ones, so that retracting it needs no matching.
    def match_fact(fact)
      memories = matching_alpha_memories(fact)
      return if memories.empty?

      @fact_memories[fact] = memories
      memories.each { |memory| memory.activate(fact) }
    end

    # Takes a fact out of the alpha memories it went into. The fact is
    # not matched again, so this works even if its attributes changed.
    def unmatch_fact(fact)
      memories = @fact_memories.delete(fact)
      memories&.each { |memory| memory.deactivate(fact) }
    end

    # The alpha memories whose pattern `fact` matches.
    def matching_alpha_memories(fact)
      @alpha_network.memories_for(fact)
    end

    # The alpha memories that hold `fact`.
    def alpha_memories_for(fact)
      @fact_memories.fetch(fact, []).dup
    end

    # Fires activations from the agenda until it is empty: the highest
    # priority first, then by the agenda's strategy. Facts that a rule
    # asserts or retracts change the agenda before the next firing, so
    # rules chain within one run. An activation fires once.
    #
    # @param limit [Integer, nil] stop after this many firings
    # @return [Integer] the number of rules fired
    def run(limit = nil)
      @halted = false
      fired = 0

      until @halted || (limit && fired >= limit)
        activation = @agenda.pop
        break unless activation

        fire_activation(activation)
        fired += 1
      end

      fired
    end

    # Stops the current run after the rule that is firing. Call it from a
    # rule action.
    def halt
      @halted = true
    end

    def strategy
      @agenda.strategy
    end

    def strategy=(strategy)
      @agenda.strategy = strategy
    end

    def fire_activation(activation)
      activation.node.fire_rule(activation.token)
    end

    # Production nodes in firing order: higher rule priority first, and
    # definition order among rules of equal priority.
    def prioritized_production_nodes
      @production_nodes.values.sort_by.with_index { |node, index| [-node.rule.priority, index] }
    end

    # Clear all transient RETE state while preserving the compiled rule network.
    #
    # The RETE network has four levels of transient state:
    #   1. WorkingMemory — holds all asserted facts
    #   2. AlphaMemory   — holds facts matching each pattern
    #   3. BetaMemory    — holds tokens from condition joins
    #   4. ProductionNode — holds tokens ready to fire
    #
    # Simply clearing working memory facts doesn't cascade reliably
    # through intermediate beta memories. Stale tokens in beta memories
    # cause false matches when new facts are asserted on the next cycle.
    #
    # This method clears all four levels directly while preserving the
    # root beta memory's dummy token (needed for first-condition joins).
    def reset
      # 1. Clear working memory directly (bypass observer — we clear everything)
      @working_memory.clear if @working_memory.respond_to?(:clear)
      @fact_memories.clear

      # 2. Clear alpha memories and their downstream beta memories
      @alpha_memories.each_value do |alpha_mem|
        alpha_mem.clear

        # Each alpha memory successor is a JoinNode or NegationNode.
        # Their successors are intermediate BetaMemory nodes.
        # The root beta memory is never a join node successor, so
        # its dummy token is preserved.
        alpha_mem.successors.each do |join_node|
          join_node.reset if join_node.respond_to?(:reset)
          next unless join_node.respond_to?(:successors)
          join_node.successors.each do |beta_or_prod|
            beta_or_prod.clear if beta_or_prod.is_a?(BetaMemory)
          end
        end
      end

      # 3. Clear production node tokens and their pending activations
      @production_nodes.each_value(&:reset)
      @agenda.clear

      # 4. Clear stale child references from the root dummy token
      @root_beta_memory.each_token { |t| t.clear_children }

      # 5. Restore leading negation matches for the now-empty working memory
      @root_beta_memory.successors.grep(NegationNode).each do |node|
        @root_beta_memory.tokens.each { |token| node.left_activate(token) }
      end
    end

    private

    def build_network_for_rule(rule)
      current_beta = @root_beta_memory

      join_tests = JoinTestBuilder.new(rule.conditions).tests

      rule.conditions.each_with_index do |condition, index|
        # Build alpha memory pattern - merge condition type
        pattern = condition.pattern.merge(type: condition.type)
        alpha_memory = get_or_create_alpha_memory(pattern)
        tests = join_tests[index]

        node = node_class_for(condition).new(alpha_memory, current_beta, tests)
        new_beta = BetaMemory.new
        node.successors << new_beta
        current_beta.tokens.each { |token| node.left_activate(token) }
        current_beta = new_beta
      end

      production_node = ProductionNode.new(rule, @agenda, order: @rules.size)
      current_beta.successors << production_node
      @production_nodes[rule.name] = production_node
      unless rule.conditions.empty?
        current_beta.tokens.each { |token| production_node.activate(token) }
      end
    end

    def node_class_for(condition)
      return NegationNode if condition.negated
      return ExistsNode if condition.exists

      JoinNode
    end

    # A new alpha memory starts with the facts already in working memory.
    # Facts go straight into its items: the memory has no successors yet,
    # and existing alpha memories already hold their facts.
    def get_or_create_alpha_memory(pattern)
      @alpha_network.fetch(pattern) do |memory|
        @working_memory.facts.each do |fact|
          next unless fact.matches?(pattern)

          memory.add_item(fact)
          (@fact_memories[fact] ||= []) << memory
        end
      end
    end
  end
end
