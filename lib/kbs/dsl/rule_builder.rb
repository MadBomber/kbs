# frozen_string_literal: true

module KBS
  module DSL
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
      def on(type, pattern = {}, &block)
        if block_given?
          pattern = pattern.merge(evaluate_block(&block))
        end
        @conditions << Condition.new(type, pattern, negated: @negated, logical: @logical)
        @negated = false
        self
      end

      def without(type = nil, pattern = {}, &block)
        if type
          # Direct negation: without(:problem)
          @negated = true
          on(type, pattern, &block)
        else
          # Chaining: without.on(:problem)
          @negated = true
          self
        end
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
      def logical(&block)
        @logical = true
        instance_eval(&block)
        self
      ensure
        @logical = false
      end

      def perform(&block)
        @action_block = block
        self
      end

      # Aliases for readability
      def given(type, pattern = {}, &block)
        on(type, pattern, &block)
      end

      def matches(type, pattern = {}, &block)
        on(type, pattern, &block)
      end

      def fact(type, pattern = {}, &block)
        on(type, pattern, &block)
      end

      # Matches once when at least one fact fits the pattern, however many
      # do. The rule's action receives no fact for this condition, and a
      # variable first used here is not bound for later conditions.
      def exists(type, pattern = {}, &block)
        pattern = pattern.merge(evaluate_block(&block)) if block_given?
        @conditions << Condition.new(type, pattern, exists: true, logical: @logical)
        @negated = false
        self
      end

      def absent(type, pattern = {}, &block)
        without.on(type, pattern, &block)
      end

      def missing(type, pattern = {}, &block)
        without.on(type, pattern, &block)
      end

      def lacks(type, pattern = {}, &block)
        without.on(type, pattern, &block)
      end

      def action(&block)
        perform(&block)
      end

      def execute(&block)
        perform(&block)
      end

      def then(&block)
        perform(&block)
      end

      def build
        Rule.new(@name,
          conditions: @conditions,
          action: @action_block,
          priority: @priority)
      end

      private

      def evaluate_block(&block)
        evaluator = PatternEvaluator.new
        evaluator.instance_eval(&block)
        evaluator.pattern
      end
    end
  end
end
