# Engine API Reference

Complete API reference for KBS engine classes.

## Table of Contents

- [KBS::Engine](#kbsengine) - Core RETE engine
- [KBS::Blackboard::Engine](#kbsblackboardengine) - Persistent RETE engine with blackboard
- [Engine Lifecycle](#engine-lifecycle)
- [Advanced Topics](#advanced-topics)

---

## KBS::Engine

The core RETE II algorithm engine for in-memory fact processing.

### Constructor

#### `initialize()`

Creates a new in-memory RETE engine.

**Parameters**: None

**Returns**: `KBS::Engine` instance

**Example**:
```ruby
require 'kbs'

engine = KBS::Engine.new
# Engine ready with empty working memory
```

**Internal State Initialized**:
- `@working_memory` - WorkingMemory instance
- `@rules` - Array of registered rules
- `@alpha_memories` - Hash of pattern → AlphaMemory
- `@production_nodes` - Hash of rule name → ProductionNode
- `@root_beta_memory` - Root BetaMemory with dummy token

---

### Public Methods

#### `add_rule(rule)`

Registers a rule and compiles it into the RETE network.

**Parameters**:
- `rule` (Rule) - Rule object with conditions and action

**Returns**: `nil`

**Side Effects**:
- Builds alpha memories for each condition pattern
- Creates join nodes or negation nodes
- Creates beta memories for partial matches
- Creates production node for rule
- Activates existing facts through new network paths

**Example**:
```ruby
rule = KBS::Rule.new(
  name: "high_temperature",
  priority: 10,
  conditions: [
    KBS::Condition.new(:temperature, { location: "server_room" })
  ],
  action: ->(bindings) { puts "Alert: High temperature!" }
)

engine.add_rule(rule)
```

**Using DSL**:
```ruby
kb = KBS.knowledge_base do
  rule "high_temperature", priority: 10 do
    on :temperature, location: "server_room", value: greater_than(80)
    perform do |facts, bindings|
      puts "Alert: #{bindings[:location?]} is #{bindings[:value?]}°F"
    end
  end
end

kb.rules.each { |rule| engine.add_rule(rule) }
```

**Performance Notes**:
- First rule with a pattern creates alpha memory
- Subsequent rules sharing patterns reuse alpha memory (network sharing)
- Cost is O(C) where C is number of conditions in rule

---

#### `add_fact(type, attributes = {})`

Adds a fact to working memory and activates matching alpha memories.

**Parameters**:
- `type` (Symbol) - Fact type (e.g., `:temperature`, `:order`)
- `attributes` (Hash) - Fact attributes (default: `{}`)

**Returns**: `KBS::Fact` - The created fact

**Side Effects**:
- Creates Fact object
- Adds to working memory
- Activates all matching alpha memories
- Propagates through join nodes
- May create new tokens in beta memories

**Example**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)
# => #<KBS::Fact:0x00... @type=:temperature @attributes={...}>

# Facts without attributes
marker = engine.add_fact(:system_ready)
# => #<KBS::Fact:0x00... @type=:system_ready @attributes={}>
```

**Thread Safety**: Not thread-safe. Wrap in mutex if adding facts from multiple threads.

**Performance**: O(A × P) where A is number of alpha memories, P is pattern matching cost

---

#### `remove_fact(fact)`

Removes a fact from working memory and deactivates it in alpha memories.

**Parameters**:
- `fact` (KBS::Fact) - Fact object to remove (must be exact object reference)

**Returns**: `nil`

**Side Effects**:
- Removes from working memory
- Deactivates fact in all alpha memories
- Removes tokens containing this fact
- May cause negation nodes to re-evaluate

**Example**:
```ruby
fact = engine.add_fact(:temperature, value: 85)
engine.remove_fact(fact)

# Common pattern: Store fact reference for later removal
@current_alert = engine.add_fact(:alert, level: "critical")
# Later...
engine.remove_fact(@current_alert) if @current_alert
```

**Important**: You must keep a reference to the fact object to remove it. Finding facts requires inspecting `engine.working_memory.facts`.

**Example - Finding and Removing**:
```ruby
# Find all temperature facts
temp_facts = engine.working_memory.facts.select { |f| f.type == :temperature }

# Remove specific fact
old_fact = temp_facts.find { |f| f[:timestamp] < Time.now - 3600 }
engine.remove_fact(old_fact) if old_fact
```

---

#### `run()`

Executes all activated rules by firing production nodes.

**Parameters**: None

**Returns**: `nil`

**Side Effects**:
- Fires actions for all tokens in production nodes
- Rule actions may add/remove facts
- Rule actions may modify external state

**Example**:
```ruby
engine.add_fact(:temperature, value: 85)
engine.add_fact(:sensor, status: "active")

# Facts are in working memory but rules haven't fired
engine.run  # Execute all matching rules

# Rules fire based on priority (highest first within each production)
```

**Execution Order**:
- Production nodes fire in arbitrary order (dictionary order by rule name)
- Within a production node, tokens fire in insertion order
- For priority-based execution, use `KBS::Blackboard::Engine`

**Example - Multiple Rule Firings**:
```ruby
fired_rules = []

kb = KBS.knowledge_base do
  rule "rule_a", priority: 10 do
    on :temperature, value: greater_than(80)
    perform { fired_rules << "rule_a" }
  end

  rule "rule_b", priority: 20 do
    on :temperature, value: greater_than(80)
    perform { fired_rules << "rule_b" }
  end
end

kb.rules.each { |r| engine.add_rule(r) }
engine.add_fact(:temperature, value: 85)
engine.run

# Both rules fire (priority doesn't affect KBS::Engine execution order)
puts fired_rules  # => ["rule_a", "rule_b"] or ["rule_b", "rule_a"]
```

**Best Practice**: Call `run` after batch adding facts:
```ruby
# Good - batch facts then run once
engine.add_fact(:temperature, value: 85)
engine.add_fact(:humidity, value: 60)
engine.add_fact(:pressure, value: 1013)
engine.run

# Avoid - running after each fact (may fire rules prematurely)
engine.add_fact(:temperature, value: 85)
engine.run  # Rule may fire with incomplete data
engine.add_fact(:humidity, value: 60)
engine.run
```

---

### Public Attributes

#### `working_memory`

**Type**: `KBS::WorkingMemory`

**Read-only**: Yes (via `attr_reader`)

**Description**: The working memory storing all facts.

**Example**:
```ruby
engine.add_fact(:temperature, value: 85)
engine.add_fact(:humidity, value: 60)

# Inspect all facts
puts engine.working_memory.facts.size  # => 2

# Find specific facts
temps = engine.working_memory.facts.select { |f| f.type == :temperature }
temps.each do |fact|
  puts "Temperature: #{fact[:value]}"
end
```

---

#### `rules`

**Type**: `Array<KBS::Rule>`

**Read-only**: Yes (via `attr_reader`)

**Description**: All registered rules.

**Example**:
```ruby
puts "Registered rules:"
engine.rules.each do |rule|
  puts "  - #{rule.name} (priority: #{rule.priority})"
  puts "    Conditions: #{rule.conditions.size}"
end
```

---

#### `alpha_memories`

**Type**: `Hash<Hash, KBS::AlphaMemory>`

**Read-only**: Yes (via `attr_reader`)

**Description**: Pattern → AlphaMemory mapping.

**Example**:
```ruby
# Inspect alpha memories (useful for debugging)
engine.alpha_memories.each do |pattern, memory|
  puts "Pattern: #{pattern}"
  puts "  Facts: #{memory.facts.size}"
  puts "  Successors: #{memory.successors.size}"
end
```

---

#### `production_nodes`

**Type**: `Hash<Symbol, KBS::ProductionNode>`

**Read-only**: Yes (via `attr_reader`)

**Description**: Rule name → ProductionNode mapping.

**Example**:
```ruby
# Check if a rule is activated
prod_node = engine.production_nodes[:high_temperature]
if prod_node && prod_node.tokens.any?
  puts "Rule 'high_temperature' has #{prod_node.tokens.size} activations"
end
```

---

### Observer Pattern

The engine implements the observer pattern to watch fact changes.

#### `update(action, fact)` (Internal)

**Parameters**:
- `action` (Symbol) - `:add` or `:remove`
- `fact` (KBS::Fact) - The fact that changed

**Description**: Called automatically by WorkingMemory when facts change. Activates/deactivates alpha memories.

**Example - Custom Observer**:
```ruby
class FactLogger
  def update(action, fact)
    puts "[#{Time.now}] #{action.upcase}: #{fact.type} #{fact.attributes}"
  end
end

logger = FactLogger.new
engine.working_memory.add_observer(logger)

engine.add_fact(:temperature, value: 85)
# Output: [2025-01-15 10:30:00] ADD: temperature {:value=>85}
```

---

## KBS::Blackboard::Engine

Persistent RETE engine with blackboard memory, audit logging, and message queue.

**Inherits**: `KBS::Engine`

**Key Differences from KBS::Engine**:
- Persistent facts (SQLite, Redis, or Hybrid)
- Audit trail of all fact changes
- Message queue for inter-agent communication
- Transaction support
- Observer notifications
- Rule firing logged with bindings

---

### Constructor

#### `initialize(db_path: ':memory:', store: nil)`

Creates a persistent RETE engine with blackboard memory.

**Parameters**:
- `db_path` (String, optional) - Path to SQLite database (default: `:memory:`)
- `store` (Store, optional) - Custom persistence store (default: `nil`, uses SQLiteStore)

**Returns**: `KBS::Blackboard::Engine` instance

**Example - In-Memory**:
```ruby
engine = KBS::Blackboard::Engine.new
# Blackboard in RAM (lost on exit)
```

**Example - SQLite Persistence**:
```ruby
engine = KBS::Blackboard::Engine.new(db_path: 'knowledge_base.db')
# Facts persisted to knowledge_base.db
```

**Example - Redis Persistence**:
```ruby
require 'kbs/blackboard/persistence/redis_store'

store = KBS::Blackboard::Persistence::RedisStore.new(url: 'redis://localhost:6379/0')
engine = KBS::Blackboard::Engine.new(store: store)
# Fast, distributed persistence
```

**Example - Hybrid Persistence**:
```ruby
require 'kbs/blackboard/persistence/hybrid_store'

store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',
  db_path: 'audit.db'
)
engine = KBS::Blackboard::Engine.new(store: store)
# Facts in Redis, audit trail in SQLite
```

---

### Public Methods

#### `add_fact(type, attributes = {})`

Adds a persistent fact to the blackboard.

**Parameters**:
- `type` (Symbol) - Fact type
- `attributes` (Hash) - Fact attributes

**Returns**: `KBS::Blackboard::Fact` - Persistent fact with UUID

**Side Effects**:
- Creates fact with UUID
- Saves to persistent store
- Logs to audit trail
- Activates alpha memories
- Notifies observers

**Example**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)
puts fact.uuid  # => "550e8400-e29b-41d4-a716-446655440000"

# Fact persists across restarts
engine2 = KBS::Blackboard::Engine.new(db_path: 'knowledge_base.db')
reloaded_facts = engine2.blackboard.get_facts_by_type(:temperature)
puts reloaded_facts.first[:value]  # => 85
```

**Difference from KBS::Engine**: Returns `KBS::Blackboard::Fact` (has `.uuid`) instead of `KBS::Fact`.

---

#### `remove_fact(fact)`

Removes a persistent fact from the blackboard.

**Parameters**:
- `fact` (KBS::Blackboard::Fact) - Fact to remove

**Returns**: `nil`

**Side Effects**:
- Marks fact as inactive in store
- Logs removal to audit trail
- Deactivates in alpha memories
- Notifies observers

**Example**:
```ruby
fact = engine.add_fact(:temperature, value: 85)
engine.remove_fact(fact)

# Fact marked inactive but remains in audit trail
audit = engine.blackboard.audit_log.get_fact_history(fact.uuid)
puts audit.last[:action]  # => "retract"
```

---

#### `run()`

Executes activated rules with audit logging.

**Parameters**: None

**Returns**: `nil`

**Side Effects**:
- Fires rules in production nodes
- Logs each rule firing to audit trail
- Records fact UUIDs and variable bindings
- Marks tokens as fired (prevents duplicate firing)

**Example**:
```ruby
engine.add_rule(my_rule)
engine.add_fact(:temperature, value: 85)
engine.run

# Check audit log
engine.blackboard.audit_log.entries.each do |entry|
  next unless entry[:event_type] == "rule_fired"
  puts "Rule #{entry[:rule_name]} fired with bindings: #{entry[:bindings]}"
end
```

**Difference from KBS::Engine**:
- Logs every rule firing
- Prevents duplicate firing of same token
- Records variable bindings in audit

---

#### `post_message(sender, topic, content, priority: 0)`

Posts a message to the blackboard message queue.

**Parameters**:
- `sender` (String) - Sender identifier (e.g., agent name)
- `topic` (String) - Message topic (channel)
- `content` (Hash) - Message payload
- `priority` (Integer, optional) - Message priority (default: 0, higher = more urgent)

**Returns**: `nil`

**Side Effects**:
- Adds message to queue
- Persists to store
- Higher priority messages consumed first

**Example**:
```ruby
# Agent 1 posts message
engine.post_message(
  "trading_agent",
  "orders",
  { action: "buy", symbol: "AAPL", quantity: 100 },
  priority: 10
)

# Agent 2 consumes message
msg = engine.consume_message("orders", "execution_agent")
puts msg[:content][:action]  # => "buy"
puts msg[:sender]  # => "trading_agent"
```

**Use Cases**:
- Inter-agent communication
- Command/event bus
- Task queues
- Priority-based scheduling

---

#### `consume_message(topic, consumer)`

Retrieves and removes the highest priority message from a topic.

**Parameters**:
- `topic` (String) - Topic to consume from
- `consumer` (String) - Consumer identifier (for audit trail)

**Returns**: `Hash` or `nil` - Message hash with `:id`, `:sender`, `:topic`, `:content`, `:priority`, `:timestamp`, or `nil` if queue empty

**Side Effects**:
- Removes message from queue
- Logs consumption to audit trail (if store supports it)

**Example**:
```ruby
# Consumer loop
loop do
  msg = engine.consume_message("tasks", "worker_1")
  break unless msg

  puts "Processing: #{msg[:content][:task_name]} (priority #{msg[:priority]})"
  # Process message...
end
```

**Thread Safety**: Atomic pop operation (PostgreSQL/Redis stores support concurrent consumers)

---

#### `stats()`

Returns blackboard statistics.

**Parameters**: None

**Returns**: `Hash` with keys:
- `:facts_count` (Integer) - Number of active facts
- `:messages_count` (Integer) - Number of queued messages (all topics)
- `:audit_entries_count` (Integer) - Total audit log entries

**Example**:
```ruby
stats = engine.stats
puts "Facts: #{stats[:facts_count]}"
puts "Messages: #{stats[:messages_count]}"
puts "Audit entries: #{stats[:audit_entries_count]}"
```

**Performance**: May be slow for large databases (counts all rows)

---

### Public Attributes

#### `blackboard`

**Type**: `KBS::Blackboard::Memory`

**Read-only**: Yes (via `attr_reader`)

**Description**: The blackboard memory (also accessible as `working_memory`).

**Example**:
```ruby
# Access blackboard components
engine.blackboard.message_queue.post("agent1", "alerts", { alert: "critical" })
engine.blackboard.audit_log.entries.last
engine.blackboard.transaction { engine.add_fact(:order, status: "pending") }

# Get facts by type
temps = engine.blackboard.get_facts_by_type(:temperature)
```

---

## Engine Lifecycle

### Typical Flow

```ruby
# 1. Create engine
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')

# 2. Define and register rules
kb = KBS.knowledge_base do
  rule "high_temp_alert", priority: 10 do
    on :temperature, value: greater_than(80)
    perform do |facts, bindings|
      puts "Alert! Temperature: #{bindings[:value?]}"
    end
  end
end
kb.rules.each { |r| engine.add_rule(r) }

# 3. Add initial facts
engine.add_fact(:sensor, id: 1, status: "active")

# 4. Main loop
loop do
  # Collect new data
  temp = read_temperature_sensor
  engine.add_fact(:temperature, value: temp, timestamp: Time.now)

  # Execute rules
  engine.run

  # Process messages
  while msg = engine.consume_message("tasks", "main_loop")
    handle_task(msg[:content])
  end

  sleep 5
end
```

---

### Restart and Recovery

```ruby
# Session 1 - Add facts
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')
engine.add_fact(:account, id: 1, balance: 1000)
# Exit

# Session 2 - Facts still present
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')
accounts = engine.blackboard.get_facts_by_type(:account)
puts accounts.first[:balance]  # => 1000

# BUT: Rules must be re-registered (not persisted)
kb = load_rules
kb.rules.each { |r| engine.add_rule(r) }
```

**Important**: Only facts persist. Rules, alpha memories, and RETE network must be rebuilt on restart.

---

### Transaction Example

```ruby
engine.blackboard.transaction do
  fact1 = engine.add_fact(:order, id: 1, status: "pending")
  fact2 = engine.add_fact(:inventory, item: "ABC", quantity: 100)

  # If error occurs here, both facts are rolled back
  raise "Validation failed" if invalid_order?(fact1)
end
```

**Database Support**: SQLite and PostgreSQL support ACID transactions. Redis and MongoDB require custom transaction logic.

---

## Advanced Topics

### Network Sharing

Multiple rules sharing condition patterns reuse alpha memories:

```ruby
# Both rules share the :temperature alpha memory
rule "high_temp_alert" do
  on :temperature, value: greater_than(80)
  perform { puts "High temperature!" }
end

rule "critical_temp_alert" do
  on :temperature, value: greater_than(100)
  perform { puts "CRITICAL temperature!" }
end

# Only 1 alpha memory created for :temperature
# Pattern matching happens once per fact
```

---

### Inspecting the RETE Network

```ruby
# Dump alpha memories
engine.alpha_memories.each do |pattern, memory|
  puts "Pattern: #{pattern.inspect}"
  puts "  Facts in alpha memory: #{memory.facts.size}"
  puts "  Successor nodes: #{memory.successors.size}"
  memory.successors.each do |succ|
    puts "    #{succ.class.name}"
  end
end

# Dump production nodes
engine.production_nodes.each do |name, node|
  puts "Rule: #{name}"
  puts "  Tokens (activations): #{node.tokens.size}"
  node.tokens.each do |token|
    puts "    Token with #{token.facts.size} facts"
  end
end
```

**Use Case**: Debugging why a rule didn't fire

---

### Custom Working Memory Observer

```ruby
class MetricsCollector
  def initialize
    @fact_count = 0
    @retract_count = 0
  end

  def update(action, fact)
    case action
    when :add
      @fact_count += 1
    when :remove
      @retract_count += 1
    end
  end

  def report
    puts "Facts added: #{@fact_count}"
    puts "Facts retracted: #{@retract_count}"
  end
end

metrics = MetricsCollector.new
engine.working_memory.add_observer(metrics)

# Run engine...
engine.add_fact(:temperature, value: 85)
engine.remove_fact(fact)

metrics.report
# => Facts added: 1
# => Facts retracted: 1
```

---

### Programmatic Rule Creation

```ruby
# Without DSL - manual Rule object
condition = KBS::Condition.new(:temperature, { value: -> (v) { v > 80 } })
action = ->(bindings) { puts "High temperature detected" }
rule = KBS::Rule.new(name: "high_temp", priority: 10, conditions: [condition], action: action)

engine.add_rule(rule)
```

**When to Use**: Dynamically generating rules at runtime based on configuration.

---

### Engine Composition

```ruby
# Multiple engines with different rule sets
class MonitoringSystem
  def initialize
    @temperature_engine = KBS::Blackboard::Engine.new(db_path: 'temp.db')
    @security_engine = KBS::Blackboard::Engine.new(db_path: 'security.db')

    setup_temperature_rules(@temperature_engine)
    setup_security_rules(@security_engine)
  end

  def process_sensor_data(data)
    if data[:type] == :temperature
      @temperature_engine.add_fact(:temperature, data)
      @temperature_engine.run
    elsif data[:type] == :motion
      @security_engine.add_fact(:motion, data)
      @security_engine.run
    end
  end
end
```

**Use Case**: Separating concerns across multiple knowledge bases

---

## Performance Considerations

### Rule Ordering

Rules are added to `@rules` array in registration order, but execution order depends on when tokens reach production nodes.

```ruby
# Both rules activated by same fact
engine.add_rule(rule_a)  # Registered first
engine.add_rule(rule_b)  # Registered second

engine.add_fact(:temperature, value: 85)
engine.run
# Both fire, but order is unpredictable in KBS::Engine
# Use KBS::Blackboard::Engine with priority for deterministic order
```

---

### Fact Batching

```ruby
# Efficient - batch facts then run once
facts_to_add.each do |data|
  engine.add_fact(:sensor_reading, data)
end
engine.run  # All rules see complete dataset

# Inefficient - run after each fact
facts_to_add.each do |data|
  engine.add_fact(:sensor_reading, data)
  engine.run  # May fire rules prematurely
end
```

---

### Memory Growth

```ruby
# Clean up old facts to prevent memory growth
cutoff_time = Time.now - 3600  # 1 hour ago
old_facts = engine.working_memory.facts.select do |fact|
  fact[:timestamp] && fact[:timestamp] < cutoff_time
end

old_facts.each { |f| engine.remove_fact(f) }
```

**Production Pattern**: Implement fact expiration in a cleanup rule:

```ruby
rule "expire_old_facts", priority: 0 do
  on :temperature, timestamp: ->(ts) { Time.now - ts > 3600 }
  perform do |facts, bindings|
    fact = bindings[:matched_fact?]
    engine.remove_fact(fact)
  end
end
```

---

## Error Handling

### Rule Action Errors

```ruby
rule "risky_operation" do
  on :task, status: "pending"
  perform do |facts, bindings|
    begin
      perform_risky_operation(bindings[:task_id?])
    rescue => e
      # Log error
      puts "Error in rule: #{e.message}"

      # Add error fact for other rules to handle
      engine.add_fact(:error, rule: "risky_operation", message: e.message)
    end
  end
end
```

---

### Store Connection Errors

```ruby
begin
  engine = KBS::Blackboard::Engine.new(db_path: '/invalid/path/kb.db')
rescue Errno::EACCES => e
  puts "Cannot access database: #{e.message}"
  # Fallback to in-memory
  engine = KBS::Blackboard::Engine.new
end
```

---

## Thread Safety

**KBS::Engine and KBS::Blackboard::Engine are NOT thread-safe.**

For multi-threaded access:

```ruby
require 'thread'

class ThreadSafeEngine
  def initialize(*args)
    @engine = KBS::Blackboard::Engine.new(*args)
    @mutex = Mutex.new
  end

  def add_fact(*args)
    @mutex.synchronize { @engine.add_fact(*args) }
  end

  def run
    @mutex.synchronize { @engine.run }
  end
end
```

**Better Approach**: Use one engine per thread or message passing between threads.

---

## See Also

- [Facts API](facts.md) - Working with fact objects
- [Rules API](rules.md) - Rule and Condition objects
- [Blackboard API](blackboard.md) - Memory, MessageQueue, AuditLog
- [DSL Guide](../guides/dsl.md) - Rule definition syntax
- [Performance Guide](../advanced/performance.md) - Optimization strategies
