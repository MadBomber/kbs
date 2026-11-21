# frozen_string_literal: true

module KBS
  # Joins the partial matches of the conditions before it with the facts
  # of one more positive condition.
  class JoinNode
    include NetworkNode
    include JoinTests
    include JoinIndexing

    attr_accessor :successors
    attr_reader :alpha_memory, :beta_memory, :tests, :left_linked, :right_linked

    def initialize(alpha_memory, beta_memory, tests = [])
      @alpha_memory = alpha_memory
      @beta_memory = beta_memory
      @successors = []
      @tests = tests
      @left_linked = true
      @right_linked = true
      @tokens_by_fact = {}

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

    def left_unlink!
      @left_linked = false
    end

    # The beta memory relinks when it gains its first token, and then
    # propagates that token itself, so there is nothing to replay here.
    def left_relink!
      @left_linked = true
    end

    def right_unlink!
      @right_linked = false
    end

    def right_relink!
      @right_linked = true
      @alpha_memory.items.each { |fact| right_activate(fact) } if @alpha_memory
    end

    def left_activate(token)
      # Left activation: a new token from beta memory needs to be joined with facts from alpha memory
      return unless @left_linked && @right_linked

      matching_facts(token).each { |fact| emit(token, fact) }
    end

    def right_activate(fact)
      return unless @left_linked && @right_linked

      parent_tokens = @beta_memory ? matching_tokens(fact) : [Token.new(nil, nil, nil)]
      parent_tokens.each { |token| emit(token, fact) }
    end

    # A token left the beta memory: remove the tokens this node built
    # from it. They are among the token's children, so nothing is searched.
    def left_deactivate(token)
      token.children.select { |child| child.node.equal?(self) }.each do |child|
        token.remove_child(child)
        forget(child)
        deactivate_successors(child)
      end
    end

    # A fact left the alpha memory: remove the tokens this node built
    # from it. The node keeps them by fact, so the beta memory is not
    # scanned.
    def right_deactivate(fact)
      tokens_for(@tokens_by_fact.delete(fact)).each do |child|
        child.parent&.remove_child(child)
        deactivate_successors(child)
      end
    end

    # The tokens this node has built from `fact`.
    def tokens_built_from(fact)
      tokens_for(@tokens_by_fact[fact])
    end

    # Forgets the tokens this node has built, without telling the successors.
    def reset
      @tokens_by_fact.clear
    end

    private

    # Passes the match of `token` and `fact` on to the successors.
    def emit(token, fact)
      new_token = Token.new(token, fact, self)
      token.add_child(new_token)
      remember(new_token)
      activate_successors(new_token)
    end

    # @tokens_by_fact maps a fact to the tokens built from it: the token
    # itself while there is one, which is the common case, and a Set once
    # there are more.
    def remember(token)
      fact = token.fact
      entry = @tokens_by_fact[fact]
      case entry
      when nil then @tokens_by_fact[fact] = token
      when Set then entry << token
      else @tokens_by_fact[fact] = Set.new.compare_by_identity << entry << token
      end
    end

    def forget(token)
      fact = token.fact
      entry = @tokens_by_fact[fact]
      if entry.equal?(token)
        @tokens_by_fact.delete(fact)
      elsif entry.is_a?(Set)
        forget_one_of(entry, token, fact)
      end
    end

    # Takes `token` out of the Set of tokens built from `fact`, and drops
    # the Set when it was the last.
    def forget_one_of(tokens, token, fact)
      @tokens_by_fact.delete(fact) if tokens.delete(token).empty?
    end

    def tokens_for(entry)
      case entry
      when nil then []
      when Set then entry.to_a
      else [entry]
      end
    end
  end
end
