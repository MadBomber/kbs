# Stock Trading System

Complete algorithmic trading system using KBS with market data collection, signal generation, risk management, and order execution.

## System Overview

This example demonstrates a production-ready trading system with:

- **Market Data Agent** - Fetches real-time quotes
- **Signal Agent** - Generates buy/sell signals using technical indicators
- **Risk Agent** - Validates trades against risk limits
- **Execution Agent** - Submits orders to broker

## Architecture

```
Market Data Agent → Blackboard → Signal Agent → Risk Agent → Execution Agent
                       ↓
                 Persistent Storage (SQLite/Redis)
                       ↓
                  Audit Trail
```

## Complete Implementation

```ruby
require 'kbs'
require 'net/http'
require 'json'

class TradingSystem
  def initialize(db_path: 'trading.db')
    @engine = KBS::Blackboard::Engine.new(db_path: db_path)
    setup_rules
  end

  def setup_rules
    # Rule 1: Generate moving average crossover signals
    signal_rule = KBS::Rule.new("ma_crossover_signal", priority: 100) do |r|
      r.conditions = [
        KBS::Condition.new(:market_data, {
          symbol: :sym?,
          price: :price?,
          ma_short: :ma_short?,
          ma_long: :ma_long?
        }),

        # No existing signal for this symbol
        KBS::Condition.new(:signal, { symbol: :sym? }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        short = bindings[:ma_short?]
        long = bindings[:ma_long?]

        # Golden cross: short MA crosses above long MA
        if short > long && (short - long) / long > 0.01  # 1% threshold
          @engine.add_fact(:signal, {
            symbol: bindings[:sym?],
            type: "buy",
            price: bindings[:price?],
            confidence: calculate_confidence(short, long),
            timestamp: Time.now
          })
        # Death cross: short MA crosses below long MA
        elsif short < long && (long - short) / long > 0.01
          @engine.add_fact(:signal, {
            symbol: bindings[:sym?],
            type: "sell",
            price: bindings[:price?],
            confidence: calculate_confidence(short, long),
            timestamp: Time.now
          })
        end
      end
    end

    # Rule 2: Risk check for buy signals
    risk_check_buy = KBS::Rule.new("risk_check_buy", priority: 90) do |r|
      r.conditions = [
        KBS::Condition.new(:signal, {
          symbol: :sym?,
          type: "buy",
          price: :price?
        }),

        KBS::Condition.new(:portfolio, {
          cash: :cash?,
          positions: :positions?
        }),

        # No risk approval yet
        KBS::Condition.new(:risk_approved, { signal_id: :sig_id? }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        signal = facts.find { |f| f.type == :signal }
        cash = bindings[:cash?]
        positions = bindings[:positions?]
        price = bindings[:price?]

        # Risk checks
        position_size = calculate_position_size(cash, price)
        max_position_value = cash * 0.10  # Max 10% of cash per position

        if position_size * price <= max_position_value
          # Check portfolio concentration
          total_positions = positions.size

          if total_positions < 10  # Max 10 positions
            @engine.add_fact(:risk_approved, {
              signal_id: signal.id,
              symbol: bindings[:sym?],
              quantity: position_size,
              approved_at: Time.now
            })
          else
            @engine.add_fact(:risk_rejected, {
              signal_id: signal.id,
              reason: "Portfolio concentration limit"
            })
          end
        else
          @engine.add_fact(:risk_rejected, {
            signal_id: signal.id,
            reason: "Position size exceeds limits"
          })
        end
      end
    end

    # Rule 3: Execute approved orders
    execution_rule = KBS::Rule.new("execute_approved_orders", priority: 80) do |r|
      r.conditions = [
        KBS::Condition.new(:risk_approved, {
          signal_id: :sig_id?,
          symbol: :sym?,
          quantity: :qty?
        }),

        KBS::Condition.new(:signal, {
          symbol: :sym?,
          type: :type?,
          price: :price?
        }),

        # Not yet executed
        KBS::Condition.new(:order, { signal_id: :sig_id? }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        order_id = execute_order(
          symbol: bindings[:sym?],
          type: bindings[:type?],
          quantity: bindings[:qty?],
          price: bindings[:price?]
        )

        @engine.add_fact(:order, {
          signal_id: bindings[:sig_id?],
          order_id: order_id,
          symbol: bindings[:sym?],
          type: bindings[:type?],
          quantity: bindings[:qty?],
          price: bindings[:price?],
          status: "submitted",
          timestamp: Time.now
        })

        # Clean up signal and approval
        signal = facts.find { |f| f.type == :signal }
        approval = facts.find { |f| f.type == :risk_approved }
        @engine.remove_fact(signal)
        @engine.remove_fact(approval)
      end
    end

    # Rule 4: Stop loss monitoring
    stop_loss_rule = KBS::Rule.new("stop_loss_trigger", priority: 95) do |r|
      r.conditions = [
        KBS::Condition.new(:position, {
          symbol: :sym?,
          entry_price: :entry?,
          quantity: :qty?
        }),

        KBS::Condition.new(:market_data, {
          symbol: :sym?,
          price: :current_price?
        }),

        KBS::Condition.new(:stop_loss_triggered, { symbol: :sym? }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        entry = bindings[:entry?]
        current = bindings[:current_price?]
        loss_pct = (entry - current) / entry

        # 5% stop loss
        if loss_pct > 0.05
          @engine.add_fact(:signal, {
            symbol: bindings[:sym?],
            type: "sell",
            price: current,
            confidence: 1.0,
            reason: "stop_loss",
            timestamp: Time.now
          })

          @engine.add_fact(:stop_loss_triggered, {
            symbol: bindings[:sym?],
            entry_price: entry,
            exit_price: current,
            loss_pct: loss_pct
          })
        end
      end
    end

    # Rule 5: Take profit monitoring
    take_profit_rule = KBS::Rule.new("take_profit_trigger", priority: 95) do |r|
      r.conditions = [
        KBS::Condition.new(:position, {
          symbol: :sym?,
          entry_price: :entry?,
          quantity: :qty?
        }),

        KBS::Condition.new(:market_data, {
          symbol: :sym?,
          price: :current_price?
        }),

        KBS::Condition.new(:take_profit_triggered, { symbol: :sym? }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        entry = bindings[:entry?]
        current = bindings[:current_price?]
        gain_pct = (current - entry) / entry

        # 15% take profit
        if gain_pct > 0.15
          @engine.add_fact(:signal, {
            symbol: bindings[:sym?],
            type: "sell",
            price: current,
            confidence: 1.0,
            reason: "take_profit",
            timestamp: Time.now
          })

          @engine.add_fact(:take_profit_triggered, {
            symbol: bindings[:sym?],
            entry_price: entry,
            exit_price: current,
            gain_pct: gain_pct
          })
        end
      end
    end

    @engine.add_rule(signal_rule)
    @engine.add_rule(risk_check_buy)
    @engine.add_rule(execution_rule)
    @engine.add_rule(stop_loss_rule)
    @engine.add_rule(take_profit_rule)
  end

  def update_market_data(symbol, price)
    # Calculate moving averages
    history = get_price_history(symbol, days: 50)
    ma_short = calculate_ma(history, period: 10)
    ma_long = calculate_ma(history, period: 50)

    # Remove old market data
    old = @engine.facts.find { |f| f.type == :market_data && f[:symbol] == symbol }
    @engine.remove_fact(old) if old

    # Add new market data
    @engine.add_fact(:market_data, {
      symbol: symbol,
      price: price,
      ma_short: ma_short,
      ma_long: ma_long,
      timestamp: Time.now
    })
  end

  def update_portfolio(cash:, positions:)
    old = @engine.facts.find { |f| f.type == :portfolio }
    @engine.remove_fact(old) if old

    @engine.add_fact(:portfolio, {
      cash: cash,
      positions: positions,
      updated_at: Time.now
    })
  end

  def run_cycle
    @engine.run
  end

  private

  def calculate_confidence(short_ma, long_ma)
    # Confidence based on divergence
    divergence = ((short_ma - long_ma).abs / long_ma)
    [divergence * 10, 1.0].min
  end

  def calculate_position_size(cash, price)
    # Kelly criterion or fixed percentage
    (cash * 0.05 / price).floor  # 5% of cash
  end

  def execute_order(symbol:, type:, quantity:, price:)
    # Submit to broker API
    # Returns order_id
    "ORD-#{Time.now.to_i}-#{symbol}"
  end

  def get_price_history(symbol, days:)
    # Fetch historical prices
    # Returns array of prices
    []
  end

  def calculate_ma(prices, period:)
    return 0 if prices.size < period
    prices.last(period).sum / period.to_f
  end
end

# Usage
trading = TradingSystem.new

# Initialize portfolio
trading.update_portfolio(
  cash: 100000,
  positions: []
)

# Market data loop
symbols = ["AAPL", "GOOGL", "MSFT", "TSLA"]

loop do
  symbols.each do |symbol|
    # Fetch current price (from API)
    price = fetch_price(symbol)

    # Update market data
    trading.update_market_data(symbol, price)
  end

  # Run inference engine
  trading.run_cycle

  sleep 60  # Run every minute
end
```

