# frozen_string_literal: true

module KBS
  # An `exists` condition: passes a token on once, while at least one
  # fact matches it, however many do. It binds no variables for later
  # conditions and adds no fact to the match.
  class ExistsNode < QuantifierNode
    def passes_when_matched?
      true
    end
  end
end
