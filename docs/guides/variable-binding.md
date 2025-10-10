# Variable Binding

Variables connect facts across conditions, enabling join constraints in the RETE network. This guide explains how binding works, join tests, and optimization strategies.

## Variable Syntax

Variables start with `?` and are symbols:

```ruby
:temp?      # Variable named "temp"
:sensor_id? # Variable named "sensor_id"
:x?         # Variable named "x"
```

**Naming conventions:**
- Use lowercase with underscores
- Be descriptive
- Match domain terminology

## Basic Binding

### Single Variable

```ruby
KBS::Condition.new(:sensor, { temp: :t? })

# Matches fact:
{ type: :sensor, temp: 28 }

# Creates binding:
{ :t? => 28 }
```

### Multiple Variables

```ruby
KBS::Condition.new(:stock, {
  symbol: :sym?,
  price: :price?,
  volume: :vol?
})

# Matches:
{ type: :stock, symbol: "AAPL", price: 150, volume: 1000 }

# Bindings:
{
  :sym? => "AAPL",
  :price? => 150,
  :vol? => 1000
}
```

## Cross-Condition Binding

### Join Constraints

Variables with the same name create equality constraints:

```ruby
r.conditions = [
  # Condition 1: Binds :id? to sensor's id
  KBS::Condition.new(:sensor, { id: :id?, temp: :temp? }),

  # Condition 2: Must match same :id?
  KBS::Condition.new(:threshold, { sensor_id: :id?, max: :max? })
]
```

**Join test:**
```
sensor[:id] == threshold[:sensor_id]
```

### Multiple Joins

```ruby
r.conditions = [
  KBS::Condition.new(:a, { x: :v1?, y: :v2? }),
  KBS::Condition.new(:b, { p: :v1?, q: :v3? }),
  KBS::Condition.new(:c, { m: :v2?, n: :v3? })
]

# Join tests:
# a[:x] == b[:p]  (via :v1?)
# a[:y] == c[:m]  (via :v2?)
# b[:q] == c[:n]  (via :v3?)
```

### Visual Example

```
Condition 1: stock(symbol: :sym?, price: :p?)
Condition 2: watchlist(symbol: :sym?)
Condition 3: alert_config(symbol: :sym?, threshold: :t?)

Variable :sym? creates two joins:
├─ stock[:symbol] == watchlist[:symbol]
└─ stock[:symbol] == alert_config[:symbol]
```

## Binding Lifecycle

### 1. First Occurrence: Bind

```ruby
# First condition with :sym?
KBS::Condition.new(:stock, { symbol: :sym? })

# Fact matches
{ type: :stock, symbol: "AAPL" }

# Binding created:
{ :sym? => "AAPL" }
```

### 2. Subsequent Occurrences: Test

```ruby
# Second condition with :sym?
KBS::Condition.new(:watchlist, { symbol: :sym? })

# Checks if symbol == "AAPL" (from previous binding)
# Matches:
{ type: :watchlist, symbol: "AAPL" }  # ✓

# Does not match:
{ type: :watchlist, symbol: "GOOGL" }  # ✗
```

### 3. Action: Access

```ruby
r.action = lambda do |facts, bindings|
  # Access bound variables
  symbol = bindings[:sym?]
  price = bindings[:p?]

  puts "#{symbol} at $#{price}"
end
```

## Join Tests

### What is a Join Test?

A join test verifies that variable values match across facts:

```ruby
r.conditions = [
  KBS::Condition.new(:a, { x: :v? }),
  KBS::Condition.new(:b, { y: :v? })
]

# Join test structure:
{
  token_field_index: 0,     # Index of fact in token (first condition)
  token_field: :x,          # Attribute name in first fact
  fact_field: :y,           # Attribute name in new fact
  operation: :eq            # Equality test
}
```

### Join Test Execution

```ruby
def perform_join_test(token, new_fact, test)
  # Get value from token (previous facts)
  token_fact = token.facts[test[:token_field_index]]
  token_value = token_fact[test[:token_field]]

  # Get value from new fact
  fact_value = new_fact[test[:fact_field]]

  # Test equality
  token_value == fact_value
end
```

