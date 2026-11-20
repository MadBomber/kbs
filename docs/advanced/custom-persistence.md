# Custom Persistence

Implement custom storage backends for KBS by extending the `Store` interface. This guide covers implementing, testing, and optimizing custom persistence layers for PostgreSQL, MongoDB, or other databases.

## Store Interface

A store keeps the blackboard's facts. `KBS::Blackboard::Persistence::Store` is the abstract base class; KBS ships `SqliteStore`, `RedisStore` and `HybridStore` built on it:

```ruby
module KBS
  module Blackboard
    module Persistence
      class Store
        def session_id
          nil
        end

        def register_knowledge_source(name, description: nil, topics: [])
          raise NotImplementedError, "#{self.class} must implement #register_knowledge_source"
        end

        def add_fact(uuid, type, attributes)
          raise NotImplementedError, "#{self.class} must implement #add_fact"
        end

        def remove_fact(uuid)
          raise NotImplementedError, "#{self.class} must implement #remove_fact"
        end

        def update_fact(uuid, attributes)
          raise NotImplementedError, "#{self.class} must implement #update_fact"
        end

        def get_fact(uuid)
          raise NotImplementedError, "#{self.class} must implement #get_fact"
        end

        def get_facts(type = nil, pattern = {})
          raise NotImplementedError, "#{self.class} must implement #get_facts"
        end

        def query_facts(conditions = nil, params = [])
          raise NotImplementedError, "#{self.class} must implement #query_facts"
        end

        def clear_session(session_id)
          raise NotImplementedError, "#{self.class} must implement #clear_session"
        end

        def stats
          raise NotImplementedError, "#{self.class} must implement #stats"
        end

        def close
          raise NotImplementedError, "#{self.class} must implement #close"
        end

        def vacuum
          # Optional operation - no-op by default
        end

        def transaction(&)
          # Default: just execute the block
          yield if block_given?
        end
      end
    end
  end
end
```

### What Each Method Must Do

`KBS::Blackboard::Memory` (the blackboard behind `KBS::Blackboard::Engine`) calls these methods and relies on what they return. A fact row is a Hash `{ uuid:, type:, attributes: }` with `type` a Symbol and `attributes` a Hash with Symbol keys.

| Method | Called when | Must return |
|--------|-------------|-------------|
| `add_fact(uuid, type, attributes)` | a fact is added; KBS makes the uuid | ignored |
| `remove_fact(uuid)` | a fact is retracted | `{ type:, attributes: }` of the removed fact, or `nil` if there is no such active fact |
| `update_fact(uuid, attributes)` | `Fact#update`, `Fact#[]=`, `engine.modify`; `attributes` is the complete new set | the fact's type (Symbol), or `nil` if there is no such active fact |
| `get_fact(uuid)` | `engine.modify`, `blackboard.find_fact` | a fact row, or `nil` |
| `get_facts(type = nil, pattern = {})` | `engine.facts`, `blackboard.get_facts`, adding a rule | an Array of fact rows; `pattern` values may be Procs, called with the attribute's value |
| `query_facts(conditions = nil, params = [])` | `blackboard.query_facts` | an Array of fact rows; a store without a query language may raise `NotImplementedError` (as `RedisStore` does) |
| `register_knowledge_source(name, description: nil, topics: [])` | `blackboard.register_knowledge_source` | ignored |
| `clear_session(session_id)` | `blackboard.clear_session` | ignored |
| `stats` | `engine.stats` | a Hash; it is merged with the message queue's and audit log's stats |
| `vacuum`, `close` | `blackboard.vacuum`, `engine.close` | ignored |
| `transaction { ... }` | around every add, remove, update and message consume | the block's value |
| `session_id` | `Memory.new`, to share the store's session | a String, or `nil` (the base class default) to let `Memory` make one |

The base class's `register_knowledge_source` raises `NotImplementedError`, like the other abstract methods. When a `Memory#transaction` block raises, `Memory` calls `get_fact` for each fact the block added and tells the engine about those that are gone, so a store that rolls back keeps the engine in step.

