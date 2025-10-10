# Writing Rules

Master the art of authoring production rules. This guide covers best practices, patterns, and strategies for writing effective, maintainable, and performant rules in KBS.

## Rule Anatomy

Every rule consists of three parts:

```ruby
KBS::Rule.new("rule_name", priority: 0) do |r|
  # 1. CONDITIONS - Pattern matching
  r.conditions = [...]

  # 2. ACTION - What to do when conditions match
  r.action = lambda do |facts, bindings|
    # Execute logic
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
KBS::Rule.new("critical_safety_check", priority: 100)  # Fires first
KBS::Rule.new("normal_processing", priority: 50)
KBS::Rule.new("cleanup_task", priority: 10)            # Fires last
```

**Priority Guidelines:**
- **100+** - Safety checks, emergency shutdowns
- **50-99** - Business logic, processing
- **1-49** - Monitoring, logging, cleanup
- **0** - Default priority (no preference)

### 3. Conditions

Patterns that must match for the rule to fire. Order matters for performance.

```ruby
r.conditions = [
  # Most selective first (fewest matches)
  KBS::Condition.new(:critical_alert, { severity: "critical" }),

  # Less selective last (more matches)
  KBS::Condition.new(:sensor, { id: :sensor_id? })
]
```

### 4. Action

Code executed when all conditions match:

```ruby
r.action = lambda do |facts, bindings|
  # Access matched facts
  alert = facts[0]
  sensor = facts[1]

  # Access variable bindings
  sensor_id = bindings[:sensor_id?]

  # Perform action
  notify_operator(sensor_id, alert[:message])
end
```

## Condition Ordering

**Golden Rule**: Order conditions from most selective to least selective.

### Why Order Matters

```ruby
# Bad: General condition first
r.conditions = [
  KBS::Condition.new(:sensor, {}),           # 1000 matches
  KBS::Condition.new(:critical_alert, {})    # 1 match
]
# Creates 1000 partial matches, wastes memory

# Good: Specific condition first
r.conditions = [
  KBS::Condition.new(:critical_alert, {}),   # 1 match
  KBS::Condition.new(:sensor, {})            # Joins with 1000
]
# Creates 1 partial match, efficient joins
```

### Selectivity Examples

```ruby
# Most selective (few facts)
KBS::Condition.new(:emergency, { level: "critical" })
KBS::Condition.new(:user, { role: "admin" })

# Moderate selectivity
KBS::Condition.new(:order, { status: "pending" })
KBS::Condition.new(:stock, { exchange: "NYSE" })

# Least selective (many facts)
KBS::Condition.new(:sensor, {})
KBS::Condition.new(:log_entry, {})
```

### Measuring Selectivity

```ruby
def measure_selectivity(engine, type, pattern)
  engine.facts.count { |f|
    f.type == type &&
    pattern.all? { |k, v| f[k] == v }
  }
end

# Compare
puts measure_selectivity(engine, :critical_alert, {})  # => 1
puts measure_selectivity(engine, :sensor, {})          # => 1000

# Order: critical_alert first, sensor second
```

## Action Design

### Single Responsibility

One action, one purpose:

```ruby
# Good: Focused action
r.action = lambda do |facts, bindings|
  send_email_alert(bindings[:email?], bindings[:message?])
end

# Bad: Multiple responsibilities
r.action = lambda do |facts, bindings|
  send_email_alert(bindings[:email?])
  update_database(bindings[:id?])
  call_external_api(bindings[:data?])
  write_log_file(bindings[:msg?])
end
```

Split complex actions into multiple rules:

```ruby
# Rule 1: Detect condition
KBS::Rule.new("detect_high_temp", priority: 50) do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { temp: :temp? }, predicate: ->(f) { f[:temp] > 30 })
  ]

  r.action = lambda do |facts, bindings|
    engine.add_fact(:high_temp_detected, { temp: bindings[:temp?] })
  end
end

# Rule 2: Send alert
KBS::Rule.new("send_temp_alert", priority: 40) do |r|
  r.conditions = [
    KBS::Condition.new(:high_temp_detected, { temp: :temp? })
  ]

  r.action = lambda do |facts, bindings|
    send_email("High temp: #{bindings[:temp?]}")
  end
end

# Rule 3: Log event
KBS::Rule.new("log_temp_event", priority: 30) do |r|
  r.conditions = [
    KBS::Condition.new(:high_temp_detected, { temp: :temp? })
  ]

  r.action = lambda do |facts, bindings|
    logger.info("Temperature spike: #{bindings[:temp?]}")
  end
end
```

