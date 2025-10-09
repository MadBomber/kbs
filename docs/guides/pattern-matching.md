# Pattern Matching

Deep dive into KBS pattern matching semantics. Learn how the RETE algorithm matches facts against condition patterns efficiently.

## Matching Fundamentals

Pattern matching determines whether a fact satisfies a condition. A match occurs when:

1. **Type matches** - Fact type equals condition type
2. **Attributes match** - All pattern constraints satisfied
3. **Predicate passes** - Custom predicate (if present) returns truthy

```ruby
# Condition pattern
KBS::Condition.new(:sensor, {
  id: "bedroom",
  temp: :?temp
})

# Matching fact
fact = { type: :sensor, id: "bedroom", temp: 28 }
# ✓ Type: :sensor == :sensor
# ✓ Attribute id: "bedroom" == "bedroom"
# ✓ Attribute temp: :?temp binds to 28
# MATCH!

# Non-matching fact
fact = { type: :sensor, id: "kitchen", temp: 28 }
# ✓ Type: :sensor == :sensor
# ✗ Attribute id: "kitchen" != "bedroom"
# NO MATCH
```

## Type Matching

Facts match only when types are identical:

```ruby
# Condition
KBS::Condition.new(:stock, {})

# Matches
engine.add_fact(:stock, { symbol: "AAPL" })  # ✓

# Does not match
engine.add_fact(:stocks, { symbol: "AAPL" })  # ✗ (:stocks != :stock)
engine.add_fact("stock", { symbol: "AAPL" })  # ✗ (String != Symbol)
```

**Type comparison uses `==`**, so symbols and strings never match.

## Literal Value Matching

### Exact Equality

```ruby
# Match exact value
KBS::Condition.new(:sensor, { id: "bedroom" })

# Matches
{ type: :sensor, id: "bedroom" }  # ✓

# Does not match
{ type: :sensor, id: "kitchen" }   # ✗
{ type: :sensor, id: :bedroom }     # ✗ (Symbol != String)
```

### Multiple Literals

```ruby
# All must match
KBS::Condition.new(:stock, {
  symbol: "AAPL",
  exchange: "NASDAQ"
})

# Matches
{ type: :stock, symbol: "AAPL", exchange: "NASDAQ" }  # ✓

# Does not match
{ type: :stock, symbol: "AAPL", exchange: "NYSE" }    # ✗
{ type: :stock, symbol: "GOOGL", exchange: "NASDAQ" } # ✗
```

### Nil Values

```ruby
# Match nil explicitly
KBS::Condition.new(:sensor, { error: nil })

# Matches
{ type: :sensor, error: nil }  # ✓

# Does not match
{ type: :sensor }  # ✗ (missing key != nil)
{ type: :sensor, error: false }  # ✗ (false != nil)
```

## Variable Binding

### Basic Binding

Variables start with `?` and bind to fact attribute values:

```ruby
# Condition with variable
KBS::Condition.new(:sensor, { temp: :?t })

# Matching fact
fact = { type: :sensor, temp: 28 }

# After matching:
bindings = { :?t => 28 }
```

### Multiple Bindings

```ruby
KBS::Condition.new(:stock, {
  symbol: :?sym,
  price: :?p,
  volume: :?v
})

# Fact
{ type: :stock, symbol: "AAPL", price: 150, volume: 1000 }

# Bindings
{
  :?sym => "AAPL",
  :?p => 150,
  :?v => 1000
}
```

### Mixed Literals and Variables

```ruby
KBS::Condition.new(:sensor, {
  id: "bedroom",     # Literal (must equal "bedroom")
  temp: :?temp       # Variable (binds to any value)
})

# Matches only bedroom sensor, binds temp
{ type: :sensor, id: "bedroom", temp: 28 }  # ✓ binds :?temp => 28
{ type: :sensor, id: "kitchen", temp: 28 }  # ✗ id doesn't match
```

## Cross-Condition Binding

Variables create join constraints across conditions:

```ruby
r.conditions = [
  # Condition 1: Binds :?sym
  KBS::Condition.new(:stock, { symbol: :?sym, price: :?price }),

  # Condition 2: Tests :?sym (must be same value)
  KBS::Condition.new(:watchlist, { symbol: :?sym })
]

# Facts
stock1 = { type: :stock, symbol: "AAPL", price: 150 }
stock2 = { type: :stock, symbol: "GOOGL", price: 2800 }
watchlist = { type: :watchlist, symbol: "AAPL" }

# Matches
# stock1 + watchlist: ✓ (:?sym = "AAPL" in both)

# Does not match
# stock2 + watchlist: ✗ (:?sym = "GOOGL" in stock, "AAPL" in watchlist)
```

