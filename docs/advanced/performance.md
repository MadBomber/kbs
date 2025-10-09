# Performance Tuning

Optimize KBS applications for speed, scalability, and efficiency. This guide covers profiling, benchmarking, rule optimization, and storage backend selection.

## Performance Overview

KBS performance depends on:

1. **Rule Complexity** - Number of conditions, predicates, and joins
2. **Fact Volume** - Size of working memory
3. **Network Structure** - Shared nodes and network branching
4. **Storage Backend** - SQLite, Redis, or in-memory
5. **Action Efficiency** - Time spent in rule actions

## Benchmarking

### Basic Benchmark

```ruby
require 'benchmark'
require 'kbs'

engine = KBS::Engine.new

# Add rules
rule = KBS::Rule.new("simple_rule") do |r|
  r.conditions = [
    KBS::Condition.new(:fact, { value: :?v })
  ]

  r.action = lambda do |facts, bindings|
    # Simple action
  end
end

engine.add_rule(rule)

# Benchmark fact addition
time = Benchmark.measure do
  10_000.times do |i|
    engine.add_fact(:fact, { value: i })
  end
end

puts "Added 10,000 facts in #{time.real} seconds"
puts "#{(10_000 / time.real).round(2)} facts/second"

# Benchmark engine run
time = Benchmark.measure do
  engine.run
end

puts "Ran engine in #{time.real} seconds"
```

### Comprehensive Benchmark

```ruby
require 'benchmark'

class KBSBenchmark
  def initialize(engine_type: :memory)
    @engine_type = engine_type
    @results = {}
  end

  def setup_engine
    case @engine_type
    when :memory
      KBS::Engine.new
    when :blackboard_sqlite
      KBS::Blackboard::Engine.new(db_path: ':memory:')
    when :blackboard_redis
      require 'kbs/blackboard/persistence/redis_store'
      store = KBS::Blackboard::Persistence::RedisStore.new(
        url: 'redis://localhost:6379/15'  # Test database
      )
      KBS::Blackboard::Engine.new(store: store)
    end
  end

  def benchmark_fact_addition(count: 10_000)
    engine = setup_engine

    time = Benchmark.measure do
      count.times do |i|
        engine.add_fact(:fact, { id: i, value: rand(1000) })
      end
    end

    @results[:fact_addition] = {
      count: count,
      time: time.real,
      rate: (count / time.real).round(2)
    }
  end

  def benchmark_simple_rules(fact_count: 1000, rule_count: 10)
    engine = setup_engine

    # Add rules
    rule_count.times do |i|
      rule = KBS::Rule.new("rule_#{i}") do |r|
        r.conditions = [
          KBS::Condition.new(:fact, { value: :?v })
        ]

        r.action = lambda do |facts, bindings|
          # Minimal action
        end
      end
      engine.add_rule(rule)
    end

    # Add facts
    fact_count.times do |i|
      engine.add_fact(:fact, { value: i })
    end

    # Benchmark engine run
    time = Benchmark.measure do
      engine.run
    end

    @results[:simple_rules] = {
      fact_count: fact_count,
      rule_count: rule_count,
      time: time.real
    }
  end

  def benchmark_complex_joins(fact_count: 500)
    engine = setup_engine

    # Rule with 3-way join
    rule = KBS::Rule.new("complex_join") do |r|
      r.conditions = [
        KBS::Condition.new(:a, { id: :?id, value: :?v }),
        KBS::Condition.new(:b, { a_id: :?id, score: :?s }),
        KBS::Condition.new(:c, { b_score: :?s })
      ]

      r.action = lambda do |facts, bindings|
        # Action
      end
    end

    engine.add_rule(rule)

    # Add facts
    fact_count.times do |i|
      engine.add_fact(:a, { id: i, value: rand(100) })
      engine.add_fact(:b, { a_id: i, score: rand(100) })
      engine.add_fact(:c, { b_score: i })
    end

    # Benchmark
    time = Benchmark.measure do
      engine.run
    end

    @results[:complex_joins] = {
      fact_count: fact_count * 3,
      time: time.real
    }
  end

  def benchmark_negation(fact_count: 1000)
    engine = setup_engine

    # Rule with negation
    rule = KBS::Rule.new("negation_rule") do |r|
      r.conditions = [
        KBS::Condition.new(:positive, { id: :?id }),
        KBS::Condition.new(:negative, { id: :?id }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        # Action
      end
    end

    engine.add_rule(rule)

    # Add facts (50% will match)
    fact_count.times do |i|
      engine.add_fact(:positive, { id: i })
      engine.add_fact(:negative, { id: i }) if i.even?
    end

    # Benchmark
    time = Benchmark.measure do
      engine.run
    end

    @results[:negation] = {
      fact_count: fact_count + (fact_count / 2),
      time: time.real
    }
  end

  def run_all
    puts "=== KBS Performance Benchmark (#{@engine_type}) ==="

    benchmark_fact_addition
    puts "\nFact Addition:"
    puts "  #{@results[:fact_addition][:count]} facts in #{@results[:fact_addition][:time].round(4)}s"
    puts "  Rate: #{@results[:fact_addition][:rate]} facts/sec"

    benchmark_simple_rules
    puts "\nSimple Rules:"
    puts "  #{@results[:simple_rules][:rule_count]} rules, #{@results[:simple_rules][:fact_count]} facts"
    puts "  Time: #{@results[:simple_rules][:time].round(4)}s"

    benchmark_complex_joins
    puts "\nComplex Joins (3-way):"
    puts "  #{@results[:complex_joins][:fact_count]} facts"
    puts "  Time: #{@results[:complex_joins][:time].round(4)}s"

    benchmark_negation
    puts "\nNegation:"
    puts "  #{@results[:negation][:fact_count]} facts"
    puts "  Time: #{@results[:negation][:time].round(4)}s"

    @results
  end
end

# Run benchmarks
memory_bench = KBSBenchmark.new(engine_type: :memory)
memory_results = memory_bench.run_all

# Compare with blackboard
blackboard_bench = KBSBenchmark.new(engine_type: :blackboard_sqlite)
blackboard_results = blackboard_bench.run_all

# Compare
puts "\n=== Performance Comparison ==="
puts "Fact addition: Memory is #{(blackboard_results[:fact_addition][:time] / memory_results[:fact_addition][:time]).round(2)}x faster"
```

