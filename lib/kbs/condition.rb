# frozen_string_literal: true

module KBS
  class Condition
    attr_reader :type, :pattern, :variable_bindings, :negated

    def initialize(type, pattern = {}, negated: false)
      @type = type
      @pattern = pattern
      @negated = negated
      @variable_bindings = extract_variables(pattern)
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
