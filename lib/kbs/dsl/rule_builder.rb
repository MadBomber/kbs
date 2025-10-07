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
        @current_condition_group = []
        @negated = false
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
        @conditions << Condition.new(type, pattern, negated: @negated)
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

      def exists(type, pattern = {}, &block)
        on(type, pattern, &block)
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
