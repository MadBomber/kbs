# frozen_string_literal: true

require_relative '../engine'
require_relative 'memory'

module KBS
  module Blackboard
    # KBS engine integrated with Blackboard memory
    class Engine < KBS::Engine
      attr_reader :blackboard

      def initialize(db_path: ':memory:', store: nil, strategy: :definition, fact_duplication: true)
        super(strategy: strategy, fact_duplication: fact_duplication)
        @blackboard = Memory.new(db_path: db_path, store: store)
        @working_memory = @blackboard
        @blackboard.add_observer(self)
        # Files the facts already stored, so duplicates of them are refused.
        self.fact_duplication = fact_duplication
      end

      # Writes the fact to the blackboard, which tells this engine to
      # match it.
      def create_fact(type, attributes)
        @blackboard.add_fact(type, attributes)
      end

      # Changes a fact's attributes in the store and matches it again. The
      # fact keeps its uuid, and the audit log records an UPDATE.
      #
      # Fact#update and Fact#[]= write to the store but do not match the
      # fact again.
      #
      # @return [KBS::Blackboard::Fact, nil] the fact with its new
      #   attributes; the existing equal fact when duplication is off and
      #   the change makes this fact a duplicate (this fact is then
      #   removed); nil when the fact is not on the blackboard
      def modify(fact, changes)
        ensure_not_matching!
        current = @blackboard.find_fact(fact)
        return nil unless current

        attributes = fact.is_a?(Fact) ? fact.attributes : current.attributes
        existing = duplicate_of(current.type, attributes.merge(changes))
        if existing && existing != current
          @blackboard.remove_fact(current)
          return existing
        end

        @blackboard.modify_fact(fact, changes)
      end

      # Records the firing in the audit log, then fires the rule.
      def fire_activation(activation)
        log_firing(activation)
        super
      end

      # Writes the activation's firing to the audit log, unless its rule
      # has fired for that token already. Rules that share join nodes
      # share tokens, so whether a rule fired is asked of its production
      # node, not of the token.
      def log_firing(activation)
        token = activation.token
        return if activation.node.fired?(token)

        rule = activation.rule
        facts = token.facts
        @blackboard.log_rule_firing(rule.name, facts.map(&:uuid), rule.bindings_for(facts))
      end

      # A reset empties the network, not the store: the persisted facts
      # stay on the blackboard.
      def clear_working_memory; end

      def post_message(sender, topic, content, priority: 0)
        @blackboard.post_message(sender, topic, content, priority: priority)
      end

      def consume_message(topic, consumer)
        @blackboard.consume_message(topic, consumer)
      end

      def stats
        @blackboard.stats
      end

      def close
        @blackboard.close
      end
    end
  end
end
