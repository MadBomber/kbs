# frozen_string_literal: true

module KBS
  # Fact#matches? for both kinds of fact. The including class has @type
  # and @attributes.
  module PatternMatching
    # Whether the fact's type and attributes fit `pattern`. A Proc is
    # called with the attribute's value, a ?variable fits anything, and
    # any other value has to be equal.
    def matches?(pattern)
      type = pattern[:type]
      return false if type && type != @type

      pattern.all? { |key, expected| key == :type || PatternMatching.value_matches?(@attributes[key], expected) }
    end

    def self.value_matches?(actual, expected)
      if expected.is_a?(Proc)
        actual && expected.call(actual)
      elsif expected.is_a?(Symbol) && expected.end_with?('?')
        true
      else
        actual == expected
      end
    end
  end
end