## Rule Optimization

### Condition Ordering

Order conditions from most to least selective:

```ruby
# Bad: Generic condition first
KBS::Rule.new("inefficient") do |r|
  r.conditions = [
    KBS::Condition.new(:any_event, {}),  # Matches ALL events (large alpha memory)
    KBS::Condition.new(:critical_error, { severity: "critical" })  # Selective
  ]
end

# Good: Selective condition first
KBS::Rule.new("efficient") do |r|
  r.conditions = [
    KBS::Condition.new(:critical_error, { severity: "critical" }),  # Selective
    KBS::Condition.new(:any_event, { error_id: :?id })  # Filtered by join
  ]
end
```

**Why it matters:**

```
Bad ordering:
  any_event alpha: 10,000 facts
  Join produces 10,000 tokens
  critical_error alpha: 5 facts
  Join filters down to 5 final matches
  → 10,000 token propagations

Good ordering:
  critical_error alpha: 5 facts
  Join produces 5 tokens
  any_event alpha: 10,000 facts
  Join filters to 5 final matches
  → 5 token propagations (2000x fewer!)
```

### Predicate Efficiency

Use simple predicates:

```ruby
# Bad: Complex predicate
KBS::Condition.new(:data, { value: :?v }, predicate: lambda { |f|
  # Expensive operations
  json = JSON.parse(f[:raw_data])
  result = ComplexCalculation.new(json).process
  result > threshold
})

# Good: Pre-process data
engine.add_fact(:data, {
  value: calculate_value(raw_data),  # Pre-calculated
  processed: true
})

KBS::Condition.new(:data, { value: :?v }, predicate: lambda { |f|
  f[:value] > threshold  # Simple comparison
})
```

### Network Sharing

Leverage shared alpha and beta memories:

