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
  def setup_engine
    KBS::Engine.new
  end

  def assert_rule_fired(engine, rule_name)
    # Check if rule action was executed
    # Implementation depends on tracking mechanism
  end

  def refute_rule_fired(engine, rule_name)
    # Check that rule did not fire
  end
end
```

## Unit Testing Rules

### Test Single Rule

```ruby
require 'test_helper'

class TestTemperatureRule < Minitest::Test
  def setup
    @engine = setup_engine
    @fired = false

    # Create test rule
    @rule = KBS::Rule.new("high_temp_alert", priority: 100) do |r|
      r.conditions = [
        KBS::Condition.new(:sensor, {
          type: "temperature",
          value: :?temp
        }, predicate: lambda { |f| f[:value] > 30 })
      ]

      r.action = lambda do |facts, bindings|
        @fired = true
        @engine.add_fact(:alert, {
          type: "high_temperature",
          temperature: bindings[:?temp]
        })
      end
    end

    @engine.add_rule(@rule)
  end

  def test_fires_when_temperature_high
    @engine.add_fact(:sensor, { type: "temperature", value: 35 })
    @engine.run

    assert @fired, "Rule should fire for high temperature"

    alerts = @engine.facts.select { |f| f.type == :alert }
    assert_equal 1, alerts.size
    assert_equal 35, alerts.first[:temperature]
  end

  def test_does_not_fire_when_temperature_normal
    @engine.add_fact(:sensor, { type: "temperature", value: 25 })
    @engine.run

    refute @fired, "Rule should not fire for normal temperature"

    alerts = @engine.facts.select { |f| f.type == :alert }
    assert_empty alerts
  end

  def test_threshold_boundary
    # Test at exact threshold
    @engine.add_fact(:sensor, { type: "temperature", value: 30 })
    @engine.run

    refute @fired, "Rule should not fire at exact threshold (>= not >)"
  end
end
```

### Test Rule with Multiple Conditions

```ruby
class TestMultiConditionRule < Minitest::Test
  def setup
    @engine = setup_engine
    @fired = false

    @rule = KBS::Rule.new("high_temp_and_low_humidity") do |r|
      r.conditions = [
        KBS::Condition.new(:temperature, {
          location: :?loc,
          value: :?temp
        }, predicate: lambda { |f| f[:value] > 30 }),

        KBS::Condition.new(:humidity, {
          location: :?loc,
          value: :?hum
        }, predicate: lambda { |f| f[:value] < 40 })
      ]

      r.action = lambda do |facts, bindings|
        @fired = true
      end
    end

    @engine.add_rule(@rule)
  end

  def test_fires_when_both_conditions_met
    @engine.add_fact(:temperature, { location: "room1", value: 35 })
    @engine.add_fact(:humidity, { location: "room1", value: 30 })
    @engine.run

    assert @fired, "Rule should fire when both conditions met"
  end

  def test_does_not_fire_with_mismatched_locations
    @engine.add_fact(:temperature, { location: "room1", value: 35 })
    @engine.add_fact(:humidity, { location: "room2", value: 30 })
    @engine.run

    refute @fired, "Rule should not fire with different locations"
  end

  def test_does_not_fire_when_only_temperature_high
    @engine.add_fact(:temperature, { location: "room1", value: 35 })
    # No humidity fact
    @engine.run

    refute @fired, "Rule should not fire without humidity fact"
  end

  def test_does_not_fire_when_temperature_normal
    @engine.add_fact(:temperature, { location: "room1", value: 25 })
    @engine.add_fact(:humidity, { location: "room1", value: 30 })
    @engine.run

    refute @fired, "Rule should not fire with normal temperature"
  end