### Messages and the Audit Log

The store holds only facts. `Memory` builds the message queue and the audit log itself, from a database connection the store exposes:

- a store that responds to `connection` gets a Redis message queue and audit log on `store.connection` (a `Redis` client)
- a store that responds to `db` gets SQLite ones on `store.db` (a `SQLite3::Database` with `results_as_hash = true`)
- a store with `hybrid?` returning true and both methods gets Redis messages and a SQLite audit log, like `HybridStore`
- any other store raises `ArgumentError` when the blackboard is created

So a store for another database keeps its facts there and offers a SQLite database (or a Redis client) for messages and the audit trail. Writes to that database are not part of the store's own transactions.

## PostgreSQL Store

### Implementation

```ruby
require 'pg'
require 'json'
require 'securerandom'
require 'sqlite3'
require 'kbs/blackboard'

class PostgresStore < KBS::Blackboard::Persistence::Store
  # The blackboard puts its message queue and audit log in `db`.
  attr_reader :session_id, :db

  def initialize(connection_string:, session_id: nil, audit_db_path: ':memory:')
    super()
    @session_id = session_id || SecureRandom.uuid
    @transaction_depth = 0
    @conn = PG.connect(connection_string)
    @db = SQLite3::Database.new(audit_db_path)
    @db.results_as_hash = true
    setup_tables
  end

  def setup_tables
    @conn.exec <<~SQL
      CREATE TABLE IF NOT EXISTS facts (
        uuid UUID PRIMARY KEY,
        fact_type VARCHAR(255) NOT NULL,
        attributes JSONB NOT NULL,
        session_id VARCHAR(255),
        retracted BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_facts_type ON facts(fact_type);
      CREATE INDEX IF NOT EXISTS idx_facts_session ON facts(session_id);
      CREATE INDEX IF NOT EXISTS idx_facts_attributes ON facts USING gin(attributes);

      CREATE TABLE IF NOT EXISTS knowledge_sources (
        name VARCHAR(255) PRIMARY KEY,
        description TEXT,
        topics JSONB NOT NULL DEFAULT '[]',
        registered_at TIMESTAMP DEFAULT NOW()
      );
    SQL
  end

  # Fact Operations

  def add_fact(uuid, type, attributes)
    exec(
      "INSERT INTO facts (uuid, fact_type, attributes, session_id) VALUES ($1, $2, $3, $4)",
      [uuid, type.to_s, JSON.generate(attributes), @session_id]
    )
  end

  def remove_fact(uuid)
    result = exec(<<~SQL, [uuid])
      UPDATE facts SET retracted = TRUE, updated_at = NOW()
      WHERE uuid = $1 AND NOT retracted
      RETURNING fact_type, attributes
    SQL

    return nil if result.ntuples.zero?

    row = result[0]
    { type: row['fact_type'].to_sym, attributes: parse(row['attributes']) }
  end

  def update_fact(uuid, attributes)
    result = exec(<<~SQL, [JSON.generate(attributes), uuid])
      UPDATE facts SET attributes = $1, updated_at = NOW()
      WHERE uuid = $2 AND NOT retracted
      RETURNING fact_type
    SQL

    result.ntuples.zero? ? nil : result[0]['fact_type'].to_sym
  end

  def get_fact(uuid)
    result = exec("SELECT * FROM facts WHERE uuid = $1 AND NOT retracted", [uuid])
    result.ntuples.zero? ? nil : fact_row(result[0])
  end

  def get_facts(type = nil, pattern = {})
    result = if type
      exec("SELECT * FROM facts WHERE NOT retracted AND fact_type = $1 ORDER BY created_at", [type.to_s])
    else
      exec("SELECT * FROM facts WHERE NOT retracted ORDER BY created_at")
    end

    result.map { |row| fact_row(row) }
          .select { |fact| matches_pattern?(fact[:attributes], pattern) }
  end

  # `conditions` is a SQL fragment with $1, $2 ... placeholders.
  def query_facts(conditions = nil, params = [])
    sql = "SELECT * FROM facts WHERE NOT retracted"
    sql += " AND #{conditions}" if conditions

    exec(sql, params).map { |row| fact_row(row) }
  end

  def register_knowledge_source(name, description: nil, topics: [])
    exec(<<~SQL, [name, description, JSON.generate(topics)])
      INSERT INTO knowledge_sources (name, description, topics) VALUES ($1, $2, $3)
      ON CONFLICT (name) DO UPDATE SET description = EXCLUDED.description, topics = EXCLUDED.topics
    SQL
  end

  def clear_session(session_id)
    exec("UPDATE facts SET retracted = TRUE, updated_at = NOW() WHERE session_id = $1", [session_id])
  end

  def stats
    {
      total_facts: exec("SELECT COUNT(*) FROM facts")[0]['count'].to_i,
      active_facts: exec("SELECT COUNT(*) FROM facts WHERE NOT retracted")[0]['count'].to_i,
      knowledge_sources: exec("SELECT COUNT(*) FROM knowledge_sources")[0]['count'].to_i
    }
  end

  def vacuum
    exec("VACUUM facts")
  end

  # Transaction Support
  #
  # Transactions nest (a removal can retract logically supported facts
  # inside its own transaction, and callers can wrap several writes in
  # blackboard.transaction), so only the outermost block opens a
  # PostgreSQL transaction. An exception
  # rolls it back and is raised again.
  def transaction
    @transaction_depth += 1
    @transaction_depth == 1 ? @conn.transaction { yield } : yield
  ensure
    @transaction_depth -= 1
  end

  def close
    @conn.close unless @conn.finished?
    @db.close unless @db.closed?
  end

  private

  def exec(sql, params = [])
    @conn.exec_params(sql, params)
  end

  def parse(json)
    JSON.parse(json, symbolize_names: true)
  end

  def fact_row(row)
    { uuid: row['uuid'], type: row['fact_type'].to_sym, attributes: parse(row['attributes']) }
  end

  def matches_pattern?(attributes, pattern)
    pattern.all? do |key, value|
      actual = attributes[key]
      value.is_a?(Proc) ? actual && value.call(actual) : actual == value
    end
  end
end

# Usage
store = PostgresStore.new(
  connection_string: "postgresql://localhost/kbs_production",
  audit_db_path: "kbs_audit.db"
)

engine = KBS::Blackboard::Engine.new(store: store)
```

