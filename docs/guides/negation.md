# Negation

Negated conditions match when a pattern is **absent** from working memory. This guide explains negation semantics, use cases, performance implications, and common pitfalls.

## Negation Basics

### Syntax

```ruby
KBS::Condition.new(:alert, { sensor_id: :id? }, negated: true)
```

**Semantics**: Condition satisfied when NO fact matches the pattern.

### Simple Example

```ruby
KBS::Rule.new("send_first_alert") do |r|
  r.conditions = [
    # Positive: High temperature detected
    KBS::Condition.new(:high_temp, { sensor_id: :id? }),

    # Negative: No alert sent yet
    KBS::Condition.new(:alert_sent, { sensor_id: :id? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    send_alert(bindings[:id?])
    engine.add_fact(:alert_sent, { sensor_id: bindings[:id?] })
  end
end
```

**Behavior**:
- First run: `:high_temp` exists, `:alert_sent` doesn't → rule fires
- Second run: Both `:high_temp` and `:alert_sent` exist → rule doesn't fire

## Negation Semantics

### Open World Assumption

Negation means "**no matching fact exists**", not "fact is explicitly false":

```ruby
# Negated condition
KBS::Condition.new(:error, { id: :id? }, negated: true)

# Matches when:
# - No :error fact exists with that id
# - Working memory is empty
# - :error facts exist but with different ids

# Does NOT match when:
# - Any :error fact with matching id exists
```

### Variable Binding in Negation

Variables in negated conditions still create join constraints:

```ruby
r.conditions = [
  KBS::Condition.new(:sensor, { id: :id?, temp: :temp? }),
  KBS::Condition.new(:alert, { sensor_id: :id? }, negated: true)
]

# For each sensor fact:
#   Check if NO alert exists with sensor_id == sensor's id
#   If no such alert: rule fires
```

### Negation Node Behavior

```
1. Token arrives with bindings { :id? => "bedroom" }
2. Check alpha memory for :alert facts
3. Filter for matches where sensor_id == "bedroom"
4. If count == 0: propagate token (condition satisfied)
5. If count > 0: block token (condition not satisfied)
```

## Use Cases

### 1. Guard Conditions

Prevent duplicate actions:

```ruby
KBS::Rule.new("process_order") do |r|
  r.conditions = [
    KBS::Condition.new(:order, { id: :id?, status: "pending" }),
    KBS::Condition.new(:processing, { order_id: :id? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    # Only process if not already processing
    engine.add_fact(:processing, { order_id: bindings[:id?] })
    process_order(bindings[:id?])
  end
end
```

### 2. Missing Information Detection

Alert when expected data is absent:

```ruby
KBS::Rule.new("missing_threshold") do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { id: :id? }),
    KBS::Condition.new(:threshold, { sensor_id: :id? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    alert("Sensor #{bindings[:id?]} has no threshold configured!")
  end
end
```

### 3. State Transitions

Ensure prerequisites before transitioning:

```ruby
KBS::Rule.new("activate_account") do |r|
  r.conditions = [
    KBS::Condition.new(:user, { id: :id?, email_verified: true }),
    KBS::Condition.new(:account_active, { user_id: :id? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    engine.add_fact(:account_active, { user_id: bindings[:id?] })
  end
end
```

### 4. Timeout Detection

Fire when response hasn't arrived:

```ruby
KBS::Rule.new("timeout_alert") do |r|
  r.conditions = [
    KBS::Condition.new(:request, {
      id: :req_id?,
      created_at: :created?
    }, predicate: lambda { |f|
      (Time.now - f[:created_at]) > 300  # 5 minutes
    }),

    KBS::Condition.new(:response, { request_id: :req_id? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    alert("Request #{bindings[:req_id?]} timed out!")
  end
end
```

### 5. Mutual Exclusion

Ensure only one option selected:

```ruby
KBS::Rule.new("select_default") do |r|
  r.conditions = [
    KBS::Condition.new(:user, { id: :id? }),
    KBS::Condition.new(:preference, { user_id: :id?, theme: :theme? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    # No preference set → use default
    engine.add_fact(:preference, { user_id: bindings[:id?], theme: "light" })
  end
end
```

## Multiple Negations

### Conjunction (AND)

All negations must be satisfied:

