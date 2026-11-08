# KBS Test Suite

Comprehensive test suite for the KBS (Knowledge-Based System) Ruby gem using Minitest and SimpleCov.

## Test Files

### Core RETE Engine Tests
- `test_fact.rb` - Fact class initialization, attributes, pattern matching
- `test_token.rb` - Token creation and fact associations
- `test_working_memory.rb` - Fact storage, observer pattern
- `test_alpha_memory.rb` - Pattern-based fact activation/deactivation
- `test_beta_memory.rb` - Token storage and management
- `test_join_node.rb` - Join operations between alpha and beta memories
- `test_negation_node.rb` - Negated conditions and unlinking
- `test_production_node.rb` - Rule firing and token management
- `test_condition.rb` - Condition creation, pattern matching, variable bindings
- `test_rule.rb` - Rule definition and action execution
- `test_rete_engine.rb` - Complete RETE network building and inference

### DSL Tests
- `test_dsl_variable.rb` - Logic variables (symbols starting with `?`)
- `test_dsl_knowledge_base.rb` - KB initialization, facts, rules, queries
- `test_dsl_rule_builder.rb` - Fluent API for rule definition, aliases
- `test_dsl_condition_helpers.rb` - Pattern matching helpers (less_than, greater_than, between, etc.)

### Blackboard Pattern Tests
- `test_blackboard_memory.rb` - Persistent facts, messages, audit trail
- `test_blackboard_engine.rb` - RETE + Blackboard integration, rule logging
- `test_optional_redis.rb` - the SQLite blackboard loads without the redis gem, and `RedisStore` still needs it

### Redis Persistence Tests
- `test_redis_store.rb` - RedisStore implementation
- `test_hybrid_store.rb` - HybridStore (Redis + SQLite) integration

These tests flush the Redis database they use, so they are skipped unless
`KBS_TEST_REDIS_URL` names a disposable one. Point it at a throwaway server,
not the Redis you use day to day:

```bash
redis-server --port 6399 --bind 127.0.0.1 --save '' --appendonly no --daemonize yes
KBS_TEST_REDIS_URL=redis://127.0.0.1:6399/15 bundle exec rake test
redis-cli -p 6399 shutdown nosave
```

### Integration Tests
- `test_integration.rb` - End-to-end scenarios:
  - Basic RETE workflow
  - DSL knowledge base usage
  - Blackboard persistence
  - Multi-condition joins
  - Message queue priority
  - Trading and IoT scenarios

## Running Tests

### All Tests
```bash
ruby -Ilib:test -e "Dir['test/test_*.rb'].each { |f| require f.sub('test/', '') }"
```

### Single Test File
```bash
ruby -Ilib:test test/test_rete_engine.rb
```

### With Coverage Report
```bash
# SimpleCov runs automatically from test_helper.rb
ruby -Ilib:test -e "Dir['test/test_*.rb'].each { |f| require f.sub('test/', '') }"
# Open coverage/index.html to view report
```

## Coverage Goals

The minimum overall coverage is set in `test/test_helper.rb`, and a run below it fails. The per-file minimum is currently disabled there.

## Test Patterns

### No Mocking Policy
All tests use **real production code** with no mocks or stubs. This ensures tests verify actual behavior.
The exceptions are `test_redis_test_support.rb`, which stubs `Redis.new` to prove the Redis tests never connect unless opted in, and `test_optional_redis.rb`, which makes `require 'redis'` fail in a child process to stand in for a missing redis gem.

### In-Memory Databases
- SQLite tests use `:memory:` databases
- Redis tests use the database named by `KBS_TEST_REDIS_URL` (cleared before each test)
- Teardown methods ensure proper cleanup

### Redis Opt-In
Redis tests skip unless `KBS_TEST_REDIS_URL` is set:
```ruby
include RedisTestSupport

def setup
  @redis = redis_test_connection # skips when KBS_TEST_REDIS_URL is unset
  @redis.flushdb
  # ... test setup
end
```

## Test Organization

### Core RETE Tests (12 files)
Tests for the RETE algorithm implementation:
- Alpha network (pattern matching)
- Beta network (join operations)
- Production nodes (rule firing)
- Unlinking optimization (negation)

### DSL Tests (4 files)
Tests for the declarative rule DSL:
- Rule builder fluent API
- Pattern evaluators
- Condition helpers
- Knowledge base management

### Blackboard Tests (4 files)
Tests for the Blackboard architectural pattern:
- Persistent fact storage
- Message queue (priority-based)
- Audit trail (fact history, rule firings)
- RETE + Blackboard integration

### Integration Tests (1 file)
End-to-end scenarios demonstrating:
- Complete inference workflows
- Real-world use cases (trading, IoT)
- Component integration

## Key Test Scenarios

### RETE Engine
- Single-condition rules
- Multi-condition joins
- Negated conditions (NOT)
- Pattern matching with procs
- Fact retraction
- Observer pattern
- Token propagation

### DSL
- Declarative rule syntax
- Helper functions (less_than, greater_than, between, one_of, etc.)
- Variable bindings
- Negation (without)
- Action blocks

### Blackboard
- UUID-based fact identification
- Persistent storage (SQLite, Redis)
- Message priority queuing
- Complete audit trail
- Session management
- Knowledge source registry

### Redis Integration
- Fast in-memory fact storage
- Distributed blackboard capability
- Redis data structures (hashes, sets, sorted sets, lists)
- HybridStore (Redis + SQLite)

## Test Data Patterns

### Common Fact Types
- `:car` - color, speed, make, model
- `:driver` - name, age, license
- `:sensor` - location, type, value, temp
- `:price` - symbol, value, timestamp
- `:order` - type, quantity, limit
- `:account` - balance, status

### Common Assertions
```ruby
# Fact creation
fact = engine.add_fact(:car, { color: :red })
assert_instance_of KBS::Fact, fact

# Pattern matching
condition = KBS::Condition.new(:car, { color: :red })
assert fact.matches?(condition.pattern.merge(type: :car))

# Rule firing
assert fired, "Rule should have fired"
assert_equal 1, results.size
```

## Continuous Integration

To run in CI:
```yaml
# .github/workflows/test.yml (example)
- name: Install dependencies
  run: bundle install

- name: Run tests with coverage
  run: bundle exec rake test
```

## Development Workflow

1. **Write failing test** for new feature
2. **Implement feature** in production code
3. **Run specific test** to verify
4. **Run full suite** to check for regressions
5. **Check coverage** to ensure adequate testing

## Test Helper

`test/test_helper.rb` provides:
- SimpleCov configuration
- Minitest autorun
- Common requires

All test files should start with:
```ruby
require_relative 'test_helper'
```

## Notes

- Tests use `frozen_string_literal: true` for performance
- All database tests use transactions or cleanup in teardown
- Redis tests skip unless `KBS_TEST_REDIS_URL` is set
- Integration tests demonstrate real-world usage patterns
- No deprecated features tested (backward compat aliases not tested)

## Future Test Additions

- Performance benchmarks (RETE vs naive approach)
- Stress tests (large fact bases, complex rule networks)
- Concurrent access tests (multi-threaded)
- PostgreSQL store tests (when implemented)
- In-memory store tests (pure Ruby, no external deps)
- Knowledge source implementation tests
