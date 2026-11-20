# DSL Reference Guide

Complete reference for the KBS Domain-Specific Language for defining knowledge bases and rules.

## Table of Contents

- [Quick Start](#quick-start)
- [Knowledge Base](#knowledge-base)
- [Rule Definition](#rule-definition)
- [Condition Syntax](#condition-syntax)
- [Pattern Helpers](#pattern-helpers)
- [Variable Binding](#variable-binding)
- [Exists](#exists)
- [Logical Conditions](#logical-conditions)
- [Negation](#negation)
- [Actions](#actions)
- [Working with Facts](#working-with-facts)
- [Introspection](#introspection)

---

## Quick Start

The KBS DSL provides a natural, English-like syntax for defining knowledge-based systems:

```ruby
require 'kbs'

kb = KBS.knowledge_base do
  # Define a rule
  rule "high_temperature_alert" do
    desc "Alert when temperature exceeds threshold"
    priority 10

    on :temperature, value: greater_than(80), location: :loc?

    perform do |facts, bindings|
      puts "High temperature at #{bindings[:loc?]}"
    end
  end

  # Add facts
  fact :temperature, value: 85, location: "server_room"

  # Execute rules
  run
end
```

---

## Knowledge Base

### Creating a Knowledge Base

#### `KBS.knowledge_base(engine: nil, &block)`

Creates a new knowledge base and evaluates the block in its context.

**Parameters**:
- `engine` - Engine to run on, such as `KBS::Blackboard::Engine.new(db_path: "knowledge.db")` for persistence (needs `require "kbs/blackboard"`; optional, a new `KBS::Engine` when omitted)

**Returns**: `KBS::DSL::KnowledgeBase` instance

**Example**:
```ruby
kb = KBS.knowledge_base do
  # Define rules and add facts here
end

# Access the underlying engine
kb.engine  # => KBS::Engine

# Access defined rules
kb.rules   # => Hash of rule_name => KBS::Rule
```

---

### Knowledge Base Methods

#### `rule(name, priority: nil, &block)` / `defrule(name, priority: nil, &block)`

Defines a new rule and adds it to the engine.

**Parameters**:
- `name` (String or Symbol) - Rule name
- `priority` (Integer, optional) - Rule priority; a `priority` call inside the block wins
- `&block` - Block containing rule definition

**Returns**: `KBS::DSL::RuleBuilder`

**Example**:
```ruby
kb = KBS.knowledge_base do
  rule "example_rule" do
    # Rule definition here
  end

  # Alias
  defrule "another_rule" do
    # Rule definition here
  end
end
```

---

#### `fact(type, attributes = {})` / `assert(type, attributes = {})`

Adds a fact to working memory.

**Parameters**:
- `type` (Symbol) - Fact type
- `attributes` (Hash) - Fact attributes

**Returns**: `KBS::Fact`. When the engine's fact duplication is off (`kb.engine.fact_duplication = false`), asserting a fact equal to one already in working memory returns that existing fact instead of adding another.

**Example**:
```ruby
kb = KBS.knowledge_base do
  fact :temperature, value: 85, location: "server_room"

  # Alias
  assert :sensor, id: 1, status: "active"
end
```

---

#### `retract(fact)`

Removes a fact from working memory.

**Parameters**:
- `fact` (KBS::Fact) - Fact to remove

**Returns**: the removed `KBS::Fact`

**Example**:
```ruby
kb = KBS.knowledge_base do
  temp_fact = fact :temperature, value: 85

  # Later...
  retract temp_fact
end
```

---

#### `run(limit = nil)`

Fires activations from the agenda, highest priority first, until the agenda is empty. Facts that an action asserts or retracts update the agenda before the next firing, so rules chain within one run. Each activation fires once.

**Parameters**:
- `limit` (Integer, optional) - Stop after this many firings

**Returns**: `Integer` - the number of rules fired

**Example**:
```ruby
kb = KBS.knowledge_base do
  rule "my_rule" do
    on :temperature, value: greater_than(80)
    perform { puts "High temperature!" }
  end

  fact :temperature, value: 85

  run  # Fires "my_rule"
end
```

---

#### `modify(fact, changes)`

Merges `changes` into the fact's attributes and matches it again (a retraction followed by an assertion), so rules that already fired for the fact can fire again for its new values. Assigning `fact[:key] = value` does not re-match the fact.

**Returns**: the fact; `nil` when the fact is not in working memory

```ruby
kb = KBS.knowledge_base do
  order = fact :order, id: 1, status: "pending"
  modify order, status: "shipped"
end
```

---

#### `halt()`

Stops the current `run` after the rule that is firing. Call it from an action, as `kb.halt` (see [Actions](#actions) for why the receiver is needed).

---

#### `reset()`

Clears all facts from working memory and every pending activation. Rules stay defined.

**Example**:
```ruby
kb = KBS.knowledge_base do
  fact :temperature, value: 85
  fact :humidity, value: 60

  reset  # All facts removed

  puts facts.size  # => 0
end
```

---

#### `facts()`

Returns all facts in working memory.

**Returns**: `Array<KBS::Fact>`

**Example**:
```ruby
kb = KBS.knowledge_base do
  fact :temperature, value: 85
  fact :humidity, value: 60

  puts facts.size  # => 2

  facts.each do |f|
    puts "#{f.type}: #{f.attributes}"
  end
end
```

---

#### `query(type, pattern = {})`

Queries facts by type and attributes.

**Parameters**:
- `type` (Symbol) - Fact type to match
- `pattern` (Hash) - Attribute key-value pairs to match. A value can be a literal, a lambda (called with the attribute's value) or a [pattern helper](#pattern-helpers) such as `greater_than(80)`

**Returns**: `Array<KBS::Fact>`

**Example**:
```ruby
kb = KBS.knowledge_base do
  fact :temperature, value: 85, location: "server_room"
  fact :temperature, value: 75, location: "lobby"
  fact :humidity, value: 60, location: "server_room"

  # Find all temperature facts
  temps = query(:temperature)
  puts temps.size  # => 2

  # Find temperature facts in server_room
  server_temps = query(:temperature, location: "server_room")
  puts server_temps.size  # => 1
  puts server_temps.first[:value]  # => 85

  # Find hot temperature facts with a pattern helper
  hot = query(:temperature, value: greater_than(80))
  puts hot.size  # => 1
end
```

---

#### `print_facts()`

Displays all facts in working memory.

**Returns**: `nil`

**Example**:
```ruby
kb = KBS.knowledge_base do
  fact :temperature, value: 85
  fact :humidity, value: 60

  print_facts
end

# Output:
# Working Memory Contents:
# ----------------------------------------
# 1. fact :temperature, value: 85
# 2. fact :humidity, value: 60
# ----------------------------------------
```

---

#### `print_rules()`

Displays all defined rules with their conditions.

**Returns**: `nil`

**Example**:
```ruby
kb = KBS.knowledge_base do
  rule "high_temp" do
    desc "Alert on high temperature"
    priority 10
    on :temperature, value: greater_than(80)
    perform { puts "High temp!" }
  end

  print_rules
end

# Output:
# Knowledge Base Rules:
# ----------------------------------------
# Rule: high_temp
#   Description: Alert on high temperature
#   Priority: 10
#   Conditions: 1
#     1. temperature(value: ->(v) { v > 80 })
#
# ----------------------------------------
```

---

## Rule Definition

Rules are defined using the `rule` method with a block containing:

1. **Metadata**: Description and priority
2. **Conditions**: Patterns to match facts
3. **Action**: Code to execute when all conditions match

### Rule Structure

```ruby
rule "rule_name" do
  desc "Optional description"
  priority 10  # Optional, default: 0

  # Conditions (one or more)
  on :fact_type, attribute: value, other: :variable?
  on :another_type, field: predicate

  # Action
  perform do |facts, bindings|
    # Code to execute
  end
end
```

---

### Rule Metadata

#### `desc(description)`

Sets the rule description (for documentation and debugging).

**Parameters**:
- `description` (String) - Human-readable description

**Returns**: `self` (chainable)

**Example**:
```ruby
rule "temperature_alert" do
  desc "Alerts when server room temperature exceeds safe threshold"

  on :temperature, location: "server_room", value: greater_than(80)
  perform { puts "High temperature alert!" }
end
```

---

#### `priority(level)`

Sets the rule priority (higher priority rules fire first).

**Parameters**:
- `level` (Integer) - Priority level (default: 0)

**Returns**: `self` (chainable)

**Note**: Both `KBS::Engine` and `KBS::Blackboard::Engine` honor priority. Rules with equal priority fire in definition order under the default `:definition` conflict-resolution strategy (`KBS::Engine.new(strategy: :depth)` or `:breadth` order them by activation age instead).

**Example**:
```ruby
rule "critical_shutdown" do
  priority 1000  # Highest priority
  on :temperature, value: greater_than(120)
  perform { shutdown_system! }
end

rule "log_reading" do
  priority 1  # Low priority
  on :temperature, value: :temp?
  perform { |facts, b| log(b[:temp?]) }
end
```

---

## Condition Syntax

Conditions specify patterns that must match facts in working memory.

### Condition Keywords

All of these are **aliases** - use whichever reads best for your domain:

- **`on(type, pattern = {}, &block)`** - Primary keyword
- **`given(type, pattern = {})`** - Alias for `on`
- **`matches(type, pattern = {})`** - Alias for `on`
- **`fact(type, pattern = {})`** - Alias for `on`

`exists` is not an alias; see [Exists](#exists).

**Parameters**:
- `type` (Symbol) - Fact type to match
- `pattern` (Hash) - Attribute constraints (key-value pairs)
- `&block` (optional) - Block-style pattern definition

**Returns**: `self` (chainable)

---

### Basic Condition Examples

```ruby
# Match any temperature fact
on :temperature

# Match temperature with specific value
on :temperature, value: 85

# Match temperature with multiple attributes
on :temperature, value: 85, location: "server_room"

# Using aliases
given :sensor, status: "active"
matches :order, status: "pending"
fact :inventory, quantity: 0
exists :alert, level: "critical"
```

---

### Literal Matching

Match exact attribute values:

```ruby
on :temperature, location: "server_room"  # location must equal "server_room"
on :order, status: "pending", total: 100  # Both must match exactly
```

---

### Variable Binding

Capture attribute values in variables (symbols ending with `?`):

```ruby
on :temperature, value: :temp?, location: :loc?

# In action:
perform do |facts, bindings|
  puts "Temperature: #{bindings[:temp?]}"
  puts "Location: #{bindings[:loc?]}"
end
```

**Join Test**: Same variable in multiple conditions creates a join:

```ruby
on :order, product_id: :pid?, quantity: :qty?
on :inventory, product_id: :pid?, available: :avail?

# These conditions only match when product_id is the same in both facts
```

---

### Predicate Matching

Use lambdas or helper methods for complex conditions:

```ruby
# Lambda predicate
on :temperature, value: ->(v) { v > 80 && v < 100 }

# Helper method (see Pattern Helpers section)
on :temperature, value: greater_than(80)
on :order, total: between(100, 1000)
on :status, code: one_of("pending", "processing", "completed")
```

---

### Block-Style Patterns

Define patterns using a block. Each call `name value` sets the pattern for attribute `name`. A variable can be written as a `:name?` symbol or as a bare name (`location loc` is `location :loc?`). Comparing a bare name with a value sets that attribute's predicate: `value > 80`, `value < 80`, `value >= 80`, `value <= 80`, `code != 3`, and `code == 3` (a literal match):

```ruby
on :temperature do
  value > 80              # Predicate (same as: value greater_than(80))
  location loc            # Binds variable (same as: location :loc?)
  sensor_id 42            # Literal match
end

# Equivalent to:
on :temperature,
   value: ->(v) { v > 80 },
   location: :loc?,
   sensor_id: 42
```

A block pattern is merged over a hash pattern given in the same call.

**Available in blocks**: every [pattern helper](#pattern-helpers), plus:
- `between(min, max)` - Range check
- `self.in(collection)` - Membership check (`in` is a Ruby keyword, so it needs the explicit receiver; `one_of` reads better)
- `matches(pattern)` - Regex match
- `any(*values)` - Match any of the values
- `all(*predicates)` - Every predicate (or literal) must hold

`status in [...]` does **not** work: it is parsed as Ruby pattern matching and silently adds nothing. Use `status one_of(...)` instead.

**Example**:
```ruby
on :order do
  total greater_than(1000)
  status one_of("pending", "processing")
  customer_email matches(/@example\.com$/)
  priority any(1, 2, 3)
end
```

---

## Pattern Helpers

Helper methods available in rule conditions and in `query` patterns (from the `ConditionHelpers` module, which both `RuleBuilder` and `KnowledgeBase` include).

### Comparison Helpers

#### `greater_than(value)`

Matches values greater than the specified value.

**Example**:
```ruby
on :temperature, value: greater_than(80)
# Equivalent to: value: ->(v) { v > 80 }
```

---

#### `less_than(value)`

Matches values less than the specified value.

**Example**:
```ruby
on :inventory, quantity: less_than(10)
# Equivalent to: quantity: ->(q) { q < 10 }
```

---

#### `equals(value)`

Explicitly matches an exact value (same as literal).

**Example**:
```ruby
on :sensor, status: equals("active")
# Equivalent to: status: "active"
```

---

#### `not_equal(value)`

Matches values not equal to the specified value.

**Example**:
```ruby
on :order, status: not_equal("cancelled")
# Equivalent to: status: ->(s) { s != "cancelled" }
```

---

### Range Helpers

#### `between(min, max)` / `range(min, max)`

Matches values in an inclusive range.

**Example**:
```ruby
on :temperature, value: between(70, 90)
# Equivalent to: value: ->(v) { v >= 70 && v <= 90 }

# Also works with Range objects:
on :temperature, value: range(70..90)
```

---

### Collection Helpers

#### `one_of(*values)`

Matches if value is one of the specified values.

**Example**:
```ruby
on :order, status: one_of("pending", "processing", "completed")
# Equivalent to: status: ->(s) { ["pending", "processing", "completed"].include?(s) }
```

---

#### `any(*values)`

- With arguments: Same as `one_of`
- Without arguments: Matches any value (always true)

**Example**:
```ruby
# Match one of several values
on :priority, level: any(1, 2, 3)

# Match any value (always true)
on :metadata, extra_data: any
```

---

### String Helpers

#### `matches(pattern)`

Matches strings against a regular expression.

**Example**:
```ruby
on :email, address: matches(/@example\.com$/)
# Equivalent to: address: ->(a) { a.match?(/@example\.com$/) }

on :sensor, name: matches(/^temp_\d+$/)
```

---

### Custom Predicates

#### `satisfies(&block)`

Creates a custom predicate from a block.

**Example**:
```ruby
on :order, total: satisfies { |t| t > 100 && t % 10 == 0 }
# Equivalent to: total: ->(t) { t > 100 && t % 10 == 0 }
```

---

## Variable Binding

Variables allow you to:
1. Capture attribute values for use in actions
2. Create join tests between conditions

### Variable Syntax

Variables are symbols ending with `?`:

```ruby
:temp?      # Variable named "temp"
:location?  # Variable named "location"
:pid?       # Variable named "pid"
```

---

### Capturing Values

```ruby
rule "temperature_report" do
  on :temperature, value: :temp?, location: :loc?, timestamp: :time?

  perform do |facts, bindings|
    puts "Temperature at #{bindings[:loc?]}: #{bindings[:temp?]}°F"
    puts "Recorded: #{bindings[:time?]}"
  end
end
```

---

### Join Tests

Variables with the same name in different conditions create a join test:

```ruby
rule "check_inventory" do
  on :order, product_id: :pid?, quantity: :qty?
  on :inventory, product_id: :pid?, available: :avail?

  perform do |facts, bindings|
    if bindings[:avail?] < bindings[:qty?]
      puts "Insufficient inventory for product #{bindings[:pid?]}"
    end
  end
end

# This rule only fires when:
# 1. An order fact exists
# 2. An inventory fact exists
# 3. Both facts have the SAME product_id
```

---

### Multiple Bindings

```ruby
rule "sensor_temperature_correlation" do
  on :sensor, id: :sensor_id?, location: :loc?, status: "active"
  on :temperature, sensor_id: :sensor_id?, value: :temp?
  on :reading, sensor_id: :sensor_id?, timestamp: :time?

  perform do |facts, bindings|
    # All three facts share the same sensor_id
    puts "Sensor #{bindings[:sensor_id?]} at #{bindings[:loc?]}"
    puts "Reading: #{bindings[:temp?]}°F at #{bindings[:time?]}"
  end
end
```

---

## Exists

`exists(type, pattern = {}, &block)` matches when **at least one** fact fits the pattern, and matches once however many do.

```ruby
rule "sound the horn" do
  exists :alarm, level: "critical"
  perform { sound_horn }
end
```

With three critical alarms in working memory, `on :alarm` fires the rule three times and `exists :alarm` fires it once. The rule stays matched until the last such alarm is retracted, and matches again when a new one arrives.

An `exists` condition tests for facts but adds none to the match:

- the action's `facts` has no entry for it
- a variable first used in it is not bound for later conditions or for the action
- a variable bound by an earlier condition does join, so `on :order, id: :id?` followed by `exists :payment, order_id: :id?` matches each order that has at least one payment, once

`exists` is the opposite of `without`: `without` matches while no fact fits, `exists` while at least one does.

---

## Logical Conditions

`logical do ... end` marks the conditions inside it as logical: every fact the rule's action asserts stays in working memory only while those conditions are matched, and is retracted automatically when they stop matching. The `logical` block must come before the rule's other conditions (`add_rule` raises `ArgumentError` otherwise).

```ruby
kb = KBS.knowledge_base do
  rule "overheating" do
    logical do
      on :sensor, temp: greater_than(90)
    end
    perform { kb.fact :overheating }
  end
end

sensor = kb.fact :sensor, temp: 95
kb.run              # asserts :overheating
kb.retract sensor   # :overheating is retracted with it
```

See the [Truth Maintenance Guide](truth-maintenance.md) for details.

---

## Negation

Negation matches when a pattern is **absent** from working memory.

### Negation Keywords

All of these are **aliases**:

- **`without(type, pattern = {})`** - Primary negation keyword
- **`absent(type, pattern = {})`** - Alias
- **`missing(type, pattern = {})`** - Alias
- **`lacks(type, pattern = {})`** - Alias

---

### Direct Negation

```ruby
# Fire when there is NO alert fact
rule "all_clear" do
  on :system, status: "running"
  without :alert
  perform { puts "All systems normal" }
end

# Fire when there is NO critical alert
rule "no_critical_alerts" do
  without :alert, level: "critical"
  perform { puts "No critical alerts" }
end

# Using aliases
absent :error
missing :problem, severity: "high"
lacks :maintenance_flag
```

---

### Chained Negation

Use `without` (without arguments) followed by `on`:

```ruby
rule "example" do
  on :order, status: "pending"
  without.on :inventory, quantity: 0
  perform { puts "Order can be fulfilled" }
end
```

---

### Negation with Variables

Variables in negated conditions create "there is no fact with this value" tests:

```ruby
rule "no_matching_inventory" do
  on :order, product_id: :pid?
  without :inventory, product_id: :pid?

  perform do |facts, bindings|
    puts "No inventory for product #{bindings[:pid?]}"
  end
end

# Fires when:
# 1. An order exists with product_id=X
# 2. NO inventory fact exists with product_id=X
```

---

### Negation Examples

```ruby
# Guard condition - only process if no errors
rule "process_order" do
  on :order, status: "pending"
  without :error
  perform { process_order }
end

# Detect missing required fact
rule "missing_configuration" do
  on :system, initialized: true
  without :config, loaded: true
  perform { puts "WARNING: Configuration not loaded" }
end

# Timeout detection
rule "sensor_timeout" do
  on :sensor, id: :sensor_id?, expected: true
  without :reading, sensor_id: :sensor_id?
  perform { |facts, b| puts "Sensor #{b[:sensor_id?]} timeout" }
end
```

---

## Actions

Actions define what happens when all conditions match.

### Action Keywords

All of these are **aliases**:

- **`perform(&block)`** - Primary action keyword
- **`action(&block)`** - Alias
- **`execute(&block)`** - Alias
- **`then(&block)`** - Alias. `then` is a Ruby keyword, so it must be called with an explicit receiver: `self.then { ... }`

---

### Action Block

An action can take no arguments, one (`facts`) or two (`facts, bindings`). `facts` holds one fact per positive condition, in condition order (`without` and `exists` conditions add none); `bindings` maps each `?variable` to its value:

```ruby
rule "example" do
  on :temperature, value: :temp?, location: :loc?

  perform do |facts, bindings|
    temp = bindings[:temp?]
    location = bindings[:loc?]
    puts "Temperature at #{location}: #{temp}°F"
  end
end
```

---

### Action Capabilities

Actions can:

1. **Read bindings**:
```ruby
perform do |facts, bindings|
  value = bindings[:temp?]
end
```

2. **Change working memory**:

The action runs with the rule builder as `self`. Once the rule is built, the builder forwards `fact`, `assert`, `retract`, `modify`, `query`, `facts`, `halt` and `engine` to the knowledge base, so they work bare inside `perform` (facts asserted from a rule with `logical` conditions get logical support either way). Condition keywords such as `on` or `without` raise `KBS::RuleBuiltError` there. A builder made with `RuleBuilder.new` and no knowledge base raises `KBS::NoKnowledgeBaseError` for these calls.

```ruby
perform do |facts|
  fact :process, status: "running"
  retract facts.first
end
```

Calling the knowledge base through a local works too:

```ruby
kb = KBS.knowledge_base do
  rule "add_fact_from_action" do
    on :trigger, event: "start"
    perform do
      kb.fact :process, status: "running"  # Add new fact
    end
  end
end

kb.fact :trigger, event: "start"
kb.run  # call run once `kb` is assigned
```

3. **Call external methods**:
```ruby
perform do |facts, bindings|
  send_email_alert(bindings[:temp?])
  log_to_database(bindings)
  trigger_alarm if bindings[:level?] == "critical"
end
```

4. **Add/remove facts**:
```ruby
perform do |facts, bindings|
  # Add derived fact
  kb.fact :alert, level: "high", source: bindings[:sensor_id?]

  # Remove triggering fact
  old_fact = kb.query(:trigger, event: "start").first
  kb.retract old_fact if old_fact
end
```

---

### Action Examples

```ruby
# Simple logging
rule "log_temperature" do
  on :temperature, value: :temp?
  perform { |facts, b| puts "Temperature: #{b[:temp?]}" }
end

# State machine transition
rule "pending_to_processing" do
  on :order, id: :order_id?, status: "pending"
  on :worker, status: "available", id: :worker_id?

  perform do |facts, bindings|
    order, worker = facts

    # Update order status
    kb.modify order, status: "processing", worker_id: bindings[:worker_id?]

    # Update worker status
    kb.modify worker, status: "busy"
  end
end

# Aggregation
rule "daily_summary" do
  on :trigger, event: "end_of_day"

  perform do
    temps = kb.query(:temperature).map { |f| f[:value] }
    avg = temps.sum / temps.size.to_f

    kb.fact :daily_summary,
         date: Date.today,
         avg_temp: avg,
         max_temp: temps.max,
         min_temp: temps.min
  end
end
```

---

## Working with Facts

### Adding Facts

```ruby
kb = KBS.knowledge_base do
  # During initialization
  fact :temperature, value: 85, location: "server_room"
  fact :sensor, id: 1, status: "active"

  # Or from action blocks
  rule "add_derived_fact" do
    on :temperature, value: greater_than(80)
    perform do
      kb.fact :alert, level: "high", timestamp: Time.now
    end
  end
end

# After creation
kb.fact :temperature, value: 90
kb.assert :humidity, value: 60  # Alias
```

---

### Removing Facts

```ruby
kb = KBS.knowledge_base do
  temp = fact :temperature, value: 85

  # Remove specific fact
  retract temp

  # Remove from action
  rule "cleanup" do
    on :trigger, event: "cleanup"
    perform do
      old_facts = kb.query(:temperature)
                    .select { |f| f[:timestamp] && f[:timestamp] < Time.now - 3600 }
      old_facts.each { |f| kb.retract f }
    end
  end
end
```

---

### Querying Facts

```ruby
kb = KBS.knowledge_base do
  fact :temperature, value: 85, location: "server_room"
  fact :temperature, value: 75, location: "lobby"
  fact :humidity, value: 60, location: "server_room"

  # Get all facts
  all = facts

  # Query by type
  temps = query(:temperature)

  # Query by type and attributes
  server_room_temps = query(:temperature, location: "server_room")

  # Use query results in actions
  rule "check_average" do
    on :trigger, event: "calculate_average"

    perform do
      temps = kb.query(:temperature).map { |f| f[:value] }
      avg = temps.sum / temps.size.to_f
      puts "Average temperature: #{avg.round(1)}°F"
    end
  end
end
```

---

## Introspection

### Inspecting Facts

```ruby
kb = KBS.knowledge_base do
  fact :temperature, value: 85
  fact :humidity, value: 60

  print_facts
end

# Output:
# Working Memory Contents:
# ----------------------------------------
# 1. fact :temperature, value: 85
# 2. fact :humidity, value: 60
# ----------------------------------------
```

---

### Inspecting Rules

```ruby
kb = KBS.knowledge_base do
  rule "high_temp" do
    desc "Alert on high temperature"
    priority 10
    on :temperature, value: greater_than(80)
    perform { puts "High!" }
  end

  print_rules
end

# Output:
# Knowledge Base Rules:
# ----------------------------------------
# Rule: high_temp
#   Description: Alert on high temperature
#   Priority: 10
#   Conditions: 1
#     1. temperature(value: ->(v) { v > 80 })
#
# ----------------------------------------
```

---

### Programmatic Access

```ruby
kb = KBS.knowledge_base do
  rule "example" do
    on :temperature, value: :temp?
    perform { |facts, b| puts b[:temp?] }
  end
end

# Access rules
kb.rules  # => Hash { "example" => KBS::Rule }
kb.rules["example"]  # => KBS::Rule instance

# Access engine
kb.engine  # => KBS::Engine
kb.engine.working_memory  # => KBS::WorkingMemory
kb.engine.rules  # => Array<KBS::Rule>
```

---

## Complete Examples

### Temperature Monitoring

```ruby
require 'kbs'

kb = KBS.knowledge_base do
  # Rules
  rule "high_temperature_alert" do
    desc "Alert when temperature exceeds safe threshold"
    priority 10

    on :sensor, id: :sensor_id?, status: "active"
    on :temperature, sensor_id: :sensor_id?, value: greater_than(80)
    without :alert, sensor_id: :sensor_id?  # No existing alert

    perform do |facts, bindings|
      puts "⚠️  HIGH TEMPERATURE ALERT"
      puts "Sensor: #{bindings[:sensor_id?]}"
      puts "Temperature: #{facts[1][:value]}°F"

      # Create alert fact
      kb.fact :alert,
           sensor_id: bindings[:sensor_id?],
           level: "high",
           timestamp: Time.now
    end
  end

  rule "temperature_normal" do
    desc "Clear alert when temperature returns to normal"
    priority 5

    on :temperature, sensor_id: :sensor_id?, value: less_than(75)
    on :alert, sensor_id: :sensor_id?

    perform do |facts, bindings|
      puts "✓ Temperature normal for sensor #{bindings[:sensor_id?]}"

      # Remove alert
      alerts = kb.query(:alert, sensor_id: bindings[:sensor_id?])
      alerts.each { |a| kb.retract a }
    end
  end

  # Initial facts
  fact :sensor, id: 1, status: "active", location: "server_room"
  fact :sensor, id: 2, status: "active", location: "lobby"

  # Simulate readings
  fact :temperature, sensor_id: 1, value: 85  # Will trigger alert
  fact :temperature, sensor_id: 2, value: 72  # Normal
end

kb.run
kb.print_facts
```

---

### Order Processing Workflow

```ruby
kb = KBS.knowledge_base do
  rule "validate_order" do
    priority 100

    on :order, id: :order_id?, status: "new", product_id: :pid?, quantity: :qty?
    on :inventory, product_id: :pid?, quantity: :available?

    perform do |facts, bindings|
      if bindings[:available?] >= bindings[:qty?]
        order = kb.query(:order, id: bindings[:order_id?]).first
        kb.retract order
        kb.fact :order,
             id: bindings[:order_id?],
             status: "validated",
             product_id: bindings[:pid?],
             quantity: bindings[:qty?]
      else
        kb.fact :alert,
             type: "insufficient_inventory",
             order_id: bindings[:order_id?]
      end
    end
  end

  rule "fulfill_order" do
    priority 50

    on :order, id: :order_id?, status: "validated",
               product_id: :pid?, quantity: :qty?
    on :inventory, product_id: :pid?, quantity: :available?

    perform do |facts, bindings|
      # Deduct inventory
      inventory = kb.query(:inventory, product_id: bindings[:pid?]).first
      kb.retract inventory
      kb.fact :inventory,
           product_id: bindings[:pid?],
           quantity: bindings[:available?] - bindings[:qty?]

      # Update order status
      order = kb.query(:order, id: bindings[:order_id?]).first
      kb.retract order
      kb.fact :order,
           id: bindings[:order_id?],
           status: "fulfilled",
           product_id: bindings[:pid?],
           quantity: bindings[:qty?]

      puts "✓ Order #{bindings[:order_id?]} fulfilled"
    end
  end

  # Initial state
  fact :inventory, product_id: "ABC", quantity: 100
  fact :inventory, product_id: "XYZ", quantity: 50

  fact :order, id: 1, status: "new", product_id: "ABC", quantity: 10
  fact :order, id: 2, status: "new", product_id: "XYZ", quantity: 60  # Insufficient!
end

kb.run
kb.print_facts
```

---

## Best Practices

### 1. Use Descriptive Names

```ruby
# Good
rule "high_temperature_alert" do
  desc "Alert when server room temperature exceeds 80°F"
  # ...
end

# Bad
rule "rule1" do
  # ...
end
```

---

### 2. Add Descriptions

```ruby
rule "complex_calculation" do
  desc "Calculates portfolio value using current market prices and holdings"
  # ... complex logic ...
end
```

---

### 3. Order Conditions by Selectivity

```ruby
# Good - Most selective first
rule "specific_sensor_alert" do
  on :sensor, id: 42, status: "active"  # Very selective
  on :temperature, sensor_id: 42, value: greater_than(80)
  perform { puts "Alert!" }
end

# Less efficient - Unselective first
rule "specific_sensor_alert" do
  on :temperature, value: greater_than(80)  # Matches many facts
  on :sensor, id: 42, status: "active"
  perform { puts "Alert!" }
end
```

---

### 4. Use Pattern Helpers

```ruby
# Good - Readable
on :temperature, value: between(70, 90)
on :order, status: one_of("pending", "processing")

# Less readable
on :temperature, value: ->(v) { v >= 70 && v <= 90 }
on :order, status: ->(s) { ["pending", "processing"].include?(s) }
```

---

### 5. Keep Actions Simple

```ruby
# Good - Simple, focused action
rule "log_temperature" do
  on :temperature, value: :temp?
  perform { |facts, b| logger.info("Temperature: #{b[:temp?]}") }
end

# Avoid - Complex logic in action
rule "complex_action" do
  on :temperature, value: :temp?
  perform do |facts, b|
    # 100 lines of complex logic...
    # Better to extract to methods
  end
end
```

---

## See Also

- [Getting Started Guide](getting-started.md) - First tutorial
- [Writing Rules Guide](writing-rules.md) - Best practices for rules
- [Pattern Matching Guide](pattern-matching.md) - Advanced pattern matching
- [Variable Binding Guide](variable-binding.md) - Join tests and bindings
- [Negation Guide](negation.md) - Negation semantics
- [Rules API](../api/rules.md) - Programmatic rule creation
