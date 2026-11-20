# frozen_string_literal: true

module KBS
  module DSL
    # Collects the conditions and action written inside a `rule do ... end`
    # block and builds the KBS::Rule.
    class RuleBuilder
      include ConditionHelpers

      attr_reader :name, :description, :conditions, :action_block

      def initialize(name)
        @name = name
        @description = nil
        @priority = 0
        @conditions = []
        @action_block = nil
        @negated = false
        @logical = false
      end

      def desc(description)
        @description = description
        self
      end

      def priority(level = nil)
        return @priority if level.nil?
        @priority = level
        self
      end

      # Primary DSL keywords (avoid Ruby reserved words)
      def on(type, pattern = {}, &)
        if block_given?
          pattern = pattern.merge(evaluate_block(&))
        end
        @conditions << Condition.new(type, pattern, negated: @negated, logical: @logical)
        @negated = false
        self
      end

      def without(type = nil, pattern = {}, &)
        @negated = true
        # Direct negation: without(:problem). Chaining: without.on(:problem).
        type ? on(type, pattern, &) : self
      end

      # Marks the conditions in the block as logical: every fact the
      # rule's action asserts stays only while those conditions are
      # matched, and is retracted when they stop matching. The block has
      # to come before the rule's other conditions.
      #
      #   rule "overheating" do
      #     logical do
      #       on :sensor, temp: greater_than(90)
      #     end
      #     perform { assert :overheating }
      #   end
      def logical(&)
        @logical = true
        instance_eval(&)
        self
      ensure
        @logical = false
      end

      def perform(&block)
        @action_block = block
        self
      end

      # Aliases for readability
      def given(type, pattern = {}, &)
        on(type, pattern, &)
      end

      def matches(type, pattern = {}, &)
        on(type, pattern, &)
      end

      def fact(type, pattern = {}, &)
        on(type, pattern, &)
      end

      # Matches once when at least one fact fits the pattern, however many
      # do. The rule's action receives no fact for this condition, and a
      # variable first used here is not bound for later conditions.
      def exists(type, pattern = {}, &)
        pattern = pattern.merge(evaluate_block(&)) if block_given?
        @conditions << Condition.new(type, pattern, exists: true, logical: @logical)
        @negated = false
        self
      end

      def absent(type, pattern = {}, &)
        without.on(type, pattern, &)
      end

      def missing(type, pattern = {}, &)
        without.on(type, pattern, &)
      end

      def lacks(type, pattern = {}, &)
        without.on(type, pattern, &)
      end

      def action(&)
        perform(&)
      end

      def execute(&)
        perform(&)
      end

      def then(&)
        perform(&)
      end

      # The rule as DSL source, rebuilt from what was collected.
      def source
        RuleSource.new(name: @name, conditions: @conditions, action: @action_block,
                       priority: @priority, description: @description).to_s
      end

      # The lines print_rules shows for this rule.
      def summary_lines
        conditions = @conditions.each_with_index.map { |condition, index| "    #{index + 1}. #{condition.summary}" }
        ["Rule: #{@name}", *("  Description: #{@description}" if @description), "  Priority: #{@priority}",
         "  Conditions: #{@conditions.size}", *conditions, ""]
      end

      def build
        Rule.new(@name,
                 conditions: @conditions,
                 action: @action_block,
                 priority: @priority)
      end

      private

      def evaluate_block(&)
        evaluator = PatternEvaluator.new
        evaluator.instance_eval(&)
        evaluator.pattern
      end
    end
  end
end
