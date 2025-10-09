# frozen_string_literal: true

require_relative '../engine'
require_relative 'memory'

module KBS
  module Blackboard
    # KBS engine integrated with Blackboard memory
    class Engine < KBS::Engine
      attr_reader :blackboard

      def initialize(db_path: ':memory:', store: nil)
        super()
        @blackboard = Memory.new(db_path: db_path, store: store)
        @working_memory = @blackboard
        @blackboard.add_observer(self)
      end

      def add_fact(type, attributes = {})
        @blackboard.add_fact(type, attributes)
      end

      def remove_fact(fact)
        @blackboard.remove_fact(fact)
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
            # Only fire if not already fired
            next if token.fired?

            fact_uuids = token.facts.map { |f| f.respond_to?(:uuid) ? f.uuid : f.object_id.to_s }
            bindings = extract_bindings_from_token(token, node.rule)

            @blackboard.log_rule_firing(node.rule.name, fact_uuids, bindings)
            node.fire_rule(token)
          end
        end
      end

      def post_message(sender, topic, content, priority: 0)
        @blackboard.post_message(sender, topic, content, priority: priority)
      end

      def consume_message(topic, consumer)
        @blackboard.consume_message(topic, consumer)
      end

      def stats
        @blackboard.stats
      end

      private

      def extract_bindings_from_token(token, rule)
        bindings = {}
        rule.conditions.each_with_index do |condition, index|
          next if condition.negated
          fact = token.facts[index]
          if fact && condition.respond_to?(:variable_bindings)
            condition.variable_bindings.each do |var, field|
              bindings[var] = fact.attributes[field] if fact.respond_to?(:attributes)
            end
          end
        end
        bindings
      end
    end
  end
end