```ruby
r.conditions = [
  KBS::Condition.new(:a, {}),
  KBS::Condition.new(:b, {}, negated: true),
  KBS::Condition.new(:c, {}, negated: true)
]

# Fires when: a exists AND b doesn't exist AND c doesn't exist
```

### Complex Negation

```ruby
KBS::Rule.new("unique_error") do |r|
  r.conditions = [
    KBS::Condition.new(:error, { type: :type? }),
    KBS::Condition.new(:error_handled, { type: :type? }, negated: true),
    KBS::Condition.new(:error_ignored, { type: :type? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    # Error exists but neither handled nor ignored
    handle_new_error(bindings[:type?])
  end
end
```

## Performance Implications

### Negation is Expensive

**Reason**: Must check alpha memory on every token arrival.

```ruby
# Expensive: Large alpha memory to search
KBS::Condition.new(:log_entry, {}, negated: true)
# Must check all log_entry facts for each token

# Better: Specific pattern
KBS::Condition.new(:error_log, { severity: "critical" }, negated: true)
# Smaller alpha memory, fewer checks
```

### Negation Node Overhead

```ruby
class NegationNode
  def left_activate(token)
    # For EVERY token:
    matching_facts = @alpha_memory.items.select { |fact|
      perform_join_tests(token, fact)
    }

    if matching_facts.empty?
      propagate(token)  # No matches = condition satisfied
    else
      block(token)      # Matches exist = condition not satisfied
      track_inhibitors(token, matching_facts)
    end
  end
end
```

**Cost**: O(A × T) where A = alpha memory size, T = join test cost

### Optimization Strategies

**1. Order negations last:**

```ruby
# Good: Positive conditions first
r.conditions = [
  KBS::Condition.new(:a, {}),
  KBS::Condition.new(:b, {}),
  KBS::Condition.new(:c, {}, negated: true)  # Last
]

# Bad: Negation first
r.conditions = [
  KBS::Condition.new(:c, {}, negated: true),  # First
  KBS::Condition.new(:a, {}),
  KBS::Condition.new(:b, {})
]
```

**2. Minimize negations:**

```ruby
# Bad: Multiple negations
r.conditions = [
  KBS::Condition.new(:foo, {}, negated: true),
  KBS::Condition.new(:bar, {}, negated: true),
  KBS::Condition.new(:baz, {}, negated: true)
]

# Better: Single positive condition
# Add fact when conditions met:
unless foo_exists? || bar_exists? || baz_exists?
  engine.add_fact(:conditions_clear, {})
end

r.conditions = [
  KBS::Condition.new(:conditions_clear, {})
]
```

**3. Use specific patterns:**

```ruby
# Expensive
KBS::Condition.new(:event, {}, negated: true)

# Cheaper
KBS::Condition.new(:event, { type: "error", severity: "critical" }, negated: true)
```

## Common Pitfalls

### 1. Forgetting Variable Binding

```ruby
# Bad: Variables don't connect
r.conditions = [
  KBS::Condition.new(:sensor, { id: :id1? }),
  KBS::Condition.new(:alert, { id: :id2? }, negated: true)  # Different variable!
]

# Good: Consistent variables
r.conditions = [
  KBS::Condition.new(:sensor, { id: :id? }),
  KBS::Condition.new(:alert, { sensor_id: :id? }, negated: true)  # Same :id?
]
```

### 2. Infinite Loops

```ruby
# Bad: Rule fires forever
KBS::Rule.new("infinite_loop") do |r|
  r.conditions = [
    KBS::Condition.new(:start, {}),
    KBS::Condition.new(:done, {}, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    # Never adds :done fact!
    do_something()
  end
end

# Good: Add termination fact
KBS::Rule.new("runs_once") do |r|
  r.conditions = [
    KBS::Condition.new(:start, {}),
    KBS::Condition.new(:done, {}, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    do_something()
    engine.add_fact(:done, {})  # Prevents re-firing
  end
end
```

### 3. Negation of Missing Attributes

```ruby
# Doesn't work as expected
KBS::Condition.new(:sensor, { error: nil }, negated: true)

# Better: Check for absence of error fact
KBS::Condition.new(:sensor, { id: :id? }),
KBS::Condition.new(:sensor_error, { sensor_id: :id? }, negated: true)
```

### 4. Over-Using Negation

