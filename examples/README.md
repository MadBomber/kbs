# KBS Examples

This directory contains comprehensive examples demonstrating the capabilities of the KBS (Knowledge-Based System) gem. Each example showcases different features and use cases of the RETE II inference engine and blackboard architecture.

## Table of Contents

- [Getting Started](#getting-started)
- [Basic Examples](#basic-examples)
  - [car_diagnostic.rb](#car_diagnosticrb)
  - [working_demo.rb](#working_demorb)
- [DSL Examples](#dsl-examples)
  - [iot_demo_using_dsl.rb](#iot_demo_using_dslrb)
  - [trading_demo.rb](#trading_demorb)
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

All examples can be run directly:

```bash
./examples/example_name.rb
# or
ruby examples/example_name.rb
```

Some examples require additional dependencies:
- **redis_trading_demo.rb**: Requires Redis server running (`redis-server`)
- **ai_enhanced_kbs.rb**: Requires Ollama with a model installed

---

## Basic Examples

### car_diagnostic.rb

**Description:** A simple expert system for diagnosing car problems. This is the most basic example, perfect for understanding the fundamentals of rule-based reasoning.

**Demonstrates:**
- Basic rule creation with `KBS::Rule.new`
- Condition matching with `KBS::Condition`
- Fact assertion and retraction
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
- Rule priority
- Working memory management

**What It Does:**
Generates trading signals based on:
- Golden cross patterns (moving average crossovers)
- High volume confirmation
- Price breakouts with momentum
- Risk management rules

**Key Concepts:**
- Forward-chaining inference
- Fact-based reasoning
- Trading signal generation

---

## DSL Examples

### iot_demo_using_dsl.rb

**Description:** IoT sensor monitoring system using the declarative KBS DSL. Shows how to write rules in a more natural, readable syntax.

**Demonstrates:**
- Declarative DSL with `KBS.knowledge_base`
- Helper functions: `greater_than`, `less_than`, `range`
- Rule descriptions and metadata
- Multi-fact pattern matching
- Negative patterns with `without`

**What It Does:**
Monitors IoT sensors and triggers alerts:
- Temperature warnings
- Humidity alerts
- Combined sensor analysis
- System health monitoring

**Key Concepts:**
- DSL-based rule definition
- Sensor data processing
- Alert generation
- Readable rule syntax

---

### trading_demo.rb

**Description:** Comprehensive trading system demonstrating the full DSL capabilities with multiple trading strategies.

**Demonstrates:**
- Full DSL syntax
- Multiple trading rules
- Priority-based rule execution
- Complex pattern matching
- Condition helpers (greater_than, one_of, range)

**What It Does:**
Implements various trading strategies:
- Momentum breakouts
- Mean reversion
- Volume analysis
- Multi-timeframe analysis

**Key Concepts:**
- Strategy combination
- Priority-based firing
- Complex condition logic

---

## Advanced Trading Examples

### advanced_example.rb

**Description:** Advanced trading patterns with golden cross detection and technical analysis.

**Demonstrates:**
- Complex multi-condition rules
- Moving average crossover detection
- Volume confirmation
- Historical data analysis
- State tracking across facts

**What It Does:**
- Detects golden cross patterns (50-MA > 200-MA)
- Validates with volume confirmation
- Generates buy signals with context
- Tracks previous state for crossover detection

**Key Concepts:**
- Technical indicator analysis
- Crossover pattern detection
- Multi-factor validation

---

### stock_trading_advanced.rb

**Description:** Production-grade trading system with position management, stop losses, and portfolio tracking.

**Demonstrates:**
- Position sizing
- Stop loss management
- Portfolio state tracking
- Risk management rules
- Trade execution simulation

**What It Does:**
- Manages open positions
- Implements trailing stops
- Calculates position sizes
- Tracks P&L
- Simulates realistic trading

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
- Knowledge source registration
- Audit logging

**What It Does:**
- Stores facts in SQLite database
- Tracks fact lifecycle (add/update/retract)
- Implements message queue
- Maintains audit trail
- Demonstrates multi-agent coordination

**Key Concepts:**
- Blackboard architecture
- Persistent storage
- Message-based coordination
- Audit trails

**Persistence Features:**
- Durable fact storage
- Query history
- Session management
- Transactional updates

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

**Requirements:** Redis server running on localhost:6379

---

## Concurrency Examples

### concurrent_inference_demo.rb

**Description:** Demonstrates concurrent rule execution and automatic inference with background threads.

**Demonstrates:**
- Auto-inference mode
- Background inference threads
- Thread-safe fact assertion
- Concurrent rule firing
- Blackboard-based coordination

**What It Does:**
- Runs inference in background
- Allows concurrent fact updates
- Demonstrates thread safety
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

**Description:** Cutting-edge integration of LLM AI (via Ollama) with rule-based reasoning, demonstrating hybrid AI systems.

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
- Ollama installed with a model (e.g., `gpt-oss:latest`)
- Model configured via `OLLAMA_MODEL` environment variable
- RubyLLM gem

**Configuration:**
```bash
export OLLAMA_MODEL=gpt-oss:latest
./examples/ai_enhanced_kbs.rb
```

---

## Summary of Capabilities

### Core KBS Features
- ✅ RETE II inference engine
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
# Simple examples
./examples/car_diagnostic.rb
./examples/working_demo.rb

# DSL examples
./examples/iot_demo_using_dsl.rb
./examples/trading_demo.rb

# Advanced trading
./examples/advanced_example.rb
./examples/stock_trading_advanced.rb

# Persistence (requires Redis)
redis-server &
./examples/redis_trading_demo.rb

# AI integration (requires Ollama)
export OLLAMA_MODEL=gpt-oss:latest
./examples/ai_enhanced_kbs.rb
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
