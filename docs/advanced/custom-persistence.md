# Custom Persistence

Implement custom storage backends for KBS by extending the `Store` interface. This guide covers implementing, testing, and optimizing custom persistence layers for PostgreSQL, MongoDB, or other databases.

## Store Interface

Custom stores must implement the `KBS::Blackboard::Persistence::Store` interface:

```ruby
module KBS
  module Blackboard
    module Persistence
      class Store
        # Fact Operations
        def save_fact(fact)
          raise NotImplementedError
        end

        def load_facts(type = nil)
          raise NotImplementedError
        end

        def update_fact(fact_id, attributes)
          raise NotImplementedError
        end

        def delete_fact(fact_id)
          raise NotImplementedError
        end

        # Message Queue Operations
        def send_message(topic, content, priority:)
          raise NotImplementedError
        end

        def pop_message(topic)
          raise NotImplementedError
        end

        # Audit Operations
        def log_fact_change(operation, fact, attributes = {})
          raise NotImplementedError
        end

        def fact_history(fact_id)
          raise NotImplementedError
        end

        def log_rule_firing(rule_name, fact_ids, bindings)
          raise NotImplementedError
        end

        def rule_firings(rule_name: nil, limit: 100)
          raise NotImplementedError
        end

        # Transaction Operations (optional)
        def transaction
          yield
        end

        def close
          # Cleanup resources
        end
      end
    end
  end
end
```

## PostgreSQL Store

### Implementation

```ruby
require 'pg'
require 'json'

class PostgresStore < KBS::Blackboard::Persistence::Store
  def initialize(connection_string:)
    @conn = PG.connect(connection_string)
    setup_tables
  end

  def setup_tables
    @conn.exec <<~SQL
      CREATE TABLE IF NOT EXISTS facts (
        id UUID PRIMARY KEY,
        fact_type VARCHAR(255) NOT NULL,
        attributes JSONB NOT NULL,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_facts_type ON facts(fact_type);
      CREATE INDEX IF NOT EXISTS idx_facts_attributes ON facts USING gin(attributes);

      CREATE TABLE IF NOT EXISTS messages (
        id SERIAL PRIMARY KEY,
        topic VARCHAR(255) NOT NULL,
        content JSONB NOT NULL,
        priority INTEGER NOT NULL,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_messages_topic_priority
        ON messages(topic, priority DESC);

      CREATE TABLE IF NOT EXISTS audit_log (
        id SERIAL PRIMARY KEY,
        fact_id UUID NOT NULL,
        operation VARCHAR(50) NOT NULL,
        attributes JSONB,
        timestamp TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_audit_fact_id ON audit_log(fact_id);

      CREATE TABLE IF NOT EXISTS rule_firings (
        id SERIAL PRIMARY KEY,
        rule_name VARCHAR(255) NOT NULL,
        fact_ids UUID[] NOT NULL,
        bindings JSONB NOT NULL,
        timestamp TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_rule_firings_name ON rule_firings(rule_name);
    SQL
  end

  # Fact Operations

  def save_fact(fact)
    @conn.exec_params(
      "INSERT INTO facts (id, fact_type, attributes) VALUES ($1, $2, $3)",
      [fact.id, fact.type.to_s, fact.attributes.to_json]
    )

    log_fact_change('add', fact, fact.attributes)
    fact
  end

  def load_facts(type = nil)
    query = if type
      @conn.exec_params(
        "SELECT id, fact_type, attributes, created_at FROM facts WHERE fact_type = $1",
        [type.to_s]
      )
    else
      @conn.exec("SELECT id, fact_type, attributes, created_at FROM facts")
    end

    query.map do |row|
      KBS::Blackboard::Fact.new(
        row['fact_type'].to_sym,
        JSON.parse(row['attributes'], symbolize_names: true),
        id: row['id'],
        created_at: Time.parse(row['created_at'])
      )
    end
  end

  def update_fact(fact_id, attributes)
    @conn.exec_params(
      "UPDATE facts SET attributes = $1, updated_at = NOW() WHERE id = $2",
      [attributes.to_json, fact_id]
    )

    log_fact_change('update', fact_id, attributes)
  end

  def delete_fact(fact_id)
    result = @conn.exec_params(
      "DELETE FROM facts WHERE id = $1 RETURNING attributes",
      [fact_id]
    )

    if result.ntuples > 0
      attrs = JSON.parse(result[0]['attributes'], symbolize_names: true)
      log_fact_change('delete', fact_id, attrs)
    end
  end

  # Message Queue Operations

  def send_message(topic, content, priority:)
    @conn.exec_params(
      "INSERT INTO messages (topic, content, priority) VALUES ($1, $2, $3)",
      [topic.to_s, content.to_json, priority]
    )
  end

  def pop_message(topic)
    # Atomic pop using DELETE RETURNING
    result = @conn.exec_params(<<~SQL, [topic.to_s])
      DELETE FROM messages
      WHERE id = (
        SELECT id FROM messages
        WHERE topic = $1
        ORDER BY priority DESC, created_at ASC
        LIMIT 1
        FOR UPDATE SKIP LOCKED
      )
      RETURNING content, priority
    SQL

    return nil if result.ntuples == 0

    {
      content: JSON.parse(result[0]['content'], symbolize_names: true),
      priority: result[0]['priority'].to_i
    }
  end

  # Audit Operations

  def log_fact_change(operation, fact_or_id, attributes)
    fact_id = fact_or_id.is_a?(String) ? fact_or_id : fact_or_id.id

    @conn.exec_params(
      "INSERT INTO audit_log (fact_id, operation, attributes) VALUES ($1, $2, $3)",
      [fact_id, operation, attributes.to_json]
    )
  end

  def fact_history(fact_id)
    result = @conn.exec_params(
      "SELECT operation, attributes, timestamp FROM audit_log WHERE fact_id = $1 ORDER BY timestamp",
      [fact_id]
    )

    result.map do |row|
      {
        operation: row['operation'],
        attributes: JSON.parse(row['attributes'], symbolize_names: true),
        timestamp: Time.parse(row['timestamp'])
      }
    end
  end

  def log_rule_firing(rule_name, fact_ids, bindings)
    @conn.exec_params(
      "INSERT INTO rule_firings (rule_name, fact_ids, bindings) VALUES ($1, $2, $3)",
      [rule_name, "{#{fact_ids.join(',')}}", bindings.to_json]
    )
  end

  def rule_firings(rule_name: nil, limit: 100)
    query = if rule_name
      @conn.exec_params(
        "SELECT rule_name, fact_ids, bindings, timestamp FROM rule_firings WHERE rule_name = $1 ORDER BY timestamp DESC LIMIT $2",
        [rule_name, limit]
      )
    else
      @conn.exec_params(
        "SELECT rule_name, fact_ids, bindings, timestamp FROM rule_firings ORDER BY timestamp DESC LIMIT $1",
        [limit]
      )
    end

    query.map do |row|
      {
        rule_name: row['rule_name'],
        fact_ids: row['fact_ids'].gsub(/[{}]/, '').split(','),
        bindings: JSON.parse(row['bindings'], symbolize_names: true),
        timestamp: Time.parse(row['timestamp'])
      }
    end
  end

  # Transaction Support

  def transaction
    @conn.exec("BEGIN")
    yield
    @conn.exec("COMMIT")
  rescue => e
    @conn.exec("ROLLBACK")
    raise e
  end

  def close
    @conn.close if @conn
  end
end

# Usage
store = PostgresStore.new(
  connection_string: "postgresql://localhost/kbs_production"
)

engine = KBS::Blackboard::Engine.new(store: store)
```