### Avoid Side Effects

Actions should be deterministic and idempotent when possible:

```ruby
# Good: Idempotent (safe to run multiple times)
r.action = lambda do |facts, bindings|
  # Remove old alert if exists
  old = engine.facts.find { |f| f.type == :alert && f[:id] == bindings[:id?] }
  engine.remove_fact(old) if old

  # Add new alert
  engine.add_fact(:alert, { id: bindings[:id?], message: "Alert!" })
end

# Bad: Non-idempotent (creates duplicates)
r.action = lambda do |facts, bindings|
  # Always adds, even if alert already exists
  engine.add_fact(:alert, { id: bindings[:id?], message: "Alert!" })
end
```

### Error Handling

Protect against failures:

```ruby
r.action = lambda do |facts, bindings|
  begin
    send_email(bindings[:email?], bindings[:message?])
  rescue Net::SMTPError => e
    logger.error("Failed to send email: #{e.message}")
    # Add failure fact for retry logic
    engine.add_fact(:email_failure, {
      email: bindings[:email?],
      error: e.message,
      timestamp: Time.now
    })
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
# Pattern: Join sensor reading with threshold
r.conditions = [
  KBS::Condition.new(:sensor, {
    id: :sensor_id?,
    temp: :current_temp?
  }),

  KBS::Condition.new(:threshold, {
    sensor_id: :sensor_id?,  # Same variable = join constraint
    max_temp: :max_temp?
  })
]

# Only matches when sensor_id is same in both facts
```

### Computed Bindings

Derive values in actions:

```ruby
r.action = lambda do |facts, bindings|
  current = bindings[:current_temp?]
  max = bindings[:max_temp?]

  # Compute derived values
  diff = current - max
  percentage_over = ((current / max.to_f) - 1) * 100

  puts "#{diff}°C over threshold (#{percentage_over.round(1)}%)"
end
```

## Rule Composition Patterns

### State Machine

Model state transitions:

```ruby
# Transition: pending → processing
KBS::Rule.new("start_processing") do |r|
  r.conditions = [
    KBS::Condition.new(:order, {
      id: :order_id?,
      status: "pending"
    })
  ]

  r.action = lambda do |facts, bindings|
    old_order = facts[0]
    engine.remove_fact(old_order)
    engine.add_fact(:order, {
      id: bindings[:order_id?],
      status: "processing",
      started_at: Time.now
    })
  end
end

# Transition: processing → completed
KBS::Rule.new("complete_processing") do |r|
  r.conditions = [
    KBS::Condition.new(:order, {
      id: :order_id?,
      status: "processing"
    }),
    KBS::Condition.new(:processing_done, {
      order_id: :order_id?
    })
  ]

  r.action = lambda do |facts, bindings|
    order = facts[0]
    engine.remove_fact(order)
    engine.remove_fact(facts[1])  # Remove trigger
    engine.add_fact(:order, {
      id: bindings[:order_id?],
      status: "completed",
      completed_at: Time.now
    })
  end
end
```

### Guard Conditions

Prevent duplicate actions:

```ruby
KBS::Rule.new("send_alert_once") do |r|
  r.conditions = [
    KBS::Condition.new(:high_temp, { sensor_id: :id? }),

    # Guard: Only fire if alert not already sent
    KBS::Condition.new(:alert_sent, { sensor_id: :id? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    send_alert(bindings[:id?])

    # Record that we sent this alert
    engine.add_fact(:alert_sent, { sensor_id: bindings[:id?] })
  end
end
```

### Cleanup Rules

Remove stale facts:

```ruby
KBS::Rule.new("cleanup_stale_alerts", priority: 1) do |r|
  r.conditions = [
    KBS::Condition.new(:alert, {
      timestamp: :time?
    }, predicate: lambda { |f|
      (Time.now - f[:timestamp]) > 3600  # 1 hour old
    })
  ]

  r.action = lambda do |facts, bindings|
    engine.remove_fact(facts[0])
    logger.info("Removed stale alert")
  end
end
```

### Aggregation Rules

Compute over multiple facts:

```ruby
KBS::Rule.new("compute_average_temp") do |r|
  r.conditions = [
    KBS::Condition.new(:compute_avg_requested, {})
  ]

  r.action = lambda do |facts, bindings|
    temps = engine.facts
      .select { |f| f.type == :sensor }
      .map { |f| f[:temp] }
      .compact

    avg = temps.sum / temps.size.to_f

    engine.add_fact(:average_temp, { value: avg })
  end
end
```

### Temporal Rules

React to time-based conditions:

```ruby
KBS::Rule.new("detect_delayed_response") do |r|
  r.conditions = [
    KBS::Condition.new(:request, {
      id: :req_id?,
      created_at: :created?
    }),

    KBS::Condition.new(:response, {
      request_id: :req_id?
    }, negated: true),

    KBS::Condition.new(:request, {},
      predicate: lambda { |f|
        (Time.now - f[:created_at]) > 300  # 5 minutes
      }
    )
  ]

  r.action = lambda do |facts, bindings|
    alert("Request #{bindings[:req_id?]} delayed!")
  end
end
```

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
KBS::Rule.new("emergency_shutdown", priority: Priority::CRITICAL) do |r|
  # ...
end

KBS::Rule.new("process_order", priority: Priority::NORMAL) do |r|
  # ...
end
```

### Priority Inversion

Avoid priority inversions where low-priority rules block high-priority rules:

```ruby
# Bad: Low priority rule creates fact needed by high priority rule
KBS::Rule.new("compute_risk", priority: 10) do |r|
  r.conditions = [...]
  r.action = lambda { |f, b| engine.add_fact(:risk_score, { ... }) }
end

KBS::Rule.new("emergency_check", priority: 100) do |r|
  r.conditions = [
    KBS::Condition.new(:risk_score, { value: :risk? })  # Depends on low priority rule!
  ]
  r.action = lambda { |f, b| emergency_shutdown if b[:risk?] > 90 }
end

# Fix: Make dependency higher priority
KBS::Rule.new("compute_risk", priority: 110) do |r|
  # Now runs before emergency_check
end
```

## Testing Strategies

### Unit Test Rules in Isolation

```ruby
require 'minitest/autorun'
require 'kbs'

class TestTemperatureRules < Minitest::Test
  def setup
    @engine = KBS::Engine.new

    @rule = KBS::Rule.new("high_temp_alert") do |r|
      r.conditions = [
        KBS::Condition.new(:sensor, { id: :id?, temp: :temp? }),
        KBS::Condition.new(:threshold, { id: :id?, max: :max? })
      ]

      r.action = lambda do |facts, bindings|
        @alert_fired = true if bindings[:temp?] > bindings[:max?]
      end
    end

    @engine.add_rule(@rule)
    @alert_fired = false
  end

  def test_fires_when_temp_exceeds_threshold
    @engine.add_fact(:sensor, { id: "bedroom", temp: 30 })
    @engine.add_fact(:threshold, { id: "bedroom", max: 25 })
    @engine.run

    assert @alert_fired, "Rule should fire when temp > threshold"
  end

  def test_does_not_fire_when_temp_below_threshold
    @engine.add_fact(:sensor, { id: "bedroom", temp: 20 })
    @engine.add_fact(:threshold, { id: "bedroom", max: 25 })
    @engine.run

    refute @alert_fired, "Rule should not fire when temp <= threshold"
  end

  def test_only_fires_for_matching_sensor
    @engine.add_fact(:sensor, { id: "bedroom", temp: 30 })
    @engine.add_fact(:threshold, { id: "kitchen", max: 25 })
    @engine.run

    refute @alert_fired, "Rule should not fire for different sensors"
  end
end
```

### Integration Tests

Test multiple rules working together:

```ruby
def test_state_machine_workflow
  # Add state transition rules
  engine.add_rule(start_processing_rule)
  engine.add_rule(complete_processing_rule)

  # Add initial state
  engine.add_fact(:order, { id: 1, status: "pending" })
  engine.run

  # Should not transition yet
  assert_equal "pending", find_order(1)[:status]

  # Trigger transition
  engine.add_fact(:processing_done, { order_id: 1 })
  engine.run

  # Should transition to processing, then completed
  assert_equal "completed", find_order(1)[:status]
