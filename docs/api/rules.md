# Rules API Reference

Complete API reference for rule classes in KBS.

## Table of Contents

- [KBS::Rule](#kbsrule) - Production rule with conditions and action
- [DSL Rule Builder](#dsl-rule-builder) - `rule`, `on`, `without`, `exists`, `logical`, `perform`, condition helpers
- [Rule Lifecycle](#rule-lifecycle)

`KBS::Condition` is documented in the [Facts API](facts.md#kbscondition).
- [Rule Patterns](#rule-patterns)
- [Best Practices](#best-practices)

---

## KBS::Rule

A production rule that fires when all conditions match.

**Structure**: A rule consists of:
1. **Name** - Unique identifier
2. **Priority** - Execution order (higher = more urgent)
3. **Conditions** - Array of patterns to match
4. **Action** - Lambda executed when all conditions match

---

### Constructor

#### `initialize(name, conditions: [], action: nil, priority: 0, &block)`

Creates a new rule.

**Parameters**:
- `name` (Symbol or String) - Unique rule identifier
- `conditions` (Array<KBS::Condition>, optional) - Conditions to match (default: `[]`)
- `action` (Proc, optional) - Action lambda to execute (default: `nil`)
- `priority` (Integer, optional) - Rule priority (default: `0`)
- `&block` (Block, optional) - Configuration block yielding self

**Returns**: `KBS::Rule` instance

**Example - Low-level API (Direct Construction)**:
```ruby
# Minimal rule
rule = KBS::Rule.new(:high_temperature)

# Rule with all parameters
rule = KBS::Rule.new(
  :high_temperature,
  conditions: [
    KBS::Condition.new(:temperature, { value: ->(v) { v > 80 } })
  ],
  action: ->(facts) { puts "High temperature detected!" },
  priority: 10
)
```

Write a condition's pattern as a braced Hash: `KBS::Condition.new(:temperature, value: 85)` without braces passes `value:` as a keyword and raises `ArgumentError: unknown keyword: :value`.

**Example - Low-level API (Block Configuration)**:
```ruby
rule = KBS::Rule.new(:high_temperature) do |r|
  r.conditions << KBS::Condition.new(:temperature, { value: ->(v) { v > 80 } })
  r.action = ->(facts) { puts "High temperature: #{facts[0][:value]}" }
end
```

**Using DSL (Recommended)**:
```ruby
kb = KBS.knowledge_base do
  rule "high_temperature", priority: 10 do
    on :temperature, value: greater_than(80)
    perform do |facts, bindings|
      puts "High temperature: #{bindings[:value?]}"
    end
  end
end

# Already added to kb.engine; the KBS::Rule is kb.rules["high_temperature"]
```

---

### Public Attributes

#### `name`

**Type**: `Symbol` or `String`

**Read-only**: Yes (via `attr_reader`)

**Description**: Unique rule identifier

**Example - Low-level API**:
```ruby
rule = KBS::Rule.new(:high_temperature, priority: 10)
puts rule.name  # => :high_temperature
```

**Using DSL (Recommended)**:
```ruby
kb = KBS.knowledge_base do
  rule "high_temperature", priority: 10 do
    on :temperature, value: greater_than(80)
    perform { puts "Alert!" }
  end
end

puts kb.engine.rules.first.name  # => "high_temperature"
```

`kb.rules` is a Hash of rule name → `KBS::Rule`; `kb.engine.rules` is an Array.

**Best Practice**: Use descriptive names that indicate the rule's purpose:
```ruby
# Good
"high_temperature_alert"
"low_inventory_reorder"
"fraud_detection_high_risk"

# Less clear
"rule1"
"temp_rule"
"check"
```

---

#### `priority`

**Type**: `Integer`

**Read-only**: Yes (via `attr_reader`)

**Description**: Rule priority (higher = executes first)

**Default**: `0`

**Range**: Any integer (commonly 0-100)

**Example - Low-level API**:
```ruby
rule = KBS::Rule.new(:critical_alert, priority: 100)
puts rule.priority  # => 100
```

**Using DSL (Recommended)**:
```ruby
kb = KBS.knowledge_base do
  rule "critical_alert", priority: 100 do
    on :alert, level: "critical"
    perform { puts "CRITICAL ALERT!" }
  end
end
```

**Priority Semantics**:
- Higher priority rules fire first in both `KBS::Engine` and `KBS::Blackboard::Engine`
- Rules with equal priority fire in the order they were defined (with the default `:definition` strategy; see [Engine API](engine.md#runlimit-nil))
- In the DSL, a `priority 100` call inside the rule block wins over the `priority:` keyword

**Common Priority Ranges**:
```ruby
# Critical safety rules
priority: 100

# Important business rules
priority: 50

# Standard rules
priority: 10

# Cleanup/logging rules
priority: 0

# Background tasks
priority: -10
```

**Example - Priority Ordering**:
```ruby
require 'kbs/blackboard'

engine = KBS::Blackboard::Engine.new

kb = KBS.knowledge_base(engine: engine) do
  rule "log_temperature", priority: 0 do
    on :temperature, value: :temp?
    perform { |facts, b| puts "Logged: #{b[:temp?]}" }
  end

  rule "critical_alert", priority: 100 do
    on :temperature, value: greater_than(100)
    perform { puts "CRITICAL TEMPERATURE!" }
  end

  rule "high_alert", priority: 50 do
    on :temperature, value: greater_than(80)
    perform { puts "High temperature warning" }
  end
end

engine.add_fact(:temperature, value: 110)
engine.run

# Output (in priority order):
# CRITICAL TEMPERATURE!      (priority 100)
# High temperature warning   (priority 50)
# Logged: 110                (priority 0)
```

---

#### `conditions`

**Type**: `Array<KBS::Condition>`

**Read/Write**: Yes (via `attr_accessor`)

**Description**: Array of conditions that must all match for rule to fire

**Example - Low-level API**:
```ruby
rule = KBS::Rule.new(:temperature_alert)
rule.conditions << KBS::Condition.new(:temperature, { value: ->(v) { v > 80 } })
rule.conditions << KBS::Condition.new(:sensor, { status: "active" })

puts rule.conditions.size  # => 2
```

**Using DSL (Recommended)**:
```ruby
kb = KBS.knowledge_base do
  rule "temperature_alert" do
    on :temperature, value: greater_than(80)
    on :sensor, status: "active"
    perform { puts "Alert!" }
  end
end

puts kb.rules["temperature_alert"].conditions.size  # => 2
```

Conditions written inside a DSL `logical do ... end` block come first and are marked logical; `KBS::Engine#add_rule` raises `ArgumentError` for a rule whose logical conditions do not all come before the others.

**Condition Order Matters** (for performance):

**Low-level API**:
```ruby
# Good - Most selective condition first
rule.conditions = [
  KBS::Condition.new(:sensor, { id: 42 }),             # Filters to 1 fact
  KBS::Condition.new(:temperature, { value: :temp? })  # Then match temperature
]

# Less optimal - Less selective first
rule.conditions = [
  KBS::Condition.new(:temperature, { value: :temp? }),  # Matches many facts
  KBS::Condition.new(:sensor, { id: 42 })               # Could have filtered first
]
```

**Using DSL (Recommended)**:
```ruby
# Good - Most selective condition first
rule "sensor_alert" do
  on :sensor, id: 42                    # Filters to 1 fact
  on :temperature, value: :temp?        # Then match temperature
  perform { |facts, b| puts b[:temp?] }
end

# Less optimal - Less selective first
rule "sensor_alert" do
  on :temperature, value: :temp?        # Matches many facts
  on :sensor, id: 42                    # Could have filtered first
  perform { |facts, b| puts b[:temp?] }
end
```

See [Performance Guide](../advanced/performance.md) for condition ordering strategies.

---

#### `action`

**Type**: `Proc` (lambda or proc) or `Method`

**Read/Write**: Yes (via `attr_accessor`)

**Description**: Lambda executed when all conditions match

**Signature**: `action.call`, `action.call(facts)`, or `action.call(facts, bindings)` (all supported)

The action's arity picks the call: arity 0 is called without arguments, arity 1 or -1 (such as `->(facts)` or `proc { |*args| }`) with the facts only, and any other arity (such as `->(facts, bindings)` or a block `|facts, bindings|`) with facts and bindings.

**Parameters**:
- `facts` (Array<KBS::Fact>) - Array of matched facts, one per condition that binds a fact, in condition order (`without` and `exists` conditions have no entry)
- `bindings` (Hash, optional) - Variable bindings extracted from facts

**Example - Low-level API (Facts Parameter)**:
```ruby
rule.action = ->(facts) do
  temp_fact = facts[0]  # First positive condition's matched fact
  sensor_fact = facts[1]  # Second positive condition's matched fact

  puts "Temperature: #{temp_fact[:value]} from sensor #{sensor_fact[:id]}"
end
```

**Example - Low-level API (Bindings Parameter)**:
```ruby
# Rule with variable bindings
rule = KBS::Rule.new(:temperature_alert) do |r|
  r.conditions << KBS::Condition.new(:temperature, { value: :temp?, location: :loc? })
  r.action = ->(facts, bindings) do
    # bindings: {:temp? => 85, :loc? => "server_room"}
    puts "#{bindings[:loc?]}: #{bindings[:temp?]}°F"
  end
end
```

**Using DSL (Recommended)**:
```ruby
rule "temperature_alert" do
  on :temperature, value: :temp?, location: :loc?
  perform do |facts, bindings|
    # Cleaner - DSL automatically provides bindings
    puts "#{bindings[:loc?]}: #{bindings[:temp?]}°F"
  end
end
```

**Action Requirements**:
- Must respond to `call` and `arity` (a lambda, proc or Method); a rule with no action fires but does nothing
- Should be idempotent if possible (safe to run multiple times)
- Should not modify facts directly with `fact[:key] = value` (use `engine.add_fact` / `engine.remove_fact` / `engine.modify` instead)
- May add/remove/modify facts (the agenda changes before the next firing, so rules chain within one `run`)
- In the DSL, `self` inside a `perform` block is the rule builder. Once the rule is built, the builder forwards `fact`, `assert`, `retract`, `modify`, `query`, `facts`, `halt` and `engine` to the knowledge base, so bare calls work, as do calls through a local (`kb.assert(...)`). Condition keywords (`on`, `without`, `exists`, `logical`, `perform` and their aliases) raise `KBS::RuleBuiltError` once the rule is built; a builder created without a knowledge base raises `KBS::NoKnowledgeBaseError` for the working-memory calls

---

### Public Methods

#### `fire(facts)`

Executes the rule's action with matched facts.

**Parameters**:
- `facts` (Array<KBS::Fact>) - Matched facts, one per condition that binds a fact, in condition order. Negated (`without`) and `exists` conditions match no fact and have no entry.

**Returns**: Result of action lambda, or `nil` if no action

**Side Effects**:
- Increments internal `@fired_count`
- Executes action lambda
- Action may modify external state, add/remove facts, etc.

**Example - Low-level API**:
```ruby
rule = KBS::Rule.new(:log_temperature) do |r|
  r.conditions << KBS::Condition.new(:temperature, { value: :temp? })
  r.action = ->(facts, bindings) do
    puts "Temperature: #{bindings[:temp?]}"
  end
end

fact = KBS::Fact.new(:temperature, value: 85)
rule.fire([fact])
# Output: Temperature: 85
```

**Using DSL (Recommended)**:
```ruby
kb = KBS.knowledge_base do
  rule "log_temperature" do
    on :temperature, value: :temp?
    perform do |facts, bindings|
      puts "Temperature: #{bindings[:temp?]}"
    end
  end

  fact :temperature, value: 85
  run  # Fires the rule automatically
end
# Output: Temperature: 85
```

**Note**: Typically called by the RETE engine, not user code. Users call `engine.run` which fires all activated rules. The engine fires each match (token) at most once.

#### `bindings_for(facts)`

Returns the variable bindings for a set of matched facts. `fire` passes these to any action whose arity is not 1 or -1, and `KBS::Blackboard::Engine` records them in its audit log.

**Parameters**:
- `facts` (Array<KBS::Fact>) - Matched facts in the same shape `fire` takes: one per condition that binds a fact, in condition order

**Returns**: `Hash` mapping each variable (such as `:temp?`) to its value in the matched facts

**Example**:
```ruby
rule = KBS::Rule.new(:check, conditions: [
  KBS::Condition.new(:sensor, { id: :id? }),
  KBS::Condition.new(:alarm, {}, negated: true),
  KBS::Condition.new(:reading, { value: :value? })
])

rule.bindings_for([KBS::Fact.new(:sensor, id: 7), KBS::Fact.new(:reading, value: 85)])
# => {id?: 7, value?: 85}
```

#### `logical_count`

**Returns**: `Integer` - the number of leading conditions that are logical. Facts the rule's action asserts are supported by the match of those conditions.

#### `logical_conditions_first?`

**Returns**: `Boolean` - whether no logical condition follows a non-logical one. `KBS::Engine#add_rule` raises `ArgumentError` when this is false.

```ruby
rule = KBS::Rule.new(:r, conditions: [
  KBS::Condition.new(:sensor, {}, logical: true),
  KBS::Condition.new(:trigger)
])
rule.logical_count               # => 1
rule.logical_conditions_first?   # => true
```

#### `to_s`

**Returns**: `String` - the rule written as DSL source, rebuilt from its parts. Predicates and the action are decompiled from bytecode, so they read as equivalent code, not necessarily the code you wrote; one that can't be decompiled shows a `<decompilation failed: ...>` placeholder. A rule built without the DSL has no `desc` line.

```ruby
kb = KBS.knowledge_base do
  rule "high_temperature", priority: 10 do
    on :temperature, location: "server_room", value: greater_than(80)
    perform { |facts, bindings| }
  end
end

puts kb.rules["high_temperature"].to_s
# rule "high_temperature" do
#   priority 10
#   on :temperature, location: "server_room", value: ->(v) { v > 80 }
#   perform { |facts, bindings| nil }
# end
```

---

## DSL Rule Builder

`KBS.knowledge_base(engine: nil) { ... }` evaluates its block in a `KBS::DSL::KnowledgeBase` and returns it. Inside, `rule` builds each rule with a `KBS::DSL::RuleBuilder` and adds it to the engine.

### `KnowledgeBase#rule(name, priority: nil, &block)` / `defrule`

Evaluates the block in a new `RuleBuilder`, builds the `KBS::Rule`, stores it in `kb.rules[name]` and calls `engine.add_rule`. Returns the builder. `defrule` is an alias. A `priority` call in the block wins over the `priority:` keyword.

`kb.rule_source(name)` returns the rule's source, read from its file when it can be found there, otherwise rebuilt like `Rule#to_s`; `kb.print_rule_source(name)` and `kb.print_rules` print them.

### `RuleBuilder` methods

| Method | Description |
|---|---|
| `desc(text)` | Sets the description (shown by `print_rules` and `rule_source`; not kept on `KBS::Rule`) |
| `priority(level = nil)` | Sets the priority; with no argument, returns it |
| `on(type, pattern = {}, &block)` | Adds a condition. Aliases: `given`, `matches`, `fact` |
| `without(type = nil, pattern = {}, &block)` | Adds a negated condition: matches while no fact fits. `without.on(type, ...)` also works. Aliases: `absent`, `missing`, `lacks` |
| `exists(type, pattern = {}, &block)` | Matches once while at least one fact fits, however many do. Contributes no fact to the action, and a variable first used here is not bound for later conditions |
| `logical(&block)` | Marks the conditions written in the block as logical: facts the action asserts are retracted when those conditions stop matching. Must come before the rule's other conditions |
| `perform(&block)` | Sets the action. Aliases: `action`, `execute`, `then` |
| `name`, `description`, `conditions`, `action_block` | Readers for what was collected |
| `source`, `summary_lines`, `build` | The rule as DSL source, the lines `print_rules` shows, and the `KBS::Rule` |

```ruby
kb = KBS.knowledge_base do
  rule "overheating" do
    desc "A hot sensor raises a warning while it stays hot"
    priority 10
    logical do
      on :sensor, id: :id?, temp: greater_than(90)
    end
    without :maintenance, sensor_id: :id?
    exists :operator, on_duty: true
    perform { |facts, bindings| kb.assert(:warning, sensor_id: bindings[:id?]) }
  end
end
```

### Block form of a condition

`on`, `without` and `exists` also take a block, merged into the pattern. Each call in the block names an attribute: with one argument it sets that attribute's value, and with a block it sets a predicate.

```ruby
on :sensor do
  id :sensor_id?                       # variable
  temp greater_than(90)                # helper predicate
  status one_of("active", "standby")
  pressure { |v| v < 30 }              # block predicate
end
```

An attribute whose name is already a method (`load`, `print`, `display`, `format`, ...) can't be set this way; put it in the hash pattern instead.

Write variables as `:name?` symbols or as bare names: `id sensor_id` is `id :sensor_id?`. A bare name compared with a value sets that attribute's predicate: `temp > 90`, `<`, `>=`, `<=` and `!=` build predicates, and `temp == 90` is a literal match.

Inside the block, `between(min, max)`, `matches(regexp)`, `any(*values)` and `all(*predicates)` return predicates (as does `self.in(collection)`; a bare `in` is Ruby syntax), along with the condition helpers below.

### Condition helpers

Available in a rule block, in condition blocks and on the knowledge base (for `query`). Each returns a predicate lambda to use as a pattern value, except `equals`, which returns the value itself.

| Helper | Matches when the attribute value... |
|---|---|
| `greater_than(x)` / `less_than(x)` | is `> x` / `< x` (false when it can't be compared) |
| `between(min, max)` / `range(min, max)` / `range(a..b)` | is within the bounds, inclusive (or within the Range) |
| `equals(x)` | equals `x` (same as writing `x`) |
| `not_equal(x)` | is not `x` |
| `one_of(*values)` | is one of `values` |
| `any(*values)` | is one of `values`; with no arguments, anything |
| `matches(regexp)` | matches the pattern |
| `satisfies { \|v\| ... }` | makes the block return truthy |

A predicate is not called when the attribute is missing or `nil`: the condition simply does not match. The helpers are also methods of the knowledge base, so `kb.query(:sensor, temp: kb.greater_than(90))` (or a bare `greater_than` inside the `KBS.knowledge_base` block) filters with them.

---

## Rule Lifecycle

### 1. Rule Creation

```ruby
# Via DSL (recommended)
kb = KBS.knowledge_base do
  rule "my_rule", priority: 10 do
    on :temperature, value: :temp?
    perform { |facts, b| puts b[:temp?] }
  end
end

# Or programmatically
rule = KBS::Rule.new(
  :my_rule,
  conditions: [KBS::Condition.new(:temperature, { value: :temp? })],
  action: ->(facts) { puts facts[0][:value] },
  priority: 10
)
```

---

### 2. Rule Registration

```ruby
engine.add_rule(rule)
# Internally:
# - Adds rule to @rules array
# - Compiles rule into RETE network
# - Creates alpha memories for condition patterns
# - Creates join nodes (or negation / exists nodes)
# - Creates production node for rule
# - Matches existing facts through new network, putting complete
#   matches on the agenda
```

With the DSL, `rule` does this for you on the knowledge base's engine.

---

### 3. Rule Activation

```ruby
engine.add_fact(:temperature, value: 85)
# Internally:
# - Fact activates matching alpha memories
# - Propagates through join nodes
# - Creates tokens in beta memories
# - Token reaches production node
# - An activation (rule + token) is put on engine.agenda (ready to fire)
```

Removing a fact before `run` takes back the activations it was part of.

---

### 4. Rule Firing

```ruby
engine.run
# Internally (KBS::Engine):
# - Pops the next activation from the agenda (highest priority first,
#   then by strategy)
# - Calls rule.fire(token.facts), which executes the action
# - Marks the token as fired (an activation fires once)
# - Facts the action adds/removes update the agenda before the next pop
# - Repeats until the agenda is empty, halt is called, or the limit is hit

# Internally (KBS::Blackboard::Engine):
# - Same as above, but:
#   - Logs rule firing to audit trail
#   - Records fact UUIDs and variable bindings
```

---

### 5. Rule Re-firing

Rules can fire multiple times:

```ruby
rule "log_temperature" do
  on :temperature, value: :temp?
  perform { |facts, b| puts "Temperature: #{b[:temp?]}" }
end

engine.add_fact(:temperature, value: 85)
engine.add_fact(:temperature, value: 90)
engine.add_fact(:temperature, value: 95)
engine.run

# Output:
# Temperature: 85
# Temperature: 90
# Temperature: 95
```

Each fact creates a separate activation (token) that fires independently.

---

## Rule Patterns

### 1. Simple Rule (One Condition)

Match single fact type:

```ruby
rule "log_all_temperatures" do
  on :temperature, value: :temp?
  perform do |facts, bindings|
    puts "Temperature: #{bindings[:temp?]}"
  end
end
```

---

### 2. Join Rule (Multiple Conditions)

Match multiple related facts:

```ruby
rule "sensor_temperature_alert" do
  on :sensor, id: :sensor_id?, status: "active"
  on :temperature, sensor_id: :sensor_id?, value: greater_than(80)
  perform do |facts, bindings|
    puts "Sensor #{bindings[:sensor_id?]} reports high temperature"
  end
end

# Matches when:
# - sensor fact with id=42, status="active" exists
# - temperature fact with sensor_id=42, value > 80 exists
```

**Variable Binding**: `:sensor_id?` in first condition must equal `sensor_id` in second condition (join test).

---

### 3. Guard Rule (Negation)

Match when fact is absent:

```ruby
rule "all_clear" do
  on :system, status: "running"
  without :alert, level: "critical"  # Fire when NO critical alerts exist
  perform do
    puts "All systems normal"
  end
end
```

---

### 4. State Machine Rule

Rules can implement state transitions:

```ruby
rule "pending_to_processing" do
  on :order, id: :order_id?, status: "pending"
  on :worker, status: "available", id: :worker_id?
  perform do |facts, bindings|
    order, worker = facts

    # Transition order to processing (re-matched, so this rule won't match it again)
    kb.modify(order, status: "processing", worker_id: bindings[:worker_id?])

    # Update worker
    kb.modify(worker, status: "busy")
  end
end
```

Use `modify`, not `fact[:status] = ...` or `Blackboard::Fact#update`: only `modify` makes the rules see the new values.

---

### 5. Cleanup Rule

Low-priority rules that clean up old facts:

```ruby
rule "expire_old_temperatures", priority: 0 do
  on :temperature, timestamp: less_than(Time.now - 3600)
  perform do |facts|
    kb.retract(facts.first)  # Remove old temperature reading
  end
end
```

`Time.now - 3600` is evaluated once, when the rule is defined, and the predicate is tested only when a fact is matched; see [Engine API: Memory Growth](engine.md#memory-growth).

---

### 6. Aggregation Rule

Collect multiple facts and compute aggregate:

```ruby
rule "daily_temperature_summary", priority: 5 do
  on :trigger, event: "end_of_day"
  perform do
    temps = kb.query(:temperature).map { |f| f[:value] }

    avg = temps.sum / temps.size.to_f
    max = temps.max
    min = temps.min

    kb.assert(:daily_summary, avg: avg, max: max, min: min, date: Date.today)
  end
end
```

---

### 7. Conflict Resolution Rule

Higher priority rule overrides lower priority:

```ruby
rule "high_risk_order", priority: 100 do
  on :order, id: :order_id?, total: greater_than(10000)
  perform do |facts, bindings|
    puts "HIGH RISK: Order #{bindings[:order_id?]} requires manual review"
    # This fires first due to priority
  end
end

rule "auto_approve_order", priority: 10 do
  on :order, id: :order_id?, status: "pending"
  perform do |facts, bindings|
    puts "Auto-approving order #{bindings[:order_id?]}"
    # This fires later (if at all)
  end
end
```

---

### 8. Recursive Rule

Rule that adds facts triggering other rules:

```ruby
rule "calculate_fibonacci" do
  on :fib_request, n: :n?
  without :fib_result, n: :n?  # Not already calculated
  perform do |facts, bindings|
    n = bindings[:n?]

    if n <= 1
      kb.assert(:fib_result, n: n, value: n)
    else
      # Request sub-problems
      kb.assert(:fib_request, n: n - 1)
      kb.assert(:fib_request, n: n - 2)

      # Wait for sub-results in another rule...
    end
  end
end

rule "combine_fibonacci" do
  on :fib_request, n: :n?
  on :fib_result, n: :n_minus_1?, value: :val1?
  on :fib_result, n: :n_minus_2?, value: :val2?
  # ... (complex join test: ?n_minus_1 == ?n - 1, etc.)
  perform do |facts, bindings|
    result = bindings[:val1?] + bindings[:val2?]
    kb.assert(:fib_result, n: bindings[:n?], value: result)
  end
end
```

---

## Best Practices

### 1. Descriptive Rule Names

```ruby
# Good
rule "high_temperature_alert"
rule "low_inventory_reorder"
rule "fraud_detection_suspicious_transaction"

# Bad
rule "rule1"
rule "temp"
rule "check"
```

---

### 2. Order Conditions by Selectivity

Most selective (fewest matching facts) first:

```ruby
# Good - sensor_id=42 filters to ~1 fact
rule "sensor_alert" do
  on :sensor, id: 42, status: :status?              # Very selective
  on :temperature, sensor_id: 42, value: :temp?     # Also selective
  perform { ... }
end

# Bad - :temperature matches many facts
rule "sensor_alert" do
  on :temperature, value: :temp?                    # Matches 1000s of facts
  on :sensor, id: 42, status: :status?              # Could have filtered first
  perform { ... }
end
```

**Why**: RETE builds network from first to last condition. Fewer intermediate tokens = faster.

---

### 3. Use Priority for Critical Rules

```ruby
rule "critical_shutdown", priority: 1000 do
  on :temperature, value: greater_than(120)
  perform { shutdown_system! }
end

rule "log_temperature", priority: 0 do
  on :temperature, value: :temp?
  perform { |facts, b| log(b[:temp?]) }
end
```

Critical safety rules should have high priority to fire before less important rules.

---

### 4. Keep Actions Idempotent

```ruby
# Good - Idempotent (safe to run multiple times)
rule "alert_high_temp" do
  on :temperature, value: greater_than(80)
  perform do |facts, bindings|
    # Check if alert already sent
    unless alert_sent?(bindings[:temp?])
      send_alert(bindings[:temp?])
      mark_alert_sent(bindings[:temp?])
    end
  end
end

# Bad - Not idempotent (sends duplicate alerts)
rule "alert_high_temp" do
  on :temperature, value: greater_than(80)
  perform do |facts, bindings|
    send_alert(bindings[:temp?])  # Sends every time rule fires
  end
end
```

---

### 5. Avoid Side Effects in Conditions

```ruby
# Bad - Side effect in condition predicate
counter = 0
rule "count_temps" do
  on :temperature, value: ->(v) { counter += 1; v > 80 }  # BAD!
  perform { puts "Count: #{counter}" }
end

# Good - Side effects in action only
counter = 0
rule "count_temps" do
  on :temperature, value: greater_than(80)
  perform { counter += 1; puts "Count: #{counter}" }
end
```

**Why**: Predicates run during pattern matching (potentially multiple times). Side effects cause unpredictable behavior.

---

### 6. Use Variable Bindings for Joins

```ruby
# Good - Variable binding creates join test
rule "order_inventory_check" do
  on :order, product_id: :pid?, quantity: :qty?
  on :inventory, product_id: :pid?, available: :available?
  perform do |facts, bindings|
    if bindings[:available?] < bindings[:qty?]
      puts "Insufficient inventory for product #{bindings[:pid?]}"
    end
  end
end

# Bad - No join test (matches all combinations)
rule "order_inventory_check" do
  on :order, product_id: :pid1?, quantity: :qty?
  on :inventory, product_id: :pid2?, available: :available?
  perform do |facts, bindings|
    # No guarantee pid1 == pid2!
    if bindings[:pid1?] == bindings[:pid2?]  # Manual check in action (inefficient)
      ...
    end
  end
end
```

---

### 7. Document Complex Rules

```ruby
# Good - Documented
rule "portfolio_rebalancing", priority: 50 do
  # Triggers when portfolio drift exceeds threshold
  # Conditions:
  # 1. Portfolio exists and is active
  # 2. Current allocation deviates > 5% from target
  # Action:
  # - Calculates rebalancing trades
  # - Creates pending orders

  on :portfolio, id: :portfolio_id?, status: "active"
  on :drift_calculation, portfolio_id: :portfolio_id?, drift: greater_than(0.05)
  perform do |facts, bindings|
    # Implementation...
  end
end
```

---

### 8. Test Rules in Isolation

```ruby
require 'minitest/autorun'

class TestHighTemperatureRule < Minitest::Test
  def setup
    @engine = KBS::Engine.new
    @fired = false

    @rule = KBS::Rule.new(:high_temp) do |r|
      r.conditions << KBS::Condition.new(:temperature, { value: ->(v) { v > 80 } })
      r.action = ->(facts) { @fired = true }
    end

    @engine.add_rule(@rule)
  end

  def test_fires_when_temperature_high
    @engine.add_fact(:temperature, value: 85)
    @engine.run
    assert @fired
  end

  def test_does_not_fire_when_temperature_low
    @engine.add_fact(:temperature, value: 75)
    @engine.run
    refute @fired
  end
end
```

---

### 9. Use Negation for Guards

```ruby
# Good - Negation ensures system ready
rule "start_processing" do
  on :work_item, status: "pending"
  without :system_error  # Don't process if system has errors
  perform { process_work_item }
end

# Alternative - Check in action (less efficient)
rule "start_processing" do
  on :work_item, status: "pending"
  perform do
    unless system_has_errors?
      process_work_item
    end
  end
end
```

**Why**: Negation in condition prevents token creation. Action-based check still creates token (wastes memory).

---

### 10. Limit Fact Growth

```ruby
# Good - Cleanup rule prevents unbounded growth
rule "expire_old_facts", priority: 0 do
  on :temperature, timestamp: less_than(Time.now - 3600)
  perform do |facts|
    kb.retract(facts.first)
  end
end

# Bad - No cleanup (memory leak)
loop do
  engine.add_fact(:temperature, value: rand(100), timestamp: Time.now)
  engine.run
  sleep 1
  # Facts accumulate forever!
end
```

---

## Common Patterns Reference

### Rule Priority Examples

```ruby
# Emergency shutdown
priority: 1000

# Critical alerts
priority: 500

# Business logic
priority: 100

# Data validation
priority: 50

# Standard processing
priority: 10

# Logging/auditing
priority: 5

# Cleanup
priority: 0
```

---

### Action Signatures

```ruby
# 0. No arguments
action: -> { puts "fired" }

# 1. Facts only
action: ->(facts) do
  temp_fact = facts[0]
  puts temp_fact[:value]
end

# 2. Facts and bindings (recommended)
action: ->(facts, bindings) do
  puts bindings[:temp?]
end

# 3. DSL style (cleanest)
perform do |facts, bindings|
  puts bindings[:temp?]
end
```

---

### Condition Patterns

```ruby
# Literal matching
on :temperature, location: "server_room"

# Range check
on :temperature, value: between(70, 90)
on :temperature, value: greater_than(80)
on :temperature, value: less_than(100)

# Variable binding
on :temperature, location: :loc?, value: :temp?

# Predicate
on :temperature, value: ->(v) { v > 80 && v < 100 }

# Negation
without :alert, level: "critical"

# Existence (matches once, however many operators are on duty)
exists :operator, on_duty: true

# Collection membership
on :order, status: one_of("pending", "processing", "completed")
```

---

## Performance Considerations

### Rule Compilation Cost

Adding a rule to the engine compiles it into the RETE network:

```ruby
# Cost: O(C) where C = number of conditions
engine.add_rule(rule)
```

**Optimization**: Add all rules before adding facts:

```ruby
# Good
rules.each { |r| engine.add_rule(r) }  # Compile all rules first
facts.each { |f| engine.add_fact(f.type, f.attributes) }  # Then add facts
engine.run

# Less optimal
facts.each do |f|
  engine.add_fact(f.type, f.attributes)
  rules.each { |r| engine.add_rule(r) }  # Recompiling for each fact!
  engine.run
end
```

---

### Condition Ordering

Order conditions from most to least selective:

```ruby
# Assume:
# - 10,000 temperature facts
# - 100 sensor facts
# - 10 sensors with id=42

# Good (selective first)
rule "alert" do
  on :sensor, id: 42, status: :status?        # Filters to 10 facts
  on :temperature, sensor_id: 42, value: :v?  # Then filters to ~100 facts
  # Creates ~10 intermediate tokens
end

# Bad (unselective first)
rule "alert" do
  on :temperature, value: :v?                 # Matches 10,000 facts!
  on :sensor, id: 42, status: :status?        # Then filters
  # Creates 10,000 intermediate tokens (slow, memory-intensive)
end
```

---

### Action Complexity

Keep actions fast:

```ruby
# Good - Fast action
perform do |facts, bindings|
  puts "Temperature: #{bindings[:temp?]}"
end

# Bad - Slow action blocks engine
perform do |facts, bindings|
  sleep 5  # Blocks engine for 5 seconds!
  send_email_alert(bindings[:temp?])  # Network I/O
end

# Better - Offload slow work
perform do |facts, bindings|
  # Post message for async worker
  engine.post_message("alert_system", "email_queue", bindings)
end
```

---

## Debugging Rules

### Why Didn't My Rule Fire?

```ruby
def debug_rule(engine, rule_name)
  rule = engine.rules.find { |r| r.name == rule_name }
  return "Rule not found" unless rule

  puts "Rule: #{rule.name}"
  puts "Conditions (#{rule.conditions.size}):"

  rule.conditions.each_with_index do |cond, i|
    matching_facts = engine.working_memory.facts.select { |f| f.matches?(cond.pattern.merge(type: cond.type)) }

    puts "  #{i + 1}. #{cond.summary}"
    puts "     Negated: #{cond.negated}  Exists: #{cond.exists}  Logical: #{cond.logical}"
    puts "     Matching facts: #{matching_facts.size}"

    if matching_facts.empty?
      puts "     ❌ NO MATCHING FACTS (rule can't fire)"
    else
      puts "     ✓ #{matching_facts.size} facts match"
      matching_facts.first(3).each do |f|
        puts "       - #{f}"
      end
    end
  end

  # Check production node
  prod_node = engine.production_nodes[rule.name]
  if prod_node
    puts "Production node matches: #{prod_node.tokens.size}"
    pending = engine.agenda.to_a.count { |activation| activation.rule.equal?(rule) }
    puts "Activations waiting on the agenda: #{pending}"
  else
    puts "Production node not found (rule not compiled?)"
  end
end

debug_rule(engine, "high_temperature")  # the name exactly as given (String for DSL rules)
```

---

## See Also

- [Engine API](engine.md) - Registering and running rules
- [Facts API](facts.md) - Understanding fact matching
- [DSL Guide](../guides/dsl.md) - Declarative rule syntax
- [Writing Rules Guide](../guides/writing-rules.md) - Best practices and patterns
- [Performance Guide](../advanced/performance.md) - Optimization strategies
- [Testing Guide](../advanced/testing.md) - Testing rules in isolation