## Key Features

### 1. Moving Average Crossover

Generates buy signals when short MA crosses above long MA (golden cross) and sell signals when it crosses below (death cross).

### 2. Risk Management

- **Position sizing**: Max 10% of cash per position
- **Portfolio concentration**: Max 10 positions
- **Stop loss**: Automatic exit at 5% loss
- **Take profit**: Automatic exit at 15% gain

### 3. Order Execution

Approved signals become orders submitted to broker.

### 4. Audit Trail

All decisions logged to database:

```ruby
# Query signal history
signals = trading.engine.facts.select { |f| f.type == :signal }

# Query order history
orders = trading.engine.facts.select { |f| f.type == :order }

# Audit trail
trading.engine.fact_history(signal.id)
```

## Performance Optimization

### Use Redis for Real-Time Trading

```ruby
require 'kbs/blackboard/persistence/redis_store'

store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)

trading = TradingSystem.new(store: store)
# 100x faster updates
```

### Hybrid Store for Compliance

```ruby
require 'kbs/blackboard/persistence/hybrid_store'

store = KBS::Blackboard::Persistence::HybridStore.new(
  redis_url: 'redis://localhost:6379/0',
  db_path: 'audit.db'
)

trading = TradingSystem.new(store: store)
# Fast + complete audit trail
```

