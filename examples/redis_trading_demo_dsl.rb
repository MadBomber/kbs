#!/usr/bin/env ruby

require_relative '../lib/kbs/blackboard'

puts "Redis-Backed High-Frequency Trading System"
puts "=" * 70

# Demo 1: Pure Redis Store (fast, in-memory)
puts "\n=== Pure Redis Store Demo ==="
puts "Fast in-memory fact storage with Redis"

begin
  redis_store = KBS::Blackboard::Persistence::RedisStore.new(
    url: 'redis://localhost:6379/1' # Use DB 1 for demo
  )

  # Clear previous demo data
  redis_store.redis.flushdb
  puts "(Cleared previous Redis data)"

  engine = KBS::Blackboard::Engine.new(store: redis_store)

  # Add trading rules (raw API since Blackboard::Engine doesn't use DSL)
  spread_rule = KBS::Rule.new('tight_spread_opportunity') do |r|
    r.conditions << KBS::Condition.new(:market_price, { symbol: 'AAPL' })
    r.conditions << KBS::Condition.new(:order, { symbol: 'AAPL', type: 'BUY' })
    r.action = ->(facts) {
      price = facts.find { |f| f.type == :market_price }
      order = facts.find { |f| f.type == :order }
      spread = 0.02 # Tight spread
      puts "\n💹 TRADING SIGNAL: Tight spread opportunity for #{price[:symbol]}"
      puts "   Price: $#{price[:price]}, Spread: $#{spread}"
      puts "   Order: #{order[:type]} #{order[:quantity]} @ $#{order[:limit]}"
    }
  end

  high_volume_rule = KBS::Rule.new('high_volume_alert') do |r|
    r.conditions << KBS::Condition.new(:market_price, { volume: ->(v) { v > 800 } })
    r.action = ->(facts) {
      price = facts.first
      puts "\n📊 HIGH VOLUME: #{price[:symbol]} trading at #{price[:volume]} shares"
    }
  end

  engine.add_rule(spread_rule)
  engine.add_rule(high_volume_rule)

  puts "\nAdding high-frequency market data..."
  price1 = engine.add_fact(:market_price, { symbol: "AAPL", price: 150.25, volume: 1000 })
  price2 = engine.add_fact(:market_price, { symbol: "GOOGL", price: 2800.50, volume: 500 })
  order = engine.add_fact(:order, { symbol: "AAPL", type: "BUY", quantity: 100, limit: 150.00 })

  puts "Facts added with UUIDs:"
  puts "  AAPL Price: #{price1.uuid}"
  puts "  GOOGL Price: #{price2.uuid}"
  puts "  Order: #{order.uuid}"

  puts "\nRunning inference engine..."
  engine.run

  puts "\nPosting trading messages..."
  engine.post_message("MarketDataFeed", "prices", { symbol: "AAPL", bid: 150.24, ask: 150.26 }, priority: 10)
  engine.post_message("OrderManager", "orders", { action: "fill", order_id: order.uuid }, priority: 5)

  puts "\nConsuming highest priority message..."
  message = engine.consume_message("prices", "TradingStrategy")
  puts "  Received: #{message[:content]}" if message

  puts "\nQuerying market prices..."
  prices = engine.blackboard.get_facts(:market_price)
  puts "  Found #{prices.size} price(s):"
  prices.each { |p| puts "    - #{p}" }

  puts "\nRedis Statistics:"
  stats = engine.stats
  stats.each do |key, value|
    puts "  #{key.to_s.gsub('_', ' ').capitalize}: #{value}"
  end

  engine.blackboard.close

rescue Redis::CannotConnectError => e
  puts "\n⚠️  Redis not available: #{e.message}"
  puts "   Please start Redis: redis-server"
  puts "   Or install Redis: brew install redis (macOS)"
end

# Demo 2: Hybrid Store (Redis + SQLite)
puts "\n\n=== Hybrid Store Demo ==="
puts "Redis for fast fact access + SQLite for durable audit trail"

begin
  hybrid_store = KBS::Blackboard::Persistence::HybridStore.new(
    redis_url: 'redis://localhost:6379/2', # Use DB 2 for demo
    db_path: ':memory:' # In-memory SQLite for demo
  )

  # Clear previous demo data from Redis
  hybrid_store.redis_store.redis.flushdb
  puts "(Cleared previous Redis data)"

  engine = KBS::Blackboard::Engine.new(store: hybrid_store)

  # Add monitoring rules (raw API since Blackboard::Engine doesn't use DSL)
  temp_alert = KBS::Rule.new('temperature_alert') do |r|
    r.conditions << KBS::Condition.new(:sensor, {
      type: 'temperature',
      value: ->(v) { v > 25 }
    })
    r.action = ->(facts) {
      sensor = facts.first
      puts "\n🌡️  TEMPERATURE ALERT: #{sensor[:location]} at #{sensor[:value]}°C (threshold: 25°C)"
    }
  end

  cpu_warning = KBS::Rule.new('cpu_warning') do |r|
    r.conditions << KBS::Condition.new(:sensor, {
      type: 'cpu_usage',
      value: ->(v) { v > 40 }
    })
    r.action = ->(facts) {
      sensor = facts.first
      puts "\n⚙️  CPU WARNING: #{sensor[:location]} at #{sensor[:value]}% (threshold: 40%)"
    }
  end

  engine.add_rule(temp_alert)
  engine.add_rule(cpu_warning)

  puts "\nAdding facts (stored in Redis)..."
  sensor1 = engine.add_fact(:sensor, { location: "trading_floor", type: "temperature", value: 22 })
  sensor2 = engine.add_fact(:sensor, { location: "data_center", type: "cpu_usage", value: 45 })

  puts "Facts added:"
  puts "  Sensor 1: #{sensor1.uuid}"
  puts "  Sensor 2: #{sensor2.uuid}"

  puts "\nRunning inference engine..."
  engine.run

  puts "\nUpdating sensor value (audit logged to SQLite)..."
  sensor1[:value] = 28

  puts "\nRunning inference again after update..."
  engine.run

  puts "\nFact History from SQLite Audit Log:"
  history = engine.blackboard.get_history(limit: 5)
  history.each do |entry|
    puts "  [#{entry[:timestamp].strftime('%H:%M:%S')}] #{entry[:action]}: #{entry[:fact_type]}(#{entry[:attributes]})"
  end

  puts "\nHybrid Store Benefits:"
  puts "  ✓ Facts in Redis (fast reads/writes)"
  puts "  ✓ Messages in Redis (real-time messaging)"
  puts "  ✓ Audit trail in SQLite (durable, queryable)"
  puts "  ✓ Best of both worlds for production systems"

  puts "\nStatistics:"
  stats = engine.stats
  stats.each do |key, value|
    puts "  #{key.to_s.gsub('_', ' ').capitalize}: #{value}"
  end

  engine.blackboard.close

rescue Redis::CannotConnectError => e
  puts "\n⚠️  Redis not available: #{e.message}"
  puts "   Hybrid store requires Redis for fact storage"
end

puts "\n" + "=" * 70
puts "Demo complete!"
puts "\nComparison:"
puts "  SQLite Store:  Durable, transactional, embedded (no server needed)"
puts "  Redis Store:   Fast (100x), distributed, requires Redis server"
puts "  Hybrid Store:  Fast facts + durable audit (production recommended)"
