# frozen_string_literal: true

module KBS
  # Fact#matches? for both kinds of fact. The including class has @type
  # and @attributes.
  module PatternMatching
    # Whether the fact's type and attributes fit `pattern`. A Proc is
    # called with the attribute's value, a ?variable fits anything, and
    # any other value has to be equal. Walks the pattern with each_pair,
    # since Hash#all? builds a [key, value] Array for every entry.
    def matches?(pattern)
      type = pattern[:type]
      return false if type && type != @type

      attributes = @attributes
      pattern.each_pair do |key, expected|
        next if key == :type
        return false unless PatternMatching.value_matches?(attributes[key], expected)
      end
      true
    end

    def self.value_matches?(actual, expected)
      if expected.is_a?(Proc)
        actual && expected.call(actual)
      elsif variable?(expected)
        true
      else
        actual == expected
      end
    end

    # A ?variable, which fits any value.
    def self.variable?(expected)
      expected.is_a?(Symbol) && expected.end_with?('?')
    end

    # The [attribute, expected value] pairs of `pattern` that can fail: all
    # but the type and the ?variables. Frozen.
    def self.tests_for(pattern)
      pattern.reject { |key, expected| key == :type || variable?(expected) }.to_a.freeze
    end

    # Whether `attributes` pass every test from #tests_for.
    def self.passes?(tests, attributes)
      tests.each do |key, expected|
        return false unless value_matches?(attributes[key], expected)
      end
      true
    end
  end
end