end
```

### Test Negated Conditions

```ruby
class TestNegationRule < Minitest::Test
  def setup
    @engine = setup_engine
    @fired = false

    @rule = KBS::Rule.new("alert_if_no_acknowledgment") do |r|
      r.conditions = [
        KBS::Condition.new(:error, { id: :?id }),
        KBS::Condition.new(:acknowledged, { error_id: :?id }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        @fired = true
      end
    end

    @engine.add_rule(@rule)
  end

  def test_fires_when_error_not_acknowledged
    @engine.add_fact(:error, { id: 1 })
    @engine.run

    assert @fired, "Rule should fire when error not acknowledged"
  end

  def test_does_not_fire_when_error_acknowledged
    @engine.add_fact(:error, { id: 1 })
    @engine.add_fact(:acknowledged, { error_id: 1 })
    @engine.run

    refute @fired, "Rule should not fire when error acknowledged"
  end
end
```

## Integration Testing

### Test Rule Interactions

```ruby
class TestRuleInteractions < Minitest::Test
  def setup
    @engine = setup_engine
    @alerts = []

    # Rule 1: Detect high temperature
    @engine.add_rule(KBS::Rule.new("detect_high_temp") do |r|
      r.conditions = [
        KBS::Condition.new(:sensor, { value: :?temp }, predicate: lambda { |f| f[:value] > 30 })
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:temp_alert, { severity: "high" })
      end
    end)

    # Rule 2: Escalate to critical
    @engine.add_rule(KBS::Rule.new("escalate_critical") do |r|
      r.conditions = [
        KBS::Condition.new(:temp_alert, { severity: "high" }),
        KBS::Condition.new(:sensor, { value: :?temp }, predicate: lambda { |f| f[:value] > 40 })
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:critical_alert, { type: "temperature" })
        @alerts << :critical
      end
    end)
  end

  def test_cascading_rules
    # Add high temperature
    @engine.add_fact(:sensor, { value: 45 })
    @engine.run

    # Both rules should fire
    assert @engine.facts.any? { |f| f.type == :temp_alert }
    assert @engine.facts.any? { |f| f.type == :critical_alert }
    assert_includes @alerts, :critical
  end

  def test_partial_cascade
    # Add moderately high temperature
    @engine.add_fact(:sensor, { value: 35 })
    @engine.run

    # Only first rule fires
    assert @engine.facts.any? { |f| f.type == :temp_alert }
    refute @engine.facts.any? { |f| f.type == :critical_alert }
  end
end
```

### Test Rule Priority

```ruby
class TestRulePriority < Minitest::Test
  def setup
    @engine = setup_engine
    @execution_order = []

    # High priority rule
    @engine.add_rule(KBS::Rule.new("high_priority", priority: 100) do |r|
      r.conditions = [KBS::Condition.new(:trigger, {})]
      r.action = lambda do |facts, bindings|
        @execution_order << :high
      end
    end)

    # Low priority rule
    @engine.add_rule(KBS::Rule.new("low_priority", priority: 10) do |r|
      r.conditions = [KBS::Condition.new(:trigger, {})]
      r.action = lambda do |facts, bindings|
        @execution_order << :low
      end
    end)
  end

  def test_executes_in_priority_order
    @engine.add_fact(:trigger, {})
    @engine.run

    assert_equal [:high, :low], @execution_order
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

  def load_facts(engine, facts)
    facts.each do |fact_data|
      engine.add_fact(fact_data[:type], fact_data[:attributes])
    end
  end
end

class TestWithFixtures < Minitest::Test
  include FactFixtures

  def test_with_high_temp_scenario
    engine = setup_engine
    # Add rules...

    load_facts(engine, high_temp_scenario)
    engine.run

    # Assertions...
  end
end
```

### Rule Fixtures

```ruby
module RuleFixtures
  def temperature_monitoring_rules
    [
      KBS::Rule.new("detect_high") do |r|
        r.conditions = [
          KBS::Condition.new(:sensor, { value: :?v }, predicate: lambda { |f| f[:value] > 30 })
        ]
        r.action = lambda { |facts, bindings| facts[0][:alerted] = true }
      end,

      KBS::Rule.new("detect_low") do |r|
        r.conditions = [
          KBS::Condition.new(:sensor, { value: :?v }, predicate: lambda { |f| f[:value] < 15 })
        ]
        r.action = lambda { |facts, bindings| facts[0][:alerted] = true }
      end
    ]
  end

  def load_rules(engine, rules)
    rules.each { |rule| engine.add_rule(rule) }
  end
end
```

## Coverage Strategies

### Track Rule Firings

```ruby
class CoverageTracker
  def initialize(engine)
    @engine = engine
    @rule_firings = Hash.new(0)
    @condition_matches = Hash.new(0)
  end

  def wrap_rules
    @engine.instance_variable_get(:@rules).each do |rule|
      original_action = rule.action

      rule.action = lambda do |facts, bindings|
        @rule_firings[rule.name] += 1
        original_action.call(facts, bindings)
      end
    end
  end

  def report
    puts "\n=== Coverage Report ==="

    total_rules = @engine.instance_variable_get(:@rules).size
    fired_rules = @rule_firings.keys.size
    coverage = (fired_rules.to_f / total_rules * 100).round(2)

    puts "Rules: #{fired_rules}/#{total_rules} (#{coverage}%)"

    puts "\nRule Firings:"
    @rule_firings.each do |name, count|
      puts "  #{name}: #{count}"
    end

    untested = @engine.instance_variable_get(:@rules).map(&:name) - @rule_firings.keys
    if untested.any?
      puts "\nUntested Rules:"
      untested.each { |name| puts "  - #{name}" }
    end
  end

  attr_reader :rule_firings, :condition_matches
end

# Usage
class TestWithCoverage < Minitest::Test
  def test_coverage
    engine = setup_engine
    # Add rules...

    tracker = CoverageTracker.new(engine)
    tracker.wrap_rules

    # Add facts and run
    engine.run

    tracker.report

    # Assert all rules fired
    assert_equal @engine.instance_variable_get(:@rules).size, tracker.rule_firings.size
  end
end
```

### Condition Coverage

```ruby
def test_all_condition_paths
  engine = setup_engine

  rule = KBS::Rule.new("multi_path") do |r|
    r.conditions = [
      KBS::Condition.new(:a, {}),
      KBS::Condition.new(:b, {}),
      KBS::Condition.new(:c, {}, negated: true)
    ]
    r.action = lambda { |facts, bindings| }
  end

  engine.add_rule(rule)

  # Test path 1: All conditions pass
  engine.add_fact(:a, {})
  engine.add_fact(:b, {})
  # c absent
  engine.run
  # Assert...

  # Test path 2: Negation fails
  engine = setup_engine
  engine.add_rule(rule)
  engine.add_fact(:a, {})
  engine.add_fact(:b, {})
  engine.add_fact(:c, {})  # Blocks negation
  engine.run
  # Assert...

  # Test path 3: Positive condition missing
  engine = setup_engine
  engine.add_rule(rule)
  engine.add_fact(:a, {})
  # b missing
  engine.run
  # Assert...
end
```

## Performance Testing

### Benchmark Rule Execution

```ruby
require 'benchmark'

class PerformanceTest < Minitest::Test
  def test_rule_performance
    engine = setup_engine

    # Add rule
    engine.add_rule(KBS::Rule.new("perf_test") do |r|
      r.conditions = [
        KBS::Condition.new(:data, { value: :?v })
      ]
      r.action = lambda { |facts, bindings| }
    end)

    # Add many facts
    1000.times { |i| engine.add_fact(:data, { value: i }) }

    # Benchmark
    time = Benchmark.measure { engine.run }

    assert time.real < 1.0, "Engine should complete in under 1 second"
  end

  def test_fact_addition_performance
    engine = setup_engine

    time = Benchmark.measure do
      10_000.times { |i| engine.add_fact(:data, { value: i }) }
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
    engine1.add_fact(:sensor, { id: 1, value: 25 })
    engine1.close

    # Session 2: Load facts
    engine2 = KBS::Blackboard::Engine.new(db_path: 'test.db')
    assert_equal 1, engine2.facts.size
    assert_equal 25, engine2.facts.first[:value]

    engine2.close
    File.delete('test.db') if File.exist?('test.db')
  end

  def test_audit_trail
    engine = KBS::Blackboard::Engine.new(db_path: ':memory:')

    fact = engine.add_fact(:data, { value: 1 })
    engine.update_fact(fact.id, { value: 2 })
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
  engine = setup_engine

  # Add ONLY the rule being tested
  engine.add_rule(my_test_rule)

  # No other rules to interfere
  engine.run
end
```

### 2. Test Edge Cases

```ruby
def test_edge_cases
  # Empty facts
  engine.run
  assert_empty engine.facts.select { |f| f.type == :alert }

  # Exact threshold
  engine.add_fact(:sensor, { value: 30 })
  engine.run

  # Just below threshold
  engine.add_fact(:sensor, { value: 29.99 })
  engine.run

  # Just above threshold
  engine.add_fact(:sensor, { value: 30.01 })
  engine.run
end
```

### 3. Test Side Effects

```ruby
def test_action_side_effects
  engine = setup_engine
  added_facts = []

  rule = KBS::Rule.new("test") do |r|
    r.conditions = [KBS::Condition.new(:trigger, {})]
    r.action = lambda do |facts, bindings|
      new_fact = engine.add_fact(:result, { value: 42 })
      added_facts << new_fact
    end
  end

  engine.add_rule(rule)
  engine.add_fact(:trigger, {})
  engine.run

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
    @engine = setup_engine
    @test_db = "test_#{SecureRandom.hex(8)}.db"
  end

  def teardown
    @engine.close if @engine.respond_to?(:close)
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
- **[Examples](../examples/stock-trading.md)** - See tested examples

---

*Good tests make rule changes safe. Test each rule thoroughly.*