```ruby
# Inefficient: Duplicate alpha nodes
rule1 = KBS::Rule.new("rule1") do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { type: "temperature", value: :?v1 })
  ]
end

rule2 = KBS::Rule.new("rule2") do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { type: "temperature", value: :?v2 })  # SAME pattern
  ]
end

# Engine automatically shares alpha memory for :sensor + type="temperature"
# Adding 1 temperature sensor fact activates BOTH rules efficiently
```

**Sharing visualization:**

```
Facts → AlphaMemory(:sensor, type=temperature) ──┬─→ Rule1
                                                  └─→ Rule2

Instead of:
Facts → AlphaMemory1(:sensor) → Rule1
     └→ AlphaMemory2(:sensor) → Rule2  (duplicate work)
```

### Minimize Negations

Negations are expensive:

```ruby
# Expensive: Multiple negations
KBS::Rule.new("many_negations") do |r|
  r.conditions = [
    KBS::Condition.new(:a, {}),
    KBS::Condition.new(:b, {}, negated: true),
    KBS::Condition.new(:c, {}, negated: true),
    KBS::Condition.new(:d, {}, negated: true)
  ]
end
# Each negation checks alpha memory on every token

# Better: Use positive logic
engine.add_fact(:conditions_clear, {}) unless b_exists? || c_exists? || d_exists?

KBS::Rule.new("positive_logic") do |r|
  r.conditions = [
    KBS::Condition.new(:a, {}),
    KBS::Condition.new(:conditions_clear, {})
  ]
end
```

### Batch Operations

Group related operations:

```ruby
# Inefficient: Add facts one by one with run after each
1000.times do |i|
  engine.add_fact(:item, { id: i })
  engine.run  # Run engine 1000 times!
end

# Efficient: Batch add, then run once
1000.times do |i|
  engine.add_fact(:item, { id: i })
end
engine.run  # Run engine once
```

## Storage Backend Selection

### Performance Characteristics

```ruby
require 'benchmark'

# In-memory (fastest)
memory_engine = KBS::Engine.new

# SQLite (persistent, slower)
sqlite_engine = KBS::Blackboard::Engine.new(db_path: 'test.db')

# Redis (persistent, fast)
require 'kbs/blackboard/persistence/redis_store'
redis_store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)
redis_engine = KBS::Blackboard::Engine.new(store: redis_store)

# Benchmark
engines = {
  memory: memory_engine,
  sqlite: sqlite_engine,
  redis: redis_engine
}

engines.each do |name, engine|
  time = Benchmark.measure do
    10_000.times { |i| engine.add_fact(:test, { value: i }) }
  end

  puts "#{name}: #{(10_000 / time.real).round(2)} facts/sec"
end

# Typical results:
# memory: 50,000 facts/sec
# sqlite: 5,000 facts/sec
# redis: 25,000 facts/sec
```

### Backend Decision Matrix

**In-Memory (`KBS::Engine`)**:
- ✅ Fastest (no I/O)
- ✅ Simple (no setup)
- ❌ No persistence
- **Use when:** Prototyping, short-lived processes, pure computation

**SQLite (`KBS::Blackboard::Engine`)**:
- ✅ Persistent
- ✅ ACID transactions
- ✅ No dependencies
- ❌ Slower writes (~5,000/sec)
- **Use when:** Single process, moderate load, need durability

**Redis (`RedisStore`)**:
- ✅ Fast (~25,000/sec)
- ✅ Distributed
- ✅ Scalable
- ❌ Requires Redis server
- **Use when:** High throughput, multiple processes, real-time systems

**Hybrid (`HybridStore`)**:
- ✅ Fast (Redis) + durable (SQLite)
- ❌ Most complex
- **Use when:** Production, need both speed and audit trail

### SQLite Optimization

```ruby
engine = KBS::Blackboard::Engine.new(
  db_path: 'optimized.db',
  journal_mode: 'WAL',         # Write-Ahead Logging (better concurrency)
  synchronous: 'NORMAL',       # Balance safety/speed
  cache_size: -64000,          # 64MB cache
  busy_timeout: 5000           # Wait 5s for locks
)

# Results: 2-3x faster than default settings
```

### Redis Optimization

```ruby
store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0',
  pool_size: 10,          # Connection pooling
  pool_timeout: 5,        # Pool timeout
  reconnect_attempts: 3   # Retry on failure
)

engine = KBS::Blackboard::Engine.new(store: store)

# Enable Redis persistence (optional)
# In redis.conf:
#   save 900 1
#   appendonly yes
```

