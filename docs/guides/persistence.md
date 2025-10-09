# Persistence Options

KBS offers multiple storage backends for persistent facts. This guide helps you choose and configure the right storage for your use case.

## Storage Backends

### 1. No Persistence (Default)

Transient in-memory facts using `KBS::Engine`:

```ruby
engine = KBS::Engine.new

# Facts exist only in memory
engine.add_fact(:sensor, { temp: 28 })

# Lost on exit
```

**When to use:**
- Prototyping
- Short-lived processes
- Pure computation (no state retention needed)
- Testing

**Pros:**
- ✅ Fastest (no I/O)
- ✅ Zero configuration
- ✅ Simple

**Cons:**
- ❌ No persistence
- ❌ Lost on crash
- ❌ No audit trail

### 2. SQLite (Default Persistent)

Embedded database using `KBS::Blackboard::Engine`:

```ruby
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')

engine.add_fact(:sensor, { temp: 28 })
engine.close

# Next run
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')
puts engine.facts.size  # => 1 (persisted)
```

**When to use:**
- Single-process applications
- Moderate fact volumes (< 1M facts)
- ACID transaction requirements
- Complete audit trails
- No external dependencies

**Pros:**
- ✅ Embedded (no server)
- ✅ ACID guarantees
- ✅ Durable
- ✅ Full audit trail
- ✅ SQL queries available

**Cons:**
- ❌ Slower than Redis
- ❌ Single writer
- ❌ Not distributed

**Configuration:**

```ruby
engine = KBS::Blackboard::Engine.new(
  db_path: 'kb.db',          # Database file path
  journal_mode: 'WAL'        # WAL mode for better concurrency
)
```

### 3. Redis (High Performance)

In-memory data structure store:

```ruby
require 'kbs/blackboard/persistence/redis_store'

store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)

engine = KBS::Blackboard::Engine.new(store: store)
```

**When to use:**
- High-frequency updates (> 1000 writes/sec)
- Real-time systems (trading, IoT)
- Distributed systems (multiple engines)
- Large fact volumes
- Speed is critical

**Pros:**
- ✅ 100x faster than SQLite
- ✅ Distributed (multiple engines share data)
- ✅ Perfect for real-time
- ✅ Scalable

**Cons:**
- ❌ Requires Redis server
- ❌ Volatile by default (enable RDB/AOF for persistence)
- ❌ No ACID across keys
- ❌ Less audit trail

**Configuration:**

```ruby
store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0',
  namespace: 'kbs',              # Key prefix
  ttl: 86400                     # Expire facts after 24h (optional)
)
```

**Redis Persistence Options:**

```bash
# In redis.conf:

# RDB: Point-in-time snapshots
save 900 1      # Save after 900s if 1 key changed
save 300 10     # Save after 300s if 10 keys changed

# AOF: Append-only file (durability)
appendonly yes
appendfsync everysec  # Sync to disk every second
```

### 4. Hybrid (Best of Both)

Combines Redis (speed) with SQLite (durability):

```ruby
require 'kbs/blackboard/persistence/hybrid_store'

store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',
  db_path: 'audit.db'
)

engine = KBS::Blackboard::Engine.new(store: store)
```

**How it works:**
- **Facts**: Stored in Redis (fast access)
- **Audit log**: Written to SQLite (durable history)
- **Messages**: Redis sorted sets (fast priority queue)

**When to use:**
- Production systems requiring both speed and auditing
- Regulatory compliance (need audit trail)
- High-frequency updates with history requirements
- Distributed systems needing accountability

**Pros:**
- ✅ Fast fact access (Redis)
- ✅ Durable audit trail (SQLite)
- ✅ Best of both worlds
- ✅ Can reconstruct from audit log

**Cons:**
- ❌ Requires both Redis and SQLite
- ❌ More complex setup
- ❌ Slightly slower writes (dual write)

**Configuration:**

```ruby
store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',
  db_path: 'audit.db',
  audit_facts: true,        # Log fact changes to SQLite
  audit_rules: true         # Log rule firings to SQLite
)
```

## Choosing a Backend

### Decision Tree

```
Need persistence?
├─ No → KBS::Engine (default)
└─ Yes
   │
   ├─ Need speed > 1000 ops/sec?
   │  ├─ Yes
   │  │  ├─ Need audit trail?
   │  │  │  ├─ Yes → Hybrid Store
   │  │  │  └─ No → Redis Store
   │  │  └─ No → Redis Store
   │  │
   │  └─ No
   │     ├─ Need distributed access?
   │     │  └─ Yes → Redis Store
   │     └─ No → SQLite Store
   │
   └─ Single machine, moderate load?
      └─ SQLite Store
```

### By Use Case

**IoT / Real-Time Sensors:**
```ruby
# High frequency, need speed
store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)
```

**Trading Systems:**
```ruby
# Speed + audit trail for compliance
store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',
  db_path: 'trading_audit.db'
)
```

