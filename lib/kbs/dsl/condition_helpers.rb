# frozen_string_literal: true

module KBS
  module DSL
    module ConditionHelpers
      def less_than(value)
        ->(v) { v < value }
      end

      def greater_than(value)
        ->(v) { v > value }
      end

      def equals(value)
        value
      end

      def not_equal(value)
        ->(v) { v != value }
      end

      def one_of(*values)
        ->(v) { values.include?(v) }
      end

      def range(min_or_range, max = nil)
        if min_or_range.is_a?(Range)
          ->(v) { min_or_range.include?(v) }
        else
          ->(v) { v >= min_or_range && v <= max }
        end
      end

      def between(min, max)
        range(min, max)
      end

      def any(*values)
        if values.empty?
          # Match anything
          ->(v) { true }
        else
          # Match one of the values
          one_of(*values)
        end
      end

      def matches(pattern)
        ->(v) { v.match?(pattern) }
      end

      def satisfies(&block)
        block
      end
    end
  end
end
