# Working with Facts

Facts are the fundamental units of knowledge in KBS. This guide covers the complete lifecycle of facts: creating, querying, updating, and removing them.

## What is a Fact?

A fact represents an observation or piece of knowledge about your domain. Facts have:

- **Type** - A symbol categorizing the fact (e.g., `:stock`, `:sensor`, `:alert`)
- **Attributes** - Key-value pairs describing the fact (e.g., `{ symbol: "AAPL", price: 150 }`)
- **Identity** - Unique instance in working memory

**Example Facts:**

```ruby
# Sensor reading
type: :sensor
attributes: { id: "bedroom", temp: 28, humidity: 65 }

# Stock quote
type: :stock
attributes: { symbol: "AAPL", price: 150.50, volume: 1000000 }

# Alert
type: :alert
attributes: { sensor_id: "bedroom", message: "High temperature" }
```

## Fact Types

KBS provides two fact implementations:

### 1. Transient Facts (`KBS::Fact`)

In-memory facts that disappear when your program exits.

```ruby
engine = KBS::Engine.new

# Add transient fact
fact = engine.add_fact(:stock, { symbol: "AAPL", price: 150 })

# Facts lost on restart
```

**Use for:**
- Short-lived applications
- Prototyping
- Testing
- Pure computation (no persistence needed)

### 2. Persistent Facts (`KBS::Blackboard::Fact`)

Database-backed facts with UUIDs that survive restarts.

```ruby
require 'kbs/blackboard'

engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')

# Add persistent fact (saved to database)
fact = engine.add_fact(:stock, { symbol: "AAPL", price: 150 })
puts fact.uuid  # => "550e8400-e29b-41d4-a716-446655440000"

# Facts reload on next run
engine.close

# Next run
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')
puts engine.facts.size  # => 1 (fact persisted)
```

**Use for:**
- Long-running systems
- Systems requiring restart
- Audit trails
- Multi-agent collaboration

**Both types share the same interface**, so code works identically:

```ruby
fact.type           # => :stock
fact[:symbol]       # => "AAPL"
fact[:price]        # => 150
fact.attributes     # => { symbol: "AAPL", price: 150 }
```

## Creating Facts

### Basic Creation

```ruby
# Method 1: Via engine (recommended)
fact = engine.add_fact(:sensor, { id: "bedroom", temp: 28 })

# Method 2: Via the DSL (fact and assert both call engine.add_fact)
kb = KBS.knowledge_base
fact = kb.fact :sensor, id: "bedroom", temp: 28
```

`add_fact` takes a type and an attributes hash, not a `KBS::Fact` object.

**`add_fact` automatically:**
- Stores fact in working memory
- Triggers pattern matching in RETE network
- Notifies observers
- Persists to database (if using Blackboard::Engine)
- Returns the fact

Rules do not fire until you call `engine.run`; matching only puts activations on the agenda.

### Duplicate Facts

By default working memory may hold two facts with the same type and attributes. Turn that off and `add_fact` returns the fact already there instead of adding another:

```ruby
engine = KBS::Engine.new(fact_duplication: false)

a = engine.add_fact(:sensor, { id: "bedroom", temp: 28 })
b = engine.add_fact(:sensor, { id: "bedroom", temp: 28 })

a.equal?(b)          # => true
engine.facts.size    # => 1
```

You can also flip it later with `engine.fact_duplication = false`; duplicates already in working memory stay.

### With Type Conversion

`KBS::Engine` stores attributes as-is:

```ruby
engine.add_fact(:reading, {
  value: 42,              # Integer
  timestamp: Time.now,    # Time object
  active: true,           # Boolean
  metadata: { foo: 1 }    # Hash
})
```

A `KBS::Blackboard::Engine` stores attributes as JSON. The fact `add_fact` returns keeps the original values, but facts read back from the store (`engine.facts`, or after a restart) have Symbol and Time values turned into Strings.

### Bulk Creation