## MongoDB Store

### Implementation

```ruby
require 'mongo'
require 'securerandom'

class MongoStore < KBS::Blackboard::Persistence::Store
  def initialize(url:, database: 'kbs')
    @client = Mongo::Client.new(url)
    @db = @client.use(database)
    setup_collections
  end

  def setup_collections
    # Facts collection
    @facts = @db[:facts]
    @facts.indexes.create_one({ fact_type: 1 })
    @facts.indexes.create_one({ created_at: 1 })

    # Messages collection
    @messages = @db[:messages]
    @messages.indexes.create_one({ topic: 1, priority: -1, created_at: 1 })

    # Audit log
    @audit = @db[:audit_log]
    @audit.indexes.create_one({ fact_id: 1, timestamp: 1 })

    # Rule firings
    @rule_firings = @db[:rule_firings]
    @rule_firings.indexes.create_one({ rule_name: 1, timestamp: -1 })
  end

  # Fact Operations

  def save_fact(fact)
    doc = {
      _id: fact.id,
      fact_type: fact.type.to_s,
      attributes: fact.attributes,
      created_at: Time.now,
      updated_at: Time.now
    }

    @facts.insert_one(doc)

    log_fact_change('add', fact, fact.attributes)
    fact
  end

  def load_facts(type = nil)
    query = type ? { fact_type: type.to_s } : {}

    @facts.find(query).map do |doc|
      KBS::Blackboard::Fact.new(
        doc['fact_type'].to_sym,
        doc['attributes'].transform_keys(&:to_sym),
        id: doc['_id'],
        created_at: doc['created_at']
      )
    end
  end

  def update_fact(fact_id, attributes)
    @facts.update_one(
      { _id: fact_id },
      { '$set' => { attributes: attributes, updated_at: Time.now } }
    )

    log_fact_change('update', fact_id, attributes)
  end

  def delete_fact(fact_id)
    doc = @facts.find_one_and_delete({ _id: fact_id })

    if doc
      log_fact_change('delete', fact_id, doc['attributes'])
    end
  end

  # Message Queue Operations

  def send_message(topic, content, priority:)
    @messages.insert_one({
      topic: topic.to_s,
      content: content,
      priority: priority,
      created_at: Time.now
    })
  end

  def pop_message(topic)
    # Find highest priority message
    doc = @messages.find_one_and_delete(
      { topic: topic.to_s },
      sort: { priority: -1, created_at: 1 }
    )

    return nil unless doc

    {
      content: doc['content'].transform_keys(&:to_sym),
      priority: doc['priority']
    }
  end

  # Audit Operations

  def log_fact_change(operation, fact_or_id, attributes)
    fact_id = fact_or_id.is_a?(String) ? fact_or_id : fact_or_id.id

    @audit.insert_one({
      fact_id: fact_id,
      operation: operation,
      attributes: attributes,
      timestamp: Time.now
    })
  end

  def fact_history(fact_id)
    @audit.find({ fact_id: fact_id })
          .sort(timestamp: 1)
          .map do |doc|
      {
        operation: doc['operation'],
        attributes: doc['attributes'].transform_keys(&:to_sym),
        timestamp: doc['timestamp']
      }
    end
  end

  def log_rule_firing(rule_name, fact_ids, bindings)
    @rule_firings.insert_one({
      rule_name: rule_name,
      fact_ids: fact_ids,
      bindings: bindings,
      timestamp: Time.now
    })
  end

  def rule_firings(rule_name: nil, limit: 100)
    query = rule_name ? { rule_name: rule_name } : {}

    @rule_firings.find(query)
                 .sort(timestamp: -1)
                 .limit(limit)
                 .map do |doc|
      {
        rule_name: doc['rule_name'],
        fact_ids: doc['fact_ids'],
        bindings: doc['bindings'].transform_keys(&:to_sym),
        timestamp: doc['timestamp']
      }
    end
  end

  # Transaction Support (MongoDB 4.0+)

  def transaction
    session = @client.start_session

    session.with_transaction do
      yield
    end
  ensure
    session.end_session if session
  end

  def close
    @client.close if @client
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

```ruby
require 'minitest/autorun'

