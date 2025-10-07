# frozen_string_literal: true

module KBS
  class Rule
    attr_reader :name, :conditions, :action, :priority

    def initialize(name, conditions: [], action: nil, priority: 0)
      @name = name
      @conditions = conditions
      @action = action
      @priority = priority
      @fired_count = 0
    end

    def fire(facts)
      @fired_count += 1
      bindings = extract_bindings(facts)
      @action.call(facts, bindings) if @action
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