## Profiling

### Ruby Profiler

```ruby
require 'ruby-prof'

engine = KBS::Engine.new

# Add rules and facts
# ...

# Profile engine run
result = RubyProf.profile do
  engine.run
end

# Print results
printer = RubyProf::FlatPrinter.new(result)
printer.print(STDOUT, min_percent: 2)

# Or use call graph
printer = RubyProf::CallTreePrinter.new(result)
File.open('profile.out', 'w') { |f| printer.print(f) }
# View with kcachegrind or qcachegrind
```

### Stackprof (Sampling Profiler)

```ruby
require 'stackprof'

engine = KBS::Engine.new

# Add rules and facts
# ...

# Profile
StackProf.run(mode: :cpu, out: 'stackprof.dump') do
  1000.times { engine.run }
end

# Analyze
# $ stackprof stackprof.dump --text
# $ stackprof stackprof.dump --method 'KBS::JoinNode#left_activate'
```

### Custom Instrumentation

```ruby
class InstrumentedEngine < KBS::Engine
  def initialize
    super
    @metrics = {
      fact_additions: 0,
      rule_firings: 0,
      alpha_activations: 0,
      beta_activations: 0
    }
  end

  def add_fact(type, attributes = {})
    @metrics[:fact_additions] += 1
    super
  end

  def run
    start = Time.now
    result = super
    elapsed = Time.now - start

    puts "Engine run: #{elapsed}s"
    puts "  Facts: #{facts.size}"
    puts "  Rules fired: #{@metrics[:rule_firings]}"

    result
  end

  def report_metrics
    @metrics
  end
end
```

## Common Bottlenecks

### 1. Large Alpha Memories

**Problem**: Conditions matching many facts slow down joins

```ruby
# Slow: Matches ALL events
KBS::Condition.new(:event, {})  # Alpha memory: 100,000 facts
```

**Solution**: Add constraints

```ruby
# Fast: Matches specific events
KBS::Condition.new(:event, { type: "error", severity: "critical" })
# Alpha memory: 50 facts
```

### 2. Expensive Predicates

**Problem**: Complex predicates evaluated repeatedly

```ruby
# Slow: Expensive predicate called for every fact
KBS::Condition.new(:data, {}, predicate: lambda { |f|
  expensive_calculation(f[:raw_data])
})
```

**Solution**: Pre-calculate

```ruby
# Fast: Calculate once when adding fact
processed_value = expensive_calculation(raw_data)
engine.add_fact(:data, { processed: processed_value })

KBS::Condition.new(:data, { processed: :?v })
```

### 3. Action Overhead

**Problem**: Slow actions block engine

```ruby
# Slow: Action makes API call
r.action = lambda do |facts, bindings|
  result = HTTParty.get("https://api.example.com/process")  # Blocks!
  engine.add_fact(:result, result)
end
```

**Solution**: Async processing

```ruby
# Fast: Queue action, process asynchronously
r.action = lambda do |facts, bindings|
  engine.send_message(:api_queue, {
    url: "https://api.example.com/process",
    fact_id: facts[0].id
  }, priority: 50)
end

# Separate worker processes messages
worker = Thread.new do
  loop do
    msg = engine.pop_message(:api_queue)
    break unless msg

    result = HTTParty.get(msg[:content][:url])
    engine.add_fact(:result, result)
  end
end
```

### 4. Memory Leaks

**Problem**: Facts accumulate indefinitely

```ruby
# Memory grows unbounded
loop do
  engine.add_fact(:sensor_reading, {
    value: read_sensor(),
    timestamp: Time.now
  })
  engine.run
end
# After 1 hour: 360,000 facts in memory!
```

**Solution**: Clean up old facts

```ruby
# Cleanup rule
cleanup_rule = KBS::Rule.new("cleanup_old_readings", priority: 1) do |r|
  r.conditions = [
    KBS::Condition.new(:sensor_reading, {
      timestamp: :?time
    }, predicate: lambda { |f|
      (Time.now - f[:timestamp]) > 300  # 5 minutes old
    })
  ]

  r.action = lambda do |facts, bindings|
    engine.remove_fact(facts[0])
  end
end
```