```ruby
facts = [
  [:stock, { symbol: "AAPL", price: 150 }],
  [:stock, { symbol: "GOOGL", price: 2800 }],
  [:stock, { symbol: "MSFT", price: 300 }]
]

facts.each do |type, attrs|
  engine.add_fact(type, attrs)
end
```

### From External Data

```ruby
require 'json'

# Load from JSON
json_data = File.read('sensors.json')
sensor_data = JSON.parse(json_data, symbolize_names: true)

sensor_data.each do |reading|
  engine.add_fact(:sensor, {
    id: reading[:sensor_id],
    temp: reading[:temperature],
    humidity: reading[:humidity]
  })
end
```

```ruby
require 'csv'

# Load from CSV
CSV.foreach('stocks.csv', headers: true) do |row|
  engine.add_fact(:stock, {
    symbol: row['symbol'],
    price: row['price'].to_f,
    volume: row['volume'].to_i
  })
end
```

## Accessing Fact Attributes

### Array-Style Access

```ruby
fact = engine.add_fact(:sensor, { id: "bedroom", temp: 28 })

# Read attributes
fact[:id]     # => "bedroom"
fact[:temp]   # => 28
fact[:missing] # => nil
```

### Attributes Hash

```ruby
fact.attributes
# => { id: "bedroom", temp: 28 }

# Iterate attributes
fact.attributes.each do |key, value|
  puts "#{key}: #{value}"
end
```

### Type Access

```ruby
fact.type  # => :sensor
```

### Identity

```ruby
# Blackboard facts have UUIDs
fact.uuid  # => "550e8400-e29b-41d4-a716-446655440000"

# Transient facts use their object_id
fact.id  # => 70123456789000 (same as fact.object_id)
```

## Querying Facts

### Get All Facts

```ruby
all_facts = engine.facts
# => [#<Fact type=:sensor>, #<Fact type=:stock>, ...]
```

### Filter by Type

```ruby
# Get all sensor facts
sensors = engine.facts.select { |f| f.type == :sensor }

# Get all stock facts
stocks = engine.facts.select { |f| f.type == :stock }
```

With the DSL, `kb.query(:sensor, id: "bedroom")` returns the facts of a type that match a pattern.

### Filter by Attribute

```ruby
# Find facts with specific attribute value
high_temps = engine.facts.select { |f|
  f.type == :sensor && f[:temp] && f[:temp] > 30
}

# Find by multiple criteria
aapl_stocks = engine.facts.select { |f|
  f.type == :stock && f[:symbol] == "AAPL"
}
```

### Find Single Fact

```ruby
# Find first matching fact
fact = engine.facts.find { |f|
  f.type == :sensor && f[:id] == "bedroom"
}

# Or return nil if not found
fact = engine.facts.find { |f|
  f.type == :alert && f[:severity] == "critical"
}
```

### Complex Queries

```ruby
# Count facts
sensor_count = engine.facts.count { |f| f.type == :sensor }

# Group by type
facts_by_type = engine.facts.group_by(&:type)
# => { sensor: [...], stock: [...], alert: [...] }

# Map attributes
symbols = engine.facts
  .select { |f| f.type == :stock }
  .map { |f| f[:symbol] }
  .uniq
# => ["AAPL", "GOOGL", "MSFT"]
```

### Query Helper Method

Create reusable query methods:

```ruby
class QueryHelper
  def initialize(engine)
    @engine = engine
  end

  def facts_of_type(type)
    @engine.facts.select { |f| f.type == type }
  end

  def facts_where(type, &block)
    facts_of_type(type).select(&block)
  end

  def fact_where(type, &block)
    facts_of_type(type).find(&block)
  end
end

# Usage
helper = QueryHelper.new(engine)

# Get all high-temp sensors
high_temps = helper.facts_where(:sensor) { |f| f[:temp] > 30 }

# Get specific sensor
bedroom = helper.fact_where(:sensor) { |f| f[:id] == "bedroom" }
```

## Updating Facts

