# frozen_string_literal: true

module KBS
  # One condition of a rule: a fact type and a pattern its attributes must
  # fit, optionally negated, existential or logical.
  class Condition
    attr_reader :type, :pattern, :variable_bindings, :negated, :exists, :logical

    # @param negated [Boolean] match when no fact fits the pattern
    # @param exists [Boolean] match once when at least one fact fits the
    #   pattern, instead of once for each fact
    # @param logical [Boolean] facts the rule asserts depend on this
    #   condition staying matched; logical conditions come first in a rule
    def initialize(type, pattern = {}, negated: false, exists: false, logical: false)
      raise ArgumentError, "a condition cannot be both negated and exists" if negated && exists

      @type = type
      @pattern = pattern
      @negated = negated
      @exists = exists
      @logical = logical
      @variable_bindings = extract_variables(pattern)
    end

    # One line for listings: the type and pattern, marked NOT or EXISTS.
    def summary
      prefix = { "without" => "NOT ", "exists" => "EXISTS " }.fetch(keyword, "")
      "#{prefix}#{@type}(#{RuleSource.pattern_source(@pattern)})"
    end

    # The value each of this condition's variables takes from `fact`.
    def bindings_from(fact)
      attributes = fact.attributes
      @variable_bindings.transform_values { |field| attributes[field] }
    end

    # Whether the condition adds a fact to the rule's match. Negated and
    # exists conditions test for facts but contribute none.
    def binds_fact?
      !@negated && !@exists
    end

    # The DSL keyword that writes this condition.
    def keyword
      return "without" if @negated
      return "exists" if @exists

      "on"
    end

    private

    def extract_variables(pattern)
      vars = {}
      pattern.each do |key, value|
        if value.is_a?(Symbol) && value.to_s.end_with?('?')
          vars[value] = key
        end
      end
      vars
    end
  end
end
