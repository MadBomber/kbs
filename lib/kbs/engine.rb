# frozen_string_literal: true

module KBS
  class Engine
    attr_reader :working_memory, :rules, :alpha_memories, :production_nodes

    def initialize
      @working_memory = WorkingMemory.new
      @rules = []
      @alpha_memories = {}
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

    def update(action, fact)
      if action == :add
        @alpha_memories.each do |pattern, memory|
          memory.activate(fact) if fact.matches?(pattern)
        end
      elsif action == :remove
        @alpha_memories.each do |pattern, memory|
          memory.deactivate(fact) if fact.matches?(pattern)
        end
      end
    end

    def run
      @production_nodes.values.each do |node|
        node.tokens.each do |token|
          node.fire_rule(token)
        end
      end
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
      @working_memory.facts.clear

      # 2. Clear alpha memories and their downstream beta memories
      @alpha_memories.each_value do |alpha_mem|
        alpha_mem.items.clear

        # Each alpha memory successor is a JoinNode or NegationNode.
        # Their successors are intermediate BetaMemory nodes.
        # The root beta memory is never a join node successor, so
        # its dummy token is preserved.
        alpha_mem.successors.each do |join_node|
          next unless join_node.respond_to?(:successors)
          join_node.successors.each do |beta_or_prod|
            beta_or_prod.tokens.clear if beta_or_prod.respond_to?(:tokens)
          end
        end
      end

      # 3. Clear production node tokens
      @production_nodes.each_value { |node| node.tokens.clear }

      # 4. Clear stale child references from the root dummy token
      @root_beta_memory.tokens.each { |t| t.children.clear }
    end

    private

    def build_network_for_rule(rule)
      current_beta = @root_beta_memory

      rule.conditions.each_with_index do |condition, index|
        # Build alpha memory pattern - merge condition type
        pattern = condition.pattern.merge(type: condition.type)
        alpha_memory = get_or_create_alpha_memory(pattern)

        # Build join tests - if pattern has :type that differs from condition.type,
        # add it as an attribute test since it was overwritten in the merge
        tests = []
        if condition.pattern[:type] && condition.pattern[:type] != condition.type
          # The pattern's :type should be checked as an attribute constraint
          tests << {
            token_field_index: index,
            token_field: :type,
            fact_field: :type,
            operation: :eq,
            expected_value: condition.pattern[:type]
          }
        end

        if condition.negated
          negation_node = NegationNode.new(alpha_memory, current_beta, tests)
          new_beta = BetaMemory.new
          negation_node.successors << new_beta
          current_beta = new_beta
        else
          join_node = JoinNode.new(alpha_memory, current_beta, tests)
          new_beta = BetaMemory.new
          join_node.successors << new_beta
          current_beta = new_beta
        end
      end

      production_node = ProductionNode.new(rule)
      current_beta.successors << production_node
      @production_nodes[rule.name] = production_node

      @working_memory.facts.each do |fact|
        @alpha_memories.each do |pattern, memory|
          memory.activate(fact) if fact.matches?(pattern)
        end
      end
    end

    def get_or_create_alpha_memory(pattern)
      @alpha_memories[pattern] ||= AlphaMemory.new(pattern)
    end
  end
end
