# Testing Rules

Comprehensive testing strategies for rule-based systems. This guide covers unit testing, integration testing, test fixtures, and coverage analysis for KBS applications.

## Testing Overview

Rule-based systems require testing at multiple levels:

1. **Unit Tests** - Test individual rules in isolation
2. **Integration Tests** - Test rule interactions
3. **Fact Fixtures** - Reusable test data
4. **Coverage** - Ensure all rules and conditions are tested
5. **Performance Tests** - Verify rule execution speed

## Setup

### Test Framework

```ruby
# Gemfile
group :test do
  gem 'minitest', '~> 5.0'
  gem 'simplecov', require: false  # Coverage
end
```

### Test Helper

```ruby
# test/test_helper.rb
require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'kbs'

class Minitest::Test
  def assert_rule_fired(kb, rule_name)
    # Check if rule action was executed
    # Implementation depends on tracking mechanism
  end

  def refute_rule_fired(kb, rule_name)
    # Check that rule did not fire
  end
end
```

## Unit Testing Rules

### Test Single Rule

```ruby
require 'test_helper'

class TestTemperatureRule < Minitest::Test
  def test_fires_when_temperature_high
    fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_alert", priority: 100 do
        on :sensor,
          type: "temperature",
          value: :temp?,
          predicate: greater_than(30)

        perform do |facts, bindings|
          fired = true
          fact :alert,
            type: "high_temperature",
            temperature: bindings[:temp?]
        end
      end

      fact :sensor, type: "temperature", value: 35
      run
    end

    assert fired, "Rule should fire for high temperature"

    alerts = kb.engine.facts.select { |f| f.type == :alert }
    assert_equal 1, alerts.size
    assert_equal 35, alerts.first[:temperature]
  end

  def test_does_not_fire_when_temperature_normal
    fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_alert", priority: 100 do
        on :sensor,
          type: "temperature",
          value: :temp?,
          predicate: greater_than(30)

        perform do |facts, bindings|
          fired = true
          fact :alert,
            type: "high_temperature",
            temperature: bindings[:temp?]
        end
      end

      fact :sensor, type: "temperature", value: 25
      run
    end

    refute fired, "Rule should not fire for normal temperature"

    alerts = kb.engine.facts.select { |f| f.type == :alert }
    assert_empty alerts
  end

  def test_threshold_boundary
    fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_alert" do
        on :sensor,
          type: "temperature",
          value: :temp?,
          predicate: greater_than(30)

        perform do |facts, bindings|
          fired = true
        end
      end

      # Test at exact threshold
      fact :sensor, type: "temperature", value: 30
      run
    end

    refute fired, "Rule should not fire at exact threshold (> not >=)"
  end
end
```

### Test Rule with Multiple Conditions

```ruby
class TestMultiConditionRule < Minitest::Test
  def test_fires_when_both_conditions_met
    fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_and_low_humidity" do
        on :temperature,
          location: :loc?,
          value: :temp?,
          predicate: greater_than(30)

        on :humidity,
          location: :loc?,
          value: :hum?,
          predicate: less_than(40)

        perform do |facts, bindings|
          fired = true
        end
      end

      fact :temperature, location: "room1", value: 35
      fact :humidity, location: "room1", value: 30
      run
    end

    assert fired, "Rule should fire when both conditions met"
  end

  def test_does_not_fire_with_mismatched_locations
    fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_and_low_humidity" do
        on :temperature,
          location: :loc?,
          value: :temp?,
          predicate: greater_than(30)

        on :humidity,
          location: :loc?,
          value: :hum?,
          predicate: less_than(40)

        perform do |facts, bindings|
          fired = true
        end
      end

      fact :temperature, location: "room1", value: 35
      fact :humidity, location: "room2", value: 30
      run
    end

    refute fired, "Rule should not fire with different locations"
  end

  def test_does_not_fire_when_only_temperature_high
    fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_and_low_humidity" do
        on :temperature,
          location: :loc?,
          value: :temp?,
          predicate: greater_than(30)

        on :humidity,
          location: :loc?,
          value: :hum?,
          predicate: less_than(40)

        perform do |facts, bindings|
          fired = true
        end
      end

      fact :temperature, location: "room1", value: 35
      # No humidity fact
      run
    end

    refute fired, "Rule should not fire without humidity fact"
  end

  def test_does_not_fire_when_temperature_normal
    fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_and_low_humidity" do
        on :temperature,
          location: :loc?,
          value: :temp?,
          predicate: greater_than(30)

        on :humidity,
          location: :loc?,
          value: :hum?,
          predicate: less_than(40)

        perform do |facts, bindings|
          fired = true
        end
      end

      fact :temperature, location: "room1", value: 25
      fact :humidity, location: "room1", value: 30
      run
    end

    refute fired, "Rule should not fire with normal temperature"
  end
end
```

