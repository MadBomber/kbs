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

#### `initialize(strategy: :definition, fact_duplication: true)`

Creates a new in-memory RETE engine.

**Parameters**:
- `strategy` (Symbol, optional) - conflict resolution strategy: `:definition` (default), `:depth` or `:breadth`. See [`run`](#runlimit-nil).
- `fact_duplication` (Boolean, optional) - whether working memory may hold two facts with the same type and attributes (default: `true`). See [`fact_duplication`](#fact_duplication-fact_duplication).

**Returns**: `KBS::Engine` instance

**Raises**: `ArgumentError` for an unknown strategy

**Example - Low-level API**:
```ruby
require 'kbs'

engine = KBS::Engine.new
# Engine ready with empty working memory

engine = KBS::Engine.new(strategy: :depth, fact_duplication: false)
```

**Using DSL (Recommended)**:
```ruby
require 'kbs'

kb = KBS.knowledge_base do
  # Engine automatically created
  # Define rules and facts here
end

# Access engine if needed
engine = kb.engine
```

**Internal State Initialized**:
- `@working_memory` - WorkingMemory instance
- `@rules` - Array of registered rules
- `@alpha_memories` - Hash of pattern → AlphaMemory
- `@production_nodes` - Hash of rule name → ProductionNode
- `@agenda` - Agenda of activations waiting to fire
- `@root_beta_memory` - Root BetaMemory with dummy token

---

### Public Methods

#### `add_rule(rule)`

Registers a rule and compiles it into the RETE network.

**Parameters**:
- `rule` (Rule) - Rule object with conditions and action

**Returns**: no meaningful value

**Raises**: `ArgumentError` when a logical condition follows a non-logical one (logical conditions must come first)

**Side Effects**:
- Builds alpha memories for each condition pattern
- Creates join nodes, negation nodes (`without`) or exists nodes (`exists`)
- Creates beta memories for partial matches
- Creates production node for rule
- Matches facts already in working memory and puts the complete matches on the agenda

**Example**:
```ruby
rule = KBS::Rule.new(
  "high_temperature",
  priority: 10,
  conditions: [
    KBS::Condition.new(:temperature, { location: "server_room" })
  ],
  action: ->(facts) { puts "Alert: High temperature!" }
)

engine.add_rule(rule)
```

**Using DSL**:
```ruby
kb = KBS.knowledge_base do
  rule "high_temperature", priority: 10 do
    on :temperature, location: :location?, value: :value?
    perform do |facts, bindings|
      puts "Alert: #{bindings[:location?]} is #{bindings[:value?]}°F"
    end
  end
end

# `rule` has already called add_rule on the knowledge base's engine
kb.engine.rules.size  # => 1
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

**Returns**: `KBS::Fact` - The created fact. With `fact_duplication` off, the existing equal fact when there is one. `nil` when called from the action of a rule with logical conditions whose match an earlier step of the same action already removed.

**Raises**: `KBS::MatchInProgressError` when called while a fact is being matched (see below)

**Side Effects**:
- Creates Fact object
- Adds to working memory
- Activates all matching alpha memories
- Propagates through join nodes
- May create new tokens in beta memories
- Puts each new complete match on the agenda (rules fire on `run`, not here)
- From the action of a rule with `logical` conditions, records the match as the fact's support (see [Truth Maintenance](#truth-maintenance))

**Example - Low-level API**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)
# => #<KBS::Fact:0x00... @id=..., @type=:temperature, @attributes={...}>

# Facts without attributes
marker = engine.add_fact(:system_ready)
# => #<KBS::Fact:0x00... @id=..., @type=:system_ready, @attributes={}>
```

**Using DSL (Recommended)**:
```ruby
kb = KBS.knowledge_base do
  fact :temperature, location: "server_room", value: 85
  fact :system_ready
end
```

**Thread Safety**: Not thread-safe. Wrap in mutex if adding facts from multiple threads.

**Performance**: O(A × P) where A is number of alpha memories, P is pattern matching cost

---

#### `remove_fact(fact)`

Removes a fact from working memory and deactivates it in alpha memories.

**Parameters**:
- `fact` (KBS::Fact) - Fact object to remove (must be exact object reference)

**Returns**: the fact

**Raises**: `KBS::MatchInProgressError` when called while a fact is being matched

**Side Effects**:
- Removes from working memory
- Deactivates fact in all alpha memories
- Removes tokens containing this fact, and takes their activations off the agenda
- May cause negation nodes to re-evaluate
- Retracts facts that were logically supported only by matches containing this fact

**Example**:
```ruby
fact = engine.add_fact(:temperature, value: 85)
engine.remove_fact(fact)

# Common pattern: Store fact reference for later removal
@current_alert = engine.add_fact(:alert, level: "critical")
# Later...
engine.remove_fact(@current_alert) if @current_alert
```

**Important**: You must keep a reference to the fact object to remove it. Finding facts requires inspecting `engine.facts` (the same as `engine.working_memory.facts`).

**Example - Finding and Removing**:
```ruby
# Find all temperature facts
temp_facts = engine.working_memory.facts.select { |f| f.type == :temperature }

# Remove specific fact
old_fact = temp_facts.find { |f| f[:timestamp] < Time.now - 3600 }
engine.remove_fact(old_fact) if old_fact
```

---

#### `modify(fact, changes)`

Changes a fact's attributes and matches it against the rules again.

`modify` works as a retraction followed by an assertion. Matches that depended on the old values go away, and every rule the new values satisfy is activated, including rules that already fired for this fact.

**Parameters**:
- `fact` - a fact in working memory (`KBS::Blackboard::Engine` also accepts a uuid)
- `changes` (Hash) - attributes to merge into the fact's

**Returns**: the fact with its new attributes, or `nil` when the fact is not in working memory. `KBS::Engine` returns the same object; `KBS::Blackboard::Engine` returns a new object with the same uuid and records an `UPDATE` in the audit log. With `fact_duplication` off, see below.

**Raises**: `KBS::MatchInProgressError` when called while a fact is being matched

```ruby
reading = engine.add_fact(:sensor, id: 1, temp: 20)
engine.run                       # "hot" rule does not fire
engine.modify(reading, temp: 45)
engine.run                       # "hot" rule fires
```

Setting an attribute directly (`fact[:temp] = 45`, or `Blackboard::Fact#update`) does **not** match the fact again: the network keeps the matches it made from the values the fact had when it was added.

A rule whose action modifies a fact that the same rule matches is activated again by the change. Guard it with a condition the change makes false, or the rule runs until `run(limit)` stops it.

---

#### `fact_duplication` / `fact_duplication=`

Whether working memory may hold two facts with the same type and attributes. `true` by default.

```ruby
engine = KBS::Engine.new(fact_duplication: false)
first = engine.add_fact(:sensor, id: 1)
again = engine.add_fact(:sensor, id: 1)   # not added
again.equal?(first)                        # => true
```

With duplication off, `add_fact` returns the existing fact instead of adding an equal one, and no rule is activated a second time. `modify` that would make a fact equal to another removes the modified fact and returns the other. Turning it off later keeps any duplicates already in working memory. A `KBS::Blackboard::Engine` created with `fact_duplication: false` on a database that already holds facts checks new facts against those too.

---

#### Changing facts while a fact is being matched

`add_fact`, `remove_fact` and `modify` raise `KBS::MatchInProgressError` when called while the engine is matching another fact. That only happens from code the engine calls during a match, such as a predicate in a pattern (`temp: ->(t) { ... }`). An observer added with `working_memory.add_observer` is called after the engine has matched the fact, so it does not raise. Change facts from rule actions, which run between matches.

`matching?` tells whether a match is in progress.

---

#### `run(limit = nil)`

Fires activations from the agenda until it is empty.

Every complete match of a rule is an *activation*. Activations wait on the agenda (`engine.agenda`) until `run`. Each step of `run` takes the next activation, fires its rule, and looks at the agenda again, so a fact that an action adds or removes takes effect before the next firing: rules chain within one `run`, and an activation whose facts were retracted never fires. An activation fires once.

**Parameters**:
- `limit` (Integer, optional) - stop after this many firings. Use it to bound a rule set that can feed itself.

**Returns**: `Integer` - the number of rules fired

**Order**: highest `priority` first. Among equal priorities the strategy decides:

| Strategy | Order |
|---|---|
| `:definition` (default) | rules in the order they were added; each rule's matches oldest first |
| `:depth` | newest match first |
| `:breadth` | oldest match first |

Set it with `KBS::Engine.new(strategy: :depth)` or `engine.strategy = :depth`.

**Stopping early**: `engine.halt`, called from a rule action, stops the run after that rule. The remaining activations stay on the agenda for the next `run`.

**Side Effects**:
- Rule actions may add/remove facts
- Rule actions may modify external state

**Example - Low-level API**:
```ruby
engine.add_fact(:temperature, value: 85)
engine.add_fact(:sensor, status: "active")

# Facts are in working memory but rules haven't fired
engine.run  # Execute all matching rules

# Rules fire in priority order (highest first)
```

**Using DSL (Recommended)**:
```ruby
kb = KBS.knowledge_base do
  rule "my_rule" do
    on :temperature, value: greater_than(80)
    perform { puts "High temperature!" }
  end

  fact :temperature, value: 85
  fact :sensor, status: "active"

  run  # Execute all matching rules
end
```

**Execution Order**:
- Activations fire in priority order, highest first
- Among equal priorities, the strategy decides: with the default `:definition`, rules fire in definition order and each rule's matches oldest first

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

kb.fact :temperature, value: 85
kb.run  # => 2

# Both rules fire, higher priority first
fired_rules  # => ["rule_b", "rule_a"]
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

#### `halt`

Stops the current `run` after the rule that is firing. Call it from a rule action. The activations still on the agenda wait for the next `run`, which clears the halt when it starts.

**Returns**: `true`

```ruby
kb = KBS.knowledge_base do
  rule "stop_on_alarm", priority: 100 do
    on :alarm
    perform { kb.halt }
  end
end
```

The DSL's `halt` delegates to `engine.halt`.

---

#### `strategy` / `strategy=(strategy)`

Reads or changes the agenda's conflict resolution strategy (`:definition`, `:depth` or `:breadth`). Changing it reorders the activations already on the agenda.

**Raises**: `ArgumentError` for an unknown strategy

```ruby
engine.strategy           # => :definition
engine.strategy = :depth
```

---

#### `reset`

Clears all transient RETE state while keeping the compiled rules: working memory, every alpha and beta memory, every production node's tokens, the agenda and the truth maintenance records. A rule that starts with a `without` condition matches again, since working memory is now empty.

**Returns**: no meaningful value

`KBS::Blackboard::Engine#reset` empties the network but not the store: persisted facts stay on the blackboard.

---

#### `close`

Releases what the engine holds open. A no-op on `KBS::Engine`; `KBS::Blackboard::Engine` closes its store.

**Returns**: `nil` for `KBS::Engine`

---

#### `facts`

**Returns**: `Array<KBS::Fact>` - the facts in working memory, in the order they were added. A copy: changing it does not change working memory.

---

#### Truth Maintenance

A fact asserted from the action of a rule with `logical` conditions is supported by the match of those conditions, and is retracted when every match that supports it is gone. See [Rules API](rules.md#logicalblock) and the [Truth Maintenance guide](../guides/truth-maintenance.md).

- `logically_supported?(fact)` → `Boolean` - whether `fact` was asserted under logical conditions and will be retracted when its supporting matches are gone. Asserting an equal fact (with `fact_duplication` off) from outside a logical rule makes it unconditional.
- `dependencies(fact)` → `Array<Array<KBS::Fact>>` - the matches that support `fact`, each as the facts that matched the rule's logical conditions. Empty for an unconditional fact.
- `dependents(fact)` → `Array<KBS::Fact>` - the facts that will lose a support if `fact` is retracted.

```ruby
kb = KBS.knowledge_base do
  rule "overheating" do
    logical do
      on :sensor, temp: greater_than(90)
    end
    perform { kb.assert(:overheating) }
  end
end

sensor = kb.fact(:sensor, temp: 95)
kb.run
warning = kb.query(:overheating).first

kb.engine.logically_supported?(warning)  # => true
kb.engine.dependencies(warning)          # => [[sensor]]
kb.engine.dependents(sensor)             # => [warning]

kb.retract(sensor)
kb.query(:overheating)                   # => []
```

---

#### `matching?`

**Returns**: `Boolean` - whether the engine is matching a fact right now. While it is, `add_fact`, `remove_fact` and `modify` raise `KBS::MatchInProgressError`.

---

#### `duplicate_of(type, attributes)`

**Returns**: the fact in working memory with this type and attributes when `fact_duplication` is off; `nil` otherwise (always `nil` while duplication is allowed).

---

#### Internal methods

These are public so that working memory, the network nodes and `KBS::Blackboard::Engine` can call them. They are not meant for application code: `update`, `create_fact`, `fire_activation`, `match_fact`, `unmatch_fact`, `matching_alpha_memories`, `alpha_memories_for`, `prioritized_production_nodes`, `token_removed`, `current_support`, `reinforce`, `attach_support`, `retract_unsupported_facts`, `ensure_not_matching!`.

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

**Description**: Pattern → AlphaMemory mapping. Each key is a condition's pattern merged with its `type:`, e.g. `{location: "server_room", type: :temperature}`.

**Example**:
```ruby
# Inspect alpha memories (useful for debugging)
engine.alpha_memories.each do |pattern, memory|
  puts "Pattern: #{pattern}"
  puts "  Facts: #{memory.items.size}"
  puts "  Successors: #{memory.successors.size}"
end
```

---

#### `production_nodes`

**Type**: `Hash<String or Symbol, KBS::ProductionNode>`

**Read-only**: Yes (via `attr_reader`)

**Description**: Rule name → ProductionNode mapping, keyed by the name exactly as the rule was given it (a DSL `rule "high_temperature"` is keyed by the String). A node's `tokens` are the rule's current matches, fired or not; the ones still waiting to fire are on the `agenda`.

**Example**:
```ruby
# Check if a rule is matched
prod_node = engine.production_nodes["high_temperature"]
if prod_node && prod_node.tokens.any?
  puts "Rule 'high_temperature' has #{prod_node.tokens.size} matches"
end
```

---

#### `agenda`

**Type**: `KBS::Agenda`

**Read-only**: Yes (via `attr_reader`)

**Description**: The conflict set: every activation (a rule plus the token that matched it) that has not fired yet, ordered by rule priority and then by the strategy. `run` pops from it.

**`KBS::Agenda` methods**:
- `size` → `Integer` - pending activations; `empty?` → `Boolean`
- `to_a` → `Array<KBS::Activation>` - pending activations in firing order
- `peek` → the next activation to fire, or `nil`
- `pop` → removes and returns the next activation, or `nil` when empty (`run` does this; popping by hand skips the rule)
- `clear` - drops every pending activation
- `strategy` / `strategy=(strategy)` - as on the engine; `KBS::Agenda::STRATEGIES` is `[:definition, :depth, :breadth]`
- `add(node, token, rule_order: 0)` / `remove(activation)` - called by production nodes

**`KBS::Activation`**: `rule`, `token`, `salience` (the rule's priority), `timetag` (arrival order), `to_s` (`"salience name: facts"`).

```ruby
engine.add_fact(:temperature, value: 85)
engine.agenda.size                         # => number of pending activations
engine.agenda.to_a.map { |a| a.rule.name } # => names in firing order
engine.run
engine.agenda.empty?                       # => true
```

---

### Observer Pattern

The engine implements the observer pattern to watch fact changes.

#### `update(action, fact)` (Internal)

**Parameters**:
- `action` (Symbol) - `:add` or `:remove`
- `fact` (KBS::Fact) - The fact that changed

**Description**: Called automatically by WorkingMemory when facts change. Activates/deactivates alpha memories. An observer you add is called in the same way, after the engine (observers run in the order they were added).

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
# Output: [2025-01-15 10:30:00 -0600] ADD: temperature {value: 85}
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

#### `initialize(db_path: ':memory:', store: nil, strategy: :definition, fact_duplication: true)`

Creates a persistent RETE engine with blackboard memory.

**Parameters**:
- `db_path` (String, optional) - Path to SQLite database (default: `:memory:`)
- `store` (Store, optional) - Custom persistence store (default: `nil`, uses SqliteStore)
- `strategy`, `fact_duplication` - as for `KBS::Engine.new`

**Returns**: `KBS::Blackboard::Engine` instance

`require 'kbs'` does not load the blackboard; add `require 'kbs/blackboard'`.

**Example - In-Memory**:
```ruby
require 'kbs/blackboard'

engine = KBS::Blackboard::Engine.new
# Blackboard in RAM (lost on exit)
```

**Example - SQLite Persistence**:
```ruby
engine = KBS::Blackboard::Engine.new(db_path: 'knowledge_base.db')
# Facts persisted to knowledge_base.db
```

**Using DSL with Blackboard (Recommended)**:
```ruby
engine = KBS::Blackboard::Engine.new(db_path: 'knowledge_base.db')

kb = KBS.knowledge_base(engine: engine) do
  rule "persistent_rule" do
    on :temperature, value: greater_than(80)
    perform { puts "High temp alert!" }
  end

  fact :temperature, value: 85
  run
end

# Facts persist across restarts
kb.close
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

**Example - Low-level API**:
```ruby
fact = engine.add_fact(:temperature, location: "server_room", value: 85)
puts fact.uuid  # => "550e8400-e29b-41d4-a716-446655440000"

# Fact persists across restarts
engine2 = KBS::Blackboard::Engine.new(db_path: 'knowledge_base.db')
reloaded_facts = engine2.blackboard.get_facts(:temperature)
puts reloaded_facts.first[:value]  # => 85
```

**Using DSL (Recommended)**:
```ruby
# Session 1
engine = KBS::Blackboard::Engine.new(db_path: 'knowledge_base.db')
kb = KBS.knowledge_base(engine: engine) do
  fact :temperature, location: "server_room", value: 85
end
kb.close

# Session 2 - facts still available
engine2 = KBS::Blackboard::Engine.new(db_path: 'knowledge_base.db')
temps = engine2.blackboard.get_facts(:temperature)
puts temps.first[:value]  # => 85
```

**Difference from KBS::Engine**: Returns `KBS::Blackboard::Fact` (has `.uuid`) instead of `KBS::Fact`.

---

#### `remove_fact(fact)`

Removes a persistent fact from the blackboard.

**Parameters**:
- `fact` (KBS::Blackboard::Fact) - Fact to remove

**Returns**: the removed `KBS::Blackboard::Fact`, or `nil` when the fact was not active, as `KBS::Engine#remove_fact` returns the fact

**Side Effects**:
- Marks fact as inactive in store
- Logs removal to audit trail
- Deactivates in alpha memories
- Notifies observers

**Example**:
```ruby
fact = engine.add_fact(:temperature, value: 85)
engine.remove_fact(fact)

# Fact marked inactive but remains in audit trail (newest entry first)
audit = engine.blackboard.audit_log.fact_history(fact.uuid)
puts audit.first[:action]  # => "REMOVE"
puts audit.last[:action]   # => "ADD"
```

---

#### `run(limit = nil)`

Fires activations from the agenda until it is empty, with audit logging. Order, `limit`, `halt` and strategies work as in `KBS::Engine#run`.

**Parameters**:
- `limit` (Integer, optional) - stop after this many firings

**Returns**: `Integer` - the number of rules fired

**Side Effects**:
- Logs each rule firing to audit trail
- Records fact UUIDs and variable bindings

**Example**:
```ruby
engine.add_rule(my_rule)
engine.add_fact(:temperature, value: 85)
engine.run

# Check audit log (newest firing first)
engine.blackboard.get_rule_firings.each do |entry|
  puts "Rule #{entry[:rule_name]} fired with bindings: #{entry[:bindings]}"
end
```

Each entry has `:rule_name`, `:fact_uuids`, `:bindings`, `:fired_at` and `:session_id`. `get_rule_firings(rule_name = nil, limit: 100)` filters by rule.

**Difference from KBS::Engine**:
- Logs every rule firing
- Records fact UUIDs and variable bindings in audit

A rule named with a Symbol (`KBS::Rule.new(:my_rule, ...)`) is logged under its String name (`"my_rule"`); `get_rule_firings` takes either.

---

#### `post_message(sender, topic, content, priority: 0)`

Posts a message to the blackboard message queue.

**Parameters**:
- `sender` (String) - Sender identifier (e.g., agent name)
- `topic` (String) - Message topic (channel)
- `content` (Hash) - Message payload
- `priority` (Integer, optional) - Message priority (default: 0, higher = more urgent)

**Returns**: no meaningful value

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

**Returns**: `Hash` or `nil` - Message hash with `:id`, `:sender`, `:topic`, `:content`, `:priority`, `:posted_at`, or `nil` if queue empty. Among equal priorities the oldest message comes first.

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

**Thread Safety**: Atomic pop operation: the SQLite queue claims a message only if no other consumer took it first, and the Redis queue pops atomically, so concurrent consumers never get the same message

---

#### `stats()`

Returns blackboard statistics.

**Parameters**: None

**Returns**: `Hash` with keys (SQLite store):
- `:total_facts` (Integer) - Facts ever added, including retracted ones
- `:active_facts` (Integer) - Facts not retracted
- `:knowledge_sources` (Integer) - Registered knowledge sources
- `:total_messages` (Integer) - Messages ever posted (all topics)
- `:unconsumed_messages` (Integer) - Messages still queued
- `:rules_fired` (Integer) - Rule firings in the audit log

The Redis store reports the same keys; the hybrid store adds `:audit_records`, the rows in its SQLite audit log (fact changes plus rule firings).

**Example**:
```ruby
stats = engine.stats
puts "Facts: #{stats[:active_facts]}"
puts "Messages: #{stats[:unconsumed_messages]}"
puts "Rules fired: #{stats[:rules_fired]}"
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
engine.blackboard.audit_log.fact_history.first   # newest fact change
engine.blackboard.transaction { engine.add_fact(:order, status: "pending") }

# Get facts by type
temps = engine.blackboard.get_facts(:temperature)
```

---

### Other Methods

- `modify(fact, changes)` - see [`KBS::Engine#modify`](#modifyfact-changes); also accepts the fact's uuid
- `reset` - empties the network but leaves the persisted facts on the blackboard
- `close` - closes the store

---

## Engine Lifecycle

### Typical Flow

```ruby
# 1. Create engine
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')

# 2. Define and register rules on that engine
kb = KBS.knowledge_base(engine: engine) do
  rule "high_temp_alert", priority: 10 do
    on :temperature, value: :value?
    perform do |facts, bindings|
      puts "Alert! Temperature: #{bindings[:value?]}" if bindings[:value?] > 80
    end
  end
end

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
accounts = engine.blackboard.get_facts(:account)
puts accounts.first[:balance]  # => 1000

# BUT: Rules must be re-registered (not persisted)
kb = load_rules            # your own method returning a KBS.knowledge_base
kb.rules.each_value { |r| engine.add_rule(r) }
```

**Important**: Only facts persist. Rules, alpha memories, and RETE network must be rebuilt on restart. A rule added to the new engine is matched against the facts already on the blackboard.

---

### Transaction Example

```ruby
engine.blackboard.transaction do
  fact1 = engine.add_fact(:order, id: 1, status: "pending")
  fact2 = engine.add_fact(:inventory, item: "ABC", quantity: 100)

  # If error occurs here, both facts are rolled back in the store and the engine
  raise "Validation failed" if invalid_order?(fact1)
end
```

**Database Support**: The SQLite store wraps the block in a SQLite transaction (nested calls join the outer one). The Redis and hybrid stores just run the block: there is nothing to roll back.

**Note**: When the block raises, the facts it added that the store rolled back are also removed from the engine, so their rules do not fire. With the Redis and hybrid stores the facts stay, in the store and in the engine. Facts the block removed or modified are restored in the store only: the engine does not see them again until it is rebuilt from the store (a new engine on the same database).

---

## Advanced Topics

### Network Sharing

Multiple rules with an equal condition pattern (same type, same attribute values) reuse one alpha memory:

```ruby
# Both rules share the {location: "server_room", type: :temperature} alpha memory
rule "log_server_room" do
  on :temperature, location: "server_room"
  perform { puts "Server room reading" }
end

rule "server_room_alarm" do
  on :temperature, location: "server_room"
  on :alarm
  perform { puts "Alarm with a server room reading!" }
end

# Only 1 alpha memory created for the :temperature pattern
# Pattern matching happens once per fact
```

Patterns are compared as hashes, so two separate predicates such as `greater_than(80)` and `greater_than(100)` (or even two calls of `greater_than(80)`, which make two lambdas) give two alpha memories.

---

### Inspecting the RETE Network

```ruby
# Dump alpha memories
engine.alpha_memories.each do |pattern, memory|
  puts "Pattern: #{pattern.inspect}"
  puts "  Facts in alpha memory: #{memory.items.size}"
  puts "  Successor nodes: #{memory.successors.size}"
  memory.successors.each do |succ|
    puts "    #{succ.class.name}"
  end
end

# Dump production nodes
engine.production_nodes.each do |name, node|
  puts "Rule: #{name}"
  puts "  Tokens (matches): #{node.tokens.size}"
  node.tokens.each do |token|
    puts "    Token with #{token.facts.size} facts#{' (fired)' if token.fired?}"
  end
end

# Dump the agenda: activations waiting to fire, in firing order
engine.agenda.to_a.each { |activation| puts activation }
```

**Use Case**: Debugging why a rule didn't fire

The engine also answers this directly. `engine.matches(rule_name)` reports how far each condition of a rule has matched, `engine.watch(:facts, :activations, :rules)` traces changes as they happen, `engine.join_activity(rule_name)` counts the work of each condition, and `engine.network_stats` sizes the network. See [Debugging](../advanced/debugging.md#built-in-tracing-and-inspection).

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
fact = engine.add_fact(:temperature, value: 85)
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
action = ->(facts) { puts "High temperature detected" }
rule = KBS::Rule.new("high_temp", priority: 10, conditions: [condition], action: action)

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

`run` fires activations in priority order, highest first. With the default `:definition` strategy, rules with equal priority fire in the order they were defined. Both `KBS::Engine` and `KBS::Blackboard::Engine` behave this way.

```ruby
# Both rules activated by same fact
condition = KBS::Condition.new(:temperature, {})
rule_a = KBS::Rule.new(:rule_a, conditions: [condition], action: ->(facts) { puts "a" }, priority: 1)
rule_b = KBS::Rule.new(:rule_b, conditions: [condition], action: ->(facts) { puts "b" }, priority: 5)

engine.add_rule(rule_a)  # Registered first
engine.add_rule(rule_b)  # Registered second

engine.add_fact(:temperature, value: 85)
engine.run
# rule_b fires first (higher priority), then rule_a
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
kb = KBS.knowledge_base do
  rule "expire_old_facts", priority: 0 do
    on :temperature, timestamp: ->(ts) { Time.now - ts > 3600 }
    perform do |facts|
      kb.retract(facts.first)
    end
  end
end
```

A predicate is tested when the fact is matched (added or modified), not again as time passes. This rule catches facts that are already old when they arrive; to expire facts as they age, sweep `engine.facts` periodically as above, or `modify` a clock fact the rule joins with.

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
      kb.assert(:error, rule: "risky_operation", message: e.message)
    end
  end
end
```

---

### Store Connection Errors

```ruby
begin
  engine = KBS::Blackboard::Engine.new(db_path: '/invalid/path/kb.db')
rescue SQLite3::CantOpenException => e
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
  def initialize(**options)
    @engine = KBS::Blackboard::Engine.new(**options)
    @mutex = Mutex.new
  end

  def add_fact(type, attributes = {})
    @mutex.synchronize { @engine.add_fact(type, attributes) }
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
