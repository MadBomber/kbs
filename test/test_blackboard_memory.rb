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
    assert(sensors.all? { |f| f.type == :sensor })
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

  # Issue #63: a String message raised JSON::ParserError and blocked its topic.
  def test_string_message_does_not_block_topic
    @memory.post_message("s", "q", "plain text")
    @memory.post_message("s", "q", { ok: true })

    assert_equal(["plain text", { ok: true }], @memory.peek_messages("q").map { |m| m[:content] })
    assert_equal "plain text", @memory.consume_message("q", "c")[:content]
    assert_equal({ ok: true }, @memory.consume_message("q", "c")[:content])
  end

  # Issue #62: SQLite stores CURRENT_TIMESTAMP as UTC text, which used to be
  # read back as local time.
  def test_timestamps_read_back_in_utc
    original_tz = ENV.fetch('TZ', nil)
    ENV['TZ'] = 'America/Chicago'

    @memory.post_message("s", "t", { a: 1 })
    @memory.log_rule_firing("r", [], {})
    fact = @memory.add_fact(:x, v: 1)

    assert_in_delta Time.now.to_f, @memory.consume_message("t", "c")[:posted_at].to_f, 60
    assert_in_delta Time.now.to_f, @memory.get_rule_firings.first[:fired_at].to_f, 60
    assert_in_delta Time.now.to_f, @memory.get_history(fact.uuid).first[:timestamp].to_f, 60
  ensure
    ENV['TZ'] = original_tz
  end

  # Issue #60: a consumer that claimed the message between another
  # consumer's read and update used to receive it as well.
  def test_message_consumed_by_only_one_consumer
    @memory.post_message("s", "q", { n: 1 })
    queue = @memory.message_queue
    db = @memory.store.db
    original = db.method(:get_first_row)
    received = []

    db.define_singleton_method(:get_first_row) do |*args|
      row = original.call(*args)
      db.singleton_class.send(:remove_method, :get_first_row)
      received << queue.consume("q", "rival")
      row
    end

    received << queue.consume("q", "c")
    assert_equal 1, received.compact.size
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
    @memory.log_rule_firing("test_rule", %w[uuid1 uuid2], { price: 150 })

    firings = @memory.get_rule_firings
    assert_equal 1, firings.size
    assert_equal "test_rule", firings.first[:rule_name]
    assert_equal %w[uuid1 uuid2], firings.first[:fact_uuids]
    assert_equal 150, firings.first[:bindings][:price]
  end

  def test_observer_pattern
    nil
    nil

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

  def test_clear_session_with_store_passed_in
    store = KBS::Blackboard::Persistence::SqliteStore.new(db_path: ':memory:')
    memory = KBS::Blackboard::Memory.new(store: store)
    memory.add_fact(:sensor, { temp: 22 })

    memory.clear_session
    assert_equal 0, memory.get_facts(:sensor).size
    assert_equal store.session_id, memory.session_id
  ensure
    memory&.close
  end

  def test_register_knowledge_source
    @memory.register_knowledge_source(
      "TemperatureMonitor",
      description: "Monitors temperature sensors",
      topics: %w[readings alerts]
    )

    stats = @memory.stats
    assert_equal 1, stats[:knowledge_sources]
  end

  # Contract: blackboard/sqlite-message-queue-accepts-symbols
  # Bug: the SQLite MessageQueue rejected Symbol topics and senders, which RedisMessageQueue accepts
  def test_message_queue_accepts_symbol_topic_and_sender
    @memory.post_message(:sensor, :readings, { temp: 22 })

    assert_equal 1, @memory.peek_messages(:readings).size
    message = @memory.consume_message(:readings, :consumer)
    assert_equal 'sensor', message[:sender]
    assert_equal 'readings', message[:topic]
  end

  # Contract: blackboard/store-base-interface
  # Bug: the Store base class lacked session_id and register_knowledge_source, which Memory calls
  def test_store_base_class_declares_session_id_and_register_knowledge_source
    store = KBS::Blackboard::Persistence::Store.new

    assert_nil store.session_id
    assert_raises(NotImplementedError) { store.register_knowledge_source('ks') }
  end

  # Contract: blackboard/memory-rejects-unsuitable-store
  # Bug: Memory.new(store: obj) raised NoMethodError for session_id before its own ArgumentError
  def test_unsuitable_store_raises_argument_error
    error = assert_raises(ArgumentError) { KBS::Blackboard::Memory.new(store: Object.new) }
    assert_match(/:connection .* :db/, error.message)
  end

  # Contract: blackboard/memory-remove-fact-returns-fact
  # Bug: Memory#remove_fact returned the observer array instead of the fact
  def test_remove_fact_returns_the_removed_fact_or_nil
    fact = @memory.add_fact(:sensor, { temp: 22 })

    assert_equal fact, @memory.remove_fact(fact)
    assert_nil @memory.remove_fact(fact)
  end

  def test_rolled_back_transaction_tells_observers_the_added_fact_is_gone
    events = []
    observer = Object.new
    observer.define_singleton_method(:update) { |action, fact| events << [action, fact.uuid] }
    @memory.add_observer(observer)
    added = nil

    assert_raises(RuntimeError) do
      @memory.transaction do
        added = @memory.add_fact(:sensor, { temp: 22 })
        raise 'boom'
      end
    end

    assert_equal [[:add, added.uuid], [:remove, added.uuid]], events
    assert_empty @memory.get_facts(:sensor)
  end

  def test_withdraw_rolled_back_skips_facts_the_store_still_holds
    stored = @memory.add_fact(:sensor, { temp: 22 })
    gone = KBS::Blackboard::Fact.new('not-stored', :sensor, {})
    removed = []
    observer = Object.new
    observer.define_singleton_method(:update) { |action, fact| removed << fact.uuid if action == :remove }
    @memory.add_observer(observer)

    @memory.withdraw_rolled_back([stored, gone])

    assert_equal ['not-stored'], removed
  end
end
