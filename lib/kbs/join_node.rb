# frozen_string_literal: true

module KBS
  class JoinNode
    attr_accessor :alpha_memory, :beta_memory, :successors, :tests
    attr_reader :left_linked, :right_linked

    def initialize(alpha_memory, beta_memory, tests = [])
      @alpha_memory = alpha_memory
      @beta_memory = beta_memory
      @successors = []
      @tests = tests
      @left_linked = true
      @right_linked = true

      alpha_memory.successors << self if alpha_memory
      beta_memory.successors << self if beta_memory
    end

    def left_unlink!
      @left_linked = false
    end

    def left_relink!
      @left_linked = true
      @beta_memory.tokens.each { |token| left_activate(token) } if @beta_memory
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

      @alpha_memory.items.each do |fact|
        if perform_join_tests(token, fact)
          new_token = Token.new(token, fact, self)
          token.children << new_token if token
          @successors.each { |s| s.activate(new_token) }
        end
      end
    end

    def right_activate(fact)
      return unless @left_linked && @right_linked

      parent_tokens = @beta_memory ? @beta_memory.tokens : [Token.new(nil, nil, nil)]

      parent_tokens.each do |token|
        if perform_join_tests(token, fact)
          new_token = Token.new(token, fact, self)
          token.children << new_token if token
          @successors.each { |s| s.activate(new_token) }
        end
      end
    end

    def left_deactivate(token)
      token.children.each do |child|
        @successors.each { |s| s.deactivate(child) if s.respond_to?(:deactivate) }
      end
      token.children.clear
    end

    def right_deactivate(fact)
      tokens_to_remove = []

      if @beta_memory
        @beta_memory.tokens.each do |token|
          token.children.select { |child| child.fact == fact }.each do |child|
            tokens_to_remove << child
            @successors.each { |s| s.deactivate(child) if s.respond_to?(:deactivate) }
          end
        end
      end

      tokens_to_remove.each { |token| token.parent.children.delete(token) if token.parent }
    end

    private

    def perform_join_tests(token, fact)
      @tests.all? do |test|
        token_value = token.facts[test[:token_field_index]]&.attributes&.[](test[:token_field])
        fact_value = fact.attributes[test[:fact_field]]

        if test[:operation] == :eq
          token_value == fact_value
        elsif test[:operation] == :ne
          token_value != fact_value
        else
          true
        end
      end
    end
  end
end