Attributes go through JSON, as they do in `SqliteStore`: a Symbol value comes back from the store as a String.

## MongoDB Store

### Implementation

The same contract on MongoDB. Attributes are kept as a JSON string so they come back with Symbol keys, like the other stores. Multi-document transactions need a replica set, so this store keeps the base class's `transaction`, which just runs the block.

```ruby
require 'mongo'
require 'json'
require 'securerandom'
require 'sqlite3'
require 'kbs/blackboard'

class MongoStore < KBS::Blackboard::Persistence::Store
  attr_reader :session_id, :db

  def initialize(url:, database: 'kbs', session_id: nil, audit_db_path: ':memory:')
    super()
    @session_id = session_id || SecureRandom.uuid
    @client = Mongo::Client.new(url, database: database)
    @db = SQLite3::Database.new(audit_db_path)
    @db.results_as_hash = true
    setup_collections
  end

  def setup_collections
    @facts = @client[:facts]
    @facts.indexes.create_one({ uuid: 1 }, unique: true)
    @facts.indexes.create_one({ fact_type: 1, retracted: 1 })
    @facts.indexes.create_one({ session_id: 1 })

    @knowledge_sources = @client[:knowledge_sources]
  end

  # Fact Operations

  def add_fact(uuid, type, attributes)
    now = Time.now
    @facts.insert_one(
      uuid: uuid,
      fact_type: type.to_s,
      attributes: JSON.generate(attributes),
      session_id: @session_id,
      retracted: false,
      created_at: now,
      updated_at: now
    )
  end

  def remove_fact(uuid)
    doc = @facts.find_one_and_update(
      { uuid: uuid, retracted: false },
      { '$set' => { retracted: true, updated_at: Time.now } }
    )

    doc && { type: doc['fact_type'].to_sym, attributes: parse(doc['attributes']) }
  end

  def update_fact(uuid, attributes)
    doc = @facts.find_one_and_update(
      { uuid: uuid, retracted: false },
      { '$set' => { attributes: JSON.generate(attributes), updated_at: Time.now } }
    )

    doc && doc['fact_type'].to_sym
  end

  def get_fact(uuid)
    doc = @facts.find(uuid: uuid, retracted: false).first
    doc && fact_row(doc)
  end

  def get_facts(type = nil, pattern = {})
    query = { retracted: false }
    query[:fact_type] = type.to_s if type

    @facts.find(query).sort(created_at: 1)
          .map { |doc| fact_row(doc) }
          .select { |fact| matches_pattern?(fact[:attributes], pattern) }
  end

  # `conditions` is a MongoDB filter Hash on the stored document.
  def query_facts(conditions = nil, _params = [])
    @facts.find({ retracted: false }.merge(conditions || {})).map { |doc| fact_row(doc) }
  end

  def register_knowledge_source(name, description: nil, topics: [])
    @knowledge_sources.update_one(
      { name: name },
      { '$set' => { description: description, topics: topics, registered_at: Time.now } },
      upsert: true
    )
  end

  def clear_session(session_id)
    @facts.update_many(
      { session_id: session_id, retracted: false },
      { '$set' => { retracted: true, updated_at: Time.now } }
    )
  end

  def stats
    {
      total_facts: @facts.count_documents({}),
      active_facts: @facts.count_documents(retracted: false),
      knowledge_sources: @knowledge_sources.count_documents({})
    }
  end

  def close
    @client.close
    @db.close unless @db.closed?
  end

  private

  def parse(json)
    JSON.parse(json, symbolize_names: true)
  end

  def fact_row(doc)
    { uuid: doc['uuid'], type: doc['fact_type'].to_sym, attributes: parse(doc['attributes']) }
  end

  def matches_pattern?(attributes, pattern)
    pattern.all? do |key, value|
      actual = attributes[key]
      value.is_a?(Proc) ? actual && value.call(actual) : actual == value
    end
  end
end

# Usage
store = MongoStore.new(
  url: 'mongodb://localhost:27017',
  database: 'kbs_production'
)

engine = KBS::Blackboard::Engine.new(store: store)
```

