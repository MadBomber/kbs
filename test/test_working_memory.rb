# frozen_string_literal: true

require_relative 'test_helper'

class TestWorkingMemory < Minitest::Test
  def setup
    @wm = KBS::WorkingMemory.new
    @fact1 = KBS::Fact.new(:person, name: "Alice")
    @fact2 = KBS::Fact.new(:person, name: "Bob")
  end

  def test_initialization
    assert_equal [], @wm.facts
  end

  def test_add_fact
    result = @wm.add_fact(@fact1)

    assert_equal @fact1, result
    assert_equal 1, @wm.facts.length
    assert_equal @fact1, @wm.facts[0]
  end

  def test_add_multiple_facts
    @wm.add_fact(@fact1)
    @wm.add_fact(@fact2)

    assert_equal 2, @wm.facts.length
    assert_includes @wm.facts, @fact1
    assert_includes @wm.facts, @fact2
  end

  def test_remove_fact
    @wm.add_fact(@fact1)
    @wm.add_fact(@fact2)

    result = @wm.remove_fact(@fact1)

    assert_equal @fact1, result
    assert_equal 1, @wm.facts.length
    refute_includes @wm.facts, @fact1
    assert_includes @wm.facts, @fact2
  end

  def test_remove_nonexistent_fact
    @wm.add_fact(@fact1)
    result = @wm.remove_fact(@fact2)

    assert_equal @fact2, result
    assert_equal 1, @wm.facts.length
  end

  def test_observer_pattern_on_add
    observations = []
    observer = Object.new
    def observer.update(action, fact)
      @observations ||= []
      @observations << [action, fact]
    end
    observer.instance_variable_set(:@observations, observations)

    @wm.add_observer(observer)
    @wm.add_fact(@fact1)

    assert_equal 1, observations.length
    assert_equal :add, observations[0][0]
    assert_equal @fact1, observations[0][1]
  end

  def test_observer_pattern_on_remove
    observations = []
    observer = Object.new
    def observer.update(action, fact)
      @observations ||= []
      @observations << [action, fact]
    end
    observer.instance_variable_set(:@observations, observations)

    @wm.add_observer(observer)
    @wm.add_fact(@fact1)
    @wm.remove_fact(@fact1)

    assert_equal 2, observations.length
    assert_equal :add, observations[0][0]
    assert_equal :remove, observations[1][0]
  end

  def test_multiple_observers
    obs1_calls = []
    obs2_calls = []

    observer1 = Object.new
    def observer1.update(action, fact)
      @calls ||= []
      @calls << action
    end
    observer1.instance_variable_set(:@calls, obs1_calls)

    observer2 = Object.new
    def observer2.update(action, fact)
      @calls ||= []
      @calls << action
    end
    observer2.instance_variable_set(:@calls, obs2_calls)

    @wm.add_observer(observer1)
    @wm.add_observer(observer2)
    @wm.add_fact(@fact1)

    assert_equal 1, obs1_calls.length
    assert_equal 1, obs2_calls.length
  end
end