### Test Negated Conditions

```ruby
class TestNegationRule < Minitest::Test
  def test_fires_when_error_not_acknowledged
    fired = false

    kb = KBS.knowledge_base do
      rule "alert_if_no_acknowledgment" do
        on :error, id: :id?
        without :acknowledged, error_id: :id?

        perform do |facts, bindings|
          fired = true
        end
      end

      fact :error, id: 1
      run
    end

    assert fired, "Rule should fire when error not acknowledged"
  end

  def test_does_not_fire_when_error_acknowledged
    fired = false

    kb = KBS.knowledge_base do
      rule "alert_if_no_acknowledgment" do
        on :error, id: :id?
        without :acknowledged, error_id: :id?

        perform do |facts, bindings|
          fired = true
        end
      end

      fact :error, id: 1
      fact :acknowledged, error_id: 1
      run
    end

    refute fired, "Rule should not fire when error acknowledged"
  end
end
```

## Integration Testing

### Test Rule Interactions

```ruby
class TestRuleInteractions < Minitest::Test
  def test_cascading_rules
    alerts = []

    kb = KBS.knowledge_base do
      # Rule 1: Detect high temperature
      rule "detect_high_temp" do
        on :sensor, value: :temp?, predicate: greater_than(30)

        perform do |facts, bindings|
          fact :temp_alert, severity: "high"
        end
      end

      # Rule 2: Escalate to critical
      rule "escalate_critical" do
        on :temp_alert, severity: "high"
        on :sensor, value: :temp?, predicate: greater_than(40)

        perform do |facts, bindings|
          fact :critical_alert, type: "temperature"
          alerts << :critical
        end
      end

      # Add high temperature
      fact :sensor, value: 45
      run
    end

    # Both rules should fire
    assert kb.engine.facts.any? { |f| f.type == :temp_alert }
    assert kb.engine.facts.any? { |f| f.type == :critical_alert }
    assert_includes alerts, :critical
  end

  def test_partial_cascade
    alerts = []

    kb = KBS.knowledge_base do
      rule "detect_high_temp" do
        on :sensor, value: :temp?, predicate: greater_than(30)
        perform { fact :temp_alert, severity: "high" }
      end

      rule "escalate_critical" do
        on :temp_alert, severity: "high"
        on :sensor, value: :temp?, predicate: greater_than(40)
        perform do |facts, bindings|
          fact :critical_alert, type: "temperature"
          alerts << :critical
        end
      end

      # Add moderately high temperature
      fact :sensor, value: 35
      run
    end

    # Only first rule fires
    assert kb.engine.facts.any? { |f| f.type == :temp_alert }
    refute kb.engine.facts.any? { |f| f.type == :critical_alert }
  end
end
```

### Test Rule Priority

```ruby
class TestRulePriority < Minitest::Test
  def test_executes_in_priority_order
    execution_order = []

    kb = KBS.knowledge_base do
      # High priority rule
      rule "high_priority", priority: 100 do
        on :trigger, {}
        perform { execution_order << :high }
      end

      # Low priority rule
      rule "low_priority", priority: 10 do
        on :trigger, {}
        perform { execution_order << :low }
      end

      fact :trigger, {}
      run
    end

    assert_equal [:high, :low], execution_order
  end
end
```

## Test Fixtures

### Fact Fixtures

```ruby
module FactFixtures
  def sensor_facts(count: 10)
    count.times.map do |i|
      { type: :sensor, attributes: { id: i, value: rand(20..40) } }
    end
  end

  def high_temp_scenario
    [
      { type: :sensor, attributes: { location: "room1", value: 35 } },
      { type: :sensor, attributes: { location: "room2", value: 38 } },
      { type: :threshold, attributes: { value: 30 } }
    ]
  end

  def normal_scenario
    [
      { type: :sensor, attributes: { location: "room1", value: 22 } },
      { type: :sensor, attributes: { location: "room2", value: 24 } },
      { type: :threshold, attributes: { value: 30 } }
    ]
  end

  def load_facts_into_kb(kb, facts)
    facts.each do |fact_data|
      kb.fact fact_data[:type], fact_data[:attributes]
    end
  end
end

class TestWithFixtures < Minitest::Test
  include FactFixtures

  def test_with_high_temp_scenario
    kb = KBS.knowledge_base do
      rule "check_threshold" do
        on :sensor, value: :v?, predicate: greater_than(30)
        perform { }
      end
    end

    load_facts_into_kb(kb, high_temp_scenario)
    kb.run

    # Assertions...
  end
end
```