## Optimization Checklist

### Rule Design

- [ ] Order conditions from most to least selective
- [ ] Minimize negations (use positive logic where possible)
- [ ] Keep predicates simple
- [ ] Pre-calculate expensive values
- [ ] Share patterns across rules

### Fact Management

- [ ] Remove facts when no longer needed
- [ ] Batch fact additions
- [ ] Use specific fact types (not generic `:data`)
- [ ] Avoid duplicate facts

### Actions

- [ ] Keep actions fast
- [ ] Avoid blocking I/O in actions
- [ ] Use message passing for async work
- [ ] Don't add/remove many facts in single action

### Storage

- [ ] Choose backend based on requirements:
  - In-memory for speed
  - SQLite for persistence + moderate load
  - Redis for persistence + high load
  - Hybrid for production
- [ ] Optimize SQLite with WAL mode
- [ ] Use connection pooling for Redis
- [ ] Monitor database size

### Monitoring

- [ ] Profile before optimizing
- [ ] Measure fact addition rate
- [ ] Track engine run time
- [ ] Monitor memory usage
- [ ] Log rule firing frequency

## Performance Targets

### Expected Performance (In-Memory)

| Operation | Target | Notes |
|-----------|--------|-------|
| Add fact | 50,000/sec | Simple facts, no rules |
| Simple rule (1 condition) | 10,000/sec | Per fact |
| Complex rule (3+ conditions) | 1,000/sec | Per fact |
| Engine run (1000 facts, 10 rules) | < 100ms | Total time |
| Negation check | 10,000/sec | Per token |

### Expected Performance (SQLite)

| Operation | Target | Notes |
|-----------|--------|-------|
| Add fact | 5,000/sec | With WAL mode |
| Query facts | 100,000/sec | Indexed queries |
| Transaction | 1,000/sec | Commit rate |

### Expected Performance (Redis)

| Operation | Target | Notes |
|-----------|--------|-------|
| Add fact | 25,000/sec | Network overhead |
| Query facts | 50,000/sec | Hash operations |
| Message queue | 50,000/sec | Sorted set operations |

## Scaling Strategies

### Vertical Scaling

**Increase single-process performance:**

```ruby
# 1. Use faster backend
store = KBS::Blackboard::Persistence::RedisStore.new(...)
engine = KBS::Blackboard::Engine.new(store: store)

# 2. Optimize rules
# - Order conditions
# - Minimize negations
# - Batch operations

# 3. Pre-process data
# - Calculate values before adding facts
# - Index frequently queried attributes
```

### Horizontal Scaling

**Multiple processes sharing Redis:**

```ruby
# Process 1: Data collector
collector_store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)
collector = KBS::Blackboard::Engine.new(store: collector_store)

# Collect data
loop do
  data = fetch_data()
  collector.add_fact(:raw_data, data)
end

# Process 2: Rule processor
processor_store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'  # Same Redis!
)
processor = KBS::Blackboard::Engine.new(store: processor_store)

# Add rules
processor.add_rule(...)

# Process data
loop do
  processor.run
  sleep 1
end
```

### Partitioning

**Split facts by domain:**

```ruby
# Engine 1: Temperature monitoring
temp_engine = KBS::Blackboard::Engine.new(db_path: 'temp.db')
# Handles :temperature_reading, :hvac_control

# Engine 2: Security monitoring
security_engine = KBS::Blackboard::Engine.new(db_path: 'security.db')
# Handles :motion_sensor, :door_sensor, :alarm

# Coordinator: Coordinates between engines
coordinator_engine = KBS::Blackboard::Engine.new(db_path: 'coordinator.db')
# Handles cross-domain rules
```

## Next Steps

- **[Debugging Guide](debugging.md)** - Debug performance issues
- **[Testing Guide](testing.md)** - Performance testing strategies
- **[Custom Persistence](custom-persistence.md)** - Optimize custom backends
- **[Architecture](../architecture/index.md)** - Understand network structure

---

*Premature optimization is the root of all evil. Profile first, then optimize the bottlenecks.*
