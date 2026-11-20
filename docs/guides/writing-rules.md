# Writing Rules

Master the art of authoring production rules. This guide covers best practices, patterns, and strategies for writing effective, maintainable, and performant rules in KBS.

## Rule Anatomy

Every rule consists of three parts:

```ruby
KBS.knowledge_base do
  rule "rule_name", priority: 0 do
    # 1. CONDITIONS - Pattern matching
    on :fact_type, attr: value

    # 2. ACTION - What to do when conditions match
    perform do |facts, bindings|
      # Execute logic
    end
  end
end
```

### 1. Rule Name

Choose descriptive, actionable names:

```ruby
# Good: Clear intent
"send_high_temperature_alert"
"cancel_duplicate_orders"
"escalate_critical_issues"

# Bad: Vague or cryptic
"rule1"
"process"
"check_stuff"
```

**Naming Conventions:**
- Use snake_case
- Start with verb (action-oriented)
- Be specific about what the rule does
- Include domain context

### 2. Priority

Control execution order when multiple rules match:

```ruby
KBS.knowledge_base do
  rule "critical_safety_check", priority: 100 do  # Fires first
    # ...
  end

  rule "normal_processing", priority: 50 do
    # ...
  end

  rule "cleanup_task", priority: 10 do            # Fires last
    # ...
  end
end
```

**Priority Guidelines:**
- **100+** - Safety checks, emergency shutdowns
- **50-99** - Business logic, processing
- **1-49** - Monitoring, logging, cleanup
- **0** - Default priority (no preference)

### 3. Conditions

Patterns that must match for the rule to fire. Order matters for performance.

```ruby
KBS.knowledge_base do
  rule "example" do
    # Most selective first (fewest matches)
    on :critical_alert, severity: "critical"

    # Less selective last (more matches)
    on :sensor, id: :sensor_id?

    perform do |facts, bindings|
      # Action
    end
  end
end
```

### 4. Action

Code executed when all conditions match:

```ruby
KBS.knowledge_base do
  rule "example" do
    on :alert, message: :msg?
    on :sensor, id: :sensor_id?

    perform do |facts, bindings|
      # Access matched facts
      alert = facts[0]
      sensor = facts[1]

      # Access variable bindings
      sensor_id = bindings[:sensor_id?]

      # Perform action
      notify_operator(sensor_id, alert[:message])
    end
  end
end
```

`facts` holds one fact per positive condition, in order; `without` and `exists` conditions contribute none. `bindings` maps each `?variable` to its value.

**Working memory inside `perform`:** the action block runs with the rule builder as `self`. Once the rule is built, the builder forwards `fact`, `assert`, `retract`, `modify`, `query`, `facts`, `halt` and `engine` to the knowledge base, so bare calls work. Condition keywords (`on`, `without`, `exists`, `logical`, `perform` and their aliases) raise `KBS::RuleBuiltError` there, since they can no longer change the rule. Calling the knowledge base through a local works as well:

```ruby
kb = KBS.knowledge_base do
  rule "derive" do
    on :sensor, temp: :temp?
    perform do |facts, bindings|
      kb.fact :reading_seen, temp: bindings[:temp?]
    end
  end
end

kb.fact :sensor, temp: 28
kb.run   # call run after `kb` is assigned
```

The examples below use either form.

## Condition Ordering

**Golden Rule**: Order conditions from most selective to least selective.

### Why Order Matters

```ruby
# Bad: General condition first
KBS.knowledge_base do
  rule "inefficient" do
    on :sensor, {}           # 1000 matches
    on :critical_alert, {}   # 1 match
    perform { }
  end
end
# Creates 1000 partial matches, wastes memory

# Good: Specific condition first
KBS.knowledge_base do
  rule "efficient" do
    on :critical_alert, {}   # 1 match
    on :sensor, {}           # Joins with 1000
    perform { }
  end
end
# Creates 1 partial match, efficient joins
```

### Selectivity Examples

```ruby
# Most selective (few facts)
on :emergency, level: "critical"
on :user, role: "admin"

# Moderate selectivity
on :order, status: "pending"
on :stock, exchange: "NYSE"

# Least selective (many facts)
on :sensor, {}
on :log_entry, {}
```

### Measuring Selectivity

```ruby
def measure_selectivity(kb, type, pattern)
  kb.engine.facts.count { |f|
    f.type == type &&
    pattern.all? { |k, v| f[k] == v }
  }
end

# Compare
puts measure_selectivity(kb, :critical_alert, {})  # => 1
puts measure_selectivity(kb, :sensor, {})          # => 1000

# Order: critical_alert first, sensor second
```

