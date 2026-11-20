# frozen_string_literal: true

module KBS
  module DSL
    # Evaluates the block form of a condition, where each method call names
    # a pattern key and a bare name is a variable.
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

      # Every name is a variable or a pattern key.
      def respond_to_missing?(_method, _include_private = false) = true

      def method_missing(method, *args, &block)
        if args.empty? && !block_given?
          Variable.new(method, self)
        elsif args.length == 1 && !block_given?
          @pattern[method] = pattern_value(args.first)
        elsif block_given?
          @pattern[method] = block
        else
          super
        end
      end

      # Sets the pattern value of `attribute`, as `value > 80` does.
      # @return the value
      def constrain(attribute, value)
        @pattern[attribute] = value
      end

      # A Variable given as a value (`location loc`) is its ?variable
      # symbol; any other value is used as is.
      def pattern_value(value)
        value.is_a?(Variable) ? value.to_sym : value
      end

      def >(other)
        ->(v) { v > other }
      end

      def <(other)
        ->(v) { v < other }
      end

      def >=(other)
        ->(v) { v >= other }
      end

      def <=(other)
        ->(v) { v <= other }
      end

      def ==(other)
        other
      end

      def !=(other)
        ->(v) { v != other }
      end

      def between(min, max)
        ->(v) { v.between?(min, max) }
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
