# frozen_string_literal: true

module KBS
  # Compiles a rule's conditions into the join tests for each condition.
  #
  # A ?variable that an earlier positive condition bound becomes an
  # equality test against that condition's fact, so the same variable in
  # two conditions joins them. A variable used twice in one condition
  # compares the two attributes of the same fact. Variables that first
  # appear in a negated or exists condition are local to it: such a
  # condition adds no fact to the match, so it binds nothing for later
  # conditions.
  class JoinTestBuilder
    def initialize(conditions)
      @conditions = conditions
    end

    # @return [Array<Array<Hash>>] the tests for each condition, in order
    def tests
      bound = {}

      @conditions.each_with_index.map do |condition, index|
        local = {}
        tests = type_tests(condition, index) + variable_tests(condition, bound, local)
        remember_bindings(bound, local, index) if condition.binds_fact?
        tests
      end
    end

    def self.variable?(value)
      value.is_a?(Symbol) && value.to_s.end_with?('?')
    end

    private

    # Records where each variable of a condition is first bound: the
    # condition's index and the field.
    def remember_bindings(bound, local, index)
      local.each { |variable, field| bound[variable] ||= [index, field] }
    end

    # Condition#type is merged over a user attribute named :type in the
    # alpha pattern, so a constant or Proc on that attribute is tested here.
    def type_tests(condition, index)
      user_type = condition.pattern[:type]
      return [] if user_type.nil? || user_type == condition.type || self.class.variable?(user_type)

      [{
        token_field_index: index,
        token_field: :type,
        fact_field: :type,
        operation: :eq,
        expected_value: user_type
      }]
    end

    # Records in `local` the first field each variable appears on in this
    # condition.
    def variable_tests(condition, bound, local)
      condition.pattern.filter_map do |field, value|
        next unless self.class.variable?(value)

        first_field = local[value]
        next { fact_field: field, other_fact_field: first_field, operation: :eq } if first_field

        local[value] = field
        token_test(bound[value], field)
      end
    end

    # The test of `field` against the earlier condition that bound the
    # variable, or nil when none did.
    def token_test(binding, field)
      return unless binding

      index, token_field = binding
      { token_field_index: index, token_field: token_field, fact_field: field, operation: :eq }
    end
  end
end
