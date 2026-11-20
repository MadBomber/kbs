# frozen_string_literal: true

module KBS
  class NegationNode
    include JoinTests
    include JoinIndexing

    attr_accessor :successors
    attr_reader :alpha_memory, :beta_memory, :tests

    def initialize(alpha_memory, beta_memory, tests = [])
      @alpha_memory = alpha_memory
      @beta_memory = beta_memory
      @successors = []
      @tests = tests
      @tokens_with_matches = Hash.new { |h, k| h[k] = [] }

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

    def left_activate(token)
      matches = matching_facts(token)

      if matches.empty?
        new_token = Token.new(token, nil, self)
        token.add_child(new_token)
        @successors.each { |s| s.activate(new_token) }
      else
        @tokens_with_matches[token] = matches
      end
    end

    def right_activate(fact)
      matching_tokens(fact).each do |token|
        if @tokens_with_matches[token].empty?
          left_deactivate(token)
        end
        @tokens_with_matches[token] << fact
      end
    end

    def right_deactivate(fact)
      @beta_memory.each_token do |token|
        if @tokens_with_matches[token].include?(fact)
          @tokens_with_matches[token].delete(fact)

          if @tokens_with_matches[token].empty?
            new_token = Token.new(token, nil, self)
            token.add_child(new_token)
            @successors.each { |s| s.activate(new_token) }
          end
        end
      end
    end

    def left_deactivate(token)
      token.children.select { |child| child.node.equal?(self) }.each do |child|
        @successors.each { |s| s.deactivate(child) if s.respond_to?(:deactivate) }
        token.remove_child(child)
      end
      @tokens_with_matches.delete(token)
    end

    def reset
      @tokens_with_matches.clear
    end
  end
end