```ruby
# Bad: Many negations
KBS::Rule.new("many_negations") do |r|
  r.conditions = [
    KBS::Condition.new(:a, {}, negated: true),
    KBS::Condition.new(:b, {}, negated: true),
    KBS::Condition.new(:c, {}, negated: true),
    KBS::Condition.new(:d, {}, negated: true)
  ]
  # Expensive! Checks 4 alpha memories per token
end

# Good: Refactor to positive logic
# Add a single fact representing "all clear" state
```

## Negation Patterns

### Default Values

```ruby
# If no preference, use default
KBS::Rule.new("set_default_theme") do |r|
  r.conditions = [
    KBS::Condition.new(:user, { id: :id? }),
    KBS::Condition.new(:theme_preference, { user_id: :id? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    engine.add_fact(:theme_preference, { user_id: bindings[:id?], theme: "dark" })
  end
end
```

### Cleanup Rules

```ruby
# Remove orphaned records
KBS::Rule.new("cleanup_orphaned_comments") do |r|
  r.conditions = [
    KBS::Condition.new(:comment, { post_id: :pid? }),
    KBS::Condition.new(:post, { id: :pid? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    comment = facts[0]
    engine.remove_fact(comment)
  end
end
```

### Prerequisite Checking

```ruby
# Ensure all prerequisites met
KBS::Rule.new("deploy_application") do |r|
  r.conditions = [
    KBS::Condition.new(:deploy_requested, {}),
    KBS::Condition.new(:tests_passed, {}),
    KBS::Condition.new(:build_succeeded, {}),
    KBS::Condition.new(:deployment_blocked, {}, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    deploy()
  end
end
```

## Debugging Negations

### Trace Negation Checks

```ruby
class DebugNegationNode < KBS::NegationNode
  def left_activate(token)
    matches = @alpha_memory.items.select { |f| perform_join_tests(token, f) }
    puts "Negation check:"
    puts "  Pattern: #{@alpha_memory.pattern}"
    puts "  Token: #{token.inspect}"
    puts "  Matching facts: #{matches.size}"
    puts "  Result: #{matches.empty? ? 'PASS' : 'BLOCK'}"
    super
  end
end
```

### Count Inhibitors

```ruby
# Check how many facts are blocking tokens
engine.production_nodes.each do |name, node|
  # Find negation nodes in network
  # Count tokens blocked by each
end
```

### Validate Negation Logic

```ruby
# Test: Rule should fire when condition absent
engine.add_fact(:trigger, {})
engine.run
assert rule_fired, "Should fire when negated condition absent"

# Test: Rule should NOT fire when condition present
engine.add_fact(:blocker, {})
engine.run
refute rule_fired, "Should not fire when negated condition present"
```

## Alternatives to Negation

Sometimes positive logic is clearer and faster:

### Pattern: Explicit State

```ruby
# Instead of:
KBS::Condition.new(:processing, { id: :id? }, negated: true)

# Use explicit state:
KBS::Condition.new(:status, { id: :id?, value: "idle" })
```

### Pattern: Status Flags

```ruby
# Instead of:
KBS::Condition.new(:error, {}, negated: true)

# Use status flag:
KBS::Condition.new(:system_status, { healthy: true })
```

### Pattern: Computed Facts

```ruby
# Instead of checking absence in rule:
KBS::Condition.new(:response, { req_id: :id? }, negated: true)

# Add a fact when timeout occurs:
KBS::Rule.new("detect_timeout") do |r|
  r.conditions = [
    KBS::Condition.new(:request, {
      id: :id?,
      created_at: :time?
    }, predicate: lambda { |f| (Time.now - f[:created_at]) > 300 })
  ]

  r.action = lambda do |facts, bindings|
    engine.add_fact(:timeout, { request_id: bindings[:id?] })
  end
end

# Then use positive check:
KBS::Condition.new(:timeout, { request_id: :id? })
```

## Next Steps

- **[Pattern Matching](pattern-matching.md)** - How negation fits with pattern matching
- **[Variable Binding](variable-binding.md)** - Variables in negated conditions
- **[Network Structure](../architecture/network-structure.md)** - Negation node implementation
- **[Performance Guide](../advanced/performance.md)** - Optimizing negation performance

---

*Negation is powerful but expensive. Use sparingly and order last for best performance.*
