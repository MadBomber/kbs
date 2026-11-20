# frozen_string_literal: true

require_relative '../engine'
require_relative 'memory'

module KBS
  module Blackboard
    # KBS engine integrated with Blackboard memory
    class Engine < KBS::Engine
      attr_reader :blackboard

      def initialize(db_path: ':memory:', store: nil, strategy: :definition)
        super(strategy: strategy)
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

      # Records the firing in the audit log, then fires the rule.
      def fire_activation(activation)
        unless activation.token.fired?
          facts = activation.token.facts
          fact_uuids = facts.map { |f| f.respond_to?(:uuid) ? f.uuid : f.object_id.to_s }
          bindings = activation.rule.bindings_for(facts)

          @blackboard.log_rule_firing(activation.rule.name, fact_uuids, bindings)
        end

        super
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

      def close
        @blackboard.close
      end
    end
  end
end
