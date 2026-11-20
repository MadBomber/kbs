# frozen_string_literal: true

require_relative 'test_helper'

class TestJoinTests < Minitest::Test
  class Host
    include KBS::JoinTests

    attr_reader :tests

    def initialize(tests)
      @tests = tests
    end
  end

  def setup
    @sensor = KBS::Fact.new(:sensor, id: 1, temp: 30)
    @token = KBS::Token.new(nil, @sensor, nil)
  end

  def test_no_tests_pass
    assert Host.new([]).perform_join_tests(@token, KBS::Fact.new(:x))
  end

  def test_token_equality
    host = Host.new([{ token_field_index: 0, token_field: :id, fact_field: :sensor_id, operation: :eq }])

    assert host.perform_join_tests(@token, KBS::Fact.new(:alert, sensor_id: 1))
    refute host.perform_join_tests(@token, KBS::Fact.new(:alert, sensor_id: 2))
  end

  def test_token_inequality
    host = Host.new([{ token_field_index: 0, token_field: :id, fact_field: :sensor_id, operation: :ne }])

    refute host.perform_join_tests(@token, KBS::Fact.new(:alert, sensor_id: 1))
    assert host.perform_join_tests(@token, KBS::Fact.new(:alert, sensor_id: 2))
  end

  def test_token_index_is_the_condition_position
    negated = KBS::Token.new(@token, nil, nil)
    reading = KBS::Fact.new(:reading, id: 7)
    token = KBS::Token.new(negated, reading, nil)
    host = Host.new([{ token_field_index: 2, token_field: :id, fact_field: :reading_id, operation: :eq }])

    assert host.perform_join_tests(token, KBS::Fact.new(:note, reading_id: 7))
    refute host.perform_join_tests(token, KBS::Fact.new(:note, reading_id: 1))
  end

  def test_expected_value_constant
    host = Host.new([{ fact_field: :type, expected_value: "temperature", operation: :eq }])

    assert host.perform_join_tests(@token, KBS::Fact.new(:sensor, type: "temperature"))
    refute host.perform_join_tests(@token, KBS::Fact.new(:sensor, type: "humidity"))
  end

  def test_expected_value_proc
    host = Host.new([{ fact_field: :type, expected_value: ->(v) { v.start_with?("temp") }, operation: :eq }])

    assert host.perform_join_tests(@token, KBS::Fact.new(:sensor, type: "temperature"))
    refute host.perform_join_tests(@token, KBS::Fact.new(:sensor, type: "humidity"))
    refute host.perform_join_tests(@token, KBS::Fact.new(:sensor))
  end

  def test_other_fact_field
    host = Host.new([{ fact_field: :right, other_fact_field: :left, operation: :eq }])

    assert host.perform_join_tests(@token, KBS::Fact.new(:pair, left: 1, right: 1))
    refute host.perform_join_tests(@token, KBS::Fact.new(:pair, left: 1, right: 2))
  end

  def test_all_tests_must_pass
    host = Host.new([
                      { token_field_index: 0, token_field: :id, fact_field: :sensor_id, operation: :eq },
                      { token_field_index: 0, token_field: :temp, fact_field: :temp, operation: :eq }
                    ])

    assert host.perform_join_tests(@token, KBS::Fact.new(:alert, sensor_id: 1, temp: 30))
    refute host.perform_join_tests(@token, KBS::Fact.new(:alert, sensor_id: 1, temp: 31))
  end
end
