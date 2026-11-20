# frozen_string_literal: true

module KBS
  class Condition
    attr_reader :type, :pattern, :variable_bindings, :negated, :exists

    # @param negated [Boolean] match when no fact fits the pattern
    # @param exists [Boolean] match once when at least one fact fits the
    #   pattern, instead of once for each fact
    def initialize(type, pattern = {}, negated: false, exists: false)
      raise ArgumentError, "a condition cannot be both negated and exists" if negated && exists

      @type = type
      @pattern = pattern
      @negated = negated
      @exists = exists
      @variable_bindings = extract_variables(pattern)
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
