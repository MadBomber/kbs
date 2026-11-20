# Getting Started

Build your first knowledge-based system in 10 minutes. This hands-on tutorial teaches the fundamentals by creating a temperature monitoring system that alerts when sensors exceed thresholds.

## What You'll Learn

- Creating rules and facts
- Variable binding across conditions
- Using negation to prevent duplicate alerts
- Persisting facts with blackboard memory
- Controlling rule execution with priorities

## Installation

Add KBS to your Gemfile:

```ruby
gem 'kbs'
```

Or install directly:

```bash
gem install kbs
```

## Your First Rule

Let's create a simple rule that fires when temperature exceeds a threshold.

### Step 1: Create a Knowledge Base

```ruby
require 'kbs'

# Create a knowledge base with DSL
kb = KBS.knowledge_base do
  # Rules will be defined here
end
```

The knowledge base manages rules, facts, and executes the pattern matching algorithm.

### Step 2: Define a Rule

```ruby
kb = KBS.knowledge_base do
  # Define a rule for high temperature alerts
  rule "high_temperature_alert" do
    on :sensor, id: :sensor_id?, temp: :temp?
    on :threshold, id: :sensor_id?, max: :max?

    perform do |facts, bindings|
      if bindings[:temp?] > bindings[:max?]
        puts "🚨 ALERT: Sensor #{bindings[:sensor_id?]} at #{bindings[:temp?]}°C"
      end
    end
  end
end
```

**What this rule does:**

- **Condition 1**: Match any `:sensor` fact, binding its `id` to `:sensor_id?` and `temp` to `:temp?`
- **Condition 2**: Match a `:threshold` fact with the same `id`, binding `max` to `:max?`
- **Action**: When both conditions match, compare temperature against threshold

**Variable binding** (`:sensor_id?`) ensures we only compare sensors with their own thresholds.

### Step 3: Add Facts and Run

```ruby
kb = KBS.knowledge_base do
  rule "high_temperature_alert" do
    on :sensor, id: :sensor_id?, temp: :temp?
    on :threshold, id: :sensor_id?, max: :max?

    perform do |facts, bindings|
      if bindings[:temp?] > bindings[:max?]
        puts "🚨 ALERT: Sensor #{bindings[:sensor_id?]} at #{bindings[:temp?]}°C"
      end
    end
  end

  # Add facts
  fact :sensor, id: "bedroom", temp: 28
  fact :threshold, id: "bedroom", max: 25

  # Run inference
  run
end
```

Facts are observations about the world. The knowledge base automatically matches them against rule conditions.

**Output:**
```
🚨 ALERT: Sensor bedroom at 28°C
```

The rule fired because the bedroom temperature (28°C) exceeds its threshold (25°C).

## Understanding Variable Binding

Variable binding connects facts across conditions. Here's how it works:

```ruby
rule "example" do
  on :sensor, id: :sensor_id?, temp: :temp?
  on :threshold, id: :sensor_id?, max: :max?
end
```

**Binding Process:**

1. Engine finds a `:sensor` fact: `{ id: "bedroom", temp: 28 }`
2. Binds `:sensor_id?` → `"bedroom"`, `:temp?` → `28`
3. Searches for `:threshold` fact where `id` also equals `"bedroom"`
4. Finds `{ id: "bedroom", max: 25 }`
5. Binds `:max?` → `25`
6. Both conditions satisfied → rule fires with bindings: `{ :sensor_id? => "bedroom", :temp? => 28, :max? => 25 }`

Without variable binding, the rule would incorrectly match bedroom sensors with kitchen thresholds.

## Preventing Duplicate Alerts with Negation

Let's prevent the same alert from firing repeatedly:

```ruby
kb = KBS.knowledge_base do
  rule "smart_temperature_alert" do
    on :sensor, id: :sensor_id?, temp: :temp?
    on :threshold, id: :sensor_id?, max: :max?
    # Only fire if no alert already exists for this sensor
    without :alert, sensor_id: :sensor_id?

    perform do |facts, bindings|
      if bindings[:temp?] > bindings[:max?]
        puts "🚨 ALERT: Sensor #{bindings[:sensor_id?]} at #{bindings[:temp?]}°C"
        # Record that we sent this alert
        kb.fact :alert, sensor_id: bindings[:sensor_id?]
      end
    end
  end
end
```

**Negated condition** (`without`): Rule fires only when NO `:alert` fact exists for this sensor.

Inside `perform`, `self` is the rule builder, not the knowledge base, so a bare `fact` there would add a condition instead of a fact. Call knowledge base methods through `kb`. (The action runs during `kb.run`, after `kb` has been assigned.)

**Flow:**

1. First execution: No `:alert` fact → rule fires, creates `:alert` fact
2. Second execution: `:alert` fact exists → rule doesn't fire (negation blocks it)

## Persisting Facts with Blackboard Memory

So far, facts disappear when your program exits. Use blackboard memory for persistence:

```ruby
require 'kbs/blackboard'

# Create engine with SQLite persistence
engine = KBS::Blackboard::Engine.new(db_path: 'sensors.db')

# Add rules (same as before) to a knowledge base that runs on this engine
kb = KBS.knowledge_base(engine: engine) do
  # rule "smart_temperature_alert" do ... end
end

# Add facts - these are saved to database
engine.add_fact(:sensor, id: "bedroom", temp: 28)
engine.add_fact(:threshold, id: "bedroom", max: 25)

engine.run

# Facts survive program restart
engine.close
```

**Next time you run:**

```ruby
engine = KBS::Blackboard::Engine.new(db_path: 'sensors.db')
# Facts automatically loaded from database
puts engine.facts.size  # => 3 (sensor, threshold, and the alert the rule added)
```

Blackboard provides:
- **Persistence**: Facts saved to SQLite/Redis
- **Audit Trail**: Complete history of changes
- **Transactions**: ACID guarantees for multi-fact updates

Learn more: [Blackboard Memory Guide](blackboard-memory.md)

## Controlling Execution with Priorities

When multiple rules match, control firing order with priorities:

```ruby
kb = KBS.knowledge_base do
  rule "critical_alert", priority: 100 do
    on :sensor, temp: :temp?

    perform do |facts, bindings|
      if bindings[:temp?] > 50
        puts "🔥 CRITICAL: Immediate shutdown required!"
        exit(1)
      end
    end
  end

  rule "normal_alert", priority: 10 do
    on :sensor, temp: :temp?
    # ... (less urgent alerts)
    perform { |facts| puts "Normal alert" }
  end
end
```

**Priority:** Higher numbers fire first. Default is `0`.

**Execution order:**
1. `critical_alert` (priority 100) - checks for emergency shutdown
2. `normal_alert` (priority 10) - handles routine alerts

## Complete Working Example

Here's a complete temperature monitoring system:

```ruby
require 'kbs/blackboard'

class TemperatureMonitor
  def initialize
    @engine = KBS::Blackboard::Engine.new(db_path: 'sensors.db')
    @kb = setup_rules
  end

  def setup_rules
    engine = @engine
    monitor = self

    KBS.knowledge_base(engine: engine) do
      kb = self   # rule actions run with the rule builder as self

      # Rule 1: Send alert when temp exceeds threshold
      rule "temperature_alert", priority: 50 do
        on :sensor, id: :id?, temp: :temp?
        on :threshold, id: :id?, max: :max?
        without :alert, sensor_id: :id?

        perform do |facts, bindings|
          if bindings[:temp?] > bindings[:max?]
            monitor.send_alert(bindings[:id?], bindings[:temp?], bindings[:max?])
            kb.fact :alert, sensor_id: bindings[:id?]
          end
        end
      end

      # Rule 2: Clear alert when temp drops below threshold
      rule "clear_alert", priority: 40 do
        on :sensor, id: :id?, temp: :temp?
        on :threshold, id: :id?, max: :max?
        on :alert, sensor_id: :id?

        perform do |facts, bindings|
          if bindings[:temp?] <= bindings[:max?]
            monitor.clear_alert(bindings[:id?])
            # Find and retract the alert fact
            alert_fact = kb.query(:alert, sensor_id: bindings[:id?]).first
            kb.retract alert_fact if alert_fact
          end
        end
      end

      # Rule 3: Emergency shutdown for extreme temps
      rule "emergency_shutdown", priority: 100 do
        on :sensor, temp: :temp?

        perform do |facts, bindings|
          if bindings[:temp?] > 60
            monitor.emergency_shutdown(bindings[:temp?])
          end
        end
      end
    end
  end

  def add_sensor(id, max_temp)
    @kb.fact :threshold, id: id, max: max_temp
  end

  def update_reading(id, temp)
    # Find and remove old reading
    old = @kb.query(:sensor, id: id).first
    @kb.retract old if old

    # Add new reading
    @kb.fact :sensor, id: id, temp: temp
    @kb.run
  end

  def send_alert(sensor_id, temp, threshold)
    puts "🚨 ALERT: #{sensor_id} at #{temp}°C (threshold: #{threshold}°C)"
  end

  def clear_alert(sensor_id)
    puts "✅ CLEAR: #{sensor_id} back to normal"
  end

  def emergency_shutdown(temp)
    puts "🔥 EMERGENCY SHUTDOWN: Temperature #{temp}°C!"
    exit(1)
  end

  def close
    @engine.close
  end
end

# Usage
monitor = TemperatureMonitor.new

# Register sensors with thresholds
monitor.add_sensor("bedroom", 25)
monitor.add_sensor("server_room", 30)

# Simulate sensor readings
monitor.update_reading("bedroom", 28)        # => 🚨 ALERT
monitor.update_reading("server_room", 45)    # => 🚨 ALERT
monitor.update_reading("bedroom", 22)        # => ✅ CLEAR
monitor.update_reading("server_room", 65)    # => 🔥 EMERGENCY SHUTDOWN

monitor.close
```

## Key Concepts Learned

✅ **Rules** - Define patterns and actions
✅ **Facts** - Observations stored in working memory
✅ **Conditions** - Patterns that match facts
✅ **Variable Binding** - Connect facts across conditions using `:variable?`
✅ **Negation** - Match when patterns are absent
✅ **Priorities** - Control rule firing order
✅ **Persistence** - Save facts to database with blackboard memory

## Troubleshooting

### Rule Not Firing

**Problem**: Added facts but rule doesn't fire

**Checklist**:
1. Did you call `engine.run`?
2. Do variable bindings match? (`:sensor_id?` must appear in both conditions)
3. Check negated conditions - is there a blocking fact?
4. Verify fact types match condition types exactly (`:sensor` vs `:sensors`)

### Performance Issues

**Problem**: Slow when adding many facts

**Solutions**:
- Order conditions from most selective to least selective
- Use Redis store for high-frequency updates: `KBS::Blackboard::Engine.new(store: KBS::Blackboard::Persistence::RedisStore.new)`
- Minimize negated conditions

### Facts Not Persisting

**Problem**: Facts disappear after restart

**Check**:
- Using `KBS::Blackboard::Engine` (not `KBS::Engine`)?
- Provided `db_path` parameter?
- Called `engine.close` before exit?

## Next Steps

Now that you understand the basics, explore:

- **[Writing Rules](writing-rules.md)** - Advanced rule patterns and techniques
- **[Pattern Matching](pattern-matching.md)** - Deep dive into condition syntax
- **[Blackboard Memory](blackboard-memory.md)** - Multi-agent collaboration
- **[Stock Trading Examples](../examples/index.md#stock-trading-systems)** - Real-world applications
- **[API Reference](../api/engine.md)** - Complete method documentation

---

**Questions?** Open an issue at [github.com/madbomber/kbs](https://github.com/madbomber/kbs)