## Action Design

### Single Responsibility

One action, one purpose:

```ruby
# Good: Focused action
KBS.knowledge_base do
  rule "send_email" do
    on :alert, email: :email?, message: :message?
    perform do |facts, bindings|
      send_email_alert(bindings[:email?], bindings[:message?])
    end
  end
end

# Bad: Multiple responsibilities
KBS.knowledge_base do
  rule "do_everything" do
    on :trigger, email: :email?, id: :id?, data: :data?, msg: :msg?
    perform do |facts, bindings|
      send_email_alert(bindings[:email?])
      update_database(bindings[:id?])
      call_external_api(bindings[:data?])
      write_log_file(bindings[:msg?])
    end
  end
end
```

Split complex actions into multiple rules:

```ruby
kb = KBS.knowledge_base do
  # Rule 1: Detect condition
  rule "detect_high_temp", priority: 50 do
    on :sensor, temp: greater_than(30)

    perform do |facts, bindings|
      kb.fact :high_temp_detected, temp: facts[0][:temp]
    end
  end

  # Rule 2: Send alert
  rule "send_temp_alert", priority: 40 do
    on :high_temp_detected, temp: :temp?

    perform do |facts, bindings|
      send_email("High temp: #{bindings[:temp?]}")
    end
  end

  # Rule 3: Log event
  rule "log_temp_event", priority: 30 do
    on :high_temp_detected, temp: :temp?

    perform do |facts, bindings|
      logger.info("Temperature spike: #{bindings[:temp?]}")
    end
  end
end
```

### Avoid Side Effects

Actions should be deterministic and idempotent when possible:

```ruby
# Good: Idempotent (safe to run multiple times)
kb = KBS.knowledge_base do
  rule "update_alert" do
    on :trigger, id: :id?

    perform do |facts, bindings|
      # Remove old alert if exists
      old = kb.query(:alert, id: bindings[:id?]).first
      kb.retract(old) if old

      # Add new alert
      kb.fact :alert, id: bindings[:id?], message: "Alert!"
    end
  end
end

# Bad: Non-idempotent (creates duplicates)
kb = KBS.knowledge_base do
  rule "duplicate_alerts" do
    on :trigger, id: :id?

    perform do |facts, bindings|
      # Always adds, even if alert already exists
      kb.fact :alert, id: bindings[:id?], message: "Alert!"
    end
  end
end
```

Alternatively, turn duplicate facts off with `kb.engine.fact_duplication = false` (or `KBS::Engine.new(fact_duplication: false)`): asserting a fact equal to one already in working memory then returns the existing fact instead of adding another.

### Error Handling

Protect against failures:

```ruby
kb = KBS.knowledge_base do
  rule "safe_email" do
    on :alert, email: :email?, message: :message?

    perform do |facts, bindings|
      begin
        send_email(bindings[:email?], bindings[:message?])
      rescue Net::SMTPError => e
        logger.error("Failed to send email: #{e.message}")
        # Add failure fact for retry logic
        kb.fact :email_failure,
          email: bindings[:email?],
          error: e.message,
          timestamp: Time.now
      end
    end
  end
end
```

## Variable Binding Strategies

### Consistent Naming

Use descriptive, consistent variable names:

```ruby
# Good: Clear intent
:sensor_id?
:temperature_celsius?
:alert_threshold?
:user_email?

# Bad: Cryptic
:s?
:t?
:x?
```

### Join Patterns

Connect facts through shared variables:

```ruby
KBS.knowledge_base do
  # Pattern: Join sensor reading with threshold
  rule "check_threshold" do
    on :sensor,
      id: :sensor_id?,
      temp: :current_temp?

    on :threshold,
      sensor_id: :sensor_id?,  # Same variable = join constraint
      max_temp: :max_temp?

    perform do |facts, bindings|
      # Only matches when sensor_id is same in both facts
    end
  end
end
```

### Computed Bindings

Derive values in actions:

```ruby
KBS.knowledge_base do
  rule "calculate_diff" do
    on :sensor, temp: :current_temp?
    on :threshold, max_temp: :max_temp?

    perform do |facts, bindings|
      current = bindings[:current_temp?]
      max = bindings[:max_temp?]

      # Compute derived values
      diff = current - max
      percentage_over = ((current / max.to_f) - 1) * 100

      puts "#{diff}°C over threshold (#{percentage_over.round(1)}%)"
    end
  end
end
```

