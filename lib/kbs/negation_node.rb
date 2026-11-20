# frozen_string_literal: true

module KBS
  class NegationNode
    include JoinTests

    attr_accessor :alpha_memory, :beta_memory, :successors, :tests

    def initialize(alpha_memory, beta_memory, tests = [])
      @alpha_memory = alpha_memory
      @beta_memory = beta_memory
      @successors = []
      @tests = tests
      @tokens_with_matches = Hash.new { |h, k| h[k] = [] }

      alpha_memory.successors << self if alpha_memory
      beta_memory.successors << self if beta_memory
    end

    def left_activate(token)
      matches = @alpha_memory.items.select { |fact| perform_join_tests(token, fact) }

      if matches.empty?
        new_token = Token.new(token, nil, self)
        token.children << new_token
        @successors.each { |s| s.activate(new_token) }
      else
        @tokens_with_matches[token] = matches
      end
    end

    def right_activate(fact)
      @beta_memory.tokens.each do |token|
        if perform_join_tests(token, fact)
          if @tokens_with_matches[token].empty?
            left_deactivate(token)
          end
          @tokens_with_matches[token] << fact
        end
      end
    end

    def right_deactivate(fact)
      @beta_memory.tokens.each do |token|
        if @tokens_with_matches[token].include?(fact)
          @tokens_with_matches[token].delete(fact)

          if @tokens_with_matches[token].empty?
            new_token = Token.new(token, nil, self)
            token.children << new_token
            @successors.each { |s| s.activate(new_token) }
          end
        end
      end
    end

    def left_deactivate(token)
      token.children.select { |child| child.node == self }.each do |child|
        @successors.each { |s| s.deactivate(child) if s.respond_to?(:deactivate) }
        token.children.delete(child)
      end
      @tokens_with_matches.delete(token)
    end

    def reset
      @tokens_with_matches.clear
    end
  end
end
