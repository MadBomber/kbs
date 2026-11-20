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
require 'kbs/blackboard'  # not loaded by require 'kbs'

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
- ✅ SQL queries available (`engine.blackboard.query_facts(sql, params)`)

**Cons:**
- ❌ Slower than Redis
- ❌ Single writer
- ❌ Not distributed

**Configuration:**

```ruby
engine = KBS::Blackboard::Engine.new(
  db_path: 'kb.db'           # Database file path (default ':memory:')
)

# WAL mode for better concurrency, set on the SQLite3::Database
engine.blackboard.store.db.execute("PRAGMA journal_mode = WAL")
```

### 3. Redis (High Performance)

In-memory data structure store:

```ruby
require 'kbs/blackboard'  # the Redis stores also need the redis gem

store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)

engine = KBS::Blackboard::Engine.new(store: store)
```

With a Redis store the message queue and audit log are kept in Redis too.

**When to use:**
- High-frequency updates (> 1000 writes/sec)
- Real-time systems (trading, IoT)
- Distributed systems (multiple engines)
- Large fact volumes
- Speed is critical

**Pros:**
- ✅ Faster than SQLite for high write rates
- ✅ Distributed (multiple engines share data)
- ✅ Perfect for real-time
- ✅ Scalable

**Cons:**
- ❌ Requires Redis server
- ❌ Volatile by default (enable RDB/AOF for persistence)
- ❌ No ACID across keys
- ❌ Audit trail capped (latest 1,000 entries per fact or rule, 10,000 overall) and no SQL queries

**Configuration:**

```ruby
store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0',  # Ignored when redis: is given
  session_id: nil,                  # Defaults to a new UUID
  redis: nil                        # An existing Redis client to use
)
```

Retracted facts stay in Redis until `engine.blackboard.vacuum` removes those retracted more than 30 days ago.

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
require 'kbs/blackboard'

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
- ❌ Slightly slower writes (each change also writes the SQLite audit log)
- ❌ No transactions (Redis and SQLite writes are separate)

**Configuration:**

```ruby
store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',  # Ignored when redis: is given
  redis: nil,                              # An existing Redis client
  db_path: 'audit.db',                     # SQLite audit log (the default)
  session_id: nil                          # Defaults to a new UUID
)
```

Fact changes and rule firings are always logged to SQLite.

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
```

### Read Performance

```ruby
# SQLite
Benchmark.bm do |x|
  x.report("SQLite reads:") do
    100.times { sqlite_engine.facts }
  end
end

# Redis
Benchmark.bm do |x|
  x.report("Redis reads:") do
    100.times { redis_engine.facts }
  end
end
```

Results depend on your hardware, Redis setup and SQLite pragmas; run these against your own workload. `engine.facts` reads every active fact from the store each time, so it slows as the store grows.

## Custom Persistence

Implement your own backend by subclassing `KBS::Blackboard::Persistence::Store`. A store keeps facts only; the blackboard picks its message queue and audit log by what the store offers, so it must also respond to `db` (a SQLite3 database) or `connection` (a Redis client):

```ruby
class PostgresStore < KBS::Blackboard::Persistence::Store
  attr_reader :session_id

  def add_fact(uuid, type, attributes)
    # Insert into PostgreSQL
  end

  def remove_fact(uuid)
    # Mark retracted; return { type:, attributes: }, or nil if not found
  end

  def update_fact(uuid, attributes)
    # Replace attributes; return the fact's type, or nil
  end

  def get_fact(uuid)
    # Return { uuid:, type:, attributes: }, or nil
  end

  def get_facts(type = nil, pattern = {})
    # Return an Array of { uuid:, type:, attributes: } for active facts
  end

  def transaction
    yield
  end

  # Also: query_facts, register_knowledge_source, clear_session,
  # stats, vacuum, close

  def connection
    # A Redis client for the message queue and audit log
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
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')
db = engine.blackboard.store.db

db.execute("PRAGMA journal_mode = WAL")
db.execute("PRAGMA synchronous = NORMAL")  # Trade some durability for speed
db.execute("PRAGMA cache_size = -64000")   # 64MB cache
```

### Redis

```ruby
# Configure the client yourself and pass it in
client = Redis.new(url: 'redis://localhost:6379/0', timeout: 5)

store = KBS::Blackboard::Persistence::RedisStore.new(redis: client)
```

### Hybrid

The hybrid store writes each audit record to SQLite as the change happens; there is no batching to configure.

## Troubleshooting

### SQLite Database Locked

```ruby
# Increase busy timeout
engine = KBS::Blackboard::Engine.new(db_path: 'kb.db')
engine.blackboard.store.db.busy_timeout = 5000  # Wait up to 5 seconds
```

### Redis Connection Issues

```ruby
# Enable retry logic on the client
client = Redis.new(
  url: 'redis://localhost:6379/0',
  reconnect_attempts: 3
)

store = KBS::Blackboard::Persistence::RedisStore.new(redis: client)
```

## Next Steps

- **[Blackboard Memory](blackboard-memory.md)** - Using persistent blackboard
- **[Custom Persistence](../advanced/custom-persistence.md)** - Implementing custom stores
- **[Performance Guide](../advanced/performance.md)** - Optimizing storage performance
- **[API Reference](../api/blackboard.md)** - Complete blackboard API

---

*Choose your backend based on speed, durability, and distribution requirements.*
