# KBS Examples

This directory contains comprehensive examples demonstrating the capabilities of the KBS (Knowledge-Based System) gem. Each example showcases different features and use cases of the RETE inference engine and blackboard architecture.

## Table of Contents

- [Getting Started](#getting-started)
- [Basic Examples](#basic-examples)
  - [car_diagnostic.rb](#car_diagnosticrb)
  - [working_demo.rb](#working_demorb)
  - [trading_demo.rb](#trading_demorb)
- [DSL Examples](#dsl-examples)
  - [iot_demo_using_dsl.rb](#iot_demo_using_dslrb)
- [Advanced Trading Examples](#advanced-trading-examples)
  - [advanced_example.rb](#advanced_examplerb)
  - [stock_trading_advanced.rb](#stock_trading_advancedrb)
  - [timestamped_trading.rb](#timestamped_tradingrb)
  - [csv_trading_system.rb](#csv_trading_systemrb)
  - [portfolio_rebalancing_system.rb](#portfolio_rebalancing_systemrb)
- [Blackboard & Persistence Examples](#blackboard--persistence-examples)
  - [blackboard_demo.rb](#blackboard_demorb)
  - [redis_trading_demo.rb](#redis_trading_demorb)
- [Concurrency Examples](#concurrency-examples)
  - [concurrent_inference_demo.rb](#concurrent_inference_demorb)
- [AI Integration Examples](#ai-integration-examples)
  - [ai_enhanced_kbs.rb](#ai_enhanced_kbsrb)

## Getting Started

Run the examples from inside `examples/`, since `csv_trading_system.rb` and `portfolio_rebalancing_system.rb` read `sample_stock_data.csv` from the current directory and `blackboard_demo.rb` writes `knowledge_base.db` there:

```bash
cd examples
bundle exec ruby example_name.rb
```

Every example except `iot_demo_using_dsl.rb` also has a DSL version, `example_name_dsl.rb`. `rule_source_demo.rb` shows rule source introspection, and `run_all.rb` / `run_all_dsl.rb` run each set in turn.

Some examples require additional dependencies:
- **redis_trading_demo.rb**: Requires Redis server running (`redis-server`); it flushes Redis databases 1 and 2
- **ai_enhanced_kbs.rb**: Requires a local LLM server: LM Studio (`lms server start`) or Apple's on-device model (`apfel --serve`)

---

## Basic Examples

### car_diagnostic.rb

**Description:** A simple expert system for diagnosing car problems. This is the most basic example, perfect for understanding the fundamentals of rule-based reasoning.

**Demonstrates:**
- Basic rule creation with `KBS::Rule.new`
- Condition matching with `KBS::Condition`
- Fact assertion
- Negated conditions (absence of facts)
- Simple forward-chaining inference

**What It Does:**
Diagnoses car problems based on symptoms:
- Dead battery (won't start + no lights)
- Flat tire (pulling to side + low pressure)
- Engine overheating (high temp + steam, but no coolant leak)

**Key Concepts:**
- Rule-based expert systems
- Pattern matching
- Negative conditions (checking for absence of facts)

---

### working_demo.rb

**Description:** A stock trading signal generator demonstrating multi-condition rules and pattern matching.

**Demonstrates:**
- Multiple conditions per rule
- Hash-based pattern matching
- Lambda predicates for dynamic conditions
- Several rules firing on the same fact

**What It Does:**
Generates trading signals based on:
- Golden cross patterns (moving average crossovers)
- Momentum with high volume
- Significant price moves
- RSI overbought and oversold levels

**Key Concepts:**
- Forward-chaining inference
- Fact-based reasoning
- Trading signal generation

---

### trading_demo.rb

**Description:** A trading system with eight rules written with `KBS::Rule` and `KBS::Condition`.

**Demonstrates:**
- Multiple trading rules
- Multi-condition rules across fact types
- Lambda predicates for dynamic conditions

**What It Does:**
Implements various trading strategies:
- Golden cross and momentum buys
- Oversold buys
- Earnings volatility plays
- Stop losses and concentration risk warnings
- News catalysts and sector rotation

**Key Concepts:**
- Strategy combination
- Complex condition logic

---

## DSL Examples

### iot_demo_using_dsl.rb

**Description:** A small expert system written with the declarative KBS DSL. Shows how to write rules in a more natural, readable syntax.

**Demonstrates:**
- Declarative DSL with `KBS.knowledge_base`
- Helper functions: `greater_than`, `less_than`, `satisfies`
- Block-form `on` conditions
- Rule descriptions and priorities
- Multi-fact pattern matching
- Negative patterns with `without` and `absent`
- `print_rules` and `print_facts`

**What It Does:**
Fires three rules:
- High temperature alert for a reactor sensor reading
- Low inventory warning for essential items
- VIP upgrade for long-standing, high-spending customers

**Key Concepts:**
- DSL-based rule definition
- Sensor data processing
- Alert generation
- Readable rule syntax

---

## Advanced Trading Examples

### advanced_example.rb

**Description:** Two expert systems in one file: a stock trading system and a network diagnostic system.

**Demonstrates:**
- Complex multi-condition rules
- Rule priority
- Negated conditions
- Lambda predicates

**What It Does:**
- Trading: bull market buys, oversold bounces, stop losses, earnings surprises and price/volume divergence
- Network: DDoS detection, bandwidth saturation and latency anomalies

**Key Concepts:**
- Technical indicator analysis
- Multi-factor validation
- One engine per domain

---

### stock_trading_advanced.rb

**Description:** Production-grade trading system with position management, stop losses, and portfolio tracking.

**Demonstrates:**
- Position sizing (Kelly criterion)
- Trailing stops
- Portfolio state tracking
- Risk management rules
- Trade execution simulation

**What It Does:**
- Manages open positions
- Implements trailing stops
- Calculates position sizes
- Takes profits on winning positions
- Simulates market ticks for several symbols

**Key Concepts:**
- Position management
- Risk control
- Portfolio tracking
- Trade lifecycle

---

### timestamped_trading.rb

**Description:** Time-aware trading system demonstrating temporal reasoning and time-based rules.

**Demonstrates:**
- Timestamp-based facts
- Time window analysis
- Temporal pattern matching
- Event sequencing
- Time-based filtering

**What It Does:**
- Analyzes price movements over time
- Detects trends within time windows
- Implements time-decay logic
- Manages time-sensitive signals

**Key Concepts:**
- Temporal reasoning
- Time-series analysis
- Event ordering

---

### csv_trading_system.rb

**Description:** Real-world example loading market data from CSV files and generating trading signals.

**Demonstrates:**
- External data integration
- CSV file processing
- Data transformation
- Batch fact assertion
- Historical backtesting

**What It Does:**
- Loads stock data from CSV
- Calculates technical indicators
- Generates trading signals
- Produces analysis reports

**Key Concepts:**
- Data pipeline integration
- Batch processing
- Real-world data handling

---

### portfolio_rebalancing_system.rb

**Description:** Sophisticated portfolio management system with rebalancing logic and allocation rules.

**Demonstrates:**
- Portfolio-level reasoning
- Asset allocation
- Rebalancing triggers
- Risk distribution
- Multi-asset coordination

**What It Does:**
- Monitors portfolio allocation
- Detects imbalances
- Suggests rebalancing trades
- Maintains target allocations
- Manages risk exposure

**Key Concepts:**
- Portfolio optimization
- Asset allocation
- Rebalancing strategies

---

## Blackboard & Persistence Examples

### blackboard_demo.rb

**Description:** Demonstrates the blackboard architecture with SQLite persistence for durable fact storage.

**Demonstrates:**
- Blackboard pattern
- SQLite persistence
- Fact history tracking
- Message passing
- Audit logging
- Database statistics

**What It Does:**
- Stores facts, with UUIDs, in a SQLite database (`knowledge_base.db`)
- Tracks fact lifecycle (add/update)
- Posts messages with priorities and consumes the highest-priority one
- Maintains audit trail
- Queries facts by type

**Key Concepts:**
- Blackboard architecture
- Persistent storage
- Message-based coordination
- Audit trails

**Persistence Features:**
- Durable fact storage
- Fact history

---

### redis_trading_demo.rb

**Description:** High-frequency trading system using Redis for fast in-memory fact storage and hybrid persistence.

**Demonstrates:**
- Redis persistence (fast)
- Hybrid storage (Redis + SQLite)
- Message queue in Redis
- High-frequency data handling
- Performance optimization
- Dual-store pattern

**What It Does:**
- Stores facts in Redis for speed
- Uses SQLite for audit trail
- Implements real-time messaging
- Handles high-frequency updates
- Demonstrates production patterns

**Key Concepts:**
- In-memory storage
- Hybrid persistence
- Real-time processing
- Performance optimization

**Storage Patterns:**
- Pure Redis: Fast, volatile
- Hybrid: Fast reads + durable audit
- Message queue for inter-component communication

**Requirements:** Redis server running on localhost:6379. The demo flushes databases 1 and 2 there.

---

## Concurrency Examples

### concurrent_inference_demo.rb

**Description:** Four ways to run inference automatically, each a subclass of `KBS::Engine` defined in the example. The engine itself has no auto-inference mode or locking; these subclasses add them.

**Demonstrates:**
- Reactive auto-inference (run after each fact is added)
- A background inference thread
- Event-driven callbacks when rules fire
- Queue-based batch processing
- Guarding the engine with a `Mutex`

**What It Does:**
- Runs inference in background
- Allows concurrent fact updates
- Shows async processing patterns

**Key Concepts:**
- Concurrent execution
- Thread safety
- Auto-inference
- Background processing

**Use Cases:**
- Real-time monitoring systems
- Event-driven architectures
- Continuous processing

---

## AI Integration Examples

### ai_enhanced_kbs.rb

**Description:** Cutting-edge integration of a local LLM (via LM Studio or Apfel) with rule-based reasoning, demonstrating hybrid AI systems.

**Demonstrates:**
- LLM integration with RubyLLM
- AI-powered sentiment analysis
- Dynamic strategy generation
- Natural language explanations
- Hybrid symbolic/neural reasoning
- Real-time AI inference

**What It Does:**
- Analyzes news sentiment with AI
- Generates trading strategies using LLMs
- Creates natural language explanations
- Performs AI-driven risk assessment
- Combines rules with machine learning

**Key Concepts:**
- Hybrid AI (symbolic + neural)
- LLM integration
- AI-enhanced decision making
- Natural language generation

**AI Capabilities:**
- News sentiment analysis
- Strategy generation
- Risk assessment
- Trade explanation
- Pattern recognition

**Requirements:**
- A local LLM server, chosen with `KBS_LLM_PROVIDER`:
  - `lms` (default): [LM Studio](https://lmstudio.ai) with its server running (`lms server start`); default model `openai/gpt-oss-20b`
  - `apfel`: Apple's on-device Foundation Model through [Apfel](https://apfel.franzai.com/) (`brew install apfel`, then `apfel --serve`); default model `apple-foundationmodel`; needs an Apple Silicon Mac with macOS 26 and Apple Intelligence
- `KBS_LLM_MODEL` overrides the model; `LMS_API_BASE` (default `http://localhost:1234/v1`) and `APFEL_API_BASE` (default `http://127.0.0.1:11434/v1`) override the server address
- The `ruby_llm`, `ruby_llm-providers-lms` and `ruby_llm-providers-apfel` gems, which are in the project Gemfile

**Configuration:**
```bash
cd examples
bundle exec ruby ai_enhanced_kbs.rb                          # LM Studio
KBS_LLM_PROVIDER=apfel bundle exec ruby ai_enhanced_kbs.rb   # Apple on-device model
```

---

## Summary of Capabilities

### Core KBS Features
- ✅ RETE inference engine
- ✅ Forward-chaining reasoning
- ✅ Pattern matching
- ✅ Negated conditions
- ✅ Rule priorities
- ✅ Working memory management

### DSL Features
- ✅ Declarative rule syntax
- ✅ Condition helpers (greater_than, less_than, range, one_of)
- ✅ Readable rule definitions
- ✅ Negative patterns (without)

### Blackboard Architecture
- ✅ Multi-agent coordination
- ✅ Message passing
- ✅ Knowledge source registration
- ✅ Shared workspace pattern

### Persistence
- ✅ SQLite storage (durable, transactional)
- ✅ Redis storage (fast, in-memory)
- ✅ Hybrid storage (best of both)
- ✅ Fact history and audit trails
- ✅ Session management

### Advanced Features
- ✅ Concurrent execution
- ✅ Auto-inference mode
- ✅ Temporal reasoning
- ✅ External data integration
- ✅ AI/LLM integration
- ✅ Real-time processing

### Use Case Coverage
- 🏭 Industrial IoT monitoring
- 📈 Financial trading systems
- 🚗 Expert systems (diagnostics)
- 💼 Portfolio management
- 🤖 AI-enhanced reasoning
- 📊 Real-time analytics

---

## Running the Examples

### Basic Usage
```bash
cd examples

# Simple examples
bundle exec ruby car_diagnostic.rb
bundle exec ruby working_demo.rb
bundle exec ruby trading_demo.rb

# DSL examples
bundle exec ruby iot_demo_using_dsl.rb
bundle exec ruby trading_demo_dsl.rb

# Advanced trading
bundle exec ruby advanced_example.rb
bundle exec ruby stock_trading_advanced.rb

# Persistence (requires Redis; flushes databases 1 and 2)
redis-server &
bundle exec ruby redis_trading_demo.rb

# AI integration (requires LM Studio's server, or `apfel --serve` with KBS_LLM_PROVIDER=apfel)
bundle exec ruby ai_enhanced_kbs.rb
```

### Viewing Output
All examples produce detailed console output showing:
- Rules being fired
- Facts being asserted
- Pattern matches
- Inference results
- Performance statistics

---

## Learning Path

**Recommended order for learning:**

1. **Start Here:** `car_diagnostic.rb` - Basic concepts
2. **DSL Syntax:** `iot_demo_using_dsl.rb` - Readable rules
3. **Pattern Matching:** `working_demo.rb` - Multi-condition rules
4. **Advanced Logic:** `advanced_example.rb` - Complex patterns
5. **Persistence:** `blackboard_demo.rb` - Durable storage
6. **Performance:** `redis_trading_demo.rb` - Fast storage
7. **Concurrency:** `concurrent_inference_demo.rb` - Async processing
8. **AI Integration:** `ai_enhanced_kbs.rb` - Hybrid AI systems

---

## Contributing Examples

When adding new examples:
- Include clear comments
- Demonstrate specific capabilities
- Provide realistic use cases
- Show expected output
- Update this README

---

## License

All examples are part of the KBS gem and share the same license.