### Binding Semantics

1. **First occurrence binds** - Variable's first use establishes the value
2. **Subsequent uses test** - Later uses check equality
3. **Scope is per-rule** - Variables don't cross rules

```ruby
r.conditions = [
  KBS::Condition.new(:a, { x: :?v }),  # Binds :?v
  KBS::Condition.new(:b, { y: :?v }),  # Tests :?v (must equal)
  KBS::Condition.new(:c, { z: :?v })   # Tests :?v (must equal)
]

# All three facts must have same value for x, y, z
```

## Empty Patterns

### Match Any

Empty pattern `{}` matches all facts of that type:

```ruby
# Matches ALL sensor facts
KBS::Condition.new(:sensor, {})

# Matches these
{ type: :sensor, id: "bedroom", temp: 28 }
{ type: :sensor, id: "kitchen", temp: 22 }
{ type: :sensor, foo: "bar", baz: 123 }
```

### Selectivity Warning

Empty patterns have minimal selectivity:

```ruby
# Bad: Very unselective (matches thousands)
r.conditions = [
  KBS::Condition.new(:log_entry, {}),     # Matches 10,000 facts
  KBS::Condition.new(:error, { id: 1 })   # Matches 1 fact
]
# Creates 10,000 partial matches!

# Good: Specific first
r.conditions = [
  KBS::Condition.new(:error, { id: 1 }),    # Matches 1 fact
  KBS::Condition.new(:log_entry, {})        # Joins with 10,000
]
# Creates 1 partial match
```

## Custom Predicates

Predicates add complex matching beyond equality:

### Basic Predicate

```ruby
KBS::Condition.new(:stock, { price: :?price },
  predicate: lambda { |fact|
    fact[:price] > 100
  }
)

# Matches
{ type: :stock, price: 150 }  # ✓ (150 > 100)

# Does not match
{ type: :stock, price: 50 }   # ✗ (50 <= 100)
```

### Predicate Execution Order

1. Type check
2. Attribute equality checks
3. Variable binding
4. **Predicate evaluation** (last)

```ruby
KBS::Condition.new(:sensor, { id: "bedroom", temp: :?temp },
  predicate: lambda { |fact|
    fact[:temp].between?(20, 30)
  }
)

# Evaluation order:
# 1. type == :sensor? ✓
# 2. id == "bedroom"? ✓
# 3. temp exists? ✓ → bind :?temp
# 4. predicate(fact)? ✓
# MATCH!
```

### Predicate Limitations

**Predicates disable network sharing:**

```ruby
# Rule 1
KBS::Condition.new(:stock, {},
  predicate: lambda { |f| f[:price] > 100 }
)

# Rule 2 (different predicate)
KBS::Condition.new(:stock, {},
  predicate: lambda { |f| f[:price] < 50 }
)

# These create SEPARATE alpha memories
# Cannot share pattern matching computation
```

**Use pattern matching when possible:**

```ruby
# Bad: Predicate for simple equality
KBS::Condition.new(:stock, {},
  predicate: lambda { |f| f[:symbol] == "AAPL" }
)

# Good: Pattern matching
KBS::Condition.new(:stock, { symbol: "AAPL" })
```

## Matching Strategies

### Conjunctive Matching (AND)

All conditions must match:

```ruby
r.conditions = [
  KBS::Condition.new(:a, {}),
  KBS::Condition.new(:b, {}),
  KBS::Condition.new(:c, {})
]

# Rule fires when:
# a_fact exists AND b_fact exists AND c_fact exists
```

### Disjunctive Matching (OR)

Use multiple rules:

```ruby
# Fire when A OR B
rule1 = KBS::Rule.new("fire_on_a") do |r|
  r.conditions = [KBS::Condition.new(:a, {})]
  r.action = lambda { |f, b| common_action }
end

rule2 = KBS::Rule.new("fire_on_b") do |r|
  r.conditions = [KBS::Condition.new(:b, {})]
  r.action = lambda { |f, b| common_action }
end
```

Or use predicates:

```ruby
KBS::Condition.new(:event, {},
  predicate: lambda { |f|
    f[:type] == "a" || f[:type] == "b"
  }
)
```

### Negation (NOT)

Match when pattern is absent:

```ruby
r.conditions = [
  KBS::Condition.new(:a, {}),
  KBS::Condition.new(:b, {}, negated: true)  # NOT B
]

# Fires when: a_fact exists AND no b_fact exists
```

See [Negation Guide](negation.md) for details.

## Pattern Matching Examples

### Range Checks

