# frozen_string_literal: true

module KBS
  class ProductionNode
    attr_accessor :rule
    attr_reader :order

    # @param agenda [KBS::Agenda, nil] where matches wait to fire; without
    #   one the node only collects tokens
    # @param order [Integer] the rule's position among the engine's rules
    def initialize(rule, agenda = nil, order: 0)
      @rule = rule
      @tokens = Set.new
      @agenda = agenda
      @order = order
      @activations = {}.compare_by_identity
      @fired = Set.new.compare_by_identity
    end

    # @return [Array<KBS::Token>] the rule's current matches, fired or
    #   not, in the order they arrived. A copy.
    def tokens
      @tokens.to_a
    end

    # A complete match. The rule does not fire here: the activation waits
    # on the agenda until Engine#run, so a later retraction can still
    # take it back.
    def activate(token)
      @tokens << token
      @activations[token] = @agenda.add(self, token, rule_order: @order) if @agenda
    end

    # Fires the rule for `token` unless this rule already fired for it.
    # Rules with the same conditions share their tokens, so the record is
    # kept here, per rule, and not only on the token.
    def fire_rule(token)
      return if fired?(token)

      @fired << token
      @rule.fire(token.facts)
      token.mark_fired!
    end

    # Whether this rule has fired for `token`.
    def fired?(token)
      @fired.include?(token)
    end

    def deactivate(token)
      @tokens.delete(token)
      @fired.delete(token)
      @agenda&.remove(@activations.delete(token))
    end

    # Forgets every match, fired or pending.
    def reset
      @activations.each_value { |activation| @agenda&.remove(activation) }
      @activations.clear
      @fired.clear
      @tokens.clear
    end
  end
end