class TestCustomStore < Minitest::Test
  def setup
    @store = MyCustomStore.new
  end

  def teardown
    @store.close
  end

  def test_save_and_load_facts
    fact = KBS::Blackboard::Fact.new(:test, { value: 42 })

    @store.save_fact(fact)
    loaded = @store.load_facts(:test)

    assert_equal 1, loaded.size
    assert_equal 42, loaded.first[:value]
  end

  def test_load_facts_by_type
    @store.save_fact(KBS::Blackboard::Fact.new(:type_a, { value: 1 }))
    @store.save_fact(KBS::Blackboard::Fact.new(:type_b, { value: 2 }))

    type_a_facts = @store.load_facts(:type_a)

    assert_equal 1, type_a_facts.size
    assert_equal :type_a, type_a_facts.first.type
  end

  def test_update_fact
    fact = KBS::Blackboard::Fact.new(:test, { value: 1 })
    @store.save_fact(fact)

    @store.update_fact(fact.id, { value: 2 })

    loaded = @store.load_facts(:test)
    assert_equal 2, loaded.first[:value]
  end

  def test_delete_fact
    fact = KBS::Blackboard::Fact.new(:test, { value: 1 })
    @store.save_fact(fact)

    @store.delete_fact(fact.id)

    loaded = @store.load_facts(:test)
    assert_empty loaded
  end

  def test_message_queue
    @store.send_message(:alerts, { text: "High priority" }, priority: 100)
    @store.send_message(:alerts, { text: "Low priority" }, priority: 10)

    # Pop should return highest priority
    msg = @store.pop_message(:alerts)

    assert_equal "High priority", msg[:content][:text]
    assert_equal 100, msg[:priority]

    # Next pop gets lower priority
    msg = @store.pop_message(:alerts)
    assert_equal "Low priority", msg[:content][:text]
  end

  def test_message_queue_empty
    msg = @store.pop_message(:nonexistent)
    assert_nil msg
  end

  def test_fact_audit_trail
    fact = KBS::Blackboard::Fact.new(:test, { value: 1 })

    @store.save_fact(fact)
    @store.update_fact(fact.id, { value: 2 })
    @store.delete_fact(fact.id)

    history = @store.fact_history(fact.id)

    assert_equal 3, history.size
    assert_equal "add", history[0][:operation]
    assert_equal "update", history[1][:operation]
    assert_equal "delete", history[2][:operation]
  end

  def test_rule_firing_log
    @store.log_rule_firing("test_rule", ["fact1", "fact2"], { var: :value })

    firings = @store.rule_firings(rule_name: "test_rule")

    assert_equal 1, firings.size
    assert_equal "test_rule", firings.first[:rule_name]
    assert_equal ["fact1", "fact2"], firings.first[:fact_ids]
  end

  def test_transactions
    fact1 = KBS::Blackboard::Fact.new(:test, { value: 1 })
    fact2 = KBS::Blackboard::Fact.new(:test, { value: 2 })

    # Successful transaction
    @store.transaction do
      @store.save_fact(fact1)
      @store.save_fact(fact2)
    end

    assert_equal 2, @store.load_facts(:test).size

    # Failed transaction
    begin
      @store.transaction do
        @store.save_fact(KBS::Blackboard::Fact.new(:test, { value: 3 }))
        raise "Rollback!"
      end
    rescue
      # Expected
    end

    # Should still be 2 facts (transaction rolled back)
    assert_equal 2, @store.load_facts(:test).size
  end
