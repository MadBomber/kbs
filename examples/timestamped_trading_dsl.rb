#!/usr/bin/env ruby

require_relative '../lib/kbs'
require 'time'

class TimestampedTradingSystem
  include KBS::DSL::ConditionHelpers

  def initialize
    @kb = nil
    @market_open = Time.parse("09:30:00")
    @market_close = Time.parse("16:00:00")
    setup_time_aware_rules
  end

  def format_volume(volume)
    if volume >= 1_000_000
      "#{(volume / 1_000_000.0).round(1)}M"
    elsif volume >= 1_000
      "#{(volume / 1_000.0).round(1)}K"
    else
      volume.to_s
    end
  end

  def setup_time_aware_rules
    ts_sys = self  # Capture self for use in perform blocks
    @kb = KBS.knowledge_base do
      rule "fresh_momentum" do
        priority 15
        on :stock,
          price_change: satisfies { |p| p && p > 2 },
          timestamp: satisfies { |t| t && (Time.now - t) < 60 },
          market_session: "regular"

        perform do |facts|
          stock = facts.find { |f| f.type == :stock }
          age = Time.now - stock[:timestamp]
          puts "🚀 FRESH MOMENTUM: #{stock[:symbol]}"
          puts "   Price Change: +#{stock[:price_change]}%"
          puts "   Data Age: #{age.round(1)} seconds"
          puts "   Market Time: #{stock[:market_time]}"
          puts "   Recommendation: BUY (fresh signal)"
        end
      end

      rule "stale_data_warning" do
        priority 20
        on :stock, timestamp: satisfies { |t| t && (Time.now - t) > 300 }

        perform do |facts|
          stock = facts.find { |f| f.type == :stock }
          age = Time.now - stock[:timestamp]
          puts "⚠️  STALE DATA: #{stock[:symbol]}"
          puts "   Data Age: #{(age / 60).round(1)} minutes"
          puts "   Last Update: #{stock[:timestamp]}"
          puts "   ACTION: IGNORE - Data too old"
        end
      end

      rule "market_hours_check" do
        on :stock,
          market_session: "after_hours",
          volume: satisfies { |v| v && v > 100_000 }

        perform do |facts|
          stock = facts.find { |f| f.type == :stock }
          puts "🌙 AFTER HOURS ACTIVITY: #{stock[:symbol]}"
          puts "   Volume: #{ts_sys.format_volume(stock[:volume])}"
          puts "   Time: #{stock[:market_time]}"
          puts "   ACTION: Monitor for gap potential"
        end
      end

      rule "rapid_movement" do
        on :price_tick,
          time_delta: satisfies { |d| d && d < 5 },
          price_delta: satisfies { |d| d && d.abs > 0.50 }

        perform do |facts|
          tick = facts.find { |f| f.type == :price_tick }
          direction = tick[:price_delta] > 0 ? "📈 UP" : "📉 DOWN"
          puts "⚡ RAPID MOVEMENT: #{tick[:symbol]} #{direction}"
          puts "   Price Change: #{tick[:price_delta] > 0 ? '+' : ''}$#{tick[:price_delta]}"
          puts "   Time Frame: #{tick[:time_delta]} seconds"
          puts "   ACTION: Check for news catalyst"
        end
      end

      rule "opening_gap" do
        on :stock,
          market_time: satisfies { |t|
            t && (t.hour == 9 && t.min >= 30 && t.min <= 35)
          },
          gap_percentage: satisfies { |g| g && g.abs > 1 }

        perform do |facts|
          stock = facts.find { |f| f.type == :stock }
          direction = stock[:gap_percentage] > 0 ? "GAP UP" : "GAP DOWN"
          puts "🔔 OPENING #{direction}: #{stock[:symbol]}"
          puts "   Gap: #{stock[:gap_percentage] > 0 ? '+' : ''}#{stock[:gap_percentage]}%"
          puts "   Time: #{stock[:market_time]}"
          puts "   Volume: #{ts_sys.format_volume(stock[:volume])}"
          puts "   ACTION: Monitor for gap fill or continuation"
        end
      end

      rule "end_of_day" do
        on :stock, market_time: satisfies { |t|
          t && (t.hour == 15 && t.min >= 45)
        }
        on :position, status: "open"

        perform do |facts|
          stock = facts.find { |f| f.type == :stock }
          position = facts.find { |f| f.type == :position }
          puts "🕐 END OF DAY: #{position[:symbol]}"
          puts "   Current Time: #{stock[:market_time]}"
          puts "   Position P&L: #{position[:unrealized_pnl]}"
          puts "   ACTION: Consider closing before market close"
        end
      end
    end
  end

  def determine_market_session(time)
    hour_min = time.hour * 100 + time.min

    case hour_min
    when 400..929 then "pre_market"
    when 930..1559 then "regular"
    when 1600..2000 then "after_hours"
    else "closed"
    end
  end

  def add_timestamped_stock_fact(symbol, price, volume, options = {})
    timestamp = options[:timestamp] || Time.now
    market_time = options[:market_time] || timestamp

    @kb.fact :stock, {
      symbol: symbol,
      price: price,
      volume: volume,
      timestamp: timestamp,
      market_time: market_time,
      market_session: determine_market_session(market_time),
      price_change: options[:price_change] || 0,
      gap_percentage: options[:gap_percentage] || 0
    }
  end

  def add_price_tick(symbol, old_price, new_price, old_time, new_time)
    price_delta = new_price - old_price
    time_delta = new_time - old_time

    @kb.fact :price_tick, {
      symbol: symbol,
      old_price: old_price,
      new_price: new_price,
      price_delta: price_delta,
      time_delta: time_delta,
      timestamp: new_time
    }
  end

  def simulate_trading_day
    puts "🏦 TIMESTAMPED STOCK TRADING SYSTEM"
    puts "=" * 60

    base_time = Time.parse("2024-08-15 09:30:00")

    # Scenario 1: Market Open with Gap
    puts "\n📊 SCENARIO 1: Market Open Gap Up"
    puts "-" * 40
    @kb.reset

    add_timestamped_stock_fact("AAPL", 185.50, 2_500_000, {
      market_time: base_time + 2*60, # 9:32 AM
      price_change: 2.1,
      gap_percentage: 2.3
    })
    @kb.run

    # Scenario 2: Fresh Momentum Signal
    puts "\n📊 SCENARIO 2: Fresh Momentum (Recent Data)"
    puts "-" * 40
    @kb.reset

    add_timestamped_stock_fact("GOOGL", 142.80, 1_200_000, {
      timestamp: Time.now - 30, # 30 seconds ago
      market_time: Time.now - 30,
      price_change: 3.2
    })
    @kb.run

    # Scenario 3: Stale Data
    puts "\n📊 SCENARIO 3: Stale Data Warning"
    puts "-" * 40
    @kb.reset

    add_timestamped_stock_fact("TSLA", 195.40, 800_000, {
      timestamp: Time.now - 600, # 10 minutes ago
      market_time: Time.now - 600,
      price_change: 1.5
    })
    @kb.run

    # Scenario 4: After Hours Activity
    puts "\n📊 SCENARIO 4: After Hours Trading"
    puts "-" * 40
    @kb.reset

    after_hours_time = Time.parse("2024-08-15 17:30:00")
    add_timestamped_stock_fact("NVDA", 425.80, 150_000, {
      market_time: after_hours_time,
      timestamp: after_hours_time
    })
    @kb.run

    # Scenario 5: Rapid Price Movement
    puts "\n📊 SCENARIO 5: Rapid Price Tick"
    puts "-" * 40
    @kb.reset

    tick_time = Time.now
    add_price_tick("META", 298.50, 299.25, tick_time - 3, tick_time)
    @kb.run

    # Scenario 6: End of Day
    puts "\n📊 SCENARIO 6: End of Trading Day"
    puts "-" * 40
    @kb.reset

    eod_time = Time.parse("2024-08-15 15:50:00")
    add_timestamped_stock_fact("AMZN", 142.30, 900_000, {
      market_time: eod_time,
      timestamp: eod_time
    })

    @kb.fact :position, {
      symbol: "AMZN",
      status: "open",
      shares: 100,
      entry_price: 140.00,
      unrealized_pnl: 230.00
    }
    @kb.run

    puts "\n" + "=" * 60
    puts "TIMESTAMPED TRADING SIMULATION COMPLETE"
  end
end

if __FILE__ == $0
  system = TimestampedTradingSystem.new
  system.simulate_trading_day
end
