# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs/blackboard'

class TestHybridStore < Minitest::Test
  include RedisTestSupport

  def setup
    @redis = redis_test_connection
    @redis.flushdb

    @store = KBS::Blackboard::Persistence::HybridStore.new(
      redis: @redis,
      db_path: ':memory:',
      session_id: 'test-session'
    )
  end

  def teardown
    @store&.close
    @redis&.flushdb
    @redis&.close
  end

  def test_initialization
    assert_instance_of KBS::Blackboard::Persistence::HybridStore, @store
    assert_instance_of KBS::Blackboard::Persistence::RedisStore, @store.redis_store
    assert_instance_of KBS::Blackboard::Persistence::SqliteStore, @store.sqlite_store
  end

  def test_hybrid_flag
    assert @store.respond_to?(:hybrid?)
    assert @store.hybrid?
  end

  def test_add_fact_to_redis
    @store.add_fact('uuid-1', :sensor, { temp: 22 })

    # Fact should be in Redis
    fact = @store.redis_store.get_fact('uuid-1')
    assert fact
    assert_equal :sensor, fact[:type]
  end

  def test_get_facts_from_redis
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    @store.add_fact('uuid-2', :sensor, { temp: 25 })

    facts = @store.get_facts(:sensor)
    assert_equal 2, facts.size
  end

  def test_query_facts_is_not_implemented
    assert_raises(NotImplementedError) do
      @store.query_facts('type = ?', ['sensor'])
    end
  end

  def test_provides_both_connection_and_db
    assert @store.respond_to?(:connection)
    assert @store.respond_to?(:db)

    assert_instance_of Redis, @store.connection
    assert_instance_of SQLite3::Database, @store.db
  end

  def test_stats_combined
    @store.add_fact('uuid-1', :sensor, { temp: 22 })

    stats = @store.stats
    assert stats[:active_facts]
    assert stats[:total_facts]
  end

  def test_vacuum_both_stores
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    @store.vacuum # Should not error
  end

  def test_close_both_stores
    @store.close
    # Verify connections are closed (should not error)
  end

  def test_remove_fact_from_redis
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    result = @store.remove_fact('uuid-1')

    assert result
    facts = @store.get_facts(:sensor)
    assert_empty facts
  end

  def test_update_fact_in_redis
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    @store.update_fact('uuid-1', { temp: 25 })

    fact = @store.get_fact('uuid-1')
    assert_equal 25, fact[:attributes][:temp]
  end

  # Contract: blackboard/register-knowledge-source-without-description
  # Bug: HybridStore#register_knowledge_source raised TypeError when description was nil
  def test_register_knowledge_source_without_description
    @store.register_knowledge_source('TempMonitor')

    assert_equal 1, @store.stats[:knowledge_sources]
  end

  # Contract: blackboard/hybrid-audit-records
  # Bug: HybridStore#stats[:audit_records] counted the unused SQLite facts table, so it was always 0
  def test_audit_records_counts_the_audit_log
    memory = KBS::Blackboard::Memory.new(store: @store)
    fact = memory.add_fact(:sensor, { temp: 22 })
    memory.remove_fact(fact)
    memory.log_rule_firing('r', [fact.uuid])

    assert_equal 3, memory.stats[:audit_records]
  end

  def test_audit_records_is_zero_before_the_audit_log_exists
    assert_equal 0, @store.stats[:audit_records]
  end

  # A Redis-backed store cannot roll back, so a fact added in a failed
  # transaction stays in the store and in the engine.
  def test_failed_transaction_keeps_facts_the_store_kept
    engine = KBS::Blackboard::Engine.new(store: @store)

    assert_raises(RuntimeError) do
      engine.blackboard.transaction do
        engine.add_fact(:sensor, { temp: 22 })
        raise 'boom'
      end
    end

    assert_equal 1, engine.facts.size
  end

  def test_memory_clear_session_without_session_id
    store = KBS::Blackboard::Persistence::HybridStore.new(redis: @redis, db_path: ':memory:')
    memory = KBS::Blackboard::Memory.new(store: store)
    memory.add_fact(:sensor, { temp: 22 })

    memory.clear_session
    assert_equal 0, memory.get_facts(:sensor).size
  ensure
    store&.close
  end
end