end
```

## Performance Considerations

### 1. Connection Pooling

```ruby
class PooledPostgresStore < PostgresStore
  def initialize(connection_string:, pool_size: 10)
    @pool = ConnectionPool.new(size: pool_size) do
      PG.connect(connection_string)
    end

    # Setup using one connection
    @pool.with { |conn| setup_tables_with_conn(conn) }
  end

  def save_fact(fact)
    @pool.with do |conn|
      conn.exec_params(
        "INSERT INTO facts (id, fact_type, attributes) VALUES ($1, $2, $3)",
        [fact.id, fact.type.to_s, fact.attributes.to_json]
      )
    end

    fact
  end

  # ... other methods using @pool.with { |conn| ... }
end
```

### 2. Batch Operations

```ruby
def save_facts(facts)
  @conn.exec("BEGIN")

  facts.each do |fact|
    save_fact(fact)
  end

  @conn.exec("COMMIT")
rescue => e
  @conn.exec("ROLLBACK")
  raise e
end
```

### 3. Indexing

```ruby
def optimize_indexes
  # Add indexes for common queries
  @conn.exec(<<~SQL)
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_facts_created
      ON facts(created_at DESC);

    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_topic_priority
      ON messages(topic, priority DESC)
      WHERE topic IN ('alerts', 'critical');

    -- JSONB indexes for attribute queries
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_facts_value
      ON facts((attributes->>'value'));
  SQL
end
```

### 4. Caching

```ruby
class CachedStore < KBS::Blackboard::Persistence::Store
  def initialize(underlying_store, cache_ttl: 300)
    @store = underlying_store
    @cache = {}
    @cache_ttl = cache_ttl
  end

  def load_facts(type = nil)
    cache_key = "facts:#{type}"

    if cached = @cache[cache_key]
      return cached[:data] if Time.now - cached[:timestamp] < @cache_ttl
    end

    facts = @store.load_facts(type)

    @cache[cache_key] = {
      data: facts,
      timestamp: Time.now
    }

    facts
  end

  def save_fact(fact)
    result = @store.save_fact(fact)

    # Invalidate cache
    @cache.delete("facts:#{fact.type}")
    @cache.delete("facts:")

    result
  end

  # Delegate other methods
  def method_missing(method, *args, &block)
    @store.send(method, *args, &block)
  end
end
```

## Best Practices

### 1. Handle Errors Gracefully

```ruby
def save_fact(fact)
  retries = 0

  begin
    @conn.exec_params(...)
  rescue PG::ConnectionBad => e
    retries += 1

    if retries < 3
      reconnect
      retry
    else
      raise e
    end
  end
end
```

### 2. Use Prepared Statements

```ruby
def initialize(connection_string:)
  super
  @conn.prepare('save_fact',
    "INSERT INTO facts (id, fact_type, attributes) VALUES ($1, $2, $3)")
end

def save_fact(fact)
  @conn.exec_prepared('save_fact', [fact.id, fact.type.to_s, fact.attributes.to_json])
end
```

### 3. Implement Health Checks

```ruby
def healthy?
  @conn.exec("SELECT 1")
  true
rescue => e
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
