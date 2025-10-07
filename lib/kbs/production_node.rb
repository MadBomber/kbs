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
      # Don't fire immediately - wait for run() to fire rules
      # This allows negation nodes to deactivate tokens before they fire
    end

    def fire_rule(token)
      return if token.fired?
      @rule.fire(token.facts)
      token.mark_fired!
    end

    def deactivate(token)
      @tokens.delete(token)
    end
  end
end
