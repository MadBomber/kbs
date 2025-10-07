# frozen_string_literal: true

module KBS
  class ReteEngine
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
