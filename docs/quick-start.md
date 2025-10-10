# Quick Start Guide

Get up and running with KBS in 5 minutes.

## Your First Rule-Based System

Let's build a simple temperature monitoring system that alerts when readings are abnormal.

### Step 1: Create a Knowledge Base and Define Rules

```ruby
require 'kbs'

kb = KBS.knowledge_base do
  # Rule 1: Alert on high temperature
  rule "high_temperature_alert" do
    on :sensor, id: :id?, temp: :temp?

    perform do |facts, bindings|
      if bindings[:temp?] > 75
        puts "⚠️  HIGH TEMP Alert: Sensor #{bindings[:id?]} at #{bindings[:temp?]}°F"
      end
    end
  end

  # Rule 2: Alert when cooling system is offline AND temp is high
  rule "critical_condition", priority: 10 do
    on :sensor, id: :id?, temp: :temp?
    on :cooling, id: :id?, status: "offline"

    perform do |facts, bindings|
      if bindings[:temp?] > 75
        puts "🚨 CRITICAL: Sensor #{bindings[:id?]} at #{bindings[:temp?]}°F with cooling OFFLINE!"
      end
    end
  end
end
```

### Step 2: Add Facts

```ruby
# Add sensor readings
kb.fact :sensor, id: "room_101", temp: 72
kb.fact :sensor, id: "server_rack", temp: 82
kb.fact :sensor, id: "storage", temp: 65

# Add cooling system status
kb.fact :cooling, id: "server_rack", status: "offline"
```

### Step 3: Run Rules

```ruby
kb.run
# Output:
# => ⚠️  HIGH TEMP Alert: Sensor server_rack at 82°F
# => 🚨 CRITICAL: Sensor server_rack at 82°F with cooling OFFLINE!
```

## Understanding What Happened

1. **Knowledge Base Creation**: `KBS.knowledge_base do...end` creates the RETE network and defines rules
2. **Rule Definition**: Rules are compiled into the discrimination network using the DSL
3. **Fact Assertion**: `kb.fact` adds facts that propagate through the network, creating partial matches
4. **Rule Firing**: `kb.run` executes actions for all complete matches

The critical rule fires because:
- Sensor "server_rack" temp (82°F) > 75
- Cooling system for "server_rack" is offline
- Both conditions are joined on the same `:id?` variable

## Using Negation

Rules can match on the **absence** of facts:

```ruby
kb = KBS.knowledge_base do
  # Alert when sensor has NO recent reading
  rule "stale_sensor" do
    on :sensor_registered, id: :id?
    # No recent reading exists (negation!)
    without :sensor, id: :id?

    perform do |facts, bindings|
      puts "⚠️  No reading from sensor #{bindings[:id?]}"
    end
  end

  # Register sensors
  fact :sensor_registered, id: "room_101"
  fact :sensor_registered, id: "room_102"

  # Only add reading for room_101
  fact :sensor, id: "room_101", temp: 70

  run
  # => ⚠️  No reading from sensor room_102
end
```

## Persistent Blackboard Memory

For production systems, use persistent storage:

```ruby
require 'kbs/blackboard'

# SQLite backend (default)
engine = KBS::Blackboard::Engine.new(db_path: 'monitoring.db')

kb = KBS.knowledge_base(engine: engine) do
  rule "temperature_monitor" do
    on :sensor, temp: greater_than(75)
    perform do |facts|
      puts "High temp alert!"
    end
  end

  # Facts survive restarts
  fact :sensor, id: "room_101", temp: 72

  run
end

# Query historical data
audit = engine.blackboard.get_history(limit: 10)
```

## Next Steps

### Learn the Fundamentals

- **[Writing Rules](guides/writing-rules.md)** - Master rule syntax and patterns
- **[Pattern Matching](guides/pattern-matching.md)** - Understand how facts match conditions
- **[Variable Binding](guides/variable-binding.md)** - Use variables to join conditions
- **[Negation](guides/negation.md)** - Express "absence" conditions

### Explore Examples

- **[Stock Trading Examples](examples/index.md#stock-trading-systems)** - Build a trading signal system
- **[Expert System Examples](examples/index.md#expert-systems)** - Diagnostic and decision support
- **[Blackboard & Multi-Agent Examples](examples/index.md#advanced-features)** - Collaborative problem-solving

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
kb = KBS.knowledge_base do
  rule "recent_spike" do
    on :reading,
       sensor: :id?,
       temp: :temp?,
       timestamp: ->(ts) { Time.now - ts < 300 }  # Within 5 minutes

    perform do |facts, bindings|
      puts "Recent spike: #{bindings[:temp?]}°F"
    end
  end
end
```

### Threshold Comparison

```ruby
kb = KBS.knowledge_base do
  rule "above_threshold" do
    on :reading, sensor: :id?, value: :val?
    on :threshold, sensor: :id?, max: :max?

    perform do |facts, bindings|
      if bindings[:val?] > bindings[:max?]
        puts "Threshold exceeded!"
      end
    end
  end
end
```

### State Machine

```ruby
kb = KBS.knowledge_base do
  # Transition from "init" to "ready"
  rule "init_to_ready" do
    on :state, current: "init"
    on :sensor, initialized: true
    # No "ready" state exists yet
    without :state, current: "ready"

    perform do |facts|
      # Note: For state transitions, you'd typically use engine methods
      # This is a simplified example
      puts "Transitioning to ready state"
    end
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
