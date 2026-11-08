![KBS - Knowledge-Based System](docs/assets/images/kbs.jpg)

# KBS - Knowledge-Based System

A comprehensive Ruby implementation of a Knowledge-Based System featuring the RETE algorithm, Blackboard architecture, and AI integration for building intelligent rule-based applications.

[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2.0-red.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

See the [full documentation website](https://madbomber.github.io/kbs/).

## 🌟 Key Features

### RETE Inference Engine
- **Optimized Pattern Matching**: RETE algorithm with unlinking optimization for high-performance forward-chaining inference
- **Incremental Updates**: Efficient fact addition/removal without full network recomputation
- **Negation Support**: Built-in handling of NOT conditions and absence patterns
- **Memory Optimization**: Nodes automatically unlink when empty to reduce computation
- **Pattern Sharing**: Common sub-patterns shared between rules for maximum efficiency

### Declarative DSL
- **Readable Syntax**: Write rules in natural, expressive Ruby syntax
- **Condition Helpers**: `greater_than`, `less_than`, `range`, `one_of`, `satisfies` and more (see [DSL Helpers](#dsl-helpers))
- **Rule Metadata**: Descriptions, priorities, and documentation built-in
- **Negative Patterns**: `without` keyword for absence testing

### Blackboard Architecture
- **Multi-Agent Coordination**: Knowledge sources collaborate via shared blackboard
- **Message Passing**: Inter-component communication with priority-based message queue
- **Knowledge Source Registration**: Modular agent registration with topic subscriptions
- **Session Management**: Isolated reasoning sessions with cleanup

### Flexible Persistence
- **SQLite Storage**: ACID-compliant persistent fact storage with full transaction support
- **Redis Storage**: High-speed in-memory fact storage for real-time systems (100x faster)
- **Hybrid Storage**: Best of both worlds - Redis for facts, SQLite for audit trail
- **Audit Trails**: Complete history of all fact changes and reasoning steps
- **Query Interface**: Powerful fact retrieval with pattern matching and SQL queries

### Concurrent Execution
- **Auto-Inference Mode**: Background thread continuously runs inference as facts change
- **Thread-Safe**: Concurrent fact assertion and rule firing
- **Real-Time Processing**: Perfect for monitoring systems and event-driven architectures

### AI Integration
- **LLM Integration**: Native support for Ollama, OpenAI via RubyLLM gem
- **Hybrid Reasoning**: Combine symbolic rules with neural AI for enhanced decision-making
- **Sentiment Analysis**: AI-powered news and text analysis
- **Strategy Generation**: LLMs create trading strategies based on market conditions
- **Natural Language**: Generate human-readable explanations for decisions
- **Pattern Recognition**: AI identifies complex patterns beyond traditional indicators

## 🚀 Quick Start

### Installation

Add to your Gemfile:

```ruby
gem 'kbs'
```

Or install directly:

```bash
gem install kbs
```

### Basic Usage

```ruby
require 'kbs'

# Create knowledge base with DSL
kb = KBS.knowledge_base do
  rule "high_temperature_alert" do
    on :sensor, type: "temperature"
    on :reading, value: greater_than(100)

    perform do |facts, bindings|
      reading = facts.find { |f| f.type == :reading }
      puts "🚨 HIGH TEMPERATURE: #{reading[:value]}°C"
    end
  end

  # Add facts
  fact :sensor, type: "temperature", location: "reactor"
  fact :reading, value: 105, unit: "celsius"

  # Run inference
  run
end
# => 🚨 HIGH TEMPERATURE: 105°C
```

### Using the DSL

```ruby
require 'kbs'

kb = KBS.knowledge_base do
  rule "momentum_breakout" do
    desc "Detect stock momentum breakouts"
    priority 10

    on :stock, volume: greater_than(1_000_000)
    on :stock, price_change_pct: greater_than(3)
    without :position, status: "open"

    perform do |facts, bindings|
      stock = facts.find { |f| f.type == :stock }
      puts "🚀 BREAKOUT: #{stock[:symbol]} +#{stock[:price_change_pct]}%"
    end
  end
end

kb.fact :stock, symbol: "AAPL", volume: 1_500_000, price_change_pct: 4.2
kb.run
# => 🚀 BREAKOUT: AAPL +4.2%
```

### Blackboard with SQLite Persistence

```ruby
require 'kbs/blackboard'

# Create persistent blackboard with DSL
engine = KBS::Blackboard::Engine.new(db_path: 'knowledge.db')

kb = KBS.knowledge_base(engine: engine) do
  rule "temperature_monitor" do
    on :sensor, type: "temperature", value: greater_than(25)

    perform do |facts|
      sensor = facts.first
      puts "⚠️  High temperature at #{sensor[:location]}: #{sensor[:value]}°C"
    end
  end

  # Add persistent facts
  fact :sensor, type: "temperature", location: "room1", value: 22
  fact :sensor, type: "temperature", location: "room2", value: 28

  run
end

# Query facts
sensors = engine.blackboard.get_facts(:sensor)
sensors.each { |s| puts "#{s[:type]} at #{s[:location]}: #{s[:value]}°C" }

# View audit history
history = engine.blackboard.get_history(limit: 10)
history.each do |entry|
  puts "[#{entry[:timestamp]}] #{entry[:action]}: #{entry[:fact_type]}"
end
```

### Redis for High-Speed Storage

```ruby
require 'kbs/blackboard'

# High-frequency trading with Redis and DSL
store = KBS::Blackboard::Persistence::RedisStore.new(url: 'redis://localhost:6379/0')
engine = KBS::Blackboard::Engine.new(store: store)

kb = KBS.knowledge_base(engine: engine) do
  rule "price_alert" do
    on :market_price, volume: greater_than(500_000)

    perform do |facts|
      price = facts.first
      puts "📊 High volume: #{price[:symbol]} - #{price[:volume]} shares"
      # Post message for other components
      engine.post_message("PriceAlert", "high_volume",
        { symbol: price[:symbol], volume: price[:volume] },
        priority: 10
      )
    end
  end

  # Fast in-memory fact storage
  fact :market_price, symbol: "AAPL", price: 150.25, volume: 1_000_000

  run
end

# Consume messages
message = engine.consume_message("high_volume", "TradingStrategy")
puts "Received: #{message[:content]}" if message
```

### AI-Enhanced Reasoning

```ruby
require 'kbs'
require 'ruby_llm'

# Requires Ollama with a model installed
# export OLLAMA_MODEL=gpt-oss:latest

kb = KBS.knowledge_base do
  rule "ai_sentiment_analysis" do
    on :news_data, symbol: satisfies { |s| s && s.length > 0 }

    perform do |facts|
      news = facts.first
      # AI-powered sentiment analysis
      client = RubyLLM::Chat.new(provider: :ollama, model: 'gpt-oss:latest')
      response = client.ask("Analyze sentiment: #{news[:headline]}")

      puts "🤖 AI SENTIMENT ANALYSIS: #{news[:symbol]}"
      puts "   Headline: #{news[:headline]}"
      puts "   AI Analysis: #{response.content}"
    end
  end

  # Add news for AI sentiment analysis
  fact :news_data,
    symbol: "AAPL",
    headline: "Apple Reports Record Q4 Earnings, Beats Expectations by 15%",
    content: "Apple Inc. announced exceptional results..."

  run
end

# Output:
# 🤖 AI SENTIMENT ANALYSIS: AAPL
#    Headline: Apple Reports Record Q4 Earnings, Beats Expectations by 15%
#    AI Analysis: positive (92%) - strong earnings growth, bullish outlook
```

## 📚 Examples

The `examples/` directory contains 13 comprehensive examples demonstrating all features:

### Basic Examples
- **car_diagnostic.rb** - Simple expert system for car diagnostics
- **working_demo.rb** - Stock trading signal generator

### DSL Examples
- **iot_demo_using_dsl.rb** - IoT sensor monitoring with declarative DSL
- **trading_demo.rb** - Multiple trading strategies

### Advanced Trading
- **advanced_example.rb** - Golden cross detection and technical analysis
- **stock_trading_advanced.rb** - Position management with stop losses
- **timestamped_trading.rb** - Time-aware temporal reasoning
- **csv_trading_system.rb** - CSV data integration and backtesting
- **portfolio_rebalancing_system.rb** - Portfolio optimization

### Persistence & Architecture
- **blackboard_demo.rb** - SQLite persistence and message queue
- **redis_trading_demo.rb** - Redis and hybrid storage patterns

### Advanced Features
- **concurrent_inference_demo.rb** - Auto-inference and background threads
- **ai_enhanced_kbs.rb** - LLM integration with Ollama

See [examples/README.md](examples/README.md) for detailed documentation of each example.

## 🏗️ Architecture

### RETE Network Structure

```
Facts → Alpha Network → Beta Network → Production Nodes
         (Pattern        (Join Nodes)    (Rule Actions)
          Matching)
```

**Key Optimizations:**
- **Left/Right Unlinking**: Join nodes unlink when memories are empty
- **Selective Activation**: Only affected network nodes are updated
- **Token Firing State**: Prevents duplicate rule executions
- **Shared Patterns**: Common sub-patterns shared across rules

### Blackboard Pattern

```
┌─────────────────────────────────────────┐
│           Blackboard (Memory)           │
│  ┌────────────────────────────────────┐ │
│  │  Facts, Messages, Audit Trail      │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
         ↑                    ↑
         │                    │
    ┌────────┐          ┌─────────┐
    │   KS   │          │   KS    │  Knowledge Sources
    │   #1   │          │   #2    │  (Agents)
    └────────┘          └─────────┘
```

## 🎯 Use Cases

### Expert Systems
- Medical diagnosis
- Fault detection and troubleshooting
- Configuration and design assistance
- Technical support automation

### Financial Applications
- Algorithmic trading systems
- Portfolio management and rebalancing
- Risk assessment and monitoring
- Market analysis and signal generation

### Real-Time Monitoring
- IoT sensor analysis and alerts
- Network monitoring and anomaly detection
- Industrial process control
- Fraud detection systems

### Business Automation
- Workflow automation
- Compliance checking
- Policy enforcement
- Dynamic pricing and promotions

## ⚡ Performance

### Benchmarks
- **Rule Compilation**: ~1ms per rule for typical patterns
- **Fact Addition**: ~0.1ms per fact (warm network)
- **Pattern Matching**: ~10μs per pattern evaluation
- **SQLite vs Redis**: Redis ~100x faster for high-frequency operations

### Complexity
- **Time**: O(RFP) where R=rules, F=facts, P=patterns per rule
- **Space**: O(RF) with unlinking optimization
- **Updates**: O(log R) for incremental fact changes

## 🧪 Testing

Run the comprehensive test suite:

```bash
rake test
```

Run a single test file (`test/test_*.rb`):

```bash
bundle exec ruby test/test_rule.rb
```

SimpleCov measures coverage on every run and fails the run below the minimum set in `test/test_helper.rb` (currently 35% line coverage).

The Redis store tests are skipped unless `KBS_TEST_REDIS_URL` names a disposable Redis database. See [test/README.md](test/README.md) before setting it, because those tests flush the database.

## 📖 Documentation

### Core Classes

- **KBS::Engine** - Main inference engine
- **KBS::Rule** - Rule definition
- **KBS::Condition** - Pattern matching conditions
- **KBS::Fact** - Working memory facts
- **KBS::Blackboard::Engine** - Blackboard coordination
- **KBS::Blackboard::Persistence::SqliteStore** - SQLite backend
- **KBS::Blackboard::Persistence::RedisStore** - Redis backend
- **KBS::Blackboard::Persistence::HybridStore** - Hybrid storage

### DSL Helpers

Use these as attribute values in the hash form of `on`, for example `on :reading, value: greater_than(100)`. The block form of `on` has its own operators; see [Block-Style Patterns](docs/guides/dsl.md#block-style-patterns).

- `greater_than(n)` - Match values > n
- `less_than(n)` - Match values < n
- `equals(value)` - Match values equal to value
- `not_equal(value)` - Match values not equal to value
- `range(min, max)`, `between(min, max)` or `range(a_range)` - Match values from min to max inclusive, or values in the Range
- `one_of(*values)` - Match any of the values
- `any(*values)` - Same as `one_of`; with no arguments, match anything
- `satisfies { |v| ... }` - Match values for which the block returns true

For a regex in the hash form, use `satisfies { |v| regex.match?(v.to_s) }`. In that position `matches` is another name for `on`, not a helper.

See the [DSL guide](docs/guides/dsl.md#pattern-helpers) for examples.

## 🔧 Requirements

- Ruby >= 3.2.0
- SQLite3 (bundled with most systems)
- Redis (optional, for Redis storage)
- Ollama (optional, for AI integration)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Charles Forgy** for the original RETE algorithm
- **Robert Doorenbos** for RETE/UL and unlinking optimizations
- The AI and knowledge systems research community
- Ruby community for excellent tooling and libraries

## 📚 References

- Forgy, C. L. (1982). "Rete: A fast algorithm for the many pattern/many object pattern match problem"
- Doorenbos, R. B. (1995). "Production Matching for Large Learning Systems" (RETE/UL)
- Friedman-Hill, E. (2003). "Jess in Action: Java Rule-based Systems"
- Englemore, R. & Morgan, T. (1988). "Blackboard Systems"

---

**Built with ❤️ for the Ruby community**

For more information, visit the [GitHub repository](https://github.com/madbomber/kbs).
