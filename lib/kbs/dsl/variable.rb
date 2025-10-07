# frozen_string_literal: true

module KBS
  module DSL
    class Variable
      attr_reader :name

      def initialize(name)
        @name = "?#{name}".to_sym
      end

      def to_sym
        @name
      end
    end
  end
end