Use `engine.modify` to change a fact. It merges the changes into the fact's attributes and matches the fact again, as a retraction followed by an assertion: matches that depended on the old values go away, and rules the new values satisfy are activated, including rules that already fired for this fact.

### Update Pattern

```ruby
# Find existing fact
fact = engine.facts.find { |f|
  f.type == :sensor && f[:id] == "bedroom"
}

if fact
  engine.modify(fact, temp: 30)  # => the fact, with temp: 30

  # Fire the rules the change activated
  engine.run
end
```

`modify` returns `nil` when the fact is not in working memory. With `fact_duplication: false`, if the change makes the fact equal to one already there, the modified fact is removed and the existing one is returned. The DSL has the same method: `kb.modify(fact, temp: 30)`.

Setting an attribute directly with `fact[:temp] = 30` changes the hash but does **not** re-match the fact; the network keeps matching the values the fact had when it was added.

### Update Helper

```ruby
def update_fact(engine, type, matcher, changes)
  fact = engine.facts.find { |f|
    f.type == type && matcher.call(f)
  }

  engine.modify(fact, changes) if fact
end

# Usage
update_fact(engine, :sensor, ->(f) { f[:id] == "bedroom" },
  { temp: 30, humidity: 65 }
)
```

### Blackboard Update (Persistent Facts)

`modify` works the same on a blackboard engine. The fact keeps its UUID and the audit log records an `UPDATE`:

```ruby
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')

fact = engine.add_fact(:sensor, { id: "bedroom", temp: 28 })

# Update via engine (saves to database and re-matches)
fact = engine.modify(fact, temp: 32)

# Or update in place (saves to database, does NOT re-match)
fact.update({ temp: 33 })
```

## Removing Facts

### Remove Single Fact

```ruby
# Find and remove
fact = engine.facts.find { |f| f.type == :alert }
engine.remove_fact(fact) if fact

# Retraction updates matches immediately; run fires any
# rule it activated (e.g. one with a `without` condition)
engine.run
```

### Remove Multiple Facts

```ruby
# Remove all alerts
alerts = engine.facts.select { |f| f.type == :alert }
alerts.each { |fact| engine.remove_fact(fact) }
engine.run
```

### Remove by Criteria

```ruby
# Remove all stale sensor readings (older than 5 minutes)
stale = engine.facts.select { |f|
  f.type == :sensor &&
  f[:timestamp] &&
  (Time.now - f[:timestamp]) > 300
}

stale.each { |fact| engine.remove_fact(fact) }
engine.run
```

### Clear All Facts

```ruby
# Clear working memory
engine.facts.each { |f| engine.remove_fact(f) }
engine.run
```

**Note:** `engine.facts` returns a copy, so removing facts while iterating over it is safe.

## Fact Lifecycle

### Lifecycle Stages

```
1. Creation
   ├─> engine.add_fact(:type, { ... })
   └─> Fact instantiated

2. Storage
   ├─> Added to WorkingMemory
   └─> Persisted (if Blackboard::Engine)

3. Matching
   ├─> Alpha network activation
   ├─> Join network propagation
   └─> Activations put on the agenda

4. Rule Firing
   ├─> engine.run()
   └─> Actions execute with fact

5. Update (Optional)
   ├─> engine.modify(fact, changes)
   └─> Matching re-triggered

6. Removal
   ├─> engine.remove_fact(fact)
   ├─> Removed from WorkingMemory
   ├─> Marked retracted in database (if persistent)
   └─> Tokens and pending activations withdrawn
```

### Observing Fact Changes

Working memory uses the Observer pattern:

```ruby
class FactObserver
  def update(operation, fact)
    case operation
    when :add
      puts "Added: #{fact.type} - #{fact.attributes}"
    when :remove
      puts "Removed: #{fact.type} - #{fact.attributes}"
    end
  end
end

observer = FactObserver.new
engine.working_memory.add_observer(observer)

engine.add_fact(:sensor, { id: "bedroom", temp: 28 })
# Output: Added: sensor - {id: "bedroom", temp: 28}
```

