# frozen_string_literal: true

module KBS
  # Lets a join or negation node find its candidates through hash indexes
  # on its two memories.
  #
  # The node's equality tests between a token and a fact (the ones a
  # shared ?variable compiles to) become the index key: the alpha memory
  # is indexed on the fact fields and the beta memory on the token
  # fields. Every other test is "residual" and is still evaluated for
  # each candidate. A node with no such test scans its memories.
  #
  # The including class supplies `tests`, `alpha_memory` and
  # `beta_memory` readers and includes KBS::JoinTests.
  module JoinIndexing
    attr_reader :residual_tests

    # Call when the tests or memories are set.
    def build_join_indexes
      keyed, @residual_tests = (tests || []).partition { |test| JoinIndexing.indexable?(test) }
      @right_index = @left_index = nil
      return if keyed.empty? || alpha_memory.nil? || beta_memory.nil?

      @fact_fields = keyed.map { |test| test[:fact_field] }
      @token_specs = keyed.map { |test| [test[:token_field_index], test[:token_field]] }
      @right_index = alpha_memory.index_on(@fact_fields)
      @left_index = beta_memory.index_on(@token_specs)
    end

    def indexed?
      !@right_index.nil?
    end

    # Facts in the alpha memory that pass the indexed tests for `token`.
    def candidate_facts(token)
      return alpha_memory.items unless indexed?

      @right_index.lookup(MemoryIndex.token_key(token, @token_specs))
    end

    # Tokens in the beta memory that pass the indexed tests for `fact`.
    def candidate_tokens(fact)
      return beta_memory.tokens unless indexed?

      @left_index.lookup(MemoryIndex.fact_key(fact, @fact_fields))
    end

    # Facts that join with `token`.
    def matching_facts(token)
      candidate_facts(token).select { |fact| join_tests_pass?(@residual_tests, token, fact) }
    end

    # Tokens that join with `fact`.
    def matching_tokens(fact)
      candidate_tokens(fact).select { |token| join_tests_pass?(@residual_tests, token, fact) }
    end

    # An equality test between a token field and a fact field.
    def self.indexable?(test)
      test[:operation] == :eq &&
        test.key?(:token_field_index) &&
        !test.key?(:expected_value) &&
        !test.key?(:other_fact_field)
    end
  end
end
