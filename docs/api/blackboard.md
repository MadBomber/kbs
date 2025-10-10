# Blackboard API Reference

Complete API reference for blackboard memory classes.

## Table of Contents

- [KBS::Blackboard::Memory](#kbsblackboardmemory) - Central blackboard workspace
- [KBS::Blackboard::MessageQueue](#kbsblackboardmessagequeue) - Inter-agent communication
- [KBS::Blackboard::AuditLog](#kbsblackboardauditlog) - Historical tracking
- [Usage Patterns](#usage-patterns)

---

## KBS::Blackboard::Memory

The central blackboard workspace that coordinates facts, messages, and audit logging.

**Architecture**: Composes three components:
1. **Store** - Persistence layer (SQLite, Redis, or Hybrid)
2. **MessageQueue** - Priority-based inter-agent messaging
3. **AuditLog** - Complete history of fact changes and rule firings

---

### Constructor

#### `initialize(db_path: ':memory:', store: nil)`

Creates a new blackboard memory.

**Parameters**:
- `db_path` (String, optional) - Path to SQLite database (default: `:memory:`)
- `store` (KBS::Blackboard::Persistence::Store, optional) - Custom store (default: `nil`, creates SQLiteStore)

**Returns**: `KBS::Blackboard::Memory` instance

**Side Effects**:
- Generates session UUID
- Creates or connects to persistence store
- Initializes message queue and audit log
- Sets up database tables/indexes

**Example - In-Memory**:
```ruby
memory = KBS::Blackboard::Memory.new
# Blackboard stored in RAM (lost on exit)
```

**Example - SQLite Persistence**:
```ruby
memory = KBS::Blackboard::Memory.new(db_path: 'knowledge_base.db')
# Facts persisted to knowledge_base.db
```

**Example - Redis Store**:
```ruby
require 'kbs/blackboard/persistence/redis_store'

store = KBS::Blackboard::Persistence::RedisStore.new(url: 'redis://localhost:6379/0')
memory = KBS::Blackboard::Memory.new(store: store)
# Fast, distributed persistence
```

**Example - Hybrid Store**:
```ruby
require 'kbs/blackboard/persistence/hybrid_store'

store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',
  db_path: 'audit.db'
)
memory = KBS::Blackboard::Memory.new(store: store)
# Facts in Redis, audit trail in SQLite
```

---

### Public Attributes

#### `session_id`

**Type**: `String`

**Read-only**: Yes (via `attr_reader`)

**Description**: Unique session identifier (UUID)

**Example**:
```ruby
memory = KBS::Blackboard::Memory.new
puts memory.session_id  # => "550e8400-e29b-41d4-a716-446655440000"
```

**Use Cases**:
- Filter audit log by session
- Separate facts from different runs
- Debugging multi-session scenarios

---

#### `store`

**Type**: `KBS::Blackboard::Persistence::Store`

**Read-only**: Yes (via `attr_reader`)

**Description**: The underlying persistence store

**Example**:
```ruby
memory = KBS::Blackboard::Memory.new(db_path: 'kb.db')
puts memory.store.class  # => KBS::Blackboard::Persistence::SqliteStore
```

---

#### `message_queue`

**Type**: `KBS::Blackboard::MessageQueue`

**Read-only**: Yes (via `attr_reader`)

**Description**: The message queue for inter-agent communication

**Example**:
```ruby
memory.message_queue.post("agent1", "alerts", { level: "critical" })
```

---

#### `audit_log`

**Type**: `KBS::Blackboard::AuditLog`

**Read-only**: Yes (via `attr_reader`)

**Description**: The audit log for tracking all changes

**Example**:
```ruby
history = memory.audit_log.fact_history(fact.uuid)
```

---

### Fact Management Methods

#### `add_fact(type, attributes = {})`

Adds a persistent fact to the blackboard.

**Parameters**:
- `type` (Symbol) - Fact type
- `attributes` (Hash, optional) - Fact attributes (default: `{}`)

**Returns**: `KBS::Blackboard::Fact` - Persistent fact with UUID

**Side Effects**:
- Generates UUID for fact
- Saves fact to store (within transaction)
- Logs addition to audit log
- Notifies observers

**Example**:
```ruby
fact = memory.add_fact(:temperature, location: "server_room", value: 85)
puts fact.uuid  # => "550e8400-e29b-41d4-a716-446655440000"
puts fact.type  # => :temperature
puts fact[:value]  # => 85
```

**Transaction Handling**:
```ruby
memory.transaction do
  fact1 = memory.add_fact(:order, id: 1, status: "pending")
  fact2 = memory.add_fact(:inventory, item: "ABC", quantity: 100)
  # Both facts committed together
end
```

---

#### `remove_fact(fact)`

Removes a fact from the blackboard.

**Parameters**:
- `fact` (KBS::Blackboard::Fact or String) - Fact object or UUID

**Returns**: `nil`

**Side Effects**:
- Marks fact as inactive in store
- Logs removal to audit log
- Notifies observers

**Example**:
```ruby
fact = memory.add_fact(:temperature, value: 85)
memory.remove_fact(fact)

# Or by UUID
memory.remove_fact("550e8400-e29b-41d4-a716-446655440000")

# Fact remains in audit log
history = memory.get_history(fact.uuid)
puts history.last[:action]  # => "REMOVE"
```

---

#### `update_fact(fact, new_attributes)`

Updates a fact's attributes.

**Parameters**:
- `fact` (KBS::Blackboard::Fact or String) - Fact object or UUID
- `new_attributes` (Hash) - New attributes to merge

**Returns**: `nil`

**Side Effects**:
- Updates fact in store
- Logs update to audit log

**Example**:
```ruby
fact = memory.add_fact(:temperature, location: "server_room", value: 85)
memory.update_fact(fact, value: 90, timestamp: Time.now)

# Or by UUID
memory.update_fact(fact.uuid, value: 95)
```

**Note**: Updates do NOT notify observers or trigger rule re-evaluation. For that, retract and re-add the fact.

---

#### `get_facts(type = nil, pattern = {})`

Retrieves facts from the blackboard.

**Parameters**:
- `type` (Symbol, optional) - Filter by fact type (default: `nil`, all types)
- `pattern` (Hash, optional) - Additional attribute filters (default: `{}`)

**Returns**: `Array<KBS::Blackboard::Fact>`

**Example**:
```ruby
# Get all facts
all_facts = memory.get_facts

# Get all temperature facts
temps = memory.get_facts(:temperature)

# Get temperature facts from specific location
server_temps = memory.get_facts(:temperature, location: "server_room")
```

**Performance**: O(N) where N = total facts (uses linear scan). For large datasets, consider `query_facts`.

---

#### `facts`

Alias for `get_facts()`. Returns all facts.

**Returns**: `Array<KBS::Blackboard::Fact>`

**Example**:
```ruby
puts "Total facts: #{memory.facts.size}"
```

---

#### `query_facts(sql_conditions = nil, params = [])`

Advanced SQL query for facts (SQLite store only).

**Parameters**:
- `sql_conditions` (String, optional) - SQL WHERE clause (default: `nil`)
- `params` (Array, optional) - Parameters for SQL query (default: `[]`)

**Returns**: `Array<KBS::Blackboard::Fact>`

**Example**:
```ruby
# Query with SQL condition
high_temps = memory.query_facts(
  "fact_type = ? AND json_extract(attributes, '$.value') > ?",
  [:temperature, 80]
)

# Complex query
recent_errors = memory.query_facts(
  "fact_type = ? AND datetime(json_extract(attributes, '$.timestamp')) > datetime(?)",
  [:error, (Time.now - 3600).iso8601]
)
```

**Important**: Only works with SQLite stores. Redis stores will raise NotImplementedError.

---

### Message Queue Methods

#### `post_message(sender, topic, content, priority: 0)`

Posts a message to the blackboard message queue.

**Parameters**:
- `sender` (String) - Sender identifier (e.g., agent name)
- `topic` (String) - Message topic (channel/category)
- `content` (Hash) - Message payload
- `priority` (Integer, optional) - Message priority (default: 0, higher = more urgent)

**Returns**: `nil`

**Side Effects**:
- Adds message to queue
- Persists to store

**Example**:
```ruby
# Post high-priority alert
memory.post_message(
  "temperature_agent",
  "alerts",
  { level: "critical", value: 110, location: "server_room" },
  priority: 100
)

# Post normal-priority task
memory.post_message(
  "scheduler",
  "tasks",
  { task_name: "cleanup", params: {} },
  priority: 10
)
```

**Message Ordering**: Messages consumed in priority order (highest first), then FIFO within same priority.

---

#### `consume_message(topic, consumer)`

Retrieves and removes the highest priority message from a topic.

**Parameters**:
- `topic` (String) - Topic to consume from
- `consumer` (String) - Consumer identifier (for audit trail)

**Returns**: `Hash` or `nil` - Message hash with `:id`, `:sender`, `:topic`, `:content`, `:priority`, `:posted_at`, or `nil` if queue empty

**Side Effects**:
- Removes message from queue (atomic operation)
- Marks message as consumed
- Records consumer and consumption timestamp

**Example**:
```ruby
# Consumer loop
loop do
  msg = memory.consume_message("tasks", "worker_1")
  break unless msg

  puts "Processing: #{msg[:content][:task_name]} (priority #{msg[:priority]})"
  puts "Sent by: #{msg[:sender]} at #{msg[:posted_at]}"

  # Process message...
  process_task(msg[:content])
end
```

**Thread Safety**: Atomic pop (safe for concurrent consumers with PostgreSQL/Redis).

---

#### `peek_messages(topic, limit: 10)`

Views messages in queue without consuming them.

**Parameters**:
- `topic` (String) - Topic to peek
- `limit` (Integer, optional) - Max messages to return (default: 10)

**Returns**: `Array<Hash>` - Array of message hashes (same format as `consume_message`)

**Example**:
```ruby
# Check queue depth
pending = memory.peek_messages("tasks", limit: 100)
puts "Pending tasks: #{pending.size}"

# Inspect high-priority messages
pending.each do |msg|
  if msg[:priority] > 50
    puts "High priority: #{msg[:content][:task_name]}"
  end
end
```

**Use Cases**:
- Monitor queue depth
- Inspect waiting messages
- Debugging message flow

---

### Audit Log Methods

#### `log_rule_firing(rule_name, fact_uuids, bindings = {})`

Logs a rule firing event.

**Parameters**:
- `rule_name` (String) - Name of fired rule
- `fact_uuids` (Array<String>) - UUIDs of facts that matched
- `bindings` (Hash, optional) - Variable bindings (default: `{}`)

**Returns**: `nil`

**Side Effects**:
- Adds entry to audit log
- Records timestamp and session ID

**Example**:
```ruby
# Typically called by engine, but can be called manually
memory.log_rule_firing(
  "high_temperature_alert",
  [fact1.uuid, fact2.uuid],
  { :temp? => 85, :location? => "server_room" }
)
```

**Note**: `KBS::Blackboard::Engine` calls this automatically. Manual calls useful for custom logging.

---

#### `get_history(fact_uuid = nil, limit: 100)`

Retrieves fact change history.

**Parameters**:
- `fact_uuid` (String, optional) - Filter by fact UUID (default: `nil`, all facts)
- `limit` (Integer, optional) - Max entries to return (default: 100)

**Returns**: `Array<Hash>` - Array of history entries with `:fact_uuid`, `:fact_type`, `:attributes`, `:action`, `:timestamp`, `:session_id`

**Example**:
```ruby
# Get history for specific fact
fact = memory.add_fact(:temperature, value: 85)
memory.update_fact(fact, value: 90)
memory.update_fact(fact, value: 95)

history = memory.get_history(fact.uuid)
history.each do |entry|
  puts "#{entry[:timestamp]}: #{entry[:action]} - #{entry[:attributes][:value]}"
end

# Output:
# 2025-01-15 10:30:03: UPDATE - 95
# 2025-01-15 10:30:02: UPDATE - 90
# 2025-01-15 10:30:00: ADD - 85
```

**All Facts History**:
```ruby
# Get recent changes across all facts
recent_changes = memory.get_history(limit: 50)
```

---

#### `get_rule_firings(rule_name = nil, limit: 100)`

Retrieves rule firing history.

**Parameters**:
- `rule_name` (String, optional) - Filter by rule name (default: `nil`, all rules)
- `limit` (Integer, optional) - Max entries to return (default: 100)

**Returns**: `Array<Hash>` - Array of firing entries with `:rule_name`, `:fact_uuids`, `:bindings`, `:fired_at`, `:session_id`

**Example**:
```ruby
# Get firings for specific rule
firings = memory.get_rule_firings("high_temperature_alert", limit: 10)
firings.each do |firing|
  puts "#{firing[:fired_at]}: #{firing[:rule_name]}"
  puts "  Bindings: #{firing[:bindings]}"
  puts "  Facts: #{firing[:fact_uuids]}"
end

# All rule firings
all_firings = memory.get_rule_firings(limit: 100)
```

**Use Cases**:
- Debugging rule behavior
- Performance analysis
- Compliance auditing

---

### Knowledge Source Methods

#### `register_knowledge_source(name, description: nil, topics: [])`

Registers an agent/knowledge source.

**Parameters**:
- `name` (String) - Knowledge source name
- `description` (String, optional) - Description (default: `nil`)
- `topics` (Array<String>, optional) - Topics this source produces/consumes (default: `[]`)

**Returns**: `nil`

**Side Effects**:
- Stores knowledge source metadata in database

**Example**:
```ruby
memory.register_knowledge_source(
  "TemperatureMonitor",
  description: "Monitors temperature sensors and generates alerts",
  topics: ["temperature_readings", "alerts"]
)

memory.register_knowledge_source(
  "AlertDispatcher",
  description: "Dispatches alerts to external systems",
  topics: ["alerts"]
)
```

**Use Cases**:
- Document multi-agent systems
- Visualize agent architecture
- Track message flow

---

### Observer Pattern Methods

#### `add_observer(observer)`

Registers an observer to receive fact change notifications.

**Parameters**:
- `observer` - Object responding to `update(action, fact)` method

**Returns**: `nil`

**Side Effects**: Adds observer to internal observers list

**Example**:
```ruby
class FactLogger
  def update(action, fact)
    case action
    when :add
      puts "Added: #{fact.type} #{fact.attributes}"
    when :remove
      puts "Removed: #{fact.uuid}"
    end
  end
end

logger = FactLogger.new
memory.add_observer(logger)

memory.add_fact(:temperature, value: 85)
# Output: Added: temperature {:value=>85}
```

**Important**: Observers are NOT persisted. Re-register after restart.

---

### Session Management Methods

#### `clear_session`

Removes all facts from current session.

**Parameters**: None

**Returns**: `nil`

**Side Effects**:
- Removes facts with matching session_id
- Preserves audit log

**Example**:
```ruby
# Add facts
memory.add_fact(:temperature, value: 85)
memory.add_fact(:humidity, value: 60)

# Clear session facts
memory.clear_session

# Facts removed, but audit log intact
puts memory.facts.size  # => 0
puts memory.get_history.size  # => 2 (ADD entries still present)
```

---

#### `transaction(&block)`

Executes block within database transaction.

**Parameters**:
- `&block` - Block to execute

**Returns**: Result of block

**Side Effects**:
- Begins transaction
- Executes block
- Commits on success
- Rolls back on exception

**Example**:
```ruby
memory.transaction do
  fact1 = memory.add_fact(:order, id: 1, total: 100)
  fact2 = memory.add_fact(:inventory, item: "ABC", quantity: 10)

  # If this raises, both facts are rolled back
  raise "Validation failed" if fact1[:total] > 1000
end
```

**Nested Transactions**: Supported (SQLite uses savepoints).

---

### Statistics Methods

#### `stats`

Returns blackboard statistics.

**Parameters**: None

**Returns**: `Hash` with keys:
- `:facts_count` (Integer) - Active facts
- `:total_messages` (Integer) - Total messages (consumed + unconsumed)
- `:unconsumed_messages` (Integer) - Unconsumed messages
- `:rules_fired` (Integer) - Total rule firings

**Example**:
```ruby
stats = memory.stats
puts "Facts: #{stats[:facts_count]}"
puts "Messages (unconsumed): #{stats[:unconsumed_messages]}"
puts "Messages (total): #{stats[:total_messages]}"
puts "Rules fired: #{stats[:rules_fired]}"
```

---

### Maintenance Methods

#### `vacuum`

Optimizes database storage (SQLite only).

**Parameters**: None

**Returns**: `nil`

**Side Effects**: Reclaims unused database space

**Example**:
```ruby
# After deleting many facts
memory.vacuum
```

**When to Use**: After bulk deletions or periodically for long-running systems.

---

#### `close`

Closes database connection.

**Parameters**: None

**Returns**: `nil`

**Side Effects**: Closes connection to store

**Example**:
```ruby
memory = KBS::Blackboard::Memory.new(db_path: 'kb.db')
# ... use memory ...
memory.close
```

**Important**: Required for proper cleanup. Use `ensure` block:
```ruby
memory = KBS::Blackboard::Memory.new(db_path: 'kb.db')
begin
  # ... use memory ...
ensure
  memory.close
end
```

---

## KBS::Blackboard::MessageQueue

Priority-based message queue for inter-agent communication.

**Typically accessed via**: `memory.message_queue` or `memory.post_message()` / `memory.consume_message()`

### Methods

#### `post(sender, topic, content, priority: 0)`

Posts a message to the queue.

**Parameters**:
- `sender` (String) - Sender identifier
- `topic` (String) - Message topic
- `content` (Hash or String) - Message payload (auto-converts to JSON)
- `priority` (Integer, optional) - Priority (default: 0)

**Returns**: `nil`

**Example**:
```ruby
memory.message_queue.post("agent1", "alerts", { alert: "critical" }, priority: 100)
```

---

#### `consume(topic, consumer)`

Consumes highest priority message from topic.

**Parameters**:
- `topic` (String) - Topic to consume from
- `consumer` (String) - Consumer identifier

**Returns**: `Hash` or `nil`

**Example**:
```ruby
msg = memory.message_queue.consume("tasks", "worker_1")
puts msg[:content] if msg
```

---

#### `peek(topic, limit: 10)`

Views messages without consuming.

**Parameters**:
- `topic` (String) - Topic to peek
- `limit` (Integer, optional) - Max messages (default: 10)

**Returns**: `Array<Hash>`

**Example**:
```ruby
pending = memory.message_queue.peek("tasks", limit: 5)
puts "Next #{pending.size} tasks:"
pending.each { |m| puts "  - #{m[:content]}" }
```

---

#### `stats`

Returns queue statistics.

**Returns**: `Hash` with `:total_messages`, `:unconsumed_messages`

**Example**:
```ruby
stats = memory.message_queue.stats
puts "Queue depth: #{stats[:unconsumed_messages]}"
```

---

## KBS::Blackboard::AuditLog

Complete audit trail of all fact changes and rule firings.

**Typically accessed via**: `memory.audit_log` or `memory.get_history()` / `memory.get_rule_firings()`

### Methods

#### `log_fact_change(fact_uuid, fact_type, attributes, action)`

Logs a fact change event.

**Parameters**:
- `fact_uuid` (String) - Fact UUID
- `fact_type` (Symbol) - Fact type
- `attributes` (Hash) - Fact attributes
- `action` (String) - Action: "ADD", "UPDATE", "REMOVE"

**Returns**: `nil`

**Example**:
```ruby
memory.audit_log.log_fact_change(
  fact.uuid,
  :temperature,
  { value: 85 },
  'ADD'
)
```

**Note**: Automatically called by Memory. Manual calls useful for custom tracking.

---

#### `log_rule_firing(rule_name, fact_uuids, bindings = {})`

Logs a rule firing event.

**Parameters**:
- `rule_name` (String) - Rule name
- `fact_uuids` (Array<String>) - Matched fact UUIDs
- `bindings` (Hash, optional) - Variable bindings (default: `{}`)

**Returns**: `nil`

**Example**:
```ruby
memory.audit_log.log_rule_firing(
  "high_temp_alert",
  [fact1.uuid, fact2.uuid],
  { :temp? => 85 }
)
```

---

#### `fact_history(fact_uuid = nil, limit: 100)`

Retrieves fact change history.

**Parameters**:
- `fact_uuid` (String, optional) - Filter by UUID (default: `nil`)
- `limit` (Integer, optional) - Max entries (default: 100)

**Returns**: `Array<Hash>`

**Example**:
```ruby
history = memory.audit_log.fact_history(fact.uuid, limit: 10)
```

---

#### `rule_firings(rule_name = nil, limit: 100)`

Retrieves rule firing history.

**Parameters**:
- `rule_name` (String, optional) - Filter by rule name (default: `nil`)
- `limit` (Integer, optional) - Max entries (default: 100)

**Returns**: `Array<Hash>`

**Example**:
```ruby
firings = memory.audit_log.rule_firings("my_rule", limit: 50)
```

---

#### `stats`

Returns audit log statistics.

**Returns**: `Hash` with `:rules_fired`

**Example**:
```ruby
stats = memory.audit_log.stats
puts "Total rule firings: #{stats[:rules_fired]}"
```

---

## Usage Patterns

### 1. Multi-Agent Coordination

```ruby
# Setup
memory = KBS::Blackboard::Memory.new(db_path: 'agents.db')

# Agent 1 - Temperature Monitor
memory.register_knowledge_source(
  "TempMonitor",
  description: "Monitors temperature sensors",
  topics: ["sensors", "alerts"]
)

def monitor_loop(memory)
  loop do
    temp = read_sensor
    fact = memory.add_fact(:temperature, value: temp, timestamp: Time.now)

    if temp > 80
      memory.post_message(
        "TempMonitor",
        "alerts",
        { type: "high_temp", value: temp },
        priority: 50
      )
    end

    sleep 5
  end
end

# Agent 2 - Alert Dispatcher
memory.register_knowledge_source(
  "AlertDispatcher",
  description: "Sends alerts to external systems",
  topics: ["alerts"]
)

def dispatch_loop(memory)
  loop do
    msg = memory.consume_message("alerts", "AlertDispatcher")
    break unless msg

    case msg[:content][:type]
    when "high_temp"
      send_email_alert(msg[:content][:value])
    end
  end
end
```

---

### 2. Audit Trail Analysis

```ruby
# Find facts that were updated multiple times
memory.get_history(limit: 1000).group_by { |e| e[:fact_uuid] }.each do |uuid, entries|
  if entries.size > 5
    puts "Fact #{uuid} changed #{entries.size} times"
    entries.each do |entry|
      puts "  #{entry[:timestamp]}: #{entry[:action]} - #{entry[:attributes]}"
    end
  end
end
```

---

### 3. Rule Performance Analysis

```ruby
# Analyze rule firing frequency
firings = memory.get_rule_firings(limit: 10000)
by_rule = firings.group_by { |f| f[:rule_name] }

by_rule.each do |rule_name, firings_list|
  puts "#{rule_name}: #{firings_list.size} firings"

  # Calculate average time between firings
  if firings_list.size > 1
    times = firings_list.map { |f| f[:fired_at] }.sort
    intervals = times.each_cons(2).map { |t1, t2| (t2 - t1).to_f }
    avg_interval = intervals.sum / intervals.size
    puts "  Avg interval: #{avg_interval.round(2)} seconds"
  end
end
```

---

### 4. Transaction-Based Workflows

```ruby
def process_order(memory, order_data)
  memory.transaction do
    # Add order fact
    order = memory.add_fact(:order, order_data)

    # Check inventory
    inventory = memory.get_facts(:inventory, product_id: order[:product_id]).first
    raise "Insufficient inventory" if inventory[:quantity] < order[:quantity]

    # Deduct inventory
    memory.update_fact(inventory, quantity: inventory[:quantity] - order[:quantity])

    # Create shipment fact
    shipment = memory.add_fact(:shipment, order_id: order.uuid, status: "pending")

    # Post message for shipping agent
    memory.post_message(
      "OrderProcessor",
      "shipments",
      { shipment_id: shipment.uuid },
      priority: 10
    )

    # If any step fails, entire transaction rolls back
  end
end
```

---

### 5. Debugging Message Flow

```ruby
# Monitor message queue
def monitor_queue(memory, topic)
  loop do
    pending = memory.peek_messages(topic, limit: 10)
    puts "#{Time.now}: #{pending.size} messages in #{topic} queue"

    pending.each do |msg|
      age = Time.now - msg[:posted_at]
      puts "  [#{msg[:priority]}] #{msg[:sender]}: #{msg[:content]} (#{age.round}s old)"
    end

    sleep 5
  end
end
```

---

### 6. Session Isolation

```ruby
# Separate test runs
test_memory = KBS::Blackboard::Memory.new(db_path: 'test.db')
puts "Session: #{test_memory.session_id}"

# Run test
test_memory.add_fact(:test_marker, run_id: 1)
run_tests(test_memory)

# Cleanup session (preserves audit log)
test_memory.clear_session

# Analyze audit log across sessions
all_history = test_memory.get_history(limit: 10000)
by_session = all_history.group_by { |e| e[:session_id] }
puts "Total sessions: #{by_session.size}"
```

---

### 7. Custom Observer for Metrics

```ruby
class MetricsObserver
  def initialize
    @fact_counts = Hash.new(0)
    @add_count = 0
    @remove_count = 0
  end

  def update(action, fact)
    case action
    when :add
      @add_count += 1
      @fact_counts[fact.type] += 1
    when :remove
      @remove_count += 1
      @fact_counts[fact.type] -= 1
    end
  end

  def report
    puts "Facts added: #{@add_count}"
    puts "Facts removed: #{@remove_count}"
    puts "Active facts by type:"
    @fact_counts.each do |type, count|
      puts "  #{type}: #{count}"
    end
  end
end

metrics = MetricsObserver.new
memory.add_observer(metrics)

# ... run system ...

metrics.report
```

---

## Performance Considerations

### Message Queue

- **Priority indexing**: Messages sorted by priority + timestamp
- **Atomic pop**: `consume` uses SELECT + UPDATE in transaction (safe for concurrent consumers)
- **Scaling**: For >10,000 messages/sec, use Redis store

### Audit Log

- **Write performance**: Each fact change = 1 audit log insert (can be disabled for high-throughput)
- **Query performance**: Indexed by `fact_uuid` and `session_id`
- **Growth**: Audit log grows unbounded. Implement periodic archival for production:

```ruby
# Archive old audit entries
def archive_old_audit(memory, cutoff_date)
  memory.store.db.execute(
    "DELETE FROM fact_history WHERE timestamp < ?",
    [cutoff_date.iso8601]
  )

  memory.store.db.execute(
    "DELETE FROM rules_fired WHERE fired_at < ?",
    [cutoff_date.iso8601]
  )

  memory.vacuum
end

# Archive entries older than 30 days
archive_old_audit(memory, Date.today - 30)
```

---

## See Also

- [Engine API](engine.md) - Blackboard::Engine integration
- [Facts API](facts.md) - Persistent fact objects
- [Custom Persistence](../advanced/custom-persistence.md) - Implementing custom stores
- [Blackboard Guide](../guides/blackboard-memory.md) - Blackboard pattern overview
- [Multi-Agent Example](../examples/multi-agent.md) - Multi-agent coordination