## Testing Custom Stores

### Test Suite

The tests call the store the way `Memory` does, then run it under a real engine. Replace `build_store` with your store.

```ruby
require 'minitest/autorun'
require 'securerandom'
require 'kbs/blackboard'

class TestCustomStore < Minitest::Test
  def build_store
    MyCustomStore.new
  end

  def setup
    @store = build_store
  end

  def teardown
    @store.close
  end

  def new_uuid
    SecureRandom.uuid
  end

  def test_add_and_get_fact
    uuid = new_uuid
    @store.add_fact(uuid, :test, { value: 42 })

    fact = @store.get_fact(uuid)

    assert_equal uuid, fact[:uuid]
    assert_equal :test, fact[:type]
    assert_equal({ value: 42 }, fact[:attributes])
  end

  def test_get_facts_by_type_and_pattern
    @store.add_fact(new_uuid, :type_a, { value: 1 })
    @store.add_fact(new_uuid, :type_a, { value: 5 })
    @store.add_fact(new_uuid, :type_b, { value: 2 })

    assert_equal 2, @store.get_facts(:type_a).size
    assert_equal 3, @store.get_facts.size

    big = @store.get_facts(:type_a, { value: ->(v) { v > 3 } })
    assert_equal [5], big.map { |fact| fact[:attributes][:value] }
  end

  def test_update_fact
    uuid = new_uuid
    @store.add_fact(uuid, :test, { value: 1 })

    assert_equal :test, @store.update_fact(uuid, { value: 2 })
    assert_equal 2, @store.get_fact(uuid)[:attributes][:value]
    assert_nil @store.update_fact(new_uuid, { value: 3 })
  end

  def test_remove_fact
    uuid = new_uuid
    @store.add_fact(uuid, :test, { value: 1 })

    removed = @store.remove_fact(uuid)

    assert_equal({ type: :test, attributes: { value: 1 } }, removed)
    assert_nil @store.get_fact(uuid)
    assert_empty @store.get_facts(:test)
    assert_nil @store.remove_fact(uuid)
  end

  def test_clear_session
    @store.add_fact(new_uuid, :test, { value: 1 })

    @store.clear_session(@store.session_id)

    assert_empty @store.get_facts
  end

  def test_stats
    @store.add_fact(new_uuid, :test, { value: 1 })
    @store.register_knowledge_source("sensor_agent", description: "Reads sensors", topics: ["temp"])

    stats = @store.stats

    assert_equal 1, stats[:active_facts]
    assert_equal 1, stats[:knowledge_sources]
  end

  def test_transaction_rolls_back
    @store.transaction { @store.add_fact(new_uuid, :test, { value: 1 }) }

    assert_raises(RuntimeError) do
      @store.transaction do
        @store.add_fact(new_uuid, :test, { value: 2 })
        raise "Rollback!"
      end
    end

    # Only for stores with real transactions
    assert_equal 1, @store.get_facts(:test).size
  end

  def test_works_under_an_engine
    engine = KBS::Blackboard::Engine.new(store: @store)
    alerts = []
    engine.add_rule(KBS::Rule.new("hot",
      conditions: [KBS::Condition.new(:sensor, { value: ->(v) { v > 30 } })],
      action: ->(facts) { alerts << facts.first[:value] }))

    fact = engine.add_fact(:sensor, value: 35)
    engine.run
    engine.modify(fact, value: 40)
    engine.run
    engine.post_message("agent", "alerts", { text: "hot" }, priority: 5)

    assert_equal [35, 40], alerts
    assert_equal({ value: 40 }, engine.blackboard.find_fact(fact.uuid).attributes)
    assert_equal "hot", engine.consume_message("alerts", "tester")[:content][:text]
    assert_equal %w[UPDATE ADD], engine.blackboard.get_history(fact.uuid).map { |entry| entry[:action] }
  end
end
```

