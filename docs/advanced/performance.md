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

### RETE Regex Baseline

The current regex path uses Ruby's built-in `Regexp#match?` inside a condition
predicate, which `Fact#matches?` evaluates while facts are asserted. Run the
reproducible benchmark from the repository root:

```bash
ruby -Ilib benchmarks/regex_baseline.rb
```

It compares regex matching with an equivalent `String#start_with?` predicate
both directly and during RETE fact assertion. `ITERATIONS` and `REPEATS`
environment variables can adjust the workload.

Baseline recorded on Ruby 3.2.3, x86_64-linux-gnu (20,000 values per sample,
five samples; median elapsed time; 50% matching values):

| Measurement | Throughput |
|-------------|-----------:|
| Direct `Regexp#match?` | 7,448,440 comparisons/sec |
| Direct `String#start_with?` | 14,964,594 comparisons/sec |
| RETE regex predicate | 415,008 facts/sec |
| RETE prefix predicate | 482,253 facts/sec |

The direct measurements isolate predicate cost; RETE measurements also include
fact creation and network propagation, so compare those rows only with each
other. These are environment-specific baseline observations, not performance
targets. Re-run the benchmark on the target Ruby/runtime before evaluating a
regex engine change.

### RETE Scaling

`benchmarks/rete_scaling.rb` measures how the network scales as facts and
rules are added: a two-condition join on a shared variable, the same join
negated, firing the matches with `run`, retraction, and fact assertion
against many alpha memories.

```bash
ruby -Ilib benchmarks/rete_scaling.rb
SIZES=500,1000,2000 REPEATS=5 ruby -Ilib benchmarks/rete_scaling.rb
```

A scenario that scales linearly keeps its rate as the size grows.

In the tables below, the "scan" columns were recorded before the indexing
and linking changes; the script measures only the current code, so a
re-run reproduces the right-hand columns.

Joins on a shared `?variable` are hash joins. The alpha memory is indexed on
the fact's fields and the beta memory on the token's fields, so a new fact or
token only visits the entries that share its value. Recorded on Ruby 4.0.9,
arm64-darwin (median of 3), for `n` orders joined with `n` payments on `?id`:

| n | Memory scan | Hash index |
|--:|------------:|-----------:|
| 500 | 15,294 facts/sec | 313,873 facts/sec |
| 1000 | 7,949 facts/sec | 327,279 facts/sec |
| 2000 | 4,120 facts/sec | 360,101 facts/sec |

Retraction follows links instead of searching. The engine records which
alpha memories each fact went into, each join records the tokens it built
from each fact, and each token records its children, so removing a fact
touches only its own matches. Removing `n` joined payments:

| n | Memory scan | Linked |
|--:|------------:|-------:|
| 500 | 16,576 facts/sec | 500,500 facts/sec |
| 1000 | 8,566 facts/sec | 392,311 facts/sec |
| 2000 | 4,251 facts/sec | 484,848 facts/sec |

Asserting a fact does not test it against every pattern. Alpha memories are
grouped by fact type, and those that test an attribute against a constant are
hashed on that value, so the cost does not grow with the number of rules.
2000 asserts against `n` rules:

| n | Each on its own type, scan | Indexed | Each on its own constant, scan | Indexed |
|--:|--:|--:|--:|--:|
| 500 | 32,965 facts/sec | 292,912 facts/sec | 7,877 facts/sec | 315,657 facts/sec |
| 1000 | 17,316 facts/sec | 336,361 facts/sec | 3,960 facts/sec | 300,661 facts/sec |
| 2000 | 8,770 facts/sec | 321,492 facts/sec | 1,996 facts/sec | 310,029 facts/sec |

A pattern is hashed on its first attribute compared with a plain value. A
pattern that only uses predicates or variables is tested for every fact of
its type, so put a constant test in the pattern when the rule has one.

`without` and `exists` conditions link each partial match to the facts that
satisfy it, and each fact to the matches it affects. Retracting `n` payments
that each block one order in a `without`:

| n | Memory scan | Linked |
|--:|------------:|-------:|
| 500 | 21,668 facts/sec | 302,847 facts/sec |
| 1000 | 10,445 facts/sec | 235,405 facts/sec |
| 2000 | 4,915 facts/sec | 244,439 facts/sec |

Rules that start with the same conditions share the nodes for them. 50 rules
that each begin with the same join of `n` orders and `n` payments:

| n | A join per rule | Shared join |
|--:|----------------:|------------:|
| 500 | 8,200 facts/sec | 105,541 facts/sec |
| 1000 | 9,633 facts/sec | 118,842 facts/sec |
| 2000 | 7,740 facts/sec | 107,411 facts/sec |

Write the conditions rules have in common first, in the same order and with
the same variable names: a pattern includes its variable names, so
`id: :id?` and `id: :order_id?` are different patterns.