## Rule Composition Patterns

### State Machine

Model state transitions:

```ruby
kb = KBS.knowledge_base do
  # Transition: pending → processing
  rule "start_processing" do
    on :order,
      id: :order_id?,
      status: "pending"

    perform do |facts, bindings|
      kb.modify(facts[0], status: "processing", started_at: Time.now)
    end
  end

  # Transition: processing → completed
  rule "complete_processing" do
    on :order,
      id: :order_id?,
      status: "processing"
    on :processing_done,
      order_id: :order_id?

    perform do |facts, bindings|
      kb.retract(facts[1])  # Remove trigger
      kb.modify(facts[0], status: "completed", completed_at: Time.now)
    end
  end
end
```

`kb.modify` changes a fact's attributes and matches it again, as a retraction followed by an assertion, so the next transition rule can match it. Assigning `order[:status] = ...` does not re-match the fact.

### Guard Conditions

Prevent duplicate actions:

```ruby
kb = KBS.knowledge_base do
  rule "send_alert_once" do
    on :high_temp, sensor_id: :id?

    # Guard: Only fire if alert not already sent
    without :alert_sent, sensor_id: :id?

    perform do |facts, bindings|
      send_alert(bindings[:id?])

      # Record that we sent this alert
      kb.fact :alert_sent, sensor_id: bindings[:id?]
    end
  end
end
```

### Cleanup Rules

Remove stale facts:

```ruby
kb = KBS.knowledge_base do
  rule "cleanup_stale_alerts", priority: 1 do
    on :alert,
      timestamp: ->(t) { (Time.now - t) > 3600 }  # 1 hour old

    perform do |facts, bindings|
      kb.retract(facts[0])
      logger.info("Removed stale alert")
    end
  end
end
```

A predicate is tested when the fact is asserted or modified, not again as time passes. To re-check an aging fact, re-match it with `kb.modify(alert, {})` (or assert a fresh tick fact your rules depend on).

### Aggregation Rules

Compute over multiple facts:

```ruby
kb = KBS.knowledge_base do
  rule "compute_average_temp" do
    on :compute_avg_requested, {}

    perform do |facts, bindings|
      temps = kb.query(:sensor)
        .map { |f| f[:temp] }
        .compact

      avg = temps.sum / temps.size.to_f

      kb.fact :average_temp, value: avg
    end
  end
end
```

### Temporal Rules

React to time-based conditions:

```ruby
KBS.knowledge_base do
  rule "detect_delayed_response" do
    on :request,
      id: :req_id?,
      created_at: ->(t) { (Time.now - t) > 300 }  # 5 minutes

    without :response,
      request_id: :req_id?

    perform do |facts, bindings|
      alert("Request #{bindings[:req_id?]} delayed!")
    end
  end
end
```

As with the cleanup rule, the age test runs when the request is asserted or modified; re-match pending requests periodically with `kb.modify(request, {})`.

## Priority Management

### Priority Levels

Establish consistent priority levels for your domain:

```ruby
# Define priority constants
module Priority
  CRITICAL = 100   # Emergency, safety
  HIGH = 75        # Important business logic
  NORMAL = 50      # Standard processing
  LOW = 25         # Cleanup, logging
  MONITORING = 10  # Metrics, diagnostics
end

# Use in rules
KBS.knowledge_base do
  rule "emergency_shutdown", priority: Priority::CRITICAL do
    # ...
  end

  rule "process_order", priority: Priority::NORMAL do
    # ...
  end
end
```

### Priority Inversion

Priority only orders the activations that are on the agenda at the same time. `run` keeps firing until the agenda is empty, so a high-priority rule that depends on a fact produced by a low-priority rule still fires in the same run, but only after the low-priority rule, and after every activation that outranks it:

```ruby
# Risky: emergency_check waits for compute_risk (priority 10), so any
# priority 11-99 activation fires before the emergency check can
kb = KBS.knowledge_base do
  rule "compute_risk", priority: 10 do
    on :data, value: :v?
    perform do |facts, bindings|
      kb.fact :risk_score, value: calculate_risk(bindings[:v?])
    end
  end

  rule "emergency_check", priority: 100 do
    on :risk_score, value: :risk?  # Depends on low priority rule!
    perform do |facts, bindings|
      emergency_shutdown if bindings[:risk?] > 90
    end
  end
end

# Fix: Make dependency higher priority
kb = KBS.knowledge_base do
  rule "compute_risk", priority: 110 do  # Now runs before other work
    on :data, value: :v?
    perform do |facts, bindings|
      kb.fact :risk_score, value: calculate_risk(bindings[:v?])
    end
  end

  rule "emergency_check", priority: 100 do
    on :risk_score, value: :risk?
    perform do |facts, bindings|
      emergency_shutdown if bindings[:risk?] > 90
    end
  end
end
```

