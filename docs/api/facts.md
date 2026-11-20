# Facts API Reference

Complete API reference for fact and condition classes in KBS.

## Table of Contents

- [KBS::Fact](#kbsfact) - Transient in-memory fact
- [KBS::Blackboard::Fact](#kbsblackboardfact) - Persistent fact with UUID
- [KBS::WorkingMemory](#kbsworkingmemory) - The set of facts an engine holds
- [KBS::Condition](#kbscondition) - Pattern matching condition
- [Fact Patterns](#fact-patterns)
- [Pattern Matching Semantics](#pattern-matching-semantics)

---

## KBS::Fact

Transient in-memory fact used by the core RETE engine.

Facts are usually created with `engine.add_fact(type, attributes)`, which builds the `KBS::Fact` and matches it against the rules. With `fact_duplication: false` the engine refuses an equal fact and returns the existing one; a fact asserted by a rule with `logical` conditions is retracted automatically when those conditions stop matching. See the [Engine API](engine.md).

### Constructor

#### `initialize(type, attributes = {})`

Creates a new transient fact.

**Parameters**:
- `type` (Symbol) - Fact type (e.g., `:temperature`, `:order`)
- `attributes` (Hash, optional) - Fact attributes (default: `{}`)

**Returns**: `KBS::Fact` instance

**Example**:
```ruby
# Fact with attributes
fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)

# Fact without attributes (marker/flag)
flag = KBS::Fact.new(:system_ready)
```

**Internal Behavior**:
- `@id` is set to `object_id` (unique Ruby object identifier)
- `@type` stores the fact type
- `@attributes` stores the attribute hash

---

### Public Attributes

#### `id`

**Type**: `Integer`

**Read-only**: Yes (via `attr_reader`)

**Description**: Unique identifier (Ruby object ID)

**Example**:
```ruby
fact = KBS::Fact.new(:temperature, value: 85)
puts fact.id  # => 70123456789012 (varies)
```

**Note**: Not stable across Ruby processes. For persistent IDs, use `KBS::Blackboard::Fact` with UUIDs.

---

#### `type`

**Type**: `Symbol`

**Read-only**: Yes (via `attr_reader`)

**Description**: The fact type

**Example**:
```ruby
fact = KBS::Fact.new(:temperature, value: 85)
puts fact.type  # => :temperature
```

---

#### `attributes`

**Type**: `Hash`

**Read-only**: Yes (via `attr_reader`)

**Description**: The fact's attribute hash

**Example**:
```ruby
fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)
puts fact.attributes  # => {location: "server_room", value: 85}
```

**Important**: Changing the hash, directly or with `[]=`, is not seen by the engine. The network keeps matching the values the fact had when it was added. To change a fact so rules see the change, use `engine.modify`:
```ruby
# Not seen by the rules
fact.attributes[:value] = 90
fact[:value] = 90

# Retracts and re-matches the fact with its new values
engine.modify(fact, value: 90)
```

---

### Public Methods

#### `[](key)`

Retrieves an attribute value.

**Parameters**:
- `key` (Symbol) - Attribute key

**Returns**: Attribute value or `nil` if not present

**Example**:
```ruby
fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)
puts fact[:location]  # => "server_room"
puts fact[:value]     # => 85
puts fact[:missing]   # => nil
```

---

#### `[]=(key, value)`

Sets an attribute value.

**Parameters**:
- `key` (Symbol) - Attribute key
- `value` - Attribute value

**Returns**: The value

**Side Effects**: Modifies the fact's attributes hash

**Example**:
```ruby
fact = KBS::Fact.new(:temperature, value: 85)
fact[:value] = 90
fact[:timestamp] = Time.now

puts fact.attributes  # => {value: 90, timestamp: 2025-01-15 10:30:00 -0600}
```

**Important for KBS::Fact**: Changes are NOT persisted and do NOT trigger re-evaluation. To have rules see the new values, use `engine.modify(fact, changes)`.

---

#### `matches?(pattern)`

Checks if this fact matches a pattern.

**Parameters**:
- `pattern` (Hash) - Pattern hash with `:type` and attribute constraints

**Returns**: `true` if matches, `false` otherwise

**Pattern Types**:
1. **Type constraint**: `pattern[:type]` must equal fact type
2. **Literal values**: Attribute must equal specified value
3. **Predicate lambdas**: `value.is_a?(Proc)` - attribute passed to lambda, must return truthy
4. **Variable bindings**: `value.is_a?(Symbol) && value.to_s.end_with?('?')` - always matches (variable captures value)

**Example - Literal Matching**:
```ruby
fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)

# Type only
fact.matches?(type: :temperature)  # => true
fact.matches?(type: :pressure)     # => false

# Type + literal attribute
fact.matches?(type: :temperature, location: "server_room")  # => true
fact.matches?(type: :temperature, location: "lobby")        # => false

# Multiple literals
fact.matches?(type: :temperature, location: "server_room", value: 85)  # => true
fact.matches?(type: :temperature, location: "server_room", value: 90)  # => false
```

**Example - Predicate Matching**:
```ruby
fact = KBS::Fact.new(:temperature, value: 85)

# Lambda predicate
fact.matches?(type: :temperature, value: ->(v) { v > 80 })   # => true
fact.matches?(type: :temperature, value: ->(v) { v > 100 })  # => false

# Complex predicate
fact.matches?(
  type: :temperature,
  value: ->(v) { v >= 70 && v <= 90 }
)  # => true
```

**Example - Variable Binding**:
```ruby
fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)

# Variables always match (they capture the value)
fact.matches?(type: :temperature, location: :loc?)  # => true
fact.matches?(type: :temperature, value: :temp?)    # => true

# Variables with other constraints
fact.matches?(
  type: :temperature,
  location: "server_room",  # Literal constraint
  value: :temp?             # Variable binding
)  # => true
```

**Example - Missing Attributes**:
```ruby
fact = KBS::Fact.new(:temperature, value: 85)  # No :location attribute

# Missing attributes fail predicate/literal checks
fact.matches?(type: :temperature, location: "server_room")  # => false
fact.matches?(type: :temperature, location: ->(l) { l.length > 5 })  # => false (no :location)

# Missing attributes match variables
fact.matches?(type: :temperature, location: :loc?)  # => true (variable matches nil)
```

**Algorithm**:
1. If `pattern[:type]` present and doesn't match fact type → return `false`
2. For each key in pattern (except `:type`):
   - If value is Proc: call with fact attribute value, return `false` if falsy or attribute missing
   - If value is variable (symbol ending with `?`): skip (always matches)
   - Otherwise: return `false` if fact attribute ≠ pattern value
3. Return `true` if all checks passed

---

#### `to_s`

Returns string representation of fact.

**Parameters**: None

**Returns**: `String` in DSL form, `"fact :type, attr1: val1, attr2: val2"` (values shown with `inspect`)

**Example**:
```ruby
fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)
puts fact.to_s  # => fact :temperature, location: "server_room", value: 85

flag = KBS::Fact.new(:system_ready)
puts flag.to_s  # => fact :system_ready
```

---

## KBS::Blackboard::Fact

Persistent fact with UUID, used by blackboard memory.

**Inherits**: None (separate implementation from `KBS::Fact`)

**Key Differences from KBS::Fact**:
- Has UUID instead of object ID
- Equality (`==`, `eql?`, `hash`) is by UUID: two `Blackboard::Fact` objects with the same UUID are equal
- `[]=` and `update()` trigger persistence and audit logging
- `retract()` method to remove from blackboard
- Reference to blackboard memory for update tracking

---

### Constructor

#### `initialize(uuid, type, attributes, blackboard = nil)`

Creates a persistent fact. Usually created via `engine.add_fact()`, not directly.

**Parameters**:
- `uuid` (String) - Unique identifier (UUID format)
- `type` (Symbol) - Fact type
- `attributes` (Hash) - Fact attributes
- `blackboard` (KBS::Blackboard::Memory, optional) - Reference to blackboard (default: `nil`)

**Returns**: `KBS::Blackboard::Fact` instance

**Example - Direct Construction** (rare):
```ruby
require 'securerandom'

fact = KBS::Blackboard::Fact.new(
  SecureRandom.uuid,
  :temperature,
  { location: "server_room", value: 85 }
)
puts fact.uuid  # => "550e8400-e29b-41d4-a716-446655440000"
```

**Example - Typical Usage**:
```ruby
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')
fact = engine.add_fact(:temperature, location: "server_room", value: 85)
# Returns KBS::Blackboard::Fact with UUID and blackboard reference
```

---

### Public Attributes

#### `uuid`

**Type**: `String`

**Read-only**: Yes (via `attr_reader`)

**Description**: Globally unique identifier (UUID format)

**Example**:
```ruby
fact = engine.add_fact(:temperature, value: 85)
puts fact.uuid  # => "550e8400-e29b-41d4-a716-446655440000"
```

**Use Cases**:
- Stable ID across restarts
- Foreign keys in external systems
- Audit trail references

---

#### `type`

**Type**: `Symbol`

**Read-only**: Yes (via `attr_reader`)

**Description**: The fact type

**Example**:
```ruby
fact = engine.add_fact(:temperature, value: 85)
puts fact.type  # => :temperature
```

---

#### `attributes`

**Type**: `Hash`

**Read-only**: Yes (via `attr_reader`)

**Description**: The fact's attribute hash

**Example**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)
puts fact.attributes  # => {location: "server_room", value: 85}
```

**Important**: Direct modification bypasses persistence:
```ruby
# Don't do this (not persisted)
fact.attributes[:value] = 90

# Persisted, but rules do not see the change
fact[:value] = 90
# or
fact.update(value: 90)

# Persisted and re-matched against the rules
engine.modify(fact, value: 90)
```

---

### Public Methods

#### `[](key)`

Retrieves an attribute value.

**Parameters**:
- `key` (Symbol) - Attribute key

**Returns**: Attribute value or `nil` if not present

**Example**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)
puts fact[:location]  # => "server_room"
puts fact[:value]     # => 85
puts fact[:missing]   # => nil
```

---

#### `[]=(key, value)`

Sets an attribute value with persistence.

**Parameters**:
- `key` (Symbol) - Attribute key
- `value` - Attribute value (must be JSON-serializable for most stores)

**Returns**: The value

**Side Effects**:
- Updates fact's attributes hash
- Calls `blackboard.update_fact(self, @attributes)` if blackboard present
- Persists change to store
- Logs an `UPDATE` to the audit trail
- Does NOT notify observers

**Example**:
```ruby
fact = engine.add_fact(:temperature, value: 85)
fact[:value] = 90  # Immediately persisted

# After restart
engine2 = KBS::Blackboard::Engine.new(db_path: 'kb.db')
reloaded = engine2.blackboard.get_facts(:temperature).first
puts reloaded[:value]  # => 90
```

**Important**: Updates do NOT trigger rule re-evaluation. To trigger rules, use `engine.modify`, which keeps the fact's UUID, logs an `UPDATE`, and matches the fact again:
```ruby
engine.modify(fact, value: 90)
engine.run
```

---

#### `update(new_attributes)`

Bulk update multiple attributes with persistence.

**Parameters**:
- `new_attributes` (Hash) - Hash of attributes to merge

**Returns**: No meaningful value (`nil` when the fact has no blackboard)

**Side Effects**:
- Merges `new_attributes` into `@attributes`
- Persists changes
- Logs an `UPDATE` to the audit trail
- Does NOT notify observers or re-match the fact (use `engine.modify` for that)

**Example**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)

fact.update(value: 90, timestamp: Time.now)

puts fact.attributes
# => {location: "server_room", value: 90, timestamp: 2025-01-15 10:30:00 -0600}
```

**Difference from `[]=`**: Updates multiple attributes in single persistence operation (more efficient).

---

#### `retract()`

Removes this fact from the blackboard.

**Parameters**: None

**Returns**: No meaningful value

**Side Effects**:
- Calls `blackboard.remove_fact(self)` if blackboard present
- Marks fact as inactive in store
- Logs a `REMOVE` to the audit trail
- Notifies observers, so an engine removes the fact from its alpha memories

**Example**:
```ruby
fact = engine.add_fact(:temperature, value: 85)
fact.retract  # Fact removed

# Equivalent to:
engine.remove_fact(fact)
```

**Use Case**: Fact self-destruction in rule actions:
```ruby
rule "auto_expire_old_alerts" do
  on :alert, timestamp: ->(ts) { Time.now - ts > 3600 }
  perform do |facts|
    # Fact can remove itself
    alert_fact = facts[0]
    alert_fact.retract
  end
end
```

---

#### `matches?(pattern)`

Checks if this fact matches a pattern. Same semantics as `KBS::Fact#matches?`.

**Parameters**:
- `pattern` (Hash) - Pattern hash with `:type` and attribute constraints

**Returns**: `true` if matches, `false` otherwise

**Example**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)

fact.matches?(type: :temperature)  # => true
fact.matches?(type: :temperature, value: ->(v) { v > 80 })  # => true
fact.matches?(type: :pressure)  # => false
```

See [`KBS::Fact#matches?`](#matchespattern) for detailed semantics.

---

#### `to_s`

Returns string representation with UUID prefix.

**Parameters**: None

**Returns**: `String` in format `"type(uuid_prefix...: attr1=val1, attr2=val2)"`

**Example**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)
puts fact.to_s
# => temperature(550e8400...: location=server_room, value=85)
```

**Note**: Only first 8 characters of UUID shown for brevity.

---

#### `to_h`

Returns hash representation of fact.

**Parameters**: None

**Returns**: `Hash` with keys `:uuid`, `:type`, `:attributes`

**Example**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)
hash = fact.to_h

puts hash
# => {uuid: "550e8400-e29b-41d4-a716-446655440000", type: :temperature, attributes: {location: "server_room", value: 85}}
```

**Use Cases**:
- Serialization for APIs
- Logging
- Testing assertions

---

## KBS::WorkingMemory

The set of facts a `KBS::Engine` holds, available as `engine.working_memory`. It tells its observers (the engine among them) of each fact added or removed. Add and remove facts through the engine (`add_fact`, `remove_fact`, `modify`), not directly, so duplicate checks and truth maintenance apply.

`KBS::Blackboard::Engine` uses a [`KBS::Blackboard::Memory`](blackboard.md#kbsblackboardmemory) in its place.

### Public Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `facts` | `Array<KBS::Fact>` | The facts in the order they were added. A copy: changing it does not change working memory |
| `each_fact(&block)` | | Yields each fact |
| `size` | `Integer` | Number of facts |
| `include?(fact)` | `Boolean` | Whether `fact` is in working memory |
| `add_fact(fact)` | the fact | Adds a `KBS::Fact` object and notifies observers with `:add` |
| `remove_fact(fact)` | the fact | Removes it and notifies observers with `:remove` |
| `clear` | | Forgets every fact without notifying observers (used by `engine.reset`) |
| `add_observer(observer)` | | Registers an object that responds to `update(action, fact)` |
| `notify_observers(action, fact)` | | Calls `update(action, fact)` on each observer |

**Example**:
```ruby
engine = KBS::Engine.new
reading = engine.add_fact(:temperature, value: 85)

engine.working_memory.size              # => 1
engine.working_memory.include?(reading) # => true
engine.working_memory.facts             # => [reading]
```

---

## KBS::Condition

Pattern matching condition used in rule definitions.

### Constructor

#### `initialize(type, pattern = {}, negated: false, exists: false, logical: false)`

Creates a condition that matches facts.

**Parameters**:
- `type` (Symbol) - Fact type to match
- `pattern` (Hash, optional) - Attribute constraints (default: `{}`)
- `negated` (Boolean, optional) - If `true`, condition matches when pattern is absent (default: `false`)
- `exists` (Boolean, optional) - If `true`, condition matches once when at least one fact fits the pattern, instead of once per fact (default: `false`)
- `logical` (Boolean, optional) - If `true`, facts the rule's action asserts are retracted when this condition stops matching; logical conditions must come first in a rule (default: `false`)

**Returns**: `KBS::Condition` instance

**Raises**: `ArgumentError` if both `negated` and `exists` are `true`

**Important**: Pass the pattern as a braced Hash. Bare `key: value` arguments are taken as keyword arguments and raise `ArgumentError` (`unknown keyword: :location`):
```ruby
KBS::Condition.new(:temperature, { location: "server_room" })  # OK
KBS::Condition.new(:temperature, location: "server_room")      # ArgumentError
```

**Example - Positive Condition**:
```ruby
# Match any temperature fact
condition = KBS::Condition.new(:temperature)

# Match temperature facts with location="server_room"
condition = KBS::Condition.new(:temperature, { location: "server_room" })

# Match temperature facts with value > 80
condition = KBS::Condition.new(:temperature, { value: ->(v) { v > 80 } })
```

**Example - Negated Condition**:
```ruby
# Match when there is NO alert fact
condition = KBS::Condition.new(:alert, {}, negated: true)

# Match when there is NO critical alert
condition = KBS::Condition.new(:alert, { level: "critical" }, negated: true)
```

**Example - Variable Binding**:
```ruby
# Capture temperature value in :temp? variable
condition = KBS::Condition.new(:temperature, { value: :temp? })

# Capture location and value
condition = KBS::Condition.new(:temperature, {
  location: :loc?,
  value: :temp?
})
```

---

### Public Attributes

#### `type`

**Type**: `Symbol`

**Read-only**: Yes (via `attr_reader`)

**Description**: The fact type this condition matches

**Example**:
```ruby
condition = KBS::Condition.new(:temperature, { value: :temp? })
puts condition.type  # => :temperature
```

---

#### `pattern`

**Type**: `Hash`

**Read-only**: Yes (via `attr_reader`)

**Description**: The attribute pattern to match

**Example**:
```ruby
condition = KBS::Condition.new(:temperature, { location: "server_room", value: :temp? })
puts condition.pattern  # => {location: "server_room", value: :temp?}
```

---

#### `negated`

**Type**: `Boolean`

**Read-only**: Yes (via `attr_reader`)

**Description**: Whether this is a negation condition

**Example**:
```ruby
pos_condition = KBS::Condition.new(:temperature, { value: :temp? })
puts pos_condition.negated  # => false

neg_condition = KBS::Condition.new(:alert, {}, negated: true)
puts neg_condition.negated  # => true
```

---

#### `variable_bindings`

**Type**: `Hash<Symbol, Symbol>`

**Read-only**: Yes (via `attr_reader`)

**Description**: Map of variable names to attribute keys (e.g., `{temp?: :value}`)

**Example**:
```ruby
condition = KBS::Condition.new(:temperature, {
  location: :loc?,
  value: :temp?
})

puts condition.variable_bindings
# => {loc?: :location, temp?: :value}
```

**Use Case**: RETE engine uses this to extract bindings when condition matches:
```ruby
fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)
bindings = {}

condition.variable_bindings.each do |var, attr|
  bindings[var] = fact[attr]
end

puts bindings  # => {loc?: "server_room", temp?: 85}
```

---

#### `exists`, `logical`

**Type**: `Boolean`

**Read-only**: Yes (via `attr_reader`)

**Description**: Whether this is an existential condition, and whether it is a logical condition (see the constructor)

---

### Public Methods

#### `bindings_from(fact)`

Returns the value each of this condition's variables takes from `fact`. Does the same as the loop above.

**Returns**: `Hash` of variable to value

```ruby
condition.bindings_from(fact)  # => {loc?: "server_room", temp?: 85}
```

---

#### `binds_fact?`

Returns `true` when the condition adds a fact to the rule's match (a plain condition), `false` for negated and exists conditions.

---

#### `keyword`

Returns the DSL keyword that writes this condition: `"without"` (negated), `"exists"`, or `"on"`.

---

#### `summary`

Returns a one-line description of the condition, marked `NOT` or `EXISTS`.

```ruby
KBS::Condition.new(:alert, { level: "critical" }, negated: true).summary
# => "NOT alert(level: \"critical\")"
```

---

## Fact Patterns

Patterns are hashes used to match facts. They appear in:
- `Condition.new(type, pattern)`
- `Fact#matches?(pattern)`
- Alpha memory keys

### Pattern Structure

```ruby
{
  type: :fact_type,           # Optional: fact type constraint
  attribute1: literal_value,   # Literal constraint
  attribute2: :variable?,      # Variable binding
  attribute3: ->(v) { ... }    # Predicate lambda
}
```

### Pattern Types

#### 1. Empty Pattern

Matches all facts of a type.

```ruby
condition = KBS::Condition.new(:temperature)
# Matches ANY temperature fact
```

#### 2. Literal Pattern

Matches facts with exact attribute values.

```ruby
condition = KBS::Condition.new(:temperature, {
  location: "server_room",
  sensor_id: 42
})

# Matches:
KBS::Fact.new(:temperature, location: "server_room", sensor_id: 42, value: 85)

# Doesn't match:
KBS::Fact.new(:temperature, location: "lobby", sensor_id: 42)
KBS::Fact.new(:temperature, location: "server_room", sensor_id: 99)
```

#### 3. Predicate Pattern

Matches facts where attribute satisfies lambda.

```ruby
condition = KBS::Condition.new(:temperature, {
  value: ->(v) { v > 80 && v < 100 },
  location: ->(l) { l.start_with?("server") }
})

# Matches:
KBS::Fact.new(:temperature, location: "server_room", value: 85)
KBS::Fact.new(:temperature, location: "server_1", value: 90)

# Doesn't match:
KBS::Fact.new(:temperature, location: "server_room", value: 110)  # value > 100
KBS::Fact.new(:temperature, location: "lobby", value: 85)  # location doesn't start with "server"
```

**Important**: Predicate fails if attribute is missing:
```ruby
fact = KBS::Fact.new(:temperature, location: "server_room")  # No :value
fact.matches?(type: :temperature, value: ->(v) { v > 0 })  # => false (no :value attribute)
```

#### 4. Variable Binding Pattern

Variables (symbols ending with `?`) capture attribute values for use in join tests and action blocks.

```ruby
condition = KBS::Condition.new(:temperature, {
  location: :loc?,
  value: :temp?
})

# Matches ANY temperature fact, binding :loc? and :temp?
fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)
# Bindings: {:loc? => "server_room", :temp? => 85}
```

#### 5. Mixed Pattern

Combine literals, predicates, and variables.

```ruby
condition = KBS::Condition.new(:temperature, {
  location: "server_room",      # Literal
  value: :temp?,                # Variable
  timestamp: ->(ts) { ts > cutoff_time }  # Predicate
})

# Only matches temperature facts from server_room with recent timestamp
# Captures value in :temp? variable
```

---

## Pattern Matching Semantics

### Matching Algorithm

For `fact.matches?(pattern)`:

1. **Type Check**: If `pattern[:type]` present, must equal `fact.type`
2. **Attribute Checks**: For each `key, value` in pattern (except `:type`):
   - **Variable** (`value.is_a?(Symbol) && value.to_s.end_with?('?')`): Always matches (captures `fact[key]`)
   - **Predicate** (`value.is_a?(Proc)`): Must satisfy `value.call(fact[key])`. **Fails, without calling the lambda, if `fact[key]` is nil or false.**
   - **Literal**: Must equal `fact[key]`
3. **Result**: `true` if all checks pass, `false` otherwise

### Open World Assumption

Facts are not required to have all attributes in the pattern. Patterns only constrain attributes they specify.

```ruby
fact = KBS::Fact.new(:temperature, location: "server_room", value: 85, timestamp: Time.now)

# Matches - pattern doesn't mention :timestamp
fact.matches?(type: :temperature, location: "server_room")  # => true

# Matches - pattern only constrains :value
fact.matches?(type: :temperature, value: ->(v) { v > 80 })  # => true
```

**But**: If pattern specifies an attribute the fact lacks, match fails:

```ruby
fact = KBS::Fact.new(:temperature, value: 85)  # No :location

# Fails - fact missing :location attribute
fact.matches?(type: :temperature, location: "server_room")  # => false

# Fails - predicate can't evaluate nil
fact.matches?(type: :temperature, location: ->(l) { l.length > 5 })  # => false

# Succeeds - variable matches nil
fact.matches?(type: :temperature, location: :loc?)  # => true (binds :loc? => nil)
```

### Variable Binding Extraction

Variables are extracted during condition construction:

```ruby
condition = KBS::Condition.new(:order, {
  symbol: :sym?,
  quantity: :qty?,
  price: :price?
})

puts condition.variable_bindings
# => {sym?: :symbol, qty?: :quantity, price?: :price}
```

When a fact matches, bindings are populated:

```ruby
fact = KBS::Fact.new(:order, symbol: "AAPL", quantity: 100, price: 150.25)

bindings = {}
condition.variable_bindings.each do |var, attr|
  bindings[var] = fact[attr]
end

puts bindings
# => {sym?: "AAPL", qty?: 100, price?: 150.25}
```

### Predicate Constraints

Predicates are powerful but have caveats:

**1. Nil Attributes Fail**:
```ruby
fact = KBS::Fact.new(:temperature, location: "server_room")  # No :value

# Predicate fails - can't call lambda on nil
fact.matches?(type: :temperature, value: ->(v) { v > 0 })  # => false
```

**2. Predicates Run on Every Match Attempt**:
```ruby
# This predicate runs every time a fact is checked
expensive_check = ->(v) { complex_calculation(v) }
condition = KBS::Condition.new(:temperature, { value: expensive_check })

# For 1000 temperature facts, expensive_check runs 1000 times
```

**3. Predicates Should Be Pure Functions**:
```ruby
# Bad - side effects
counter = 0
condition = KBS::Condition.new(:temperature, { value: ->(v) { counter += 1; v > 80 } })

# Good - pure predicate
condition = KBS::Condition.new(:temperature, { value: ->(v) { v > 80 } })
```

**4. Predicates Can't Access Other Attributes**:
```ruby
# This doesn't work - predicate only receives attribute value
condition = KBS::Condition.new(:temperature, {
  value: ->(v) { v > @threshold }  # @threshold from where?
})

# Use closures to capture context
threshold = 80
condition = KBS::Condition.new(:temperature, {
  value: ->(v) { v > threshold }  # Closure captures threshold
})
```

### Negation Semantics

Negated conditions match when NO fact satisfies the pattern:

```ruby
# Rule fires when there's NO critical alert
rule "all_clear" do
  without :alert, level: "critical"  # negated: true
  perform { puts "All systems normal" }
end
```

**Important**: Negation matches absence, not presence of opposite:

```ruby
# Matches when NO alert with level="critical" exists
without :alert, level: "critical"

# NOT equivalent to: Match when alert with level != "critical" exists
# To match non-critical alerts, use predicate:
on :alert, level: ->(l) { l != "critical" }
```

See [Negation Guide](../guides/negation.md) for detailed semantics.

---

## Common Patterns

### 1. Range Checks

```ruby
# Between 70 and 90
condition = KBS::Condition.new(:temperature, {
  value: ->(v) { v >= 70 && v <= 90 }
})

# Outside range
condition = KBS::Condition.new(:temperature, {
  value: ->(v) { v < 70 || v > 90 }
})
```

### 2. String Matching

```ruby
# Starts with
condition = KBS::Condition.new(:sensor, {
  name: ->(n) { n.start_with?("temp_") }
})

# Regex match
condition = KBS::Condition.new(:sensor, {
  name: ->(n) { n =~ /^sensor_\d+$/ }
})

# Contains substring
condition = KBS::Condition.new(:log_entry, {
  message: ->(m) { m.include?("ERROR") }
})
```

### 3. Collection Membership

```ruby
# One of several values
valid_statuses = ["pending", "processing", "completed"]
condition = KBS::Condition.new(:order, {
  status: ->(s) { valid_statuses.include?(s) }
})

# Not in collection
invalid_statuses = ["cancelled", "failed"]
condition = KBS::Condition.new(:order, {
  status: ->(s) { !invalid_statuses.include?(s) }
})
```

### 4. Timestamp Checks

```ruby
# Recent facts (last hour)
cutoff = Time.now - 3600
condition = KBS::Condition.new(:temperature, {
  timestamp: ->(ts) { ts > cutoff }
})

# Old facts (older than 1 day)
cutoff = Time.now - 86400
condition = KBS::Condition.new(:temperature, {
  timestamp: ->(ts) { ts < cutoff }
})
```

### 5. Cross-Attribute Constraints (Using Multiple Conditions)

You can't directly compare two attributes of the same fact in one condition. Use multiple conditions:

```ruby
# Want: Match orders where quantity * price > 10000
# Can't do this in one condition:
# condition = KBS::Condition.new(:order, ...)  # No way to access both :quantity and :price

# Instead: Capture variables and check in action or use join test
rule "large_order" do
  on :order, quantity: :qty?, price: :price?
  perform do |facts, bindings|
    total = bindings[:qty?] * bindings[:price?]
    if total > 10000
      puts "Large order: $#{total}"
    end
  end
end
```

### 6. Null/Nil Checks

Variables capture `nil`, predicates fail on `nil`:

```ruby
# Match facts with ANY value for :location (including nil)
condition = KBS::Condition.new(:temperature, { location: :loc? })
# Matches KBS::Fact.new(:temperature, location: nil)  → binds :loc? => nil
# Matches KBS::Fact.new(:temperature)  → binds :loc? => nil

# Match facts with NON-NIL :location
condition = KBS::Condition.new(:temperature, {
  location: ->(l) { !l.nil? }
})
# Fails KBS::Fact.new(:temperature, location: nil)
# Fails KBS::Fact.new(:temperature)  (no :location attribute)
```

---

## Performance Tips

### 1. Order Predicates by Selectivity

```ruby
# Good - Most selective predicate first
condition = KBS::Condition.new(:temperature, {
  sensor_id: 42,              # Likely filters to 1 fact
  value: ->(v) { v > 80 }     # Then check value
})

# Less optimal - Expensive check first
condition = KBS::Condition.new(:temperature, {
  value: ->(v) { expensive_calculation(v) },  # Runs on many facts
  sensor_id: 42               # Could have filtered first
})
```

**Note**: `matches?` checks constraints in the pattern's insertion order and stops at the first one that fails. In an engine, the alpha network also files each pattern under its first literal (constant) attribute, so a fact reaches the pattern's predicates only when that literal already matches, wherever the literal appears in the hash. Both conditions above therefore run the predicate only on facts with `sensor_id: 42`. The bigger optimization is condition ordering in rules.

### 2. Avoid Expensive Predicates

```ruby
# Bad - Complex regex on every fact
condition = KBS::Condition.new(:log_entry, {
  message: ->(m) { m =~ /very.*complex.*regex.*pattern/ }
})

# Better - Simple check first, complex check in action
rule "complex_log_analysis" do
  on :log_entry, level: "ERROR", message: :msg?  # Simple literal filter
  perform do |facts, bindings|
    if bindings[:msg?] =~ /very.*complex.*regex.*pattern/
      # Expensive check runs only on ERROR logs
    end
  end
end
```

### 3. Use Literals When Possible

Literals are fastest (hash equality check). Predicates are slower (lambda call).

```ruby
# Fast
condition = KBS::Condition.new(:temperature, { location: "server_room" })

# Slower (but necessary for ranges/complex checks)
condition = KBS::Condition.new(:temperature, { value: ->(v) { v > 80 } })
```

---

## Testing Patterns

### Testing Fact Matching

```ruby
require 'minitest/autorun'

class TestFactMatching < Minitest::Test
  def test_literal_match
    fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)

    assert fact.matches?(type: :temperature)
    assert fact.matches?(type: :temperature, location: "server_room")
    refute fact.matches?(type: :temperature, location: "lobby")
  end

  def test_predicate_match
    fact = KBS::Fact.new(:temperature, value: 85)

    assert fact.matches?(type: :temperature, value: ->(v) { v > 80 })
    refute fact.matches?(type: :temperature, value: ->(v) { v > 100 })
  end

  def test_variable_binding
    fact = KBS::Fact.new(:temperature, location: "server_room", value: 85)

    # Variables always match
    assert fact.matches?(type: :temperature, location: :loc?, value: :temp?)
  end

  def test_missing_attribute
    fact = KBS::Fact.new(:temperature, value: 85)  # No :location

    # Literal fails on missing
    refute fact.matches?(type: :temperature, location: "server_room")

    # Predicate fails on missing
    refute fact.matches?(type: :temperature, location: ->(l) { l.length > 0 })

    # Variable succeeds on missing (binds to nil)
    assert fact.matches?(type: :temperature, location: :loc?)
  end
end
```

### Testing Variable Extraction

```ruby
class TestVariableExtraction < Minitest::Test
  def test_variable_bindings
    condition = KBS::Condition.new(:temperature, {
      location: :loc?,
      value: :temp?
    })

    expected = { :loc? => :location, :temp? => :value }
    assert_equal expected, condition.variable_bindings
  end

  def test_no_variables
    condition = KBS::Condition.new(:temperature, { location: "server_room" })

    assert_empty condition.variable_bindings
  end
end
```

---

## See Also

- [Engine API](engine.md) - Adding facts to engines
- [Rules API](rules.md) - Using conditions in rules
- [Pattern Matching Guide](../guides/pattern-matching.md) - Detailed pattern semantics
- [Variable Binding Guide](../guides/variable-binding.md) - Join tests and bindings
- [DSL Guide](../guides/dsl.md) - Declarative condition syntax
