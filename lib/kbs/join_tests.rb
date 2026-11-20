# frozen_string_literal: true

module KBS
  # Evaluates the tests a join or negation node applies to a token and a
  # fact. A test is a Hash in one of three forms:
  #
  #   { fact_field:, expected_value:, operation: }
  #     compares a fact attribute with a constant, or calls a Proc with it
  #
  #   { fact_field:, other_fact_field:, operation: }
  #     compares two attributes of the same fact
  #
  #   { token_field_index:, token_field:, fact_field:, operation: }
  #     compares a fact attribute with an attribute of the fact that an
  #     earlier condition matched; token_field_index is that condition's
  #     position in the rule
  #
  # The including class supplies the tests through a `tests` reader.
  module JoinTests
    def perform_join_tests(token, fact)
      join_tests_pass?(tests, token, fact)
    end

    def join_tests_pass?(tests, token, fact)
      tests.all? { |test| join_test_passes?(test, token, fact) }
    end

    def join_test_passes?(test, token, fact)
      expected = test[:expected_value]
      return predicate_passes?(expected, fact.attributes[test[:fact_field]]) if expected.is_a?(Proc)

      compare_join_values(test[:operation], *join_operands(test, token, fact))
    end

    # An operation with no entry here passes.
    COMPARISONS = { eq: :==, ne: :!= }.freeze

    def compare_join_values(operation, left, right)
      comparison = COMPARISONS[operation]
      comparison ? left.public_send(comparison, right) : true
    end

    private

    # A Proc given as the expected value is called with the fact's value,
    # and fails without one.
    def predicate_passes?(predicate, value)
      value && predicate.call(value)
    end

    # The two values a test compares: the fact's field against a constant,
    # against another field of the same fact, or against a field of a fact
    # matched earlier (in which case the earlier value comes first).
    def join_operands(test, token, fact)
      attributes = fact.attributes
      fact_value = attributes[test[:fact_field]]
      if test.key?(:expected_value)
        [fact_value, test[:expected_value]]
      elsif test.key?(:other_fact_field)
        [fact_value, attributes[test[:other_fact_field]]]
      else
        [token.fact_at(test[:token_field_index])&.attributes&.[](test[:token_field]), fact_value]
      end
    end
  end
end