Only equality between two conditions is indexed. A condition with no shared
variable, or one that only uses predicates, still scans its memories, so put
a shared variable on the join where the data allows it.

Firing does not sort the agenda. As in CLIPS, activations are grouped by
salience, and under the `:definition` strategy also by rule; within a group,
`:depth` takes the newest first and the other strategies the oldest first, so
adding and popping an activation compare nothing. Three rules at different
priorities on the same join of `n` orders and `n` payments, asserted and then
`run` (3n firings, `:definition` strategy):

| n | 0.3.0 (binary heap) | 0.3.1 (salience groups) | 0.3.0, YJIT | 0.3.1, YJIT |
|--:|--:|--:|--:|--:|
| 500 | 110,726 firings/sec | 274,273 firings/sec | 140,845 firings/sec | 463,822 firings/sec |
| 1000 | 108,980 firings/sec | 257,003 firings/sec | 175,757 firings/sec | 482,160 firings/sec |
| 2000 | 97,575 firings/sec | 270,234 firings/sec | 152,858 firings/sec | 552,181 firings/sec |

### Running with YJIT

YJIT, the JIT compiler built into CRuby, speeds up KBS by roughly 1.5 to 2.5
times on these benchmarks with no code changes. Turn it on with any of:

```bash
ruby --yjit app.rb            # one process
RUBY_YJIT_ENABLE=1 ruby app.rb  # through the environment, e.g. in a Procfile
```

```ruby
RubyVM::YJIT.enable           # from code, early in boot
RubyVM::YJIT.enabled?         # => true
```

Compare both ways on your own rules by running the benchmark with and without
the flag:

```bash
ruby -Ilib benchmarks/rete_scaling.rb
ruby --yjit -Ilib benchmarks/rete_scaling.rb
```

### Basic Benchmark

```ruby
require 'benchmark'
require 'kbs'

kb = KBS.knowledge_base do
  rule "simple_rule" do
    on :fact, value: :v?
    perform do |facts, bindings|
      # Simple action
    end
  end
end

# Benchmark fact addition
time = Benchmark.measure do
  10_000.times do |i|
    kb.fact :fact, value: i
  end
end

puts "Added 10,000 facts in #{time.real} seconds"
puts "#{(10_000 / time.real).round(2)} facts/second"

# Benchmark engine run
time = Benchmark.measure do
  kb.run
end

puts "Ran engine in #{time.real} seconds"
```

### Comprehensive Benchmark

```ruby
require 'benchmark'
require 'kbs/blackboard'

class KBSBenchmark
  def initialize(engine_type: :memory)
    @engine_type = engine_type
    @results = {}
  end

  # A fresh engine of the type under test
  def new_engine
    case @engine_type
    when :memory
      KBS::Engine.new
    when :blackboard_sqlite
      KBS::Blackboard::Engine.new(db_path: ':memory:')
    when :blackboard_redis
      store = KBS::Blackboard::Persistence::RedisStore.new(
        url: 'redis://localhost:6379/15'  # Test database
      )
      KBS::Blackboard::Engine.new(store: store)
    end
  end

  def benchmark_fact_addition(count: 10_000)
    kb = KBS.knowledge_base(engine: new_engine)

    time = Benchmark.measure do
      count.times do |i|
        kb.fact :fact, id: i, value: rand(1000)
      end
    end

    @results[:fact_addition] = {
      count: count,
      time: time.real,
      rate: (count / time.real).round(2)
    }
  end

  def benchmark_simple_rules(fact_count: 1000, rule_count: 10)
    kb = KBS.knowledge_base(engine: new_engine) do
      # Add rules
      rule_count.times do |i|
        rule "rule_#{i}" do
          on :fact, value: :v?
          perform { }  # Minimal action
        end
      end

      # Add facts
      fact_count.times do |i|
        fact :fact, value: i
      end
    end

    # Benchmark engine run
    time = Benchmark.measure do
      kb.run
    end

    @results[:simple_rules] = {
      fact_count: fact_count,
      rule_count: rule_count,
      time: time.real
    }
  end

  def benchmark_complex_joins(fact_count: 500)
    kb = KBS.knowledge_base(engine: new_engine) do
      # Rule with 3-way join
      rule "complex_join" do
        on :a, id: :id?, value: :v?
        on :b, a_id: :id?, score: :s?
        on :c, b_score: :s?
        perform do |facts, bindings|
          # Action
        end
      end

      # Add facts
      fact_count.times do |i|
        fact :a, id: i, value: rand(100)
        fact :b, a_id: i, score: rand(100)
        fact :c, b_score: i
      end
    end

    # Benchmark
    time = Benchmark.measure do
      kb.run
    end

    @results[:complex_joins] = {
      fact_count: fact_count * 3,
      time: time.real
    }
  end

  def benchmark_negation(fact_count: 1000)
    kb = KBS.knowledge_base(engine: new_engine) do
      # Rule with negation
      rule "negation_rule" do
        on :positive, id: :id?
        without :negative, id: :id?
        perform do |facts, bindings|
          # Action
        end
      end

      # Add facts (50% will match)
      fact_count.times do |i|
        fact :positive, id: i
        fact :negative, id: i if i.even?
      end
    end

    # Benchmark
    time = Benchmark.measure do
      kb.run
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

Run it with `ruby -Ilib`, as for the scripts in `benchmarks/`: on Ruby 4, `benchmark` is a bundled gem that is not in the project's Gemfile, so `bundle exec` cannot load it.

## Rule Optimization

### Condition Ordering

Order conditions from most to least selective:

```ruby
# Bad: Generic condition first
KBS::Rule.new("inefficient") do |r|
  r.conditions = [
    KBS::Condition.new(:any_event, { error_id: :id? }),  # Matches ALL events (large alpha memory)
    KBS::Condition.new(:critical_error, { id: :id?, severity: "critical" })  # Selective
  ]
