# frozen_string_literal: true

module KBS
  # Records which partial matches logically support which facts.
  #
  # A fact asserted by a rule with `logical` conditions is supported by
  # the token that matched those conditions. A fact may have several such
  # supports. When a support token is removed, each fact it supported
  # loses that support, and a fact with none left is handed back to be
  # retracted. A fact with no recorded support is unconditional: it stays
  # until someone retracts it.
  class TruthMaintenance
    def initialize
      @supports = {}
      @dependents = {}.compare_by_identity
    end

    # Records that `token` supports `fact`.
    def support(fact, token)
      (@supports[fact] ||= Set.new.compare_by_identity) << token
      (@dependents[token] ||= Set.new) << fact
    end

    # Whether `fact` stays only as long as a supporting match does.
    def supported?(fact)
      @supports.key?(fact)
    end

    # The tokens that support `fact`.
    def supports_of(fact)
      @supports[fact].to_a
    end

    # The facts that `token` supports.
    def dependents_of(token)
      @dependents[token].to_a
    end

    # The facts that have `fact` in one of their supporting matches.
    def facts_depending_on(fact)
      @dependents.each_with_object([]) do |(token, facts), found|
        found.concat(facts.to_a) if token.facts.include?(fact)
      end.uniq
    end

    # Makes `fact` unconditional, or forgets it once it is retracted.
    def release(fact)
      tokens = @supports.delete(fact)
      tokens&.each do |token|
        facts = @dependents[token]
        next unless facts

        facts.delete(fact)
        @dependents.delete(token) if facts.empty?
      end
    end

    # A support token went away.
    #
    # @return [Array] the facts left with no support, to be retracted
    def withdraw(token)
      facts = @dependents.delete(token)
      return [] unless facts

      facts.select do |fact|
        tokens = @supports[fact]
        tokens.delete(token)
        @supports.delete(fact) if tokens.empty?
        tokens.empty?
      end
    end

    def clear
      @supports.clear
      @dependents.clear
    end

    def size
      @supports.size
    end
  end
end
