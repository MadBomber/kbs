# frozen_string_literal: true

module KBS
  # Base for the nodes that test whether a token has any matching fact
  # rather than joining it with each one: NegationNode passes a token on
  # while it has no match, ExistsNode while it has at least one. The
  # token passed on carries no fact.
  #
  # Each token is linked to the facts that match it, and each fact to the
  # tokens it matches. Adding or removing a fact follows those links to
  # the affected tokens, so neither memory is searched.
  class QuantifierNode
    include NetworkNode
    include JoinTests
    include JoinIndexing

    attr_accessor :successors
    attr_reader :alpha_memory, :beta_memory, :tests

    def initialize(alpha_memory, beta_memory, tests = [])
      @alpha_memory = alpha_memory
      @beta_memory = beta_memory
      @successors = []
      @tests = tests
      @facts_matching = {}.compare_by_identity
      @tokens_matched_by = {}

      alpha_memory.successors << self if alpha_memory
      beta_memory.successors << self if beta_memory
      build_join_indexes
    end

    def tests=(tests)
      @tests = tests
      build_join_indexes
    end

    def alpha_memory=(memory)
      @alpha_memory = memory
      build_join_indexes
    end

    def beta_memory=(memory)
      @beta_memory = memory
      build_join_indexes
    end

    # Subclasses answer whether a token is passed on while it has a
    # matching fact (exists) or while it has none (negation).
    def passes_when_matched?
      raise NotImplementedError, "#{self.class} must define passes_when_matched?"
    end

    def left_activate(token)
      matching_facts(token).each { |fact| link(token, fact) }
      emit(token) if matched?(token) == passes_when_matched?
    end

    def right_activate(fact)
      matching_tokens(fact).each do |token|
        already_matched = matched?(token)
        link(token, fact)
        next if already_matched

        passes_when_matched? ? emit(token) : retract(token)
      end
    end

    def right_deactivate(fact)
      tokens = @tokens_matched_by.delete(fact)
      return unless tokens

      tokens.each do |token|
        facts = @facts_matching[token]
        facts.delete(fact)
        next unless facts.empty?

        @facts_matching.delete(token)
        passes_when_matched? ? retract(token) : emit(token)
      end
    end

    def left_deactivate(token)
      retract(token)
      facts = @facts_matching.delete(token)
      facts&.each { |fact| unlink_token(fact, token) }
    end

    # Whether `token` has at least one matching fact.
    def matched?(token)
      @facts_matching.key?(token)
    end

    # The facts that match `token`.
    def facts_matching(token)
      @facts_matching[token].to_a
    end

    # The tokens that `fact` matches.
    def tokens_matched_by(fact)
      @tokens_matched_by[fact].to_a
    end

    # Forgets every link, without telling the successors.
    def reset
      @facts_matching.clear
      @tokens_matched_by.clear
    end

    private

    def link(token, fact)
      (@facts_matching[token] ||= Set.new) << fact
      (@tokens_matched_by[fact] ||= Set.new) << token
    end

    def unlink_token(fact, token)
      tokens = @tokens_matched_by[fact]
      return unless tokens

      tokens.delete(token)
      @tokens_matched_by.delete(fact) if tokens.empty?
    end

    # Passes `token` on, extended by a position that holds no fact.
    def emit(token)
      new_token = Token.new(token, nil, self)
      token.add_child(new_token)
      activate_successors(new_token)
    end

    # Takes back what this node passed on for `token`.
    def retract(token)
      token.children.select { |child| child.node.equal?(self) }.each do |child|
        token.remove_child(child)
        deactivate_successors(child)
      end
    end
  end
end
