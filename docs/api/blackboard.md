# Blackboard API Reference

Complete API reference for blackboard memory classes.

## Table of Contents

- [KBS::Blackboard::Memory](#kbsblackboardmemory) - Central blackboard workspace
- [KBS::Blackboard::MessageQueue](#kbsblackboardmessagequeue) - Inter-agent communication
- [KBS::Blackboard::AuditLog](#kbsblackboardauditlog) - Historical tracking
- [Persistence Stores](#persistence-stores) - `Store`, `SqliteStore`, `RedisStore`, `HybridStore`
- [Usage Patterns](#usage-patterns)

The blackboard classes are not loaded by `require 'kbs'`. Load them with:

```ruby
require 'kbs/blackboard'
```

`KBS::Blackboard::Engine`, the rule engine that uses a `Memory` as its working memory, is documented in the [Engine API](engine.md#kbsblackboardengine).

---

## KBS::Blackboard::Memory

The central blackboard workspace that coordinates facts, messages, and audit logging.

**Architecture**: Composes three components:
1. **Store** - Persistence layer (SQLite, Redis, or Hybrid)
2. **MessageQueue** - Priority-based inter-agent messaging (`MessageQueue` in SQLite, `RedisMessageQueue` for Redis and Hybrid stores)
3. **AuditLog** - Complete history of fact changes and rule firings (`AuditLog` in SQLite for SQLite and Hybrid stores, `RedisAuditLog` for Redis)

---

### Constructor

#### `initialize(db_path: ':memory:', store: nil)`

Creates a new blackboard memory.

**Parameters**:
- `db_path` (String, optional) - Path to SQLite database (default: `:memory:`)
- `store` (KBS::Blackboard::Persistence::Store, optional) - Custom store (default: `nil`, creates SqliteStore)

**Returns**: `KBS::Blackboard::Memory` instance

**Raises**: `ArgumentError` if `store` responds to neither `connection` (Redis) nor `db` (SQLite)

**Side Effects**:
- Uses the store's `session_id`, or generates a session UUID when no store is given
- Creates or connects to persistence store
- Initializes the message queue and audit log that match the store
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

**Type**: `KBS::Blackboard::MessageQueue` or `KBS::Blackboard::RedisMessageQueue`

**Read-only**: Yes (via `attr_reader`)

**Description**: The message queue for inter-agent communication

**Example**:
```ruby
memory.message_queue.post("agent1", "alerts", { level: "critical" })
```

---

#### `audit_log`

**Type**: `KBS::Blackboard::AuditLog` or `KBS::Blackboard::RedisAuditLog`

**Read-only**: Yes (via `attr_reader`)

**Description**: The audit log for tracking all changes

**Example**:
```ruby
history = memory.audit_log.fact_history(fact.uuid)
```

---

#### `db`

Alias for `store` (kept for backward compatibility). It returns the store object, not the SQLite database; use `memory.store.db` for that.

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

**Returns**: No meaningful value

**Side Effects** (only when the fact is active; otherwise nothing happens):
- Marks fact as inactive in store
- Logs removal to audit log
- Notifies observers with `:remove`

**Example**:
```ruby
fact = memory.add_fact(:temperature, value: 85)
memory.remove_fact(fact)

# Or by UUID
memory.remove_fact("550e8400-e29b-41d4-a716-446655440000")

# Fact remains in audit log (newest entry first)
history = memory.get_history(fact.uuid)
puts history.first[:action]  # => "REMOVE"
```

---

#### `update_fact(fact, new_attributes)`

Replaces a fact's stored attributes.

**Parameters**:
- `fact` (KBS::Blackboard::Fact or String) - Fact object or UUID
- `new_attributes` (Hash) - The complete new attribute hash. It is NOT merged: attributes left out are dropped from the store

**Returns**: No meaningful value

**Side Effects**:
- Updates fact in store
- Logs update to audit log

**Example**:
```ruby
fact = memory.add_fact(:temperature, location: "server_room", value: 85)
memory.update_fact(fact, fact.attributes.merge(value: 90, timestamp: Time.now))

# Or by UUID (the stored fact is now just {value: 95})
memory.update_fact(fact.uuid, value: 95)
```

**Note**: Updates do NOT notify observers or trigger rule re-evaluation, and do not change `fact.attributes` of a `Fact` object you hold. For that, use `modify_fact` (or `engine.modify` on a `KBS::Blackboard::Engine`).

---

#### `modify_fact(fact, changes)`

Merges `changes` into a fact's attributes, persists them, and tells the observers the fact was removed and added again, so an engine matches the new values. The UUID is kept.

**Parameters**:
- `fact` (KBS::Blackboard::Fact or String) - Fact object or UUID
- `changes` (Hash) - Attributes to merge

**Returns**: `KBS::Blackboard::Fact` with the new attributes, or `nil` when the fact is not active in the store

**Side Effects**:
- Logs an `UPDATE` to the audit log
- Notifies observers with `:remove` then `:add`

**Example**:
```ruby
reading = memory.add_fact(:temperature, value: 99)
modified = memory.modify_fact(reading, value: 100)
modified.uuid == reading.uuid  # => true
modified.attributes            # => {value: 100}
```

**Note**: With a `KBS::Blackboard::Engine`, prefer `engine.modify(fact, changes)`, which also applies the engine's duplicate check.

---

#### `find_fact(fact)`

Returns the fact with this UUID as the store holds it now.

**Parameters**:
- `fact` (KBS::Blackboard::Fact or String) - Fact object or UUID

**Returns**: `KBS::Blackboard::Fact` or `nil` if the fact is not active

**Example**:
```ruby
current = memory.find_fact(fact.uuid)
current[:value] if current
```

---

#### `get_facts(type = nil, pattern = {})`

Retrieves facts from the blackboard.

**Parameters**:
- `type` (Symbol, optional) - Filter by fact type (default: `nil`, all types)
- `pattern` (Hash, optional) - Additional attribute filters; values are literals or Procs (default: `{}`)

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
  ["temperature", 80]
)

# Complex query
recent_errors = memory.query_facts(
  "fact_type = ? AND datetime(json_extract(attributes, '$.timestamp')) > datetime(?)",
  ["error", (Time.now - 3600).iso8601]
)
```

**Important**: Only works with SQLite stores. Redis and Hybrid stores raise `NotImplementedError`. Bind parameters must be types SQLite accepts (pass `"temperature"`, not `:temperature`; a Symbol raises an error).

---

### Message Queue Methods

#### `post_message(sender, topic, content, priority: 0)`

Posts a message to the blackboard message queue.

**Parameters**:
- `sender` (String) - Sender identifier (e.g., agent name)
- `topic` (String) - Message topic (channel/category)
- `content` (Hash or String) - Message payload. A Hash is stored as JSON and comes back with Symbol keys; a String is stored as is
- `priority` (Integer, optional) - Message priority (default: 0, higher = more urgent)

**Returns**: The new message id (Integer) with a Redis queue; no meaningful value with the SQLite queue

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

**Thread Safety**: Each message goes to one consumer. The SQLite queue claims a message with a conditional `UPDATE ... WHERE consumed = 0` and retries if another consumer took it first; the Redis queue pops it atomically with `ZPOPMIN`.

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

**Returns**: No meaningful value

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

**Returns**: `Array<Hash>` - History entries, newest first, with `:fact_uuid`, `:fact_type`, `:attributes`, `:action`, `:timestamp`, `:session_id`

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

**Returns**: `Array<Hash>` - Firing entries, newest first, with `:rule_name`, `:fact_uuids`, `:bindings`, `:fired_at`, `:session_id`

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

**Returns**: No meaningful value

**Side Effects**:
- Stores knowledge source metadata in the store (registering the same name again replaces it)

**Note**: With a Redis or Hybrid store, pass a `description`; the default `nil` makes the Redis client raise `TypeError`.

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

**Returns**: No meaningful value

**Side Effects**: Adds observer to internal observers list. Observers are called with `:add` and `:remove`; `modify_fact` sends a `:remove` followed by an `:add`

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
# Output: Added: temperature {value: 85}
```

**Important**: Observers are NOT persisted. Re-register after restart.

---

### Session Management Methods

#### `clear_session`

Removes all facts from current session.

**Parameters**: None

**Returns**: No meaningful value

**Side Effects**:
- Marks facts with matching session_id as retracted
- Preserves audit log, and writes no `REMOVE` entries
- Does NOT notify observers, so an engine using this memory still holds the facts in its network

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

**Side Effects** (SqliteStore):
- Begins transaction
- Executes block
- Commits on success
- Rolls back on exception

Redis and Hybrid stores just run the block: there is no rollback. Observers are notified as each fact is added, before the transaction commits.

**Example**:
```ruby
memory.transaction do
  fact1 = memory.add_fact(:order, id: 1, total: 100)
  fact2 = memory.add_fact(:inventory, item: "ABC", quantity: 10)

  # If this raises, both facts are rolled back
  raise "Validation failed" if fact1[:total] > 1000
end
```

**Nested Transactions**: A `transaction` inside another joins the outer one; there are no savepoints, so an exception rolls back the whole outer transaction.

---

### Statistics Methods

#### `stats`

Returns blackboard statistics.

**Parameters**: None

**Returns**: `Hash` with keys:
- `:total_facts` (Integer) - Facts ever stored, including retracted ones
- `:active_facts` (Integer) - Active facts
- `:knowledge_sources` (Integer) - Registered knowledge sources
- `:total_messages` (Integer) - Total messages (consumed + unconsumed)
- `:unconsumed_messages` (Integer) - Unconsumed messages
- `:rules_fired` (Integer) - Total rule firings
- `:audit_records` (Integer) - Hybrid store only; currently the row count of the SQLite `facts` table, which the hybrid store does not write to, so it is always 0

Counts cover the whole database (or Redis DB), not just this session.

**Example**:
```ruby
stats = memory.stats
puts "Facts: #{stats[:active_facts]}"
puts "Messages (unconsumed): #{stats[:unconsumed_messages]}"
puts "Messages (total): #{stats[:total_messages]}"
puts "Rules fired: #{stats[:rules_fired]}"
```

---

### Maintenance Methods

#### `vacuum`

Compacts storage.

**Parameters**: None

**Returns**: No meaningful value

**Side Effects**: SqliteStore runs SQLite `VACUUM`. RedisStore deletes facts retracted more than 30 days ago (`RedisStore::RETENTION_SECONDS`). HybridStore does both

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

**Returns**: No meaningful value

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

**Constructor**: `MessageQueue.new(db)` takes a SQLite3 database and creates the `blackboard_messages` table.

**`KBS::Blackboard::RedisMessageQueue`**: `RedisMessageQueue.new(redis)` takes a Redis connection and has the same methods. Each topic is a sorted set (`messages:<topic>`) ordered by priority then post time; message data lives in `message:<id>` hashes. Its `stats` counts every message in the Redis DB.

### Methods

#### `post(sender, topic, content, priority: 0)`

Posts a message to the queue.

**Parameters**:
- `sender` (String) - Sender identifier
- `topic` (String) - Message topic
- `content` (Hash or String) - Message payload (a Hash is converted to JSON; a String is stored as is)
- `priority` (Integer, optional) - Priority (default: 0)

**Returns**: The message id with `RedisMessageQueue`; no meaningful value with `MessageQueue`

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

**Returns**: `Hash` (`:id`, `:sender`, `:topic`, `:content`, `:priority`, `:posted_at`) or `nil` when the topic is empty

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

**Constructor**: `AuditLog.new(db, session_id)` takes a SQLite3 database and creates the `fact_history` and `rules_fired` tables.

**`KBS::Blackboard::RedisAuditLog`**: `RedisAuditLog.new(redis, session_id)` has the same methods, keeping entries in Redis lists. It keeps only the newest 10,000 entries overall and the newest 1,000 per fact or per rule.

### Methods

#### `log_fact_change(fact_uuid, fact_type, attributes, action)`

Logs a fact change event.

**Parameters**:
- `fact_uuid` (String) - Fact UUID
- `fact_type` (Symbol) - Fact type
- `attributes` (Hash) - Fact attributes
- `action` (String) - Action: "ADD", "UPDATE", "REMOVE"

**Returns**: No meaningful value

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

**Returns**: No meaningful value

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

## Persistence Stores

A store keeps the facts of a `Memory`. Pass one as `store:` to `KBS::Blackboard::Memory.new` or `KBS::Blackboard::Engine.new`; without one, a `SqliteStore` is created from `db_path:`.

All stores live in `KBS::Blackboard::Persistence` and share this interface:

| Method | Returns |
|--------|---------|
| `add_fact(uuid, type, attributes)` | no meaningful value |
| `remove_fact(uuid)` | `{type:, attributes:}` of the retracted fact, or `nil` if it was not active |
| `update_fact(uuid, attributes)` | the fact type (Symbol); replaces the attributes. SQLite returns `nil` only for an unknown uuid, Redis also when the fact is retracted |
| `get_fact(uuid)` | `{uuid:, type:, attributes:}` or `nil` |
| `get_facts(type = nil, pattern = {})` | `Array` of `{uuid:, type:, attributes:}`; pattern values are literals or Procs |
| `query_facts(conditions = nil, params = [])` | SQLite only; others raise `NotImplementedError` |
| `register_knowledge_source(name, description: nil, topics: [])` | no meaningful value |
| `clear_session(session_id)` | retracts the session's facts, without audit entries |
| `stats` | `{total_facts:, active_facts:, knowledge_sources:}` |
| `transaction { ... }` | the block's result (SQLite) |
| `vacuum` | no meaningful value |
| `close` | no meaningful value |

Retracted facts stay in the store, marked retracted; `get_fact` and `get_facts` skip them.

### `KBS::Blackboard::Persistence::Store`

Abstract base class. Every method above except `vacuum`, `transaction` and `register_knowledge_source` raises `NotImplementedError` until a subclass defines it; `vacuum` does nothing and `transaction` just yields. `register_knowledge_source` is not defined on the base class, but `Memory#register_knowledge_source` calls it. `Memory` also needs a store to respond to `session_id` and to `db` (SQLite) or `connection` (Redis). See [Custom Persistence](../advanced/custom-persistence.md).

### `KBS::Blackboard::Persistence::SqliteStore`

#### `initialize(db_path: ':memory:', session_id: nil)`

Opens (or creates) the SQLite database and its `facts` and `knowledge_sources` tables. `session_id` defaults to a new UUID.

**Attributes**: `db` (the `SQLite3::Database`), `db_path`, `session_id`

`transaction` opens a SQLite transaction; nested calls join the outer one.

```ruby
store = KBS::Blackboard::Persistence::SqliteStore.new(db_path: 'kb.db')
memory = KBS::Blackboard::Memory.new(store: store)
```

### `KBS::Blackboard::Persistence::RedisStore`

#### `initialize(url: 'redis://localhost:6379/0', session_id: nil, redis: nil)`

Connects to Redis, or uses the `redis` connection given. Requires the `redis` gem; without it the constructor raises `LoadError`.

**Attributes**: `redis`, `session_id`; `connection` returns the Redis connection.

- Facts are hashes at `fact:<uuid>`, indexed by the sets `facts:active`, `facts:all`, `facts:type:<type>` and `facts:session:<session_id>`
- `transaction` just yields; there is no rollback
- `vacuum` deletes facts retracted more than `RETENTION_SECONDS` (30 days) ago
- `query_facts` raises `NotImplementedError`

```ruby
store = KBS::Blackboard::Persistence::RedisStore.new(url: 'redis://localhost:6379/0')
memory = KBS::Blackboard::Memory.new(store: store)
memory.message_queue.class  # => KBS::Blackboard::RedisMessageQueue
memory.audit_log.class      # => KBS::Blackboard::RedisAuditLog
```

### `KBS::Blackboard::Persistence::HybridStore`

#### `initialize(redis_url: 'redis://localhost:6379/0', redis: nil, db_path: 'audit.db', session_id: nil)`

Keeps facts and messages in Redis (a `RedisStore`) and the audit log in SQLite (a `SqliteStore` at `db_path`).

**Attributes**: `redis_store`, `sqlite_store`, `session_id`; `connection` returns the Redis connection, `db` the SQLite database, and `hybrid?` returns `true`.

- Fact operations are delegated to the `RedisStore`
- `transaction` just yields
- `vacuum` vacuums both stores; `close` closes both

```ruby
store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',
  db_path: 'audit.db'
)
memory = KBS::Blackboard::Memory.new(store: store)
memory.message_queue.class  # => KBS::Blackboard::RedisMessageQueue
memory.audit_log.class      # => KBS::Blackboard::AuditLog
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

    # Deduct inventory (update_fact replaces the attributes, so merge first)
    memory.update_fact(inventory, inventory.attributes.merge(quantity: inventory[:quantity] - order[:quantity]))

    # Create shipment fact
    shipment = memory.add_fact(:shipment, order_id: order.uuid, status: "pending")

    # Post message for shipping agent
    memory.post_message(
      "OrderProcessor",
      "shipments",
      { shipment_id: shipment.uuid },
      priority: 10
    )

    # With a SqliteStore, if any step fails, the entire transaction rolls back
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
- **Single delivery**: `consume` uses SELECT + conditional UPDATE in a transaction, retrying if another consumer claimed the message first (safe for concurrent consumers)
- **Scaling**: For >10,000 messages/sec, use Redis store

### Audit Log

- **Write performance**: Each fact change = 1 audit log insert (there is no option to turn this off)
- **Query performance**: `fact_history` is indexed by `fact_uuid`; `rules_fired` by `session_id`
- **Growth**: The SQLite audit log grows unbounded (`RedisAuditLog` keeps only the newest entries). Implement periodic archival for production:

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
- [Blackboard Examples](../examples/index.md#advanced-features) - Multi-agent coordination and blackboard systems