**Expert Systems:**
```ruby
# Moderate load, need durability
engine = KBS::Blackboard::Engine.new(db_path: 'expert.db')
```

**Development / Testing:**
```ruby
# No persistence needed
engine = KBS::Engine.new
```

## Migration Between Backends

### SQLite → Redis

```ruby
# 1. Load from SQLite
sqlite_engine = KBS::Blackboard::Engine.new(db_path: 'old.db')
facts = sqlite_engine.facts

# 2. Save to Redis
redis_store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)
redis_engine = KBS::Blackboard::Engine.new(store: redis_store)

facts.each do |fact|
  redis_engine.add_fact(fact.type, fact.attributes)
end
```

### Redis → SQLite

```ruby
# 1. Load from Redis
redis_store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)
redis_engine = KBS::Blackboard::Engine.new(store: redis_store)
facts = redis_engine.facts

# 2. Save to SQLite
sqlite_engine = KBS::Blackboard::Engine.new(db_path: 'new.db')

facts.each do |fact|
  sqlite_engine.add_fact(fact.type, fact.attributes)
end

sqlite_engine.close
```

## Performance Comparison

### Write Performance

```ruby
require 'benchmark'

# SQLite
sqlite_engine = KBS::Blackboard::Engine.new(db_path: 'perf.db')
Benchmark.bm do |x|
  x.report("SQLite writes:") do
    10_000.times { |i| sqlite_engine.add_fact(:test, { value: i }) }
  end
end
# ~5,000 ops/sec

# Redis
redis_store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)
redis_engine = KBS::Blackboard::Engine.new(store: redis_store)
Benchmark.bm do |x|
  x.report("Redis writes:") do
    10_000.times { |i| redis_engine.add_fact(:test, { value: i }) }
  end
end
# ~50,000 ops/sec (10x faster)
```

### Read Performance

```ruby
# SQLite
Benchmark.bm do |x|
  x.report("SQLite reads:") do
    10_000.times { sqlite_engine.facts }
  end
end
# ~10,000 ops/sec

# Redis
Benchmark.bm do |x|
  x.report("Redis reads:") do
    10_000.times { redis_engine.facts }
  end
end
# ~100,000 ops/sec (10x faster)
```

## Custom Persistence

Implement your own backend by subclassing `KBS::Blackboard::Persistence::Store`:

```ruby
class PostgresStore < KBS::Blackboard::Persistence::Store
  def save_fact(fact)
    # Insert into PostgreSQL
  end

  def load_facts(type = nil)
    # Query from PostgreSQL
  end

  def delete_fact(id)
    # Delete from PostgreSQL
  end

  def save_message(topic, message, priority)
    # Store message
  end

  def pop_message(topic)
    # Retrieve highest priority message
  end

  def log_fact_change(operation, fact)
    # Audit logging
  end

  def fact_history(fact_id)
    # Get change history
  end
end

# Use custom store
store = PostgresStore.new(connection_string: "...")
engine = KBS::Blackboard::Engine.new(store: store)
```

See [Custom Persistence](../advanced/custom-persistence.md) for details.

## Configuration Best Practices

### SQLite

```ruby
# Enable WAL mode for better concurrency
engine = KBS::Blackboard::Engine.new(
  db_path: 'kb.db',
  journal_mode: 'WAL',
  synchronous: 'NORMAL',  # Trade some durability for speed
  cache_size: -64000      # 64MB cache
)
```

### Redis

```ruby
# Connection pooling for high concurrency
store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0',
  pool_size: 10,          # Connection pool size
  pool_timeout: 5         # Timeout in seconds
)
```

### Hybrid

```ruby
# Balance between speed and durability
store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',
  db_path: 'audit.db',
  batch_audit_writes: true,   # Batch SQLite writes
  audit_batch_size: 100       # Flush every 100 changes
)
```

## Troubleshooting

### SQLite Database Locked

```ruby
# Increase busy timeout
engine = KBS::Blackboard::Engine.new(
  db_path: 'kb.db',
  busy_timeout: 5000  # Wait up to 5 seconds
)
```

### Redis Connection Issues

```ruby
# Enable retry logic
store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0',
  reconnect_attempts: 3,
  reconnect_delay: 1.0
)
```

### Hybrid Sync Issues

```ruby
# Force synchronous audit writes
store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',
  db_path: 'audit.db',
  sync_audit_writes: true  # Don't batch, write immediately
)
```

## Next Steps

- **[Blackboard Memory](blackboard-memory.md)** - Using persistent blackboard
- **[Custom Persistence](../advanced/custom-persistence.md)** - Implementing custom stores
- **[Performance Guide](../advanced/performance.md)** - Optimizing storage performance
- **[API Reference](../api/blackboard.md)** - Complete blackboard API

---

*Choose your backend based on speed, durability, and distribution requirements.*
