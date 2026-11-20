# frozen_string_literal: true

module KBS
  module DSL
    # A bare name written in a pattern block. Used as a value
    # (`location loc`) it is the ?variable `:loc?`. Compared with a value
    # (`value > 80`) it stands for the attribute of that name, and the
    # comparison becomes that attribute's predicate in the block's pattern.
    class Variable
      # Operators that turn `name <op> operand` into a predicate on the
      # attribute `name`, built by PatternEvaluator's operator of the same name.
      COMPARISONS = %i[> < >= <=].freeze

      attr_reader :name

      # @param evaluator [PatternEvaluator, nil] the pattern block this name
      #   was written in; comparisons need it to record their predicate
      def initialize(name, evaluator = nil)
        @name = :"#{name.to_s.delete_suffix('?')}?"
        @evaluator = evaluator
      end

      def to_sym
        @name
      end

      def to_s
        @name.to_s
      end

      # The attribute this name stands for in a comparison.
      def attribute
        @name.to_s.delete_suffix('?').to_sym
      end

      COMPARISONS.each do |operator|
        define_method(operator) do |operand|
          constrain(operator, operand) do
            raise KBS::Error, "`#{attribute} #{operator} ...` only works inside a pattern block"
          end
        end
      end

      # Another Variable: whether both are the same variable. Any other
      # value in a pattern block: `value == 80` requires that value.
      def ==(other)
        return @name == other.name if other.is_a?(Variable)

        constrain(:==, other) { false }
      end

      # Another Variable: whether they differ. Any other value in a
      # pattern block: `code != 3` requires a value other than that.
      def !=(other)
        return @name != other.name if other.is_a?(Variable)

        constrain(:!=, other) { true }
      end

      def eql?(other)
        other.is_a?(Variable) && @name == other.name
      end

      def hash
        @name.hash
      end

      private

      # Records `attribute <operator> operand` as the attribute's pattern
      # value in the evaluator and returns that value. Outside a pattern
      # block there is no evaluator, and the block's result is returned.
      def constrain(operator, operand)
        return yield unless @evaluator

        @evaluator.constrain(attribute, @evaluator.public_send(operator, operand))
      end
    end
  end
end
