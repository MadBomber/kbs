# frozen_string_literal: true

module KBS
  class ProductionNode
    attr_accessor :rule, :tokens

    def initialize(rule)
      @rule = rule
      @tokens = []
    end

    def activate(token)
      @tokens << token
      @rule.fire(token.facts)
    end

    def deactivate(token)
      @tokens.delete(token)
    end
  end
end
