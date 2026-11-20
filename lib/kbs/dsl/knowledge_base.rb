# frozen_string_literal: true

module KBS
  module DSL
    # The object the DSL block runs in: defines rules, asserts and retracts
    # facts, and runs the engine.
    class KnowledgeBase
      include ConditionHelpers

      attr_reader :engine, :rules

      # @param engine [KBS::Engine, nil] engine to run on; a new KBS::Engine when nil
      # Drawn above and below the listings.
      SEPARATOR = ("-" * 40).freeze

      def initialize(engine: nil)
        @engine = engine || Engine.new
        @rules = {}
        @rule_builders = {}
        @rule_source_locations = {}
      end

      # @param priority [Integer, nil] rule priority; a `priority` call in the block wins
      def rule(name, priority: nil, &block)
        @rule_source_locations[name] = block.source_location if block
        builder = RuleBuilder.new(name, knowledge_base: self)
        builder.priority(priority) unless priority.nil?
        builder.instance_eval(&block) if block_given?
        @rule_builders[name] = builder
        rule = builder.build
        @rules[name] = rule
        @engine.add_rule(rule)
        builder
      end

      def defrule(name, priority: nil, &)
        rule(name, priority: priority, &)
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

      # Changes a fact's attributes and matches it against the rules again.
      # See KBS::Engine#modify.
      def modify(fact, changes)
        @engine.modify(fact, changes)
      end

      # @param limit [Integer, nil] stop after this many rule firings
      # @return [Integer] the number of rules fired
      def run(limit = nil)
        @engine.run(limit)
      end

      def halt
        @engine.halt
      end

      # See KBS::Engine#watch.
      def watch(*items)
        @engine.watch(*items)
        self
      end

      def unwatch(*items)
        @engine.unwatch(*items)
        self
      end

      # See KBS::Engine#matches.
      def matches(rule_name)
        @engine.matches(rule_name)
      end

      def reset
        @engine.reset
      end

      def close
        @engine.close
      end

      def facts
        @engine.working_memory.facts
      end

      def query(type, pattern = {})
        typed = pattern.merge(type: type)
        @engine.working_memory.facts.select { |fact| fact.matches?(typed) }
      end

      def print_facts
        numbered = facts.each_with_index.map { |fact, index| "#{index + 1}. #{fact}" }
        puts ["Working Memory Contents:", SEPARATOR, *numbered, SEPARATOR]
      end

      def rule_source(name)
        # Try file-based source first
        if (location = @rule_source_locations[name])
          file, line = location
          if file && File.exist?(file)
            source = extract_rule_source(file, line)
            return source if source
          end
        end

        # Fall back to reconstruction from internal state
        reconstruct_rule_source(name)
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
        puts ["Knowledge Base Rules:", SEPARATOR, *@rule_builders.each_value.flat_map(&:summary_lines), SEPARATOR]
      end

      private

      def reconstruct_rule_source(name)
        @rule_builders[name]&.source
      end

      def extract_rule_source(file, start_line)
        lines = File.readlines(file)
        start_idx = start_line - 1
        return nil unless start_idx.between?(0, lines.length - 1)

        rule_lines(lines.drop(rule_line_index(lines, start_idx))).join.chomp
      end

      # source_location points to the block's `do` line, which is normally
      # the same line as the `rule` call. Walks back up to 2 lines in case
      # they are on separate lines.
      def rule_line_index(lines, start_idx)
        earliest = [start_idx - 2, 0].max
        start_idx.downto(earliest).find { |index| lines[index].match?(/\b(?:rule|defrule)\b/) } || start_idx
      end

      # The rule's first line through the `end` at the same indentation,
      # or every line when there is no such `end`.
      def rule_lines(lines)
        end_pattern = /^\s{#{lines.first[/^\s*/].length}}end\b/
        last = lines.drop(1).index { |line| line.match?(end_pattern) }
        last ? lines.first(last + 2) : lines
      end
    end
  end
end
