# Pattern Matching

Deep dive into KBS pattern matching semantics. Learn how the RETE algorithm matches facts against condition patterns efficiently.

## Matching Fundamentals

Pattern matching determines whether a fact satisfies a condition. A match occurs when:

1. **Type matches** - Fact type equals condition type
2. **Attributes match** - Every pattern value is satisfied: a literal must be equal, a `?variable` accepts any value, and a predicate (a lambda) must return truthy
3. **Join tests pass** - A variable already bound by an earlier condition must have the same value

```ruby
# Condition pattern
KBS::Condition.new(:sensor, {
  id: "bedroom",
  temp: :temp?
})

# Matching fact
fact = { type: :sensor, id: "bedroom", temp: 28 }
# ✓ Type: :sensor == :sensor
# ✓ Attribute id: "bedroom" == "bedroom"
# ✓ Attribute temp: :temp? binds to 28
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
{ type: :sensor }              # ✓ (a missing key reads as nil)

# Does not match
{ type: :sensor, error: false }  # ✗ (false != nil)
```

## Variable Binding

### Basic Binding

Variables end with `?` and bind to fact attribute values:

```ruby
# Condition with variable
KBS::Condition.new(:sensor, { temp: :t? })

# Matching fact
fact = { type: :sensor, temp: 28 }

# After matching:
bindings = { :t? => 28 }
```

A variable accepts any value, so it also matches a fact that lacks the attribute; the variable is then bound to `nil`.

### Multiple Bindings

```ruby
KBS::Condition.new(:stock, {
  symbol: :sym?,
  price: :p?,
  volume: :v?
})

# Fact
{ type: :stock, symbol: "AAPL", price: 150, volume: 1000 }

# Bindings
{
  :sym? => "AAPL",
  :p? => 150,
  :v? => 1000
}
```

### Mixed Literals and Variables

```ruby
KBS::Condition.new(:sensor, {
  id: "bedroom",     # Literal (must equal "bedroom")
  temp: :temp?       # Variable (binds to any value)
})

# Matches only bedroom sensor, binds temp
{ type: :sensor, id: "bedroom", temp: 28 }  # ✓ binds :temp? => 28
{ type: :sensor, id: "kitchen", temp: 28 }  # ✗ id doesn't match
```

## Cross-Condition Binding

Variables create join constraints across conditions:

```ruby
r.conditions = [
  # Condition 1: Binds :sym?
  KBS::Condition.new(:stock, { symbol: :sym?, price: :price? }),

  # Condition 2: Tests :sym? (must be same value)
  KBS::Condition.new(:watchlist, { symbol: :sym? })
]

# Facts
stock1 = { type: :stock, symbol: "AAPL", price: 150 }
stock2 = { type: :stock, symbol: "GOOGL", price: 2800 }
watchlist = { type: :watchlist, symbol: "AAPL" }

# Matches
# stock1 + watchlist: ✓ (:sym? = "AAPL" in both)

# Does not match
# stock2 + watchlist: ✗ (:sym? = "GOOGL" in stock, "AAPL" in watchlist)
```

### Binding Semantics

1. **First occurrence binds** - Variable's first use establishes the value
2. **Subsequent uses test** - Later uses check equality
3. **Scope is per-rule** - Variables don't cross rules

```ruby
r.conditions = [
  KBS::Condition.new(:a, { x: :v? }),  # Binds :v?
  KBS::Condition.new(:b, { y: :v? }),  # Tests :v? (must equal)
  KBS::Condition.new(:c, { z: :v? })   # Tests :v? (must equal)
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

Predicates add complex matching beyond equality. A predicate is a lambda given as the value of the attribute it tests; there is no separate `predicate:` option. The lambda is called with that attribute's value:

### Basic Predicate

```ruby
KBS::Condition.new(:stock, { price: ->(price) { price > 100 } })

# Matches
{ type: :stock, price: 150 }  # ✓ (150 > 100)

# Does not match
{ type: :stock, price: 50 }   # ✗ (50 <= 100)
{ type: :stock }              # ✗ (a predicate is not called for a nil value)
```

In the DSL, helpers such as `greater_than(100)`, `between(20, 30)` and `one_of(...)` build these lambdas for you.

### Predicate Evaluation

A fact is checked against each entry of the pattern:

1. Type check
2. Each attribute: literal equality, `?variable` (always passes), or predicate call
3. Join tests on variables bound by earlier conditions (in the beta network)

```ruby
KBS::Condition.new(:sensor, { id: "bedroom", temp: ->(t) { t.between?(20, 30) } })

