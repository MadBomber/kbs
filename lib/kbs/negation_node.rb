# frozen_string_literal: true

module KBS
  # A `without` condition: passes a token on while no fact matches it.
  # A fact that matches the token blocks it; the token passes again when
  # its last blocker is retracted.
  class NegationNode < QuantifierNode
    def passes_when_matched?
      false
    end
  end
end