## Performance Considerations

### 1. Connection Pooling

A pool hands each call its own connection, so the statements of one transaction must share the connection the transaction checked out. With the `connection_pool` gem, and `PostgresStore` running all its SQL through `exec`:

```ruby
require 'connection_pool'

class PooledPostgresStore < PostgresStore
  def initialize(connection_string:, pool_size: 10, **options)
    @pool = ConnectionPool.new(size: pool_size) { PG.connect(connection_string) }
    super(connection_string: connection_string, **options)
  end

  def transaction
    return yield if current_connection

    @pool.with do |conn|
      Thread.current[:kbs_pg_connection] = conn
      conn.transaction { yield }
    ensure
      Thread.current[:kbs_pg_connection] = nil
    end
  end

  def close
    @pool.shutdown(&:close)
    super
  end

  private

  def current_connection
    Thread.current[:kbs_pg_connection]
  end

  def exec(sql, params = [])
    conn = current_connection
    return conn.exec_params(sql, params) if conn

    @pool.with { |pooled| pooled.exec_params(sql, params) }
  end
end
```

### 2. Batch Operations

`Memory#transaction` runs a block in the store's transaction, so many facts can be added with one commit:

```ruby
engine.blackboard.transaction do
  readings.each do |reading|
    engine.add_fact(:sensor, reading)
  end
end
```

