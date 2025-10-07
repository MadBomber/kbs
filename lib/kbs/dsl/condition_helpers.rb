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

      def range(min, max)
        ->(v) { v >= min && v <= max }
      end

      def satisfies(&block)
        block
      end
    end
  end
end