## Best Practices

### 1. Use Consistent Fact Types

```ruby
# Good: Consistent naming
:sensor_reading
:stock_quote
:user_alert

# Bad: Inconsistent
:sensor
:Stock
:UserAlert
```

### 2. Keep Attributes Flat

```ruby
# Good: Flat structure
engine.add_fact(:sensor, {
  sensor_id: "bedroom",
  temp: 28,
  humidity: 65
})

# Bad: Nested (harder to match)
engine.add_fact(:sensor, {
  id: "bedroom",
  readings: { temp: 28, humidity: 65 }
})
```

### 3. Include Timestamps

```ruby
# Good: Temporal reasoning enabled
engine.add_fact(:reading, {
  sensor_id: "bedroom",
  value: 28,
  timestamp: Time.now
})
```

### 4. Validate Before Adding

```ruby
def add_sensor_reading(engine, id, temp)
  # Validate
  raise ArgumentError, "Invalid temp" unless temp.is_a?(Numeric)
  raise ArgumentError, "Temp out of range" unless temp.between?(-50, 100)

  # Add fact
  engine.add_fact(:sensor, {
    id: id,
    temp: temp,
    timestamp: Time.now
  })
end
```

### 5. Use Symbols for Type

```ruby
# Good
engine.add_fact(:sensor, { ... })

# Bad
engine.add_fact("sensor", { ... })  # Strings not idiomatic
```

### 6. Namespace Fact Types

```ruby
# Good: Clear namespacing for large systems
:trading_order
:trading_execution
:trading_alert

:sensor_temp
:sensor_humidity
:sensor_pressure
```

## Common Patterns

### Fact Factory

```ruby
class SensorFactFactory
  def self.create_reading(id, temp, humidity)
    {
      type: :sensor,
      attributes: {
        id: id,
        temp: temp,
        humidity: humidity,
        timestamp: Time.now
      }
    }
  end
end

# Usage
reading = SensorFactFactory.create_reading("bedroom", 28, 65)
engine.add_fact(reading[:type], reading[:attributes])
```

### Fact Builder

```ruby
class FactBuilder
  def initialize(type)
    @type = type
    @attributes = {}
  end

  def with(key, value)
    @attributes[key] = value
    self
  end

  def build
    [@type, @attributes]
  end
end

# Usage
type, attrs = FactBuilder.new(:stock)
  .with(:symbol, "AAPL")
  .with(:price, 150)
  .with(:volume, 1000000)
  .build

engine.add_fact(type, attrs)
```

### Fact Repository

```ruby
class FactRepository
  def initialize(engine)
    @engine = engine
  end

  def add(type, attributes)
    @engine.add_fact(type, attributes.merge(created_at: Time.now))
  end

  def find_by_id(type, id)
    @engine.facts.find { |f| f.type == type && f[:id] == id }
  end

  def where(type, &block)
    @engine.facts.select { |f| f.type == type && block.call(f) }
  end

  def remove_where(type, &block)
    facts = where(type, &block)
    facts.each { |f| @engine.remove_fact(f) }
    @engine.run
  end
end

# Usage
repo = FactRepository.new(engine)
repo.add(:sensor, { id: "bedroom", temp: 28 })

bedroom = repo.find_by_id(:sensor, "bedroom")
high_temps = repo.where(:sensor) { |f| f[:temp] > 30 }
repo.remove_where(:alert) { |f| f[:stale] }
```

## Next Steps

- **[Pattern Matching](pattern-matching.md)** - How facts match conditions
- **[Writing Rules](writing-rules.md)** - Using facts in rule conditions
- **[Blackboard Memory](blackboard-memory.md)** - Persistent fact storage
- **[Persistence Guide](persistence.md)** - SQLite, Redis, and hybrid storage
- **[API Reference](../api/facts.md)** - Complete Fact API documentation

---

*Facts are knowledge. When facts change, modify them through the engine to trigger re-evaluation.*
