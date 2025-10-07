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

      bindings = extract_bindings(facts)

      # Support both 1-parameter and 2-parameter actions
      if @action.arity == 1 || @action.arity == -1
        @action.call(facts)
      else
        @action.call(facts, bindings)
      end
    end

    private

    def extract_bindings(facts)
      bindings = {}
      @conditions.each_with_index do |condition, index|
        next if condition.negated
        fact = facts[index]
        condition.variable_bindings.each do |var, field|
          bindings[var] = fact.attributes[field] if fact
        end
      end
      bindings
    end
  end
end
