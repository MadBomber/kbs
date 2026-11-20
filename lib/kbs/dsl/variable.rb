# frozen_string_literal: true

module KBS
  module DSL
    # A ?variable written as a bare name in a pattern block.
    class Variable
      attr_reader :name

      def initialize(name)
        @name = :"#{name.to_s.delete_suffix('?')}?"
      end

      def to_sym
        @name
      end

      def to_s
        @name.to_s
      end

      def ==(other)
        return false unless other.is_a?(Variable)
        @name == other.name
      end

      def eql?(other)
        self == other
      end

      def hash
        @name.hash
      end
    end
  end
end