### Rule Fixtures

```ruby
module RuleFixtures
  # Note: Since DSL rules are defined in blocks,
  # we provide factory methods instead of rule objects

  def add_temperature_monitoring_rules(kb)
    kb.instance_eval do
      rule "detect_high" do
        on :sensor, value: :v?, predicate: greater_than(30)
        perform { |facts, bindings| facts[0][:alerted] = true }
      end

      rule "detect_low" do
        on :sensor, value: :v?, predicate: less_than(15)
        perform { |facts, bindings| facts[0][:alerted] = true }
      end
    end
  end
end
```

## Coverage Strategies

### Track Rule Firings

```ruby
class CoverageTracker
  def initialize(kb)
    @kb = kb
    @rule_firings = Hash.new(0)
  end

  def wrap_rules
    @kb.engine.instance_variable_get(:@rules).each do |rule|
      original_action = rule.action

      rule.action = lambda do |facts, bindings|
        @rule_firings[rule.name] += 1
        original_action.call(facts, bindings)
      end
    end
  end

  def report
    puts "\n=== Coverage Report ==="

    total_rules = @kb.engine.instance_variable_get(:@rules).size
    fired_rules = @rule_firings.keys.size
    coverage = (fired_rules.to_f / total_rules * 100).round(2)

    puts "Rules: #{fired_rules}/#{total_rules} (#{coverage}%)"

    puts "\nRule Firings:"
    @rule_firings.each do |name, count|
      puts "  #{name}: #{count}"
    end

    untested = @kb.engine.instance_variable_get(:@rules).map(&:name) - @rule_firings.keys
    if untested.any?
      puts "\nUntested Rules:"
      untested.each { |name| puts "  - #{name}" }
    end
  end

  attr_reader :rule_firings
end

# Usage
class TestWithCoverage < Minitest::Test
  def test_coverage
    kb = KBS.knowledge_base do
      rule "rule1" do
        on :fact, {}
        perform { }
      end

      rule "rule2" do
        on :other, {}
        perform { }
      end
    end

    tracker = CoverageTracker.new(kb)
    tracker.wrap_rules

    # Add facts and run
    kb.fact :fact, {}
    kb.run

    tracker.report

    # Assert all rules fired
    # (or check specific coverage requirements)
  end
end
```

### Condition Coverage

```ruby
def test_all_condition_paths
  # Test path 1: All conditions pass
  kb1 = KBS.knowledge_base do
    rule "multi_path" do
      on :a, {}
      on :b, {}
      without :c, {}
      perform { }
    end

    fact :a, {}
    fact :b, {}
    # c absent
    run
  end
  # Assert...

  # Test path 2: Negation fails
  kb2 = KBS.knowledge_base do
    rule "multi_path" do
      on :a, {}
      on :b, {}
      without :c, {}
      perform { }
    end

    fact :a, {}
    fact :b, {}
    fact :c, {}  # Blocks negation
    run
  end
  # Assert...

  # Test path 3: Positive condition missing
  kb3 = KBS.knowledge_base do
    rule "multi_path" do
      on :a, {}
      on :b, {}
      without :c, {}
      perform { }
    end

    fact :a, {}
    # b missing
    run
  end
  # Assert...
end
```

## Performance Testing

### Benchmark Rule Execution

```ruby
require 'benchmark'

class PerformanceTest < Minitest::Test
  def test_rule_performance
    time = Benchmark.measure do
      kb = KBS.knowledge_base do
        rule "perf_test" do
          on :data, value: :v?
          perform { }
        end

        # Add many facts
        1000.times { |i| fact :data, value: i }
        run
      end
    end

    assert time.real < 1.0, "Engine should complete in under 1 second"
  end

  def test_fact_addition_performance
    kb = KBS.knowledge_base

    time = Benchmark.measure do
      10_000.times { |i| kb.fact :data, value: i }
    end

    rate = 10_000 / time.real
    assert rate > 10_000, "Should add >10k facts/sec, got #{rate.round(2)}"
  end
end
```

