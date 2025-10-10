#!/usr/bin/env ruby

require_relative '../lib/kbs'
include KBS::DSL::ConditionHelpers

# Define the knowledge base with rules
kb = KBS.knowledge_base do
  # Rule 1: Simple stock momentum
  rule "momentum_buy" do
    on :stock, symbol: "AAPL"

    perform do |facts, bindings|
      stock = facts.find { |f| f.type == :stock }
      puts "🚀 MOMENTUM SIGNAL: #{stock[:symbol]}"
      puts "   Price: $#{stock[:price]}"
      puts "   Volume: #{stock[:volume].to_s.reverse.scan(/\d{1,3}/).join(',').reverse}"
      puts "   Recommendation: BUY"
    end
  end

  # Rule 2: High volume alert
  rule "high_volume" do
    on :stock do
      volume greater_than(1000000)
    end

    perform do |facts, bindings|
      stock = facts.find { |f| f.type == :stock }
      puts "📊 HIGH VOLUME ALERT: #{stock[:symbol]}"
      puts "   Volume: #{stock[:volume].to_s.reverse.scan(/\d{1,3}/).join(',').reverse}"
      puts "   Above 1M shares traded"
    end
  end

  # Rule 3: Price movement
  rule "price_movement" do
    on :stock do
      price_change satisfies { |p| p && p.abs > 2 }
    end

    perform do |facts, bindings|
      stock = facts.find { |f| f.type == :stock }
      direction = stock[:price_change] > 0 ? "UP" : "DOWN"
      puts "📈 SIGNIFICANT MOVE: #{stock[:symbol]} #{direction}"
      puts "   Change: #{stock[:price_change] > 0 ? '+' : ''}#{stock[:price_change]}%"
    end
  end

  # Rule 4: RSI signals
  rule "rsi_signal" do
    on :stock do
      rsi satisfies { |r| r && (r < 30 || r > 70) }
    end

    perform do |facts, bindings|
      stock = facts.find { |f| f.type == :stock }
      condition = stock[:rsi] < 30 ? "OVERSOLD" : "OVERBOUGHT"
      action = stock[:rsi] < 30 ? "BUY" : "SELL"
      puts "⚡ RSI SIGNAL: #{stock[:symbol]} #{condition}"
      puts "   RSI: #{stock[:rsi].round(1)}"
      puts "   Recommendation: #{action}"
    end
  end

  # Rule 5: Multi-condition golden cross
  rule "golden_cross_complete" do
    on :stock, symbol: "AAPL"
    on :ma_signal, type: "golden_cross"

    perform do |facts, bindings|
      stock = facts.find { |f| f.type == :stock }
      signal = facts.find { |f| f.type == :ma_signal }
      puts "🌟 GOLDEN CROSS CONFIRMED: #{stock[:symbol]}"
      puts "   50-day MA crossed above 200-day MA"
      puts "   Price: $#{stock[:price]}"
      puts "   Recommendation: STRONG BUY"
    end
  end
end

def run_scenarios(kb)
  puts "🏦 STOCK TRADING EXPERT SYSTEM"
  puts "=" * 50

  # Scenario 1: Apple momentum
  puts "\n📊 SCENARIO 1: Apple with High Volume"
  puts "-" * 30
  kb.reset
  kb.fact :stock, {
    symbol: "AAPL",
    price: 185.50,
    volume: 1_500_000,
    price_change: 3.2,
    rsi: 68
  }
  kb.run

  # Scenario 2: Google big move
  puts "\n📊 SCENARIO 2: Google Big Price Move"
  puts "-" * 30
  kb.reset
  kb.fact :stock, {
    symbol: "GOOGL",
    price: 142.80,
    volume: 800_000,
    price_change: -4.1,
    rsi: 75
  }
  kb.run

  # Scenario 3: Tesla oversold
  puts "\n📊 SCENARIO 3: Tesla Oversold"
  puts "-" * 30
  kb.reset
  kb.fact :stock, {
    symbol: "TSLA",
    price: 195.40,
    volume: 2_200_000,
    price_change: -1.8,
    rsi: 25
  }
  kb.run

  # Scenario 4: Apple Golden Cross
  puts "\n📊 SCENARIO 4: Apple Golden Cross"
  puts "-" * 30
  kb.reset
  kb.fact :stock, {
    symbol: "AAPL",
    price: 190.25,
    volume: 1_100_000,
    price_change: 2.1,
    rsi: 55
  }
  kb.fact :ma_signal, {
    symbol: "AAPL",
    type: "golden_cross"
  }
  kb.run

  # Scenario 5: Multiple signals
  puts "\n📊 SCENARIO 5: NVIDIA Multiple Signals"
  puts "-" * 30
  kb.reset
  kb.fact :stock, {
    symbol: "NVDA",
    price: 425.80,
    volume: 3_500_000,
    price_change: 8.7,
    rsi: 78
  }
  kb.run

  puts "\n" + "=" * 50
  puts "DEMONSTRATION COMPLETE"
end

if __FILE__ == $0
  run_scenarios(kb)
end
