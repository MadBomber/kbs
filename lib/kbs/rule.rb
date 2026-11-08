# frozen_string_literal: true

module KBS
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

      # Support both 1-parameter and 2-parameter actions
      if @action.arity == 1 || @action.arity == -1
        @action.call(facts)
      else
        @action.call(facts, bindings)
      end
    end

    # Maps each variable to its value in the matched facts. The facts
    # line up with the positive conditions only; negated conditions
    # match no fact.
    def bindings_for(facts)
      bindings = {}
      @conditions.reject(&:negated).zip(facts) do |condition, fact|
        next unless fact
        condition.variable_bindings.each do |var, field|
          bindings[var] = fact.attributes[field]
        end
      end
      bindings
    end
  end
end
