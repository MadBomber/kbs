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

  engine = KBS::Blackboard::Engine.new(store: redis_store)

  puts "\nAdding high-frequency market data..."
  price1 = engine.add_fact(:market_price, { symbol: "AAPL", price: 150.25, volume: 1000 })
  price2 = engine.add_fact(:market_price, { symbol: "GOOGL", price: 2800.50, volume: 500 })
  order = engine.add_fact(:order, { symbol: "AAPL", type: "BUY", quantity: 100, limit: 150.00 })

  puts "Facts added with UUIDs:"
  puts "  AAPL Price: #{price1.uuid}"
  puts "  GOOGL Price: #{price2.uuid}"
  puts "  Order: #{order.uuid}"

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

  engine = KBS::Blackboard::Engine.new(store: hybrid_store)

  puts "\nAdding facts (stored in Redis)..."
  sensor1 = engine.add_fact(:sensor, { location: "trading_floor", type: "temperature", value: 22 })
  sensor2 = engine.add_fact(:sensor, { location: "data_center", type: "cpu_usage", value: 45 })

  puts "Facts added:"
  puts "  Sensor 1: #{sensor1.uuid}"
  puts "  Sensor 2: #{sensor2.uuid}"

  puts "\nUpdating sensor value (audit logged to SQLite)..."
  sensor1[:value] = 28

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
