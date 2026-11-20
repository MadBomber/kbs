# frozen_string_literal: true

module KBS
  # A named set of conditions and the action to run for each match.
  class Rule
    attr_reader :name, :priority
    attr_accessor :conditions, :action

    def initialize(name, conditions: [], action: nil, priority: 0, &block)
      @name = name
      @conditions = conditions
      @action = action
      @priority = priority
      @fired_count = 0

      yield self if block_given?
    end

    def fire(facts)
      @fired_count += 1
      return unless @action

      bindings = bindings_for(facts)

      # Support 0-parameter, 1-parameter and 2-parameter actions
      if @action.arity.zero?
        @action.call
      elsif [1, -1].include?(@action.arity)
        @action.call(facts)
      else
        @action.call(facts, bindings)
      end
    end

    # The number of leading conditions that are logical. Facts the rule
    # asserts are supported by the match of those conditions.
    def logical_count
      @conditions.take_while(&:logical).size
    end

    # Logical conditions have to come before every other condition.
    def logical_conditions_first?
      @conditions.drop(logical_count).none?(&:logical)
    end

    # Maps each variable to its value in the matched facts. The facts
    # line up with the conditions that bind a fact; negated and exists
    # conditions contribute none.
    def bindings_for(facts)
      @conditions.select(&:binds_fact?).zip(facts).each_with_object({}) do |(condition, fact), bindings|
        bindings.merge!(condition.bindings_from(fact)) if fact
      end
    end

    def to_s
      RuleSource.new(name: @name, conditions: @conditions, action: @action, priority: @priority).to_s
    end
  end
end
