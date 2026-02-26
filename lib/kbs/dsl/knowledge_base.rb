# frozen_string_literal: true

module KBS
  module DSL
    class KnowledgeBase
      attr_reader :engine, :rules

      def initialize
        @engine = Engine.new
        @rules = {}
        @rule_builders = {}
        @rule_source_locations = {}
      end

      def rule(name, &block)
        @rule_source_locations[name] = block.source_location if block
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

      def rule_source(name)
        location = @rule_source_locations[name]
        return nil unless location

        file, line = location
        return nil unless file && File.exist?(file)

        extract_rule_source(file, line)
      end

      def print_rule_source(name)
        source = rule_source(name)
        unless source
          puts "No source available for rule '#{name}'"
          return
        end

        puts source
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

      private

      def extract_rule_source(file, start_line)
        lines = File.readlines(file)
        start_idx = start_line - 1
        return nil if start_idx < 0 || start_idx >= lines.length

        # source_location points to the block's `do` line, which is
        # normally the same line as the `rule` call.  Walk back up to
        # 2 lines in case they are on separate lines.
        rule_idx = start_idx.downto([start_idx - 2, 0].max).find do |i|
          lines[i].match?(/\b(?:rule|defrule)\b/)
        end || start_idx

        base_indent = lines[rule_idx][/^\s*/].length
        end_pattern = /^\s{#{base_indent}}end\b/

        result = []
        (rule_idx...lines.length).each do |i|
          result << lines[i]
          break if i > rule_idx && lines[i].match?(end_pattern)
        end

        result.join.chomp
      end
    end
  end
end