## Testing Blackboard Persistence

### Test with SQLite

```ruby
class TestBlackboardPersistence < Minitest::Test
  def test_facts_persist_across_sessions
    # Session 1: Add facts
    engine1 = KBS::Blackboard::Engine.new(db_path: 'test.db')
    kb1 = KBS.knowledge_base(engine: engine1) do
      fact :sensor, id: 1, value: 25
    end
    kb1.close

    # Session 2: Load facts
    engine2 = KBS::Blackboard::Engine.new(db_path: 'test.db')
    assert_equal 1, engine2.facts.size
    assert_equal 25, engine2.facts.first[:value]

    engine2.close
    File.delete('test.db') if File.exist?('test.db')
  end

  def test_audit_trail
    engine = KBS::Blackboard::Engine.new(db_path: ':memory:')

    fact = engine.add_fact(:data, value: 1)
    engine.update_fact(fact.id, value: 2)
    engine.delete_fact(fact.id)

    history = engine.fact_history(fact.id)

    assert_equal 3, history.size
    assert_equal "add", history[0][:operation]
    assert_equal "update", history[1][:operation]
    assert_equal "delete", history[2][:operation]
  end
end
```

## Testing Best Practices

### 1. Isolate Rules

```ruby
def test_single_rule_only
  kb = KBS.knowledge_base do
    # Add ONLY the rule being tested
    rule "my_test_rule" do
      on :trigger, {}
      perform { }
    end

    # No other rules to interfere
    fact :trigger, {}
    run
  end
end
```

### 2. Test Edge Cases

```ruby
def test_edge_cases
  # Empty facts
  kb = KBS.knowledge_base do
    rule "check" do
      on :sensor, value: :v?
      perform { }
    end
    run
  end
  assert_empty kb.engine.facts.select { |f| f.type == :alert }

  # Exact threshold
  kb = KBS.knowledge_base do
    rule "check" do
      on :sensor, value: :v?, predicate: greater_than(30)
      perform { }
    end
    fact :sensor, value: 30
    run
  end

  # Just below threshold
  kb = KBS.knowledge_base do
    rule "check" do
      on :sensor, value: :v?, predicate: greater_than(30)
      perform { }
    end
    fact :sensor, value: 29.99
    run
  end

  # Just above threshold
  kb = KBS.knowledge_base do
    rule "check" do
      on :sensor, value: :v?, predicate: greater_than(30)
      perform { }
    end
    fact :sensor, value: 30.01
    run
  end
end
```

### 3. Test Side Effects

```ruby
def test_action_side_effects
  added_facts = []

  kb = KBS.knowledge_base do
    rule "test" do
      on :trigger, {}
      perform do |facts, bindings|
        new_fact = fact :result, value: 42
        added_facts << new_fact
      end
    end

    fact :trigger, {}
    run
  end

  assert_equal 1, added_facts.size
  assert_equal 42, added_facts.first[:value]
end
```

### 4. Use Descriptive Test Names

```ruby
def test_high_temperature_alert_fires_when_sensor_exceeds_threshold
  # Clear what this tests
end

def test_alert_not_sent_twice_for_same_sensor
  # Explains the scenario
end
```

### 5. Setup and Teardown

```ruby
class TestWithSetup < Minitest::Test
  def setup
    @test_db = "test_#{SecureRandom.hex(8)}.db"
  end

  def teardown
    File.delete(@test_db) if File.exist?(@test_db)
  end
end
```

## Testing Checklist

- [ ] Test each rule fires with correct facts
- [ ] Test each rule doesn't fire without required facts
- [ ] Test boundary conditions
- [ ] Test negated conditions
- [ ] Test variable bindings
- [ ] Test rule priorities
- [ ] Test rule interactions
- [ ] Test action side effects
- [ ] Test persistence (if using blackboard)
- [ ] Measure performance
- [ ] Achieve high rule coverage

## Next Steps

- **[Debugging Guide](debugging.md)** - Debug failing tests
- **[Performance Guide](performance.md)** - Optimize slow tests
- **[Architecture](../architecture/index.md)** - Understand rule execution
- **[Examples](../examples/index.md)** - See tested examples

---

*Good tests make rule changes safe. Test each rule thoroughly.*
