# frozen_string_literal: true

module KBS
  module DSL
    class KnowledgeBase
      attr_reader :engine, :rules

      def initialize
        @engine = Engine.new
        @rules = {}
        @rule_builders = {}
      end

      def rule(name, &block)
        builder = RuleBuilder.new(name)
        builder.instance_eval(&block) if block_given?
        @rule_builders[name] = builder
        rule = builder.build
        @rules[name] = rule
        @engine.add_rule(rule)
        builder
      end

      def defrule(name, &block)
        rule(name, &block)
      end

      def fact(type, attributes = {})
        @engine.add_fact(type, attributes)
      end

      def assert(type, attributes = {})
        fact(type, attributes)
      end

      def retract(fact)
        @engine.remove_fact(fact)
      end

      def run
        @engine.run
      end

      def reset
        @engine.reset
      end

      def facts
        @engine.working_memory.facts
      end

      def query(type, pattern = {})
        @engine.working_memory.facts.select do |fact|
          next false unless fact.type == type
          pattern.all? { |key, value| fact.attributes[key] == value }
        end
      end

      def print_facts
        puts "Working Memory Contents:"
        puts "-" * 40
        facts.each_with_index do |fact, i|
          puts "#{i + 1}. #{fact}"
        end
        puts "-" * 40
      end

      def print_rules
        puts "Knowledge Base Rules:"
        puts "-" * 40
        @rule_builders.each do |name, builder|
          puts "Rule: #{name}"
          puts "  Description: #{builder.description}" if builder.description
          puts "  Priority: #{builder.priority}"
          puts "  Conditions: #{builder.conditions.size}"
          builder.conditions.each_with_index do |cond, i|
            negated = cond.negated ? "NOT " : ""
            puts "    #{i + 1}. #{negated}#{cond.type}(#{cond.pattern})"
          end
          puts ""
        end
        puts "-" * 40
      end
    end
  end
end
