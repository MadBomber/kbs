# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs'
require_relative '../lib/kbs/dsl'
require_relative '../lib/kbs/blackboard'

class TestIntegration < Minitest::Test
  def test_basic_rete_workflow
    engine = KBS::ReteEngine.new

    # Define rule
    rule = KBS::Rule.new('fast_car') do |r|
      r.conditions << KBS::Condition.new(:car, { speed: ->(s) { s > 100 } })
      r.action = ->(facts) { facts.first[:alert] = true }
    end

    engine.add_rule(rule)
    engine.add_fact(:car, { speed: 150, color: :red })
    engine.run

    # Verify rule fired
    assert engine.working_memory.facts.first[:alert]
  end

  def test_dsl_knowledge_base_workflow
    results = []

    kb = KBS.knowledge_base do
      rule 'high_temperature' do
        on :sensor, temp: greater_than(25)
        perform { |facts| results << facts.first[:temp] }
      end

      fact :sensor, temp: 20
      fact :sensor, temp: 30
      fact :sensor, temp: 28

      run
    end

    assert_equal 2, results.size
    assert_includes results, 30
    assert_includes results, 28
  end

  def test_blackboard_persistence_workflow
    engine = KBS::Blackboard::Engine.new(db_path: ':memory:')

    # Add facts
    sensor1 = engine.add_fact(:sensor, { location: "room_1", temp: 22 })
    sensor2 = engine.add_fact(:sensor, { location: "room_2", temp: 28 })

    # Post message
    engine.post_message("Monitor", "alerts", { message: "Check sensors" })

    # Define and run rule
    results = []
    rule = KBS::Rule.new('high_temp_alert') do |r|
      r.conditions << KBS::Condition.new(:sensor, { temp: ->(t) { t > 25 } })
      r.action = ->(facts) { results << facts.first.uuid }
    end

    engine.add_rule(rule)
    engine.run

    # Verify
    assert_equal 1, results.size
    assert_equal sensor2.uuid, results.first

    # Check history
    history = engine.blackboard.get_history(sensor1.uuid)
    assert_equal 1, history.size
    assert_equal 'ADD', history.first[:action]

    # Check stats
    stats = engine.stats
    assert_equal 2, stats[:active_facts]
    assert_equal 1, stats[:unconsumed_messages]

    engine.blackboard.close
  end

  def test_dsl_with_negation
    results = []

    kb = KBS.knowledge_base do
      rule 'safe_to_proceed' do
        on :car, color: :red
        without :problem
        perform { |facts| results << :safe }
      end

      fact :car, color: :red
      run
    end

    assert_equal 1, results.size
    assert_equal :safe, results.first
  end

  def test_multi_condition_join
    results = []

    kb = KBS.knowledge_base do
      rule 'young_driver_red_car' do
        on :driver, age: between(18, 25)
        on :car, color: :red
        perform { |facts| results << facts.map(&:type) }
      end

      fact :driver, age: 20, name: "John"
      fact :car, color: :red, speed: 100
      fact :driver, age: 30, name: "Jane"

      run
    end

    assert_equal 1, results.size
    assert_equal [:driver, :car], results.first
  end

  def test_pattern_matching_with_helpers
    results = []

    KBS.knowledge_base do
      rule 'primary_color_car' do
        on :car, color: one_of(:red, :blue, :yellow)
        perform { |facts| results << facts.first[:color] }
      end

      fact :car, color: :red
      fact :car, color: :green
      fact :car, color: :blue

      run
    end

    assert_equal 2, results.size
    assert_includes results, :red
    assert_includes results, :blue
  end

  def test_blackboard_message_priority
    engine = KBS::Blackboard::Engine.new(db_path: ':memory:')

    engine.post_message("Sensor1", "alerts", { priority: "low" }, priority: 1)
    engine.post_message("Sensor2", "alerts", { priority: "high" }, priority: 10)
    engine.post_message("Sensor3", "alerts", { priority: "medium" }, priority: 5)

    # Consume in priority order
    msg1 = engine.consume_message("alerts", "Consumer")
    msg2 = engine.consume_message("alerts", "Consumer")
    msg3 = engine.consume_message("alerts", "Consumer")

    assert_equal "high", msg1[:content][:priority]
    assert_equal "medium", msg2[:content][:priority]
    assert_equal "low", msg3[:content][:priority]

    engine.blackboard.close
  end

  def test_fact_update_and_history
    engine = KBS::Blackboard::Engine.new(db_path: ':memory:')

    sensor = engine.add_fact(:sensor, { temp: 20 })
    sensor[:temp] = 25
    sensor[:temp] = 30
    sensor.update({ temp: 35, location: "room_1" })

    history = engine.blackboard.get_history(sensor.uuid)

    # Should have ADD + 3 UPDATEs
    assert history.size >= 4
    assert_equal 'ADD', history.last[:action]
    assert history.any? { |h| h[:action] == 'UPDATE' && h[:attributes][:temp] == 35 }

    engine.blackboard.close
  end

  def test_complex_trading_scenario
    engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
    orders = []

    # Define trading rules
    buy_rule = KBS::Rule.new('buy_signal') do |r|
      r.conditions << KBS::Condition.new(:price, { symbol: "AAPL", value: ->(v) { v < 150 } })
      r.conditions << KBS::Condition.new(:account, { balance: ->(b) { b > 10000 } })
      r.action = ->(facts) { orders << { action: :buy, symbol: facts[0][:symbol] } }
    end

    engine.add_rule(buy_rule)

    # Add facts
    engine.add_fact(:price, { symbol: "AAPL", value: 145 })
    engine.add_fact(:account, { balance: 50000 })

    engine.run

    assert_equal 1, orders.size
    assert_equal :buy, orders.first[:action]
    assert_equal "AAPL", orders.first[:symbol]

    # Check rule firing was logged
    firings = engine.blackboard.get_rule_firings
    assert_equal 1, firings.size
    assert_equal 'buy_signal', firings.first[:rule_name]

    engine.blackboard.close
  end

  def test_iot_sensor_scenario
    engine = KBS::Blackboard::Engine.new(db_path: ':memory:')
    alerts = []

    # High temperature alert rule
    alert_rule = KBS::Rule.new('temp_alert') do |r|
      r.conditions << KBS::Condition.new(:sensor, { type: "temperature", value: ->(v) { v > 30 } })
      r.action = ->(facts) {
        sensor = facts.first
        alerts << { location: sensor[:location], temp: sensor[:value] }
        engine.post_message("AlertSystem", "critical", { sensor_id: sensor.uuid }, priority: 10)
      }
    end

    engine.add_rule(alert_rule)

    # Simulate sensor readings
    engine.add_fact(:sensor, { type: "temperature", location: "server_room", value: 22 })
    engine.add_fact(:sensor, { type: "temperature", location: "warehouse", value: 35 })
    engine.add_fact(:sensor, { type: "humidity", location: "office", value: 65 })

    engine.run

    # Verify alert was generated
    assert_equal 1, alerts.size
    assert_equal "warehouse", alerts.first[:location]
    assert_equal 35, alerts.first[:temp]

    # Verify message was posted
    messages = engine.blackboard.peek_messages("critical")
    assert_equal 1, messages.size
    assert_equal 10, messages.first[:priority]

    engine.blackboard.close
  end
end