### Example Execution

```ruby
# Rule
r.conditions = [
  KBS::Condition.new(:sensor, { id: :id?, temp: :temp? }),
  KBS::Condition.new(:threshold, { sensor_id: :id?, max: :max? })
]

# Facts
sensor = { type: :sensor, id: "bedroom", temp: 28 }
threshold = { type: :threshold, sensor_id: "bedroom", max: 25 }

# Join execution:
# 1. sensor matches → token created
token = Token.new(parent: root, fact: sensor)
# Bindings: { :id? => "bedroom", :temp? => 28 }

# 2. threshold tested against token
test = {
  token_field_index: 0,       # sensor is first fact
  token_field: :id,           # sensor's id attribute
  fact_field: :sensor_id,     # threshold's sensor_id attribute
  operation: :eq
}

# 3. Perform join
token_value = sensor[:id]              # "bedroom"
fact_value = threshold[:sensor_id]     # "bedroom"
result = token_value == fact_value     # true
# ✓ Join succeeds → new token created
```

## Binding Strategies

### Pattern 1: Primary Key Join

Connect facts via identifier:

```ruby
r.conditions = [
  KBS::Condition.new(:order, {
    id: :order_id?,
    status: "pending"
  }),

  KBS::Condition.new(:payment, {
    order_id: :order_id?,
    verified: true
  })
]

# Matches orders with verified payments
```

### Pattern 2: Multi-Attribute Join

Join on multiple fields:

```ruby
r.conditions = [
  KBS::Condition.new(:trade, {
    symbol: :sym?,
    date: :date?,
    volume: :vol?
  }),

  KBS::Condition.new(:settlement, {
    symbol: :sym?,
    trade_date: :date?
  })
]

# Joins on both symbol AND date
```

### Pattern 3: Transitive Binding

Chain bindings across three+ conditions:

```ruby
r.conditions = [
  KBS::Condition.new(:a, { id: :x? }),
  KBS::Condition.new(:b, { a_id: :x?, id: :y? }),
  KBS::Condition.new(:c, { b_id: :y? })
]

# a[:id] == b[:a_id]
# b[:id] == c[:b_id]
# Creates chain: a → b → c
```

### Pattern 4: Fan-Out Join

One fact joins with multiple:

```ruby
r.conditions = [
  KBS::Condition.new(:sensor, { id: :id?, temp: :t? }),
  KBS::Condition.new(:threshold, { sensor_id: :id? }),
  KBS::Condition.new(:alert_config, { sensor_id: :id? }),
  KBS::Condition.new(:location, { sensor_id: :id? })
]

# All join on :id?
```

## Performance Implications

### Join Cardinality

```ruby
# Condition 1: 100 sensor facts
KBS::Condition.new(:sensor, { temp: :t? })

# Condition 2: 200 threshold facts
KBS::Condition.new(:threshold, { max: :m? })

# Without variable binding:
# Potential matches: 100 × 200 = 20,000

# With variable binding:
KBS::Condition.new(:sensor, { id: :id?, temp: :t? })
KBS::Condition.new(:threshold, { sensor_id: :id?, max: :m? })

# Actual matches: ~100 (1:1 relationship)
```

**Variable bindings dramatically reduce join size.**

### Beta Memory Size

```ruby
# Bad: No shared variables
r.conditions = [
  KBS::Condition.new(:a, {}),  # 1000 facts
  KBS::Condition.new(:b, {}),  # 1000 facts
  KBS::Condition.new(:c, {})   # 1000 facts
]
# Beta memory: 1000 × 1000 × 1000 = 1,000,000,000 tokens!

# Good: Shared variables
r.conditions = [
  KBS::Condition.new(:a, { id: :id? }),
  KBS::Condition.new(:b, { a_id: :id? }),
  KBS::Condition.new(:c, { a_id: :id? })
]
# Beta memory: ~1000 tokens (assuming 1:1:1 relationship)
```