end

# Good: Selective condition first
KBS::Rule.new("efficient") do |r|
  r.conditions = [
    KBS::Condition.new(:critical_error, { id: :id?, severity: "critical" }),  # Selective
    KBS::Condition.new(:any_event, { error_id: :id? })  # Filtered by join on ?id
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

Both orderings find the 5 matches through a hash lookup on `?id`; the
difference is the 10,000 partial-match tokens the bad ordering builds and
stores in its first beta memory.

### Predicate Efficiency

Use simple predicates. A predicate is a Proc given as an attribute's
expected value; it is called with that attribute's value for each candidate
fact as it is asserted:

```ruby
# Bad: Complex predicate
KBS::Condition.new(:data, { raw_data: lambda { |raw|
  # Expensive operations
  json = JSON.parse(raw)
  result = ComplexCalculation.new(json).process
  result > threshold
} })

# Good: Pre-process data
engine.add_fact(:data, {
  value: calculate_value(raw_data),  # Pre-calculated
  processed: true
})

KBS::Condition.new(:data, { value: ->(v) { v > threshold } })  # Simple comparison
```

### Network Sharing

Leverage shared alpha memories (join nodes and beta memories are built per
rule and are not shared). Two conditions share an alpha memory only when
their type and whole pattern are equal, variable names included:

```ruby
rule1 = KBS::Rule.new("rule1") do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { kind: "temperature", value: :v? })
  ]
end

rule2 = KBS::Rule.new("rule2") do |r|
  r.conditions = [
    KBS::Condition.new(:sensor, { kind: "temperature", value: :v? })  # SAME pattern
  ]
end

# Engine automatically shares alpha memory for :sensor + kind="temperature"
# Adding 1 temperature sensor fact activates BOTH rules efficiently.
# With value: :v1? in one rule and :v2? in the other, the patterns differ
# and each rule gets its own alpha memory.
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

Negations cost more than a plain join: each keeps links between partial
matches and the facts that block them, and a negation without a shared
`?variable` checks the whole alpha memory for every new token:

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
# Each of these negations has no shared variable, so it checks its whole
# alpha memory for every token

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
# Add facts one by one with run after each
1000.times do |i|
  engine.add_fact(:item, { id: i })
  engine.run  # Run engine 1000 times
end

# Batch add, then run once
1000.times do |i|
  engine.add_fact(:item, { id: i })
end
engine.run  # Run engine once
```

Matching happens as each fact is added, and `run` only pops the agenda, so
both forms do about the same matching work. The difference is *when* rules
fire: running after each fact fires rules before later facts arrive, while
one `run` lets priorities and the strategy order all activations together,
and lets a later fact cancel an activation before it fires. With a
blackboard, wrap the batch in `memory.transaction` to commit once.

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

# One run on Ruby 4.0.9, arm64-darwin, file-backed SQLite, local Redis:
# memory: ~930,000 facts/sec
# sqlite: ~1,900 facts/sec
# redis:  ~1,700 facts/sec
```

Each blackboard `add_fact` writes the fact and an audit entry; outside a
transaction SQLite commits each one, and Redis makes several round trips.
Measure on your own hardware and network.

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
- ❌ Slower writes (each fact also writes an audit entry; batch in a transaction)
- **Use when:** Single process, moderate load, need durability

**Redis (`RedisStore`)**:
- ✅ Shared between processes
- ✅ In-memory storage
- ❌ Requires Redis server
- ❌ A network round trip per operation; not faster than SQLite per fact in the run above
- **Use when:** High throughput, multiple processes, real-time systems

**Hybrid (`HybridStore`)**:
- ✅ Fast (Redis) + durable (SQLite)
- ❌ Most complex
- **Use when:** Production, need both speed and audit trail

### SQLite Optimization

`Blackboard::Engine.new` takes only `db_path:`, `store:`, `strategy:` and
`fact_duplication:`. Set SQLite pragmas on the store's database handle:

```ruby
engine = KBS::Blackboard::Engine.new(db_path: 'optimized.db')
db = engine.blackboard.store.db   # SQLite3::Database

db.execute("PRAGMA journal_mode = WAL")      # Write-Ahead Logging (better concurrency)
db.execute("PRAGMA synchronous = NORMAL")    # Balance safety/speed
db.execute("PRAGMA cache_size = -64000")     # 64MB cache
db.busy_timeout = 5000                       # Wait 5s for locks
```

Batching writes in `engine.blackboard.transaction { ... }` usually matters
more: in one run, 1,000 `add_fact` calls took 0.6 s one by one and 0.02 s
in a single transaction.

### Redis Optimization

`RedisStore.new` takes `url:`, `session_id:` and `redis:`. To configure the
connection (timeouts, reconnects), build the `Redis` client yourself and
pass it in; the store has no connection pool:

```ruby
redis = Redis.new(url: 'redis://localhost:6379/0', reconnect_attempts: 3)
store = KBS::Blackboard::Persistence::RedisStore.new(redis: redis)

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

  def fire_activation(activation)
    @metrics[:rule_firings] += 1
    super
  end

  def run(limit = nil)
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
KBS::Condition.new(:event, { kind: "error", severity: "critical" })
# Alpha memory: 50 facts
```

### 2. Expensive Predicates

**Problem**: Complex predicates evaluated repeatedly

```ruby
# Slow: Expensive predicate called for every :data fact asserted
KBS::Condition.new(:data, { raw_data: ->(raw) { expensive_calculation(raw) } })
```

**Solution**: Pre-calculate

```ruby
# Fast: Calculate once when adding fact
processed_value = expensive_calculation(raw_data)
engine.add_fact(:data, { processed: processed_value })

KBS::Condition.new(:data, { processed: :v? })
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
# Fast: Queue action, process asynchronously (KBS::Blackboard::Engine)
r.action = lambda do |facts, bindings|
  engine.post_message("rules", "api_queue", {
    url: "https://api.example.com/process",
    fact_id: facts[0].uuid
  }, priority: 50)
end

# Separate worker processes messages
worker = Thread.new do
  loop do
    msg = engine.consume_message("api_queue", "api_worker")
    break unless msg

    result = HTTParty.get(msg[:content][:url])
    # The engine is not thread-safe: hand the result back to the thread
    # that runs the engine (e.g. post it as another message) rather than
    # calling engine.add_fact from here
    engine.post_message("api_worker", "api_results", { body: result.body })
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

A predicate is evaluated when the fact is asserted, so a rule cannot notice
a reading becoming old later. Prune from the loop instead:

```ruby
loop do
  engine.add_fact(:sensor_reading, {
    value: read_sensor(),
    timestamp: Time.now
  })
  engine.run

  cutoff = Time.now - 300  # 5 minutes
  engine.facts.each do |fact|
    engine.remove_fact(fact) if fact.type == :sensor_reading && fact[:timestamp] < cutoff
  end
end
```

Facts a rule asserts under `logical` conditions are retracted automatically
when the facts that support them go.

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
- [ ] Avoid duplicate facts (`KBS::Engine.new(fact_duplication: false)` makes `add_fact` return the existing equal fact)

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
- [ ] Optimize SQLite with WAL mode and batch writes in transactions
- [ ] Configure the Redis client you pass to `RedisStore.new(redis:)`
- [ ] Monitor database size

### Monitoring

- [ ] Profile before optimizing
- [ ] Measure fact addition rate
- [ ] Track engine run time
- [ ] Monitor memory usage
- [ ] Log rule firing frequency

## Performance Targets

These are rough targets, not measurements, and the measured rates above
differ from them substantially (in-memory assertion is much faster; a
blackboard backend without batching is much slower). Use them as a
starting point and measure your own workload.

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

Each engine matches only the facts asserted through it (plus the facts
already in the store when its rules are added, which seed new alpha
memories). Facts another process writes later do not reach its network, so
hand work between processes through the shared message queue:

```ruby
# Process 1: Data collector
collector_store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)
collector = KBS::Blackboard::Engine.new(store: collector_store)

# Collect data
loop do
  data = fetch_data()
  collector.post_message("collector", "raw_data", data)
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
  while (msg = processor.consume_message("raw_data", "processor"))
    processor.add_fact(:raw_data, msg[:content])
  end
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
