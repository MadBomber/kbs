#!/usr/bin/env ruby

require_relative '../lib/kbs'

class StockTradingExpertSystem
  include KBS::DSL::ConditionHelpers

  def initialize
    @kb = nil
    setup_rules
  end

  def setup_rules
    @kb = KBS.knowledge_base do
      rule "bull_market_buy" do
        priority 10
        on :market, trend: "bullish"
        on :stock, rsi: satisfies { |rsi| rsi < 70 }
        on :stock, pe_ratio: satisfies { |pe| pe < 25 }

        perform do |facts|
          stock = facts.find { |f| f.type == :stock }
          puts "📈 BUY SIGNAL: #{stock[:symbol]} - Bull market with good fundamentals"
          puts "   RSI: #{stock[:rsi]}, P/E: #{stock[:pe_ratio]}"
        end
      end

      rule "oversold_bounce" do
        priority 8
        on :stock, rsi: satisfies { |rsi| rsi < 30 }
        on :stock, volume: satisfies { |v| v > 1000000 }
        without.on :news, sentiment: "negative"

        perform do |facts|
          stock = facts.find { |f| f.type == :stock }
          puts "🔄 OVERSOLD BOUNCE: #{stock[:symbol]} - Potential reversal opportunity"
          puts "   RSI: #{stock[:rsi]}, Volume: #{stock[:volume]}"
        end
      end

      rule "stop_loss_trigger" do
        priority 15
        on :position, loss_percent: satisfies { |loss| loss > 8 }
        on :market, trend: "bearish"

        perform do |facts|
          position = facts.find { |f| f.type == :position }
          puts "🛑 STOP LOSS: #{position[:symbol]} - Exit position immediately"
          puts "   Loss: #{position[:loss_percent]}%"
        end
      end

      rule "earnings_surprise" do
        priority 12
        on :earnings, surprise: satisfies { |s| s > 10 }
        on :stock, momentum: satisfies { |m| m > 0 }

        perform do |facts|
          earnings = facts.find { |f| f.type == :earnings }
          stock = facts.find { |f| f.type == :stock }
          puts "💰 EARNINGS BEAT: #{stock[:symbol]} - Strong earnings surprise"
          puts "   Surprise: #{earnings[:surprise]}%, Momentum: #{stock[:momentum]}"
        end
      end

      rule "price_volume_divergence" do
        priority 5
        on :stock, price_trend: "up"
        on :stock, volume_trend: "down"

        perform do |facts|
          stock = facts.find { |f| f.type == :stock }
          puts "⚠️  DIVERGENCE WARNING: #{stock[:symbol]} - Price/volume divergence detected"
        end
      end
    end
  end

  def analyze_market(market_conditions)
    puts "\n" + "=" * 70
    puts "MARKET ANALYSIS - #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "=" * 70

    market_conditions.each do |condition|
      case condition[:type]
      when :market
        @kb.fact :market, condition[:data]
      when :stock
        @kb.fact :stock, condition[:data]
      when :position
        @kb.fact :position, condition[:data]
      when :earnings
        @kb.fact :earnings, condition[:data]
      when :news
        @kb.fact :news, condition[:data]
      end
    end

    @kb.run
    puts "=" * 70
  end

  def clear_facts
    @kb.reset
  end
end

class NetworkDiagnosticSystem
  include KBS::DSL::ConditionHelpers

  def initialize
    @kb = nil
    setup_network_rules
  end

  def setup_network_rules
    @kb = KBS.knowledge_base do
      rule "ddos_detection" do
        on :traffic, requests_per_second: satisfies { |rps| rps > 10000 }
        on :traffic, unique_ips: satisfies { |ips| ips < 100 }
        without.on :firewall, status: "active"

        perform do |facts|
          traffic = facts.find { |f| f.type == :traffic }
          puts "🚨 DDoS ATTACK DETECTED!"
          puts "   Requests/sec: #{traffic[:requests_per_second]}"
          puts "   Unique IPs: #{traffic[:unique_ips]}"
          puts "   ACTION: Enabling rate limiting and firewall rules"
        end
      end

      rule "bandwidth_saturation" do
        on :network, bandwidth_usage: satisfies { |usage| usage > 90 }
        on :service, priority: "high"

        perform do |facts|
          network = facts.find { |f| f.type == :network }
          service = facts.find { |f| f.type == :service }
          puts "⚠️  BANDWIDTH SATURATION: #{network[:bandwidth_usage]}% utilized"
          puts "   High priority service affected: #{service[:name]}"
          puts "   ACTION: Implementing QoS policies"
        end
      end

      rule "latency_anomaly" do
        on :latency, current_ms: satisfies { |ms| ms > 200 }
        on :latency, baseline_ms: satisfies { |ms| ms < 50 }

        perform do |facts|
          latency = facts.find { |f| f.type == :latency }
          puts "🔧 LATENCY SPIKE DETECTED"
          puts "   Current: #{latency[:current_ms]}ms (baseline: #{latency[:baseline_ms]}ms)"
          puts "   ACTION: Rerouting traffic to alternate path"
        end
      end
    end
  end

  def diagnose(conditions)
    puts "\n" + "=" * 70
    puts "NETWORK DIAGNOSTIC REPORT - #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "=" * 70

    conditions.each do |condition|
      @kb.fact condition[:type], condition[:data]
    end

    @kb.run
    puts "=" * 70
  end
end

if __FILE__ == $0
  puts "\n🏦 STOCK TRADING EXPERT SYSTEM DEMONSTRATION"
  puts "=" * 70

  trading_system = StockTradingExpertSystem.new

  scenario1 = [
    { type: :market, data: { trend: "bullish", volatility: "low" } },
    { type: :stock, data: { symbol: "AAPL", rsi: 45, pe_ratio: 22, momentum: 5 } },
    { type: :stock, data: { symbol: "GOOGL", rsi: 28, volume: 2000000, momentum: -2 } }
  ]

  trading_system.analyze_market(scenario1)
  trading_system.clear_facts

  scenario2 = [
    { type: :market, data: { trend: "bearish", volatility: "high" } },
    { type: :position, data: { symbol: "TSLA", loss_percent: 12, shares: 100 } },
    { type: :earnings, data: { symbol: "MSFT", surprise: 15, quarter: "Q4" } },
    { type: :stock, data: { symbol: "MSFT", momentum: 8, rsi: 62 } }
  ]

  trading_system.analyze_market(scenario2)
  trading_system.clear_facts

  scenario3 = [
    { type: :stock, data: { symbol: "META", price_trend: "up", volume_trend: "down" } },
    { type: :stock, data: { symbol: "NVDA", rsi: 25, volume: 5000000, momentum: 3 } }
  ]

  trading_system.analyze_market(scenario3)

  puts "\n\n🌐 NETWORK DIAGNOSTIC SYSTEM DEMONSTRATION"
  puts "=" * 70

  network_system = NetworkDiagnosticSystem.new

  network_scenario1 = [
    { type: :traffic, data: { requests_per_second: 15000, unique_ips: 50, protocol: "HTTP" } },
    { type: :network, data: { bandwidth_usage: 95, packet_loss: 2 } },
    { type: :service, data: { name: "API Gateway", priority: "high" } }
  ]

  network_system.diagnose(network_scenario1)

  network_scenario2 = [
    { type: :latency, data: { current_ms: 250, baseline_ms: 30, endpoint: "database" } },
    { type: :network, data: { bandwidth_usage: 60, packet_loss: 0 } }
  ]

  network_system.diagnose(network_scenario2)
end