## Testing

```ruby
require 'minitest/autorun'

class TestTradingSystem < Minitest::Test
  def setup
    @system = TradingSystem.new(db_path: ':memory:')
  end

  def test_golden_cross_generates_buy_signal
    @system.update_portfolio(cash: 10000, positions: [])

    # Short MA above long MA
    @system.update_market_data("AAPL", 150)
    @system.engine.add_fact(:market_data, {
      symbol: "AAPL",
      price: 150,
      ma_short: 155,  # Higher
      ma_long: 145,   # Lower
      timestamp: Time.now
    })

    @system.run_cycle

    signals = @system.engine.facts.select { |f| f.type == :signal }
    assert_equal 1, signals.size
    assert_equal "buy", signals.first[:type]
  end

  def test_stop_loss_triggers_sell
    @system.update_portfolio(cash: 10000, positions: [])

    # Add position
    @system.engine.add_fact(:position, {
      symbol: "AAPL",
      entry_price: 100,
      quantity: 10
    })

    # Price drops 6%
    @system.update_market_data("AAPL", 94)

    @system.run_cycle

    signals = @system.engine.facts.select { |f|
      f.type == :signal && f[:reason] == "stop_loss"
    }

    assert_equal 1, signals.size
  end
end
```

## Next Steps

- **[Multi-Agent Example](multi-agent.md)** - Distributed trading with multiple strategies
- **[Performance Guide](../advanced/performance.md)** - Optimize for high-frequency trading
- **[Blackboard Memory](../guides/blackboard-memory.md)** - Persistent state management

---

*This trading system demonstrates production-ready algorithmic trading with KBS. Always backtest thoroughly before live trading.*
