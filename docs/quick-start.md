# Quick Start Guide

Get up and running with KBS in 5 minutes.

## Your First Rule-Based System

Let's build a simple temperature monitoring system that alerts when readings are abnormal.

### Step 1: Create the Engine

```ruby
require 'kbs'

# Create a RETE engine
engine = KBS::Engine.new
```

### Step 2: Define Rules

```ruby
# Rule 1: Alert on high temperature
high_temp_rule = KBS::Rule.new("high_temperature_alert") do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { id: :id?, temp: :temp? })
  ]

  r.action = lambda do |facts, bindings|
    if bindings[:temp?] > 75
      puts "⚠️  HIGH TEMP Alert: Sensor #{bindings[:id?]} at #{bindings[:temp?]}°F"
    end
  end
end

engine.add_rule(high_temp_rule)

# Rule 2: Alert when cooling system is offline AND temp is high
critical_rule = KBS::Rule.new("critical_condition", priority: 10) do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { id: :id?, temp: :temp? }),
    KBS::Condition.new(:cooling, { id: :id?, status: "offline" })
  ]

  r.action = lambda do |facts, bindings|
    if bindings[:temp?] > 75
      puts "🚨 CRITICAL: Sensor #{bindings[:id?]} at #{bindings[:temp?]}°F with cooling OFFLINE!"
    end
  end
end

engine.add_rule(critical_rule)
```

### Step 3: Add Facts

```ruby
# Add sensor readings
engine.add_fact(:sensor, id: "room_101", temp: 72)
engine.add_fact(:sensor, id: "server_rack", temp: 82)
engine.add_fact(:sensor, id: "storage", temp: 65)

# Add cooling system status
engine.add_fact(:cooling, id: "server_rack", status: "offline")
```

### Step 4: Run Rules

```ruby
engine.run
# Output:
# => ⚠️  HIGH TEMP Alert: Sensor server_rack at 82°F
# => 🚨 CRITICAL: Sensor server_rack at 82°F with cooling OFFLINE!
```

## Understanding What Happened

1. **Engine Creation**: `Engine.new` builds an empty RETE network
2. **Rule Addition**: Rules are compiled into the discrimination network
3. **Fact Assertion**: Facts propagate through the network, creating partial matches
4. **Rule Firing**: `engine.run()` executes actions for all complete matches

The critical rule fires because:
- Sensor "server_rack" temp (82°F) > 75
- Cooling system for "server_rack" is offline
- Both conditions are joined on the same `:id?` variable

## Using Negation

Rules can match on the **absence** of facts:

```ruby
# Alert when sensor has NO recent reading
stale_sensor_rule = KBS::Rule.new("stale_sensor") do |r|
  r.conditions = [
    KBS::Condition.new(:sensor_registered, { id: :id? }),
    # No recent reading exists (negation!)
    KBS::Condition.new(:sensor, { id: :id? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    puts "⚠️  No reading from sensor #{bindings[:id?]}"
  end
end

engine.add_rule(stale_sensor_rule)

# Register sensors
engine.add_fact(:sensor_registered, id: "room_101")
engine.add_fact(:sensor_registered, id: "room_102")

# Only add reading for room_101
engine.add_fact(:sensor, id: "room_101", temp: 70)

engine.run
# => ⚠️  No reading from sensor room_102
```

## Persistent Blackboard Memory

For production systems, use persistent storage:

```ruby
require 'kbs/blackboard'

# SQLite backend (default)
engine = KBS::Blackboard::Engine.new(db_path: 'monitoring.db')

# Facts survive restarts
engine.add_fact(:sensor, id: "room_101", temp: 72)

# Query historical data
memory = engine.working_memory
audit = memory.audit_log.recent_changes(limit: 10)
```

## Next Steps

### Learn the Fundamentals

- **[Writing Rules](guides/writing-rules.md)** - Master rule syntax and patterns
- **[Pattern Matching](guides/pattern-matching.md)** - Understand how facts match conditions
- **[Variable Binding](guides/variable-binding.md)** - Use variables to join conditions
- **[Negation](guides/negation.md)** - Express "absence" conditions

### Explore Examples

- **[Stock Trading](examples/stock-trading.md)** - Build a trading signal system
- **[Expert Systems](examples/expert-systems.md)** - Diagnostic and decision support
- **[Multi-Agent Systems](examples/multi-agent.md)** - Collaborative problem-solving

### Advanced Topics

- **[Blackboard Memory](guides/blackboard-memory.md)** - Persistent storage and audit trails
- **[Performance Tuning](advanced/performance.md)** - Optimize for production workloads
- **[Debugging](advanced/debugging.md)** - Trace rule execution and network state

### Understand the Engine

- **[RETE Algorithm](architecture/rete-algorithm.md)** - Deep dive into pattern matching
- **[Network Structure](architecture/network-structure.md)** - How rules are compiled
- **[API Reference](api/index.md)** - Complete class documentation

## Common Patterns

### Time-Based Rules

```ruby
rule = KBS::Rule.new("recent_spike") do |r|
  r.conditions = [
    KBS::Condition.new(:reading, {
      sensor: :id?,
      temp: :temp?,
      timestamp: ->(ts) { Time.now - ts < 300 }  # Within 5 minutes
    })
  ]

  r.action = lambda do |facts, bindings|
    puts "Recent spike: #{bindings[:temp?]}°F"
  end
end
```

### Threshold Comparison

```ruby
rule = KBS::Rule.new("above_threshold") do |r|
  r.conditions = [
    KBS::Condition.new(:reading, { sensor: :id?, value: :val? }),
    KBS::Condition.new(:threshold, { sensor: :id?, max: :max? })
  ]

  r.action = lambda do |facts, bindings|
    if bindings[:val?] > bindings[:max?]
      puts "Threshold exceeded!"
    end
  end
end
```

### State Machine

```ruby
# Transition from "init" to "ready"
transition_rule = KBS::Rule.new("init_to_ready") do |r|
  r.conditions = [
    KBS::Condition.new(:state, { current: "init" }),
    KBS::Condition.new(:sensor, { initialized: true }),
    # No "ready" state exists yet
    KBS::Condition.new(:state, { current: "ready" }, negated: true)
  ]

  r.action = lambda do |facts|
    # Remove old state
    engine.remove_fact(facts[0])
    # Add new state
    engine.add_fact(:state, current: "ready")
  end
end
```

## Tips

1. **Use descriptive rule names**: Makes debugging easier
2. **Set priorities**: Higher priority rules fire first
3. **Call `run()` explicitly**: Rules don't fire automatically
4. **Leverage negation**: Express "when X is absent" naturally
5. **Profile performance**: Use `advanced/debugging.md` techniques

Ready to dive deeper? Check out the [Writing Rules Guide](guides/writing-rules.md)!
