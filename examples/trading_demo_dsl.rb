#!/usr/bin/env ruby

require_relative '../lib/kbs/dsl'
include KBS::DSL::ConditionHelpers

class TradingDemo
  attr_reader :kb

  def initialize
    @kb = create_knowledge_base
    puts "🏦 STOCK TRADING EXPERT SYSTEM LOADED"
    puts "📊 #{@kb.rules.size} trading strategies active"
  end

  def create_knowledge_base
    demo = self  # Capture self for use in perform blocks
    KBS.knowledge_base do
      rule "golden_cross_buy" do
        on :ma_signal, type: "golden_cross"
        on :stock do
          volume greater_than(500000)
        end

        perform do |facts, bindings|
          stock = facts.find { |f| f.type == :stock }
          signal = facts.find { |f| f.type == :ma_signal }
          puts "📈 GOLDEN CROSS SIGNAL: #{stock[:symbol]}"
          puts "   50-MA crossed above 200-MA"
          puts "   Volume: #{demo.format_volume(stock[:volume])}"
          puts "   Price: $#{stock[:price]}"
          puts "   Recommendation: STRONG BUY"
        end
      end

      rule "momentum_breakout" do
        on :stock do
          price_change greater_than(2)
          rsi between(50, 75)
        end

        perform do |facts, bindings|
          stock = facts.find { |f| f.type == :stock }
          puts "🚀 MOMENTUM BREAKOUT: #{stock[:symbol]}"
          puts "   Price Change: +#{stock[:price_change].round(1)}%"
          puts "   RSI: #{stock[:rsi].round(1)} (strong but not overbought)"
          puts "   Recommendation: BUY"
        end
      end

      rule "oversold_reversal" do
        on :stock do
          rsi less_than(35)
        end
        on :market, trend: "bullish"

        perform do |facts, bindings|
          stock = facts.find { |f| f.type == :stock }
          puts "🔄 OVERSOLD REVERSAL: #{stock[:symbol]}"
          puts "   RSI: #{stock[:rsi].round(1)} (oversold)"
          puts "   Market: Bullish environment"
          puts "   Recommendation: CONTRARIAN BUY"
        end
      end

      rule "earnings_play" do
        on :earnings do
          days_until satisfies { |d| d <= 3 }
        end
        on :options do
          iv greater_than(40)
        end

        perform do |facts, bindings|
          earnings = facts.find { |f| f.type == :earnings }
          options = facts.find { |f| f.type == :options }
          puts "💰 EARNINGS PLAY: #{earnings[:symbol]}"
          puts "   Earnings in #{earnings[:days_until]} day(s)"
          puts "   Implied Volatility: #{options[:iv].round(1)}%"
          puts "   Recommendation: VOLATILITY STRATEGY"
        end
      end

      rule "stop_loss_alert" do
        on :position do
          status "open"
          loss_pct greater_than(8)
        end

        perform do |facts, bindings|
          position = facts.find { |f| f.type == :position }
          puts "🛑 STOP LOSS TRIGGERED: #{position[:symbol]}"
          puts "   Loss: #{position[:loss_pct].round(1)}%"
          puts "   Entry: $#{position[:entry_price]}"
          puts "   Current: $#{position[:current_price]}"
          puts "   Recommendation: SELL IMMEDIATELY"
        end
      end

      rule "concentration_risk" do
        on :portfolio do
          concentration greater_than(25)
        end

        perform do |facts, bindings|
          portfolio = facts.find { |f| f.type == :portfolio }
          puts "⚠️  CONCENTRATION RISK: #{portfolio[:top_holding]}"
          puts "   Position Size: #{portfolio[:concentration].round(1)}% of portfolio"
          puts "   Recommendation: DIVERSIFY HOLDINGS"
        end
      end

      rule "news_sentiment" do
        on :news do
          sentiment satisfies { |s| s.abs > 0.6 }
          impact "high"
        end

        perform do |facts, bindings|
          news = facts.find { |f| f.type == :news }
          sentiment = news[:sentiment] > 0 ? "POSITIVE" : "NEGATIVE"
          action = news[:sentiment] > 0 ? "BUY" : "SELL"
          puts "📰 NEWS CATALYST: #{news[:symbol]}"
          puts "   Sentiment: #{sentiment} (#{news[:sentiment].round(2)})"
          puts "   Impact: HIGH"
          puts "   Recommendation: #{action} ON NEWS"
        end
      end

      rule "sector_strength" do
        on :sector do
          performance greater_than(5)
          trend "accelerating"
        end

        perform do |facts, bindings|
          sector = facts.find { |f| f.type == :sector }
          puts "🔄 SECTOR ROTATION: #{sector[:name]}"
          puts "   Performance: +#{sector[:performance].round(1)}%"
          puts "   Trend: Accelerating"
          puts "   Recommendation: INCREASE ALLOCATION"
        end
      end
    end
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

  def generate_scenario(name, &block)
    puts "\n" + "="*60
    puts "SCENARIO: #{name}"
    puts "="*60

    @kb.reset

    yield

    puts "\nFacts in working memory:"
    @kb.facts.each do |fact|
      puts "  #{fact}"
    end
    puts ""

    @kb.run

    puts "-"*60
  end

  def demo_scenarios
    generate_scenario("Bull Market with Golden Cross") do
      @kb.fact :stock, {
        symbol: "AAPL",
        price: 185.50,
        volume: 1_250_000,
        price_change: 1.2,
        rsi: 65
      }

      @kb.fact :ma_signal, {
        symbol: "AAPL",
        type: "golden_cross"
      }

      @kb.fact :market, { trend: "bullish" }
    end

    generate_scenario("Momentum Breakout") do
      @kb.fact :stock, {
        symbol: "NVDA",
        price: 425.80,
        volume: 980_000,
        price_change: 4.7,
        rsi: 68
      }

      @kb.fact :market, { trend: "bullish" }
    end

    generate_scenario("Oversold Bounce Opportunity") do
      @kb.fact :stock, {
        symbol: "TSLA",
        price: 178.90,
        volume: 750_000,
        price_change: -2.1,
        rsi: 28
      }

      @kb.fact :market, { trend: "bullish" }
    end

    generate_scenario("Earnings Volatility Play") do
      @kb.fact :earnings, {
        symbol: "GOOGL",
        days_until: 2,
        expected_move: 8.5
      }

      @kb.fact :options, {
        symbol: "GOOGL",
        iv: 45.2,
        iv_rank: 75
      }
    end

    generate_scenario("Stop Loss Alert") do
      @kb.fact :position, {
        symbol: "META",
        status: "open",
        entry_price: 320.00,
        current_price: 285.40,
        loss_pct: 10.8,
        shares: 100
      }
    end

    generate_scenario("Portfolio Risk Warning") do
      @kb.fact :portfolio, {
        total_value: 250_000,
        top_holding: "AAPL",
        concentration: 32.5,
        cash_pct: 5
      }
    end

    generate_scenario("News-Driven Trade") do
      @kb.fact :news, {
        symbol: "MSFT",
        sentiment: -0.75,
        impact: "high",
        headlines: "Major cloud outage affects services"
      }

      @kb.fact :stock, {
        symbol: "MSFT",
        price: 395.20,
        price_change: -1.2,
        volume: 890_000
      }
    end

    generate_scenario("Sector Rotation Signal") do
      @kb.fact :sector, {
        name: "Technology",
        performance: 7.3,
        trend: "accelerating",
        leaders: ["AAPL", "MSFT", "GOOGL"]
      }
    end

    generate_scenario("Complex Multi-Signal Day") do
      @kb.fact :stock, {
        symbol: "AMZN",
        price: 142.50,
        volume: 1_800_000,
        price_change: 3.8,
        rsi: 72
      }

      @kb.fact :ma_signal, {
        symbol: "AMZN",
        type: "golden_cross"
      }

      @kb.fact :news, {
        symbol: "AMZN",
        sentiment: 0.8,
        impact: "high",
        headlines: "AWS wins major government contract"
      }

      @kb.fact :earnings, {
        symbol: "AMZN",
        days_until: 1,
        expected_move: 6.2
      }

      @kb.fact :options, {
        symbol: "AMZN",
        iv: 52.1,
        iv_rank: 85
      }

      @kb.fact :market, { trend: "bullish" }
    end
  end
end

if __FILE__ == $0
  demo = TradingDemo.new
  demo.demo_scenarios

  puts "\n" + "="*60
  puts "TRADING SYSTEM DEMONSTRATION COMPLETE"
  puts "="*60
end
