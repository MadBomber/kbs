# frozen_string_literal: true

module KBS
  module DSL
    # Collects the conditions and action written inside a `rule do ... end`
    # block and builds the KBS::Rule.
    #
    # The rule's `perform` block runs with the builder as self, so the
    # builder forwards working-memory calls (assert, retract, modify,
    # query, facts, halt, engine) to the knowledge base that owns the
    # rule. `fact` adds a condition while the rule is being defined and
    # asserts a fact once it is built. Condition keywords called after
    # the build raise KBS::RuleBuiltError.
    class RuleBuilder
      include ConditionHelpers

      attr_reader :name, :description, :conditions, :action_block

      # @param knowledge_base [KBS::DSL::KnowledgeBase, nil] where working-memory
      #   calls made on the builder, such as those in a perform block, go
      def initialize(name, knowledge_base: nil)
        @name = name
        @knowledge_base = knowledge_base
        @built = false
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
        ensure_building!(:on)
        if block_given?
          pattern = pattern.merge(evaluate_block(&))
        end
        @conditions << Condition.new(type, pattern, negated: @negated, logical: @logical)
        @negated = false
        self
      end

      def without(type = nil, pattern = {}, &)
        ensure_building!(:without)
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
        ensure_building!(:logical)
        @logical = true
        instance_eval(&)
        self
      ensure
        @logical = false
      end

      def perform(&block)
        ensure_building!(:perform)
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

      # A condition while the rule is being defined; once it is built, as
      # in a perform block, asserts a fact through the knowledge base.
      def fact(type, pattern = {}, &)
        return knowledge_base!(:fact).fact(type, pattern) if built?

        on(type, pattern, &)
      end

      # Matches once when at least one fact fits the pattern, however many
      # do. The rule's action receives no fact for this condition, and a
      # variable first used here is not bound for later conditions.
      def exists(type, pattern = {}, &)
        ensure_building!(:exists)
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

      # Working-memory calls, forwarded to the knowledge base so that a
      # perform block can make them bare.
      def assert(type, attributes = {}) = knowledge_base!(:assert).assert(type, attributes)
      def retract(fact) = knowledge_base!(:retract).retract(fact)
      def modify(fact, changes) = knowledge_base!(:modify).modify(fact, changes)
      def query(type, pattern = {}) = knowledge_base!(:query).query(type, pattern)
      def facts = knowledge_base!(:facts).facts
      def halt = knowledge_base!(:halt).halt
      def engine = knowledge_base!(:engine).engine

      # Whether #build has run. After that, condition keywords raise.
      def built?
        @built
      end

      def build
        @built = true
        Rule.new(@name,
                 conditions: @conditions,
                 action: @action_block,
                 priority: @priority)
      end

      private

      def ensure_building!(keyword)
        raise RuleBuiltError.new(@name, keyword) if built?
      end

      def knowledge_base!(method)
        @knowledge_base || raise(NoKnowledgeBaseError.new(@name, method))
      end

      def evaluate_block(&)
        evaluator = PatternEvaluator.new
        evaluator.instance_eval(&)
        evaluator.pattern
      end
    end
  end
end