```ruby
# Temperature in range 20-30
KBS::Condition.new(:sensor, { temp: :?temp },
  predicate: lambda { |f|
    f[:temp].between?(20, 30)
  }
)
```

### String Matching

```ruby
# Symbol starts with "TECH"
KBS::Condition.new(:stock, { symbol: :?sym },
  predicate: lambda { |f|
    f[:symbol].start_with?("TECH")
  }
)

# Regex match
KBS::Condition.new(:log, { message: :?msg },
  predicate: lambda { |f|
    f[:message] =~ /ERROR|FATAL/
  }
)
```

### Collection Membership

```ruby
# Status is one of pending, processing, approved
KBS::Condition.new(:order, { status: :?status },
  predicate: lambda { |f|
    %w[pending processing approved].include?(f[:status])
  }
)
```

### Temporal Conditions

```ruby
# Reading older than 5 minutes
KBS::Condition.new(:sensor, { timestamp: :?time },
  predicate: lambda { |f|
    (Time.now - f[:timestamp]) > 300
  }
)
```

### Computed Values

```ruby
# Price changed more than 10%
KBS::Condition.new(:stock, {
  symbol: :?sym,
  current_price: :?curr,
  previous_price: :?prev
}, predicate: lambda { |f|
  change = ((f[:current_price] - f[:previous_price]).abs / f[:previous_price].to_f)
  change > 0.10
})
```

### Nested Attribute Access

```ruby
# Access nested hash
KBS::Condition.new(:event, { data: :?data },
  predicate: lambda { |f|
    f[:data].is_a?(Hash) &&
    f[:data][:severity] == "critical"
  }
)
```

## Performance Implications

### Alpha Network

Facts are tested against patterns in alpha memory:

```ruby
# Pattern
{ type: :stock, symbol: "AAPL" }

# 10,000 facts tested
# Only matching facts stored in alpha memory
# O(N) where N = total facts
```

### Join Network

Partial matches combine in beta network:

```ruby
r.conditions = [
  KBS::Condition.new(:a, {}),  # 100 matches
  KBS::Condition.new(:b, {})   # 200 matches
]

# Worst case: 100 × 200 = 20,000 join tests
# Actual: Usually much fewer (variable bindings reduce combinations)
```

### Optimization Strategies

**1. Specific patterns first:**

```ruby
# Good
r.conditions = [
  KBS::Condition.new(:critical, {}),  # 1 match
  KBS::Condition.new(:sensor, {})     # 1000 matches
]
# Beta memory size: 1

# Bad
r.conditions = [
  KBS::Condition.new(:sensor, {}),     # 1000 matches
  KBS::Condition.new(:critical, {})    # 1 match
]
# Beta memory size: 1000
```

**2. Use literals over predicates:**

```ruby
# Good: O(1) hash lookup
KBS::Condition.new(:stock, { exchange: "NASDAQ" })

# Bad: O(N) linear scan
KBS::Condition.new(:stock, {},
  predicate: lambda { |f| f[:exchange] == "NASDAQ" }
)
```

**3. Minimize empty patterns:**

```ruby
# Expensive
KBS::Condition.new(:log_entry, {})  # Matches everything

# Better
KBS::Condition.new(:log_entry, { level: "ERROR" })  # More selective
```

## Debugging Patterns

### Trace Matching

```ruby
class DebugCondition < KBS::Condition
  def matches?(fact)
    result = super
    puts "#{pattern} vs #{fact.attributes}: #{result}"
    result
  end
end

# Use for debugging
r.conditions = [
  DebugCondition.new(:sensor, { id: "bedroom" })
]
```

### Inspect Alpha Memories

```ruby
engine.alpha_memories.each do |pattern, memory|
  puts "Pattern: #{pattern}"
  puts "  Matches: #{memory.items.size}"
  memory.items.each do |fact|
    puts "    #{fact.attributes}"
  end
end
```

### Test Patterns in Isolation

```ruby
condition = KBS::Condition.new(:sensor, { temp: :?t },
  predicate: lambda { |f| f[:temp] > 30 }
)

fact = KBS::Fact.new(:sensor, { temp: 35 })

# Manually test
condition.matches?(fact)  # => true
```

## Next Steps

- **[Variable Binding](variable-binding.md)** - Join tests and binding extraction
- **[Negation](negation.md)** - Negated condition behavior
- **[RETE Algorithm](../architecture/rete-algorithm.md)** - How matching works internally
- **[Performance Guide](../advanced/performance.md)** - Optimization techniques

---

*Pattern matching is the heart of the RETE algorithm. Efficient patterns = fast rule systems.*