### 3. Indexing

`CREATE INDEX CONCURRENTLY` cannot run inside a transaction, so issue each one on its own:

```ruby
def optimize_indexes
  # Add indexes for common queries
  @conn.exec(<<~SQL)
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_facts_active_type
      ON facts(fact_type) WHERE NOT retracted
  SQL

  # JSONB index for attribute queries
  @conn.exec(<<~SQL)
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_facts_value
      ON facts((attributes->>'value'))
  SQL
end
```

### 4. Caching

A caching wrapper has to pass through `db`, `connection` and `hybrid?` exactly as the store underneath answers them, since `Memory` picks the message queue and audit log by asking `respond_to?`.

```ruby
class CachedStore < KBS::Blackboard::Persistence::Store
  def initialize(underlying_store, cache_ttl: 300)
    @store = underlying_store
    @cache = {}
    @cache_ttl = cache_ttl
  end

  def get_facts(type = nil, pattern = {})
    return @store.get_facts(type, pattern) unless pattern.empty?

    cache_key = "facts:#{type}"

    if (cached = @cache[cache_key])
      return cached[:data] if Time.now - cached[:timestamp] < @cache_ttl
    end

    facts = @store.get_facts(type)

    @cache[cache_key] = {
      data: facts,
      timestamp: Time.now
    }

    facts
  end

  # Writes invalidate the cache
  def add_fact(uuid, type, attributes)
    @cache.clear
    @store.add_fact(uuid, type, attributes)
  end

  def remove_fact(uuid)
    @cache.clear
    @store.remove_fact(uuid)
  end

  def update_fact(uuid, attributes)
    @cache.clear
    @store.update_fact(uuid, attributes)
  end

  def clear_session(session_id)
    @cache.clear
    @store.clear_session(session_id)
  end

  # Delegate everything else
  %i[get_fact query_facts stats vacuum close session_id].each do |name|
    define_method(name) { |*args, **kwargs, &block| @store.public_send(name, *args, **kwargs, &block) }
  end

  def transaction(&)
    @store.transaction(&)
  end

  def register_knowledge_source(...)
    @store.register_knowledge_source(...)
  end

  def respond_to_missing?(name, include_private = false)
    @store.respond_to?(name, include_private) || super
  end

  def method_missing(name, ...)
    @store.respond_to?(name) ? @store.public_send(name, ...) : super
  end
end

# Usage
engine = KBS::Blackboard::Engine.new(store: CachedStore.new(store))
```

## Best Practices

### 1. Handle Errors Gracefully

```ruby
def add_fact(uuid, type, attributes)
  retries = 0

  begin
    exec(
      "INSERT INTO facts (uuid, fact_type, attributes, session_id) VALUES ($1, $2, $3, $4)",
      [uuid, type.to_s, JSON.generate(attributes), @session_id]
    )
  rescue PG::ConnectionBad => e
    retries += 1

    if retries < 3
      @conn.reset
      retry
    else
      raise e
    end
  end
end
```

### 2. Use Prepared Statements

```ruby
def initialize(connection_string:, **options)
  super
  @conn.prepare('add_fact',
    "INSERT INTO facts (uuid, fact_type, attributes, session_id) VALUES ($1, $2, $3, $4)")
end

def add_fact(uuid, type, attributes)
  @conn.exec_prepared('add_fact', [uuid, type.to_s, JSON.generate(attributes), @session_id])
end
```

### 3. Implement Health Checks

```ruby
def healthy?
  @conn.exec("SELECT 1")
  true
rescue PG::Error
  false
end
```

## Next Steps

- **[Persistence Guide](../guides/persistence.md)** - Choosing backends
- **[Testing Guide](testing.md)** - Testing custom stores
- **[Performance Guide](performance.md)** - Optimizing queries
- **[API Reference](../api/blackboard.md)** - Complete API documentation

---

*Custom stores enable KBS to work with any database. Implement the Store interface and test thoroughly.*
