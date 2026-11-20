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
      fact_value = fact.attributes[test[:fact_field]]

      if test.key?(:expected_value)
        expected = test[:expected_value]
        return fact_value && expected.call(fact_value) if expected.is_a?(Proc)

        compare_join_values(test[:operation], fact_value, expected)
      elsif test.key?(:other_fact_field)
        compare_join_values(test[:operation], fact_value, fact.attributes[test[:other_fact_field]])
      else
        token_value = token.fact_at(test[:token_field_index])&.attributes&.[](test[:token_field])
        compare_join_values(test[:operation], token_value, fact_value)
      end
    end

    def compare_join_values(operation, left, right)
      case operation
      when :eq then left == right
      when :ne then left != right
      else true
      end
    end
  end
end