## Testing Strategies

### Unit Test Rules in Isolation

```ruby
require 'minitest/autorun'
require 'kbs'

class TestTemperatureRules < Minitest::Test
  def test_fires_when_temp_exceeds_threshold
    alert_fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_alert" do
        on :sensor, id: :id?, temp: :temp?
        on :threshold, id: :id?, max: :max?

        perform do |facts, bindings|
          alert_fired = true if bindings[:temp?] > bindings[:max?]
        end
      end

      fact :sensor, id: "bedroom", temp: 30
      fact :threshold, id: "bedroom", max: 25
      run
    end

    assert alert_fired, "Rule should fire when temp > threshold"
  end

  def test_does_not_fire_when_temp_below_threshold
    alert_fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_alert" do
        on :sensor, id: :id?, temp: :temp?
        on :threshold, id: :id?, max: :max?

        perform do |facts, bindings|
          alert_fired = true if bindings[:temp?] > bindings[:max?]
        end
      end

      fact :sensor, id: "bedroom", temp: 20
      fact :threshold, id: "bedroom", max: 25
      run
    end

    refute alert_fired, "Rule should not fire when temp <= threshold"
  end

  def test_only_fires_for_matching_sensor
    alert_fired = false

    kb = KBS.knowledge_base do
      rule "high_temp_alert" do
        on :sensor, id: :id?, temp: :temp?
        on :threshold, id: :id?, max: :max?

        perform do |facts, bindings|
          alert_fired = true if bindings[:temp?] > bindings[:max?]
        end
      end

      fact :sensor, id: "bedroom", temp: 30
      fact :threshold, id: "kitchen", max: 25
      run
    end

    refute alert_fired, "Rule should not fire for different sensors"
  end
end
```

### Integration Tests

Test multiple rules working together:

```ruby
def test_state_machine_workflow
  kb = KBS.knowledge_base do
    # Add state transition rules
    rule "start_processing" do
      on :order, id: :id?, status: "pending"
      perform do |facts, bindings|
        kb.retract(facts[0])
        kb.fact :order, id: bindings[:id?], status: "processing"
      end
    end

    rule "complete_processing" do
      on :order, id: :id?, status: "processing"
      on :processing_done, order_id: :id?
      perform do |facts, bindings|
        kb.retract(facts[0])
        kb.retract(facts[1])
        kb.fact :order, id: bindings[:id?], status: "completed"
      end
    end

    # Add initial state
    fact :order, id: 1, status: "pending"
  end
  kb.run

  # Started, but not completed yet
  order = kb.engine.facts.find { |f| f.type == :order && f[:id] == 1 }
  assert_equal "processing", order[:status]

  # Trigger transition
  kb.fact :processing_done, order_id: 1
  kb.run

  # Should transition to completed
  order = kb.engine.facts.find { |f| f.type == :order && f[:id] == 1 }
  assert_equal "completed", order[:status]
end
```

### Property-Based Testing

Test rule invariants:

```ruby
def test_no_duplicate_alerts
  kb = KBS.knowledge_base do
    rule "send_alert_once" do
      on :high_temp, sensor_id: :id?
      without :alert_sent, sensor_id: :id?

      perform do |facts, bindings|
        send_alert(bindings[:id?])
        kb.fact :alert_sent, sensor_id: bindings[:id?]
      end
    end

    # Add facts
    100.times do |i|
      fact :high_temp, sensor_id: i
    end
  end

  # Run engine multiple times
  10.times { kb.run }

  # Property: At most one alert per sensor
  alert_counts = kb.engine.facts
    .select { |f| f.type == :alert_sent }
    .group_by { |f| f[:sensor_id] }
    .transform_values(&:count)

  alert_counts.each do |sensor_id, count|
    assert_equal 1, count, "Sensor #{sensor_id} has #{count} alerts, expected 1"
  end
end
```

## Performance Optimization

### Minimize Negations

Each negation adds a node to the rule's path that tracks, for every partial match, the facts that block it. Negations that share a `?variable` with earlier conditions are hash-indexed; unconstrained ones (like `without :foo, {}`) are checked against every partial match:

```ruby
# Expensive: 3 negations
KBS.knowledge_base do
  rule "many_negations" do
    without :foo, {}
    without :bar, {}
    without :baz, {}
    perform { }
  end
end

# Better: Combine into positive condition
KBS.knowledge_base do
  rule "positive_logic" do
    on :conditions_met, {}
    perform { }
  end

  # Add conditions_met fact if foo, bar, baz don't exist
  unless engine.facts.any? { |f| [:foo, :bar, :baz].include?(f.type) }
    fact :conditions_met, {}
  end
end
```

### Avoid Predicates for Simple Checks

A constant test is filed in a hash, so a fact reaches the matching alpha memory with one lookup on its value, and rules with the same pattern share that memory. A lambda is called for every fact of the type, and two patterns share a memory only when they hold the same lambda object.

```ruby
# Expensive: Lambda called for every :stock fact
KBS.knowledge_base do
  rule "with_predicate" do
    on :stock, symbol: ->(s) { s == "AAPL" }
    perform { }
  end
end

# Better: Use pattern matching
KBS.knowledge_base do
  rule "with_pattern" do
    on :stock, symbol: "AAPL"
    perform { }
  end
end
```

### Cache Computed Values

```ruby
# Bad: Recomputes every time rule fires
kb = KBS.knowledge_base do
  rule "check_average" do
    on :sensor, temp: :temp?

    perform do |facts, bindings|
      avg = compute_expensive_average(kb.facts)
      alert(avg) if avg > threshold
    end
  end
end

# Good: Cache as fact, recompute only when needed
kb = KBS.knowledge_base do
  rule "update_average", priority: 100 do
    on :sensor, temp: :temp?  # Triggers when sensor added

    perform do |facts, bindings|
      avg = compute_expensive_average(kb.facts)
      kb.fact :cached_average, value: avg
    end
  end

  rule "check_average", priority: 50 do
    on :cached_average, value: :avg?

    perform do |facts, bindings|
      alert(bindings[:avg?]) if bindings[:avg?] > threshold
    end
  end
end
```

## Common Pitfalls

### 1. Infinite Loops

```ruby
# Bad: Rule fires itself indefinitely
kb = KBS.knowledge_base do
  rule "infinite_loop" do
    on :sensor, temp: :temp?

    perform do |facts, bindings|
      # This triggers the rule again!
      kb.fact :sensor, temp: bindings[:temp?] + 1
    end
  end
end

# Fix: Add termination condition
kb = KBS.knowledge_base do
  rule "limited_increment" do
    on :sensor, temp: :temp?
    without :increment_done, {}

    perform do |facts, bindings|
      kb.fact :sensor, temp: bindings[:temp?] + 1
      kb.fact :increment_done, {}
    end
  end
end
```

As a safety net while developing, `kb.run(100)` stops after 100 firings, and `kb.halt` called from an action stops the current run.

### 2. Writing Conditions Inside `perform`

```ruby
# Bad: the rule is already built when the action runs
kb = KBS.knowledge_base do
  rule "derive" do
    on :reading, {}
    perform { on :other }   # raises KBS::RuleBuiltError during run
  end
end

# Fine: working-memory calls, bare or through kb
kb = KBS.knowledge_base do
  rule "derive" do
    on :reading, {}
    perform { fact :derived, {} }   # same as kb.fact :derived, {}
  end
end
```

### 3. Forgetting to Call `run`

Facts are matched as they are added, but matching only puts activations on the agenda; rules fire when `run` is called.

```ruby
# Bad: Facts matched but rules never fire
kb = KBS.knowledge_base do
  rule "example" do
    on :sensor, temp: :temp?
    on :threshold, max: :max?
    perform { }
  end

  fact :sensor, temp: 30
  fact :threshold, max: 25
  # Rules never fire!
end

# Good: Run after adding facts
kb = KBS.knowledge_base do
  rule "example" do
    on :sensor, temp: :temp?
    on :threshold, max: :max?
    perform { }
  end

  fact :sensor, temp: 30
  fact :threshold, max: 25
  run  # Match and fire rules
end
```

## Next Steps

- **[Pattern Matching](pattern-matching.md)** - Deep dive into condition matching
- **[Variable Binding](variable-binding.md)** - Join tests and binding extraction
- **[Negation](negation.md)** - Negated condition behavior
- **[Performance Guide](../advanced/performance.md)** - Profiling and optimization
- **[Testing Guide](../advanced/testing.md)** - Comprehensive test strategies

---

*Well-designed rules are self-documenting. If a rule is hard to understand, it's probably doing too much.*
