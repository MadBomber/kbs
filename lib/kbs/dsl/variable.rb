# frozen_string_literal: true

module KBS
  module DSL
    class Variable
      attr_reader :name

      def initialize(name)
        name_str = name.to_s
        @name = name_str.start_with?('?') ? name_str.to_sym : "?#{name_str}".to_sym
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
