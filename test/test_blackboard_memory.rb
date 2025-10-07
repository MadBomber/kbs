# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs/blackboard'

class TestBlackboardMemory < Minitest::Test
  def setup
    @memory = KBS::Blackboard::Memory.new(db_path: ':memory:')
  end

  def teardown
    @memory.close if @memory
  end

  def test_initialization
    assert_instance_of KBS::Blackboard::Memory, @memory
    assert @memory.session_id
    assert_instance_of String, @memory.session_id
  end

  def test_add_fact
    fact = @memory.add_fact(:sensor, { location: "room_1", temp: 22 })

    assert_instance_of KBS::Blackboard::Fact, fact
    assert fact.uuid
    assert_equal :sensor, fact.type
    assert_equal "room_1", fact[:location]
    assert_equal 22, fact[:temp]
  end

  def test_get_facts_by_type
    @memory.add_fact(:sensor, { location: "room_1", temp: 22 })
    @memory.add_fact(:sensor, { location: "room_2", temp: 25 })
    @memory.add_fact(:alert, { level: "warning" })

    sensors = @memory.get_facts(:sensor)
    assert_equal 2, sensors.size
    assert sensors.all? { |f| f.type == :sensor }
  end

  def test_get_facts_with_pattern
    @memory.add_fact(:sensor, { location: "room_1", temp: 22 })
    @memory.add_fact(:sensor, { location: "room_2", temp: 25 })

    room1_sensors = @memory.get_facts(:sensor, location: "room_1")
    assert_equal 1, room1_sensors.size
    assert_equal "room_1", room1_sensors.first[:location]
  end

  def test_remove_fact
    fact = @memory.add_fact(:sensor, { temp: 22 })
    facts_before = @memory.get_facts(:sensor)
    assert_equal 1, facts_before.size

    @memory.remove_fact(fact)
    facts_after = @memory.get_facts(:sensor)
    assert_equal 0, facts_after.size
  end

  def test_update_fact
    fact = @memory.add_fact(:sensor, { temp: 22 })
    assert_equal 22, fact[:temp]

    fact[:temp] = 25
    # Re-fetch to verify persistence
    facts = @memory.get_facts(:sensor)
    assert_equal 1, facts.size
  end

  def test_message_queue
    @memory.post_message("Sensor1", "readings", { temp: 22 }, priority: 5)
    @memory.post_message("Sensor2", "readings", { temp: 25 }, priority: 10)

    # Higher priority message should be consumed first
    message = @memory.consume_message("readings", "Consumer1")
    assert message
    assert_equal "Sensor2", message[:sender]
    assert_equal 10, message[:priority]
  end

  def test_peek_messages
    @memory.post_message("Sensor1", "readings", { temp: 22 })
    @memory.post_message("Sensor2", "readings", { temp: 25 })

    messages = @memory.peek_messages("readings", limit: 10)
    assert_equal 2, messages.size

    # Peeking shouldn't consume
    messages_again = @memory.peek_messages("readings", limit: 10)
    assert_equal 2, messages_again.size
  end

  def test_audit_log
    fact = @memory.add_fact(:sensor, { temp: 22 })
    fact[:temp] = 25
    @memory.remove_fact(fact)

    history = @memory.get_history(fact.uuid)
    assert_equal 3, history.size
    assert_equal 'ADD', history[2][:action]
    assert_equal 'UPDATE', history[1][:action]
    assert_equal 'REMOVE', history[0][:action]
  end

  def test_rule_firing_log
    @memory.log_rule_firing("test_rule", ["uuid1", "uuid2"], { price: 150 })

    firings = @memory.get_rule_firings
    assert_equal 1, firings.size
    assert_equal "test_rule", firings.first[:rule_name]
    assert_equal ["uuid1", "uuid2"], firings.first[:fact_uuids]
    assert_equal 150, firings.first[:bindings][:price]
  end

  def test_observer_pattern
    observer_called = false
    action_received = nil
    fact_received = nil

    observer = Object.new
    def observer.update(action, fact)
      @called = true
      @action = action
      @fact = fact
    end

    class << observer
      attr_reader :called, :action, :fact
    end

    @memory.add_observer(observer)
    @memory.add_fact(:sensor, { temp: 22 })

    assert observer.called
    assert_equal :add, observer.action
    assert_instance_of KBS::Blackboard::Fact, observer.fact
  end

  def test_stats
    @memory.add_fact(:sensor, { temp: 22 })
    @memory.add_fact(:alert, { level: "warning" })
    @memory.post_message("Sensor1", "readings", { temp: 22 })

    stats = @memory.stats
    assert_equal 2, stats[:active_facts]
    assert_equal 1, stats[:unconsumed_messages]
  end

  def test_transaction
    @memory.transaction do
      @memory.add_fact(:sensor, { temp: 22 })
      @memory.add_fact(:sensor, { temp: 25 })
    end

    sensors = @memory.get_facts(:sensor)
    assert_equal 2, sensors.size
  end

  def test_clear_session
    @memory.add_fact(:sensor, { temp: 22 })
    assert_equal 1, @memory.get_facts(:sensor).size

    @memory.clear_session
    assert_equal 0, @memory.get_facts(:sensor).size
  end

  def test_register_knowledge_source
    @memory.register_knowledge_source(
      "TemperatureMonitor",
      description: "Monitors temperature sensors",
      topics: ["readings", "alerts"]
    )

    stats = @memory.stats
    assert_equal 1, stats[:knowledge_sources]
  end
end
