# frozen_string_literal: true

module KBS
  class NegationNode
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
            token.children.each do |child|
              @successors.each { |s| s.deactivate(child) if s.respond_to?(:deactivate) }
            end
            token.children.clear
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

    private

    def perform_join_tests(token, fact)
      @tests.all? do |test|
        fact_value = fact.attributes[test[:fact_field]]

        # If test has expected_value, compare against that constant
        if test.key?(:expected_value)
          if test[:operation] == :eq
            fact_value == test[:expected_value]
          elsif test[:operation] == :ne
            fact_value != test[:expected_value]
          else
            true
          end
        else
          # Otherwise compare with token value
          token_value = token.facts[test[:token_field_index]]&.attributes&.[](test[:token_field])

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
end