end
```

### Property-Based Testing

Test rule invariants:

```ruby
def test_no_duplicate_alerts
  # Add facts
  100.times do |i|
    engine.add_fact(:high_temp, { sensor_id: i })
  end

  # Run engine multiple times
  10.times { engine.run }

  # Property: At most one alert per sensor
  alert_counts = engine.facts
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

Negations are expensive:

```ruby
# Expensive: 3 negations
r.conditions = [
  KBS::Condition.new(:foo, {}, negated: true),
  KBS::Condition.new(:bar, {}, negated: true),
  KBS::Condition.new(:baz, {}, negated: true)
]

# Better: Combine into positive condition
engine.add_fact(:conditions_met, {}) unless foo_exists? || bar_exists? || baz_exists?

r.conditions = [
  KBS::Condition.new(:conditions_met, {})
]
```

### Avoid Predicates for Simple Checks

```ruby
# Expensive: Predicate disables network sharing
KBS::Condition.new(:stock, {},
  predicate: lambda { |f| f[:symbol] == "AAPL" }
)

# Better: Use pattern matching
KBS::Condition.new(:stock, { symbol: "AAPL" })
```

### Cache Computed Values

```ruby
# Bad: Recomputes every time rule fires
r.action = lambda do |facts, bindings|
  avg = compute_expensive_average(engine.facts)
  if avg > threshold
    alert(avg)
  end
end

# Good: Cache as fact, recompute only when needed
KBS::Rule.new("update_average", priority: 100) do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { temp: :temp? })  # Triggers when sensor added
  ]

  r.action = lambda do |facts, bindings|
    avg = compute_expensive_average(engine.facts)
    engine.add_fact(:cached_average, { value: avg })
  end
end

KBS::Rule.new("check_average", priority: 50) do |r|
  r.conditions = [
    KBS::Condition.new(:cached_average, { value: :avg? })
  ]

  r.action = lambda do |facts, bindings|
    alert(bindings[:avg?]) if bindings[:avg?] > threshold
  end
end
```

## Common Pitfalls

### 1. Infinite Loops

```ruby
# Bad: Rule fires itself indefinitely
KBS::Rule.new("infinite_loop") do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { temp: :temp? })
  ]

  r.action = lambda do |facts, bindings|
    # This triggers the rule again!
    engine.add_fact(:sensor, { temp: bindings[:temp?] + 1 })
  end
end

# Fix: Add termination condition
KBS::Rule.new("limited_increment") do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { temp: :temp? }),
    KBS::Condition.new(:increment_done, {}, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    engine.add_fact(:sensor, { temp: bindings[:temp?] + 1 })
    engine.add_fact(:increment_done, {})
  end
end
```

### 2. Variable Scope Confusion

```ruby
# Bad: Closure captures wrong variable
rules = []
%w[sensor1 sensor2 sensor3].each do |sensor|
  rules << KBS::Rule.new("process_#{sensor}") do |r|
    r.conditions = [...]
    r.action = lambda do |facts, bindings|
      # All rules reference same 'sensor' variable (last value!)
      puts sensor
    end
  end
end

# Fix: Force closure with parameter
%w[sensor1 sensor2 sensor3].each do |sensor_name|
  rules << KBS::Rule.new("process_#{sensor_name}") do |r|
    captured_sensor = sensor_name  # Force capture
    r.conditions = [...]
    r.action = lambda do |facts, bindings|
      puts captured_sensor  # Correct value
    end
  end
end
```

### 3. Forgetting to Call `engine.run`

```ruby
# Bad: Facts added but never matched
engine.add_fact(:sensor, { temp: 30 })
engine.add_fact(:threshold, { max: 25 })
# Rules never fire!

# Good: Run after adding facts
engine.add_fact(:sensor, { temp: 30 })
engine.add_fact(:threshold, { max: 25 })
engine.run  # Match and fire rules
```

## Next Steps

- **[Pattern Matching](pattern-matching.md)** - Deep dive into condition matching
- **[Variable Binding](variable-binding.md)** - Join tests and binding extraction
- **[Negation](negation.md)** - Negated condition behavior
- **[Performance Guide](../advanced/performance.md)** - Profiling and optimization
- **[Testing Guide](../advanced/testing.md)** - Comprehensive test strategies

---

*Well-designed rules are self-documenting. If a rule is hard to understand, it's probably doing too much.*
