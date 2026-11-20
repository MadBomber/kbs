# frozen_string_literal: true

module KBS
  class Error < StandardError; end

  # Raised when a fact is added, removed or modified while the engine is
  # in the middle of matching another fact. This happens when a pattern
  # predicate or a working-memory observer changes facts. Change facts
  # from rule actions instead, which run between matches.
  class MatchInProgressError < Error
    def initialize(message = "facts cannot be added, removed or modified while a fact is being matched")
      super
    end
  end
end