# Evaluation:
# 1. type == :sensor? ✓
# 2. id == "bedroom"? ✓
# 3. temp.between?(20, 30)? ✓
# MATCH!
```

A predicate sees one attribute value and runs when the fact is added (or modified), not again later.

### Predicate Limitations

**Predicates limit network sharing:**

```ruby
# Rule 1
KBS::Condition.new(:stock, { price: ->(p) { p > 100 } })

# Rule 2 (different predicate)
KBS::Condition.new(:stock, { price: ->(p) { p < 50 } })

# These create SEPARATE alpha memories
# Cannot share pattern matching computation
```

Alpha memories are keyed by pattern, and two lambda objects are never equal, so even identical-looking predicates in two rules get two memories. Reuse the same lambda object to share one.

**Use pattern matching when possible:**

```ruby
# Bad: Predicate for simple equality
KBS::Condition.new(:stock, { symbol: ->(s) { s == "AAPL" } })

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
KBS::Condition.new(:event, { kind: ->(k) { k == "a" || k == "b" } })
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
KBS::Condition.new(:sensor, { temp: ->(t) { t.between?(20, 30) } })
```

### String Matching

```ruby
# Symbol starts with "TECH"
KBS::Condition.new(:stock, { symbol: ->(sym) { sym.start_with?("TECH") } })

# Regex match
KBS::Condition.new(:log, { message: ->(msg) { msg =~ /ERROR|FATAL/ } })
```

### Collection Membership

```ruby
# Status is one of pending, processing, approved
KBS::Condition.new(:order, {
  status: ->(status) { %w[pending processing approved].include?(status) }
})
```

### Temporal Conditions

```ruby
# Reading older than 5 minutes
KBS::Condition.new(:sensor, { timestamp: ->(time) { (Time.now - time) > 300 } })
```

The predicate is evaluated when the fact is added. A reading that is fresh then does not start matching five minutes later; `modify` the fact or assert a clock fact to have it checked again.

### Computed Values

A predicate sees only its own attribute, so a test that needs several attributes of the same fact works best on a value computed when the fact is added:

```ruby
# Price changed more than 10%
change = (current_price - previous_price).abs / previous_price.to_f
engine.add_fact(:stock, symbol: "AAPL", current_price: current_price,
                        previous_price: previous_price, change: change)

KBS::Condition.new(:stock, { symbol: :sym?, change: ->(c) { c > 0.10 } })
```

### Nested Attribute Access

```ruby
# Access nested hash
KBS::Condition.new(:event, {
  data: ->(data) { data.is_a?(Hash) && data[:severity] == "critical" }
})
```

## Performance Implications

### Alpha Network

Facts are tested against patterns in alpha memory:

```ruby
# Pattern
{ type: :stock, symbol: "AAPL" }

# Alpha memories are grouped by fact type, and a pattern with a
# literal is filed under its first literal (symbol: "AAPL"), so a
# new fact reaches it with one hash lookup on its own value.
# Only matching facts are stored in alpha memory.
```

### Join Network

Partial matches combine in beta network:

```ruby
r.conditions = [
  KBS::Condition.new(:a, {}),  # 100 matches
  KBS::Condition.new(:b, {})   # 200 matches
]

# No shared variables: 100 × 200 = 20,000 combinations
# With a shared ?variable, join memories are hash-indexed on it,
# so each token only meets the facts with the same value
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

# Bad: predicate called for every :stock fact
KBS::Condition.new(:stock, { exchange: ->(e) { e == "NASDAQ" } })
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

`Fact#matches?` takes a pattern hash (the condition's pattern plus its `:type`) and tells you whether a fact fits:

```ruby
pattern = { type: :sensor, id: "bedroom" }

engine.facts.map { |fact| [fact.attributes, fact.matches?(pattern)] }
# => [[{id: "bedroom", temp: 28}, true], [{id: "kitchen", temp: 22}, false]]
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
condition = KBS::Condition.new(:sensor, { temp: ->(t) { t > 30 } })

fact = KBS::Fact.new(:sensor, { temp: 35 })

# Manually test
fact.matches?(condition.pattern.merge(type: condition.type))  # => true
```

## Next Steps

- **[Variable Binding](variable-binding.md)** - Join tests and binding extraction
- **[Negation](negation.md)** - Negated condition behavior
- **[RETE Algorithm](../architecture/rete-algorithm.md)** - How matching works internally
- **[Performance Guide](../advanced/performance.md)** - Optimization techniques

---

*Pattern matching is the heart of the RETE algorithm. Efficient patterns = fast rule systems.*
