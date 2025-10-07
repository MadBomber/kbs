# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs/blackboard'

class TestHybridStore < Minitest::Test
  def redis_available?
    begin
      require 'redis'
      redis = Redis.new(url: 'redis://localhost:6379/15', timeout: 1)
      redis.ping
      redis.close
      true
    rescue LoadError, Redis::CannotConnectError, Redis::TimeoutError
      false
    end
  end

  def setup
    skip "Redis not available" unless redis_available?

    require 'redis'
    @redis = Redis.new(url: 'redis://localhost:6379/15')
    @redis.flushdb

    @store = KBS::Blackboard::Persistence::HybridStore.new(
      redis: @redis,
      db_path: ':memory:',
      session_id: 'test-session'
    )
  end

  def teardown
    if redis_available?
      @store.close if @store
      @redis.flushdb if @redis
      @redis.close if @redis
    end
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
end