### Optimization Tips

**1. Use specific bindings:**

```ruby
# Good: Binds sensor to specific readings
KBS::Condition.new(:sensor, { id: :id? })
KBS::Condition.new(:reading, { sensor_id: :id? })

# Bad: No binding (cross product)
KBS::Condition.new(:sensor, {})
KBS::Condition.new(:reading, {})
```

**2. Order by selectivity:**

```ruby
# Good: Specific first
r.conditions = [
  KBS::Condition.new(:critical_alert, { id: :id? }),  # 1 fact
  KBS::Condition.new(:sensor, { id: :id? })          # 1000 facts
]
# Beta memory: 1 token

# Bad: General first
r.conditions = [
  KBS::Condition.new(:sensor, { id: :id? }),          # 1000 facts
  KBS::Condition.new(:critical_alert, { id: :id? })   # 1 fact
]
# Beta memory: 1000 tokens
```

**3. Minimize cross products:**

```ruby
# Bad: No shared variables between first two conditions
r.conditions = [
  KBS::Condition.new(:a, { x: :v1? }),
  KBS::Condition.new(:b, { y: :v2? }),  # No :v1?!
  KBS::Condition.new(:c, { p: :v1?, q: :v2? })
]
# Creates a × b cross product

# Good: Progressive joining
r.conditions = [
  KBS::Condition.new(:a, { x: :v1? }),
  KBS::Condition.new(:c, { p: :v1?, q: :v2? }),
  KBS::Condition.new(:b, { y: :v2? })
]
# Each condition reduces search space
```

## Common Patterns

### One-to-Many Relationship

```ruby
# One customer, many orders
r.conditions = [
  KBS::Condition.new(:customer, {
    id: :cust_id?,
    status: "active"
  }),

  KBS::Condition.new(:order, {
    customer_id: :cust_id?,
    status: "pending"
  })
]

# Fires once per pending order for active customers
```

### Many-to-Many Relationship

```ruby
# Students enrolled in courses
r.conditions = [
  KBS::Condition.new(:student, { id: :student_id? }),
  KBS::Condition.new(:enrollment, {
    student_id: :student_id?,
    course_id: :course_id?
  }),
  KBS::Condition.new(:course, { id: :course_id? })
]

# Fires for each student-course pair
```

### Hierarchical Join

```ruby
# Parent → Child → Grandchild
r.conditions = [
  KBS::Condition.new(:category, { id: :cat_id? }),
  KBS::Condition.new(:product, {
    category_id: :cat_id?,
    id: :prod_id?
  }),
  KBS::Condition.new(:review, {
    product_id: :prod_id?,
    rating: :rating?
  })
]
```

## Debugging Bindings

### Print Bindings

```ruby
r.action = lambda do |facts, bindings|
  puts "Bindings: #{bindings.inspect}"
  puts "Facts:"
  facts.each_with_index do |fact, i|
    puts "  #{i}: #{fact.type} #{fact.attributes}"
  end
end
```

### Trace Join Tests

```ruby
class DebugJoinNode < KBS::JoinNode
  def perform_join_tests(token, fact)
    result = super
    puts "Join test: #{@tests.inspect}"
    puts "  Token: #{token.inspect}"
    puts "  Fact: #{fact.inspect}"
    puts "  Result: #{result}"
    result
  end
end
```

### Validate Bindings

```ruby
r.action = lambda do |facts, bindings|
  # Ensure expected bindings exist
  required = [:sensor_id?, :temp?, :max?]
  missing = required - bindings.keys

  if missing.any?
    raise "Missing bindings: #{missing}"
  end

  # Proceed with action
  # ...
end
```

## Next Steps

- **[Pattern Matching](pattern-matching.md)** - How facts match conditions
- **[Negation](negation.md)** - Negated conditions and binding
- **[Network Structure](../architecture/network-structure.md)** - How joins compile into networks
- **[Performance Guide](../advanced/performance.md)** - Optimizing join performance

---

*Variable binding is the glue that connects facts. Master bindings, master rule performance.*
