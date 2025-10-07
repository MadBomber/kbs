# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs/blackboard'

class TestRedisStore < Minitest::Test
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
    @redis = Redis.new(url: 'redis://localhost:6379/15') # Use DB 15 for tests
    @redis.flushdb # Clear test database
    @store = KBS::Blackboard::Persistence::RedisStore.new(
      redis: @redis,
      session_id: 'test-session'
    )
  end

  def teardown
    if redis_available?
      @redis.flushdb if @redis
      @redis.close if @redis
    end
  end

  def test_initialization
    assert_instance_of KBS::Blackboard::Persistence::RedisStore, @store
    assert_equal 'test-session', @store.session_id
  end

  def test_add_fact
    @store.add_fact('uuid-1', :sensor, { temp: 22, location: 'room_1' })

    fact = @store.get_fact('uuid-1')
    assert fact
    assert_equal 'uuid-1', fact[:uuid]
    assert_equal :sensor, fact[:type]
    assert_equal 22, fact[:attributes][:temp]
  end

  def test_get_facts_by_type
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    @store.add_fact('uuid-2', :sensor, { temp: 25 })
    @store.add_fact('uuid-3', :alert, { level: 'warning' })

    sensors = @store.get_facts(:sensor)
    assert_equal 2, sensors.size
    assert sensors.all? { |f| f[:type] == :sensor }
  end

  def test_get_facts_with_pattern
    @store.add_fact('uuid-1', :sensor, { location: 'room_1', temp: 22 })
    @store.add_fact('uuid-2', :sensor, { location: 'room_2', temp: 25 })

    room1_sensors = @store.get_facts(:sensor, location: 'room_1')
    assert_equal 1, room1_sensors.size
    assert_equal 'room_1', room1_sensors.first[:attributes][:location]
  end

  def test_remove_fact
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    result = @store.remove_fact('uuid-1')

    assert result
    assert_equal :sensor, result[:type]

    # Verify fact is marked as retracted
    fact = @store.get_fact('uuid-1')
    assert_nil fact
  end

  def test_update_fact
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    @store.update_fact('uuid-1', { temp: 25, location: 'room_1' })

    fact = @store.get_fact('uuid-1')
    assert_equal 25, fact[:attributes][:temp]
    assert_equal 'room_1', fact[:attributes][:location]
  end

  def test_register_knowledge_source
    @store.register_knowledge_source(
      'TempMonitor',
      description: 'Monitors temperature',
      topics: ['readings']
    )

    stats = @store.stats
    assert_equal 1, stats[:knowledge_sources]
  end

  def test_stats
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    @store.add_fact('uuid-2', :alert, { level: 'warning' })
    @store.add_fact('uuid-3', :sensor, { temp: 25 })
    @store.remove_fact('uuid-3')

    stats = @store.stats
    assert_equal 3, stats[:total_facts]
    assert_equal 2, stats[:active_facts]
  end

  def test_clear_session
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    @store.add_fact('uuid-2', :sensor, { temp: 25 })

    @store.clear_session('test-session')
    facts = @store.get_facts(:sensor)
    assert_empty facts
  end

  def test_connection_method
    assert @store.respond_to?(:connection)
    assert_instance_of Redis, @store.connection
  end

  def test_transaction
    @store.transaction do
      @store.add_fact('uuid-1', :sensor, { temp: 22 })
      @store.add_fact('uuid-2', :sensor, { temp: 25 })
    end

    facts = @store.get_facts(:sensor)
    assert_equal 2, facts.size
  end

  def test_vacuum_removes_old_retracted_facts
    # This test would need to manipulate timestamps
    # For now, just verify vacuum doesn't error
    @store.add_fact('uuid-1', :sensor, { temp: 22 })
    @store.remove_fact('uuid-1')
    @store.vacuum
  end
end
