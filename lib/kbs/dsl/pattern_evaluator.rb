# frozen_string_literal: true

module KBS
  module DSL
    class PatternEvaluator
      # The block form of `on` runs here, so helpers such as greater_than
      # must resolve to the helper, not fall into method_missing as keys.
      # Methods this class defines itself (between, matches, any, all)
      # still take precedence over the module's.
      include ConditionHelpers

      attr_reader :pattern

      def initialize
        @pattern = {}
      end

      def method_missing(method, *args, &block)
        if args.empty? && !block_given?
          Variable.new(method)
        elsif args.length == 1 && !block_given?
          @pattern[method] = args.first
        elsif block_given?
          @pattern[method] = block
        else
          super
        end
      end

      def >(value)
        ->(v) { v > value }
      end

      def <(value)
        ->(v) { v < value }
      end

      def >=(value)
        ->(v) { v >= value }
      end

      def <=(value)
        ->(v) { v <= value }
      end

      def ==(value)
        value
      end

      def !=(value)
        ->(v) { v != value }
      end

      def between(min, max)
        ->(v) { v >= min && v <= max }
      end

      def in(collection)
        ->(v) { collection.include?(v) }
      end

      def matches(pattern)
        ->(v) { v.match?(pattern) }
      end

      def any(*values)
        ->(v) { values.include?(v) }
      end

      def all(*conditions)
        ->(v) { conditions.all? { |c| c.is_a?(Proc) ? c.call(v) : c == v } }
      end
    end
  end
end
