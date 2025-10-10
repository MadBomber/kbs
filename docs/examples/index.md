# Examples

Real-world applications demonstrating KBS capabilities. Each example is available in both low-level API and DSL versions.

## Getting Started

### Working Demo
**Files:** [`working_demo.rb`](https://github.com/madbomber/kbs/blob/main/examples/working_demo.rb) | [`working_demo_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/working_demo_dsl.rb)

Simple trading system demonstrating the basics of KBS with momentum signals, volume alerts, and price movement detection. Perfect starting point for learning KBS fundamentals.

**Features:**

- Basic rule definition and pattern matching
- Stock momentum detection
- High volume alerts
- Price change notifications

### Advanced Example
**Files:** [`advanced_example.rb`](https://github.com/madbomber/kbs/blob/main/examples/advanced_example.rb) | [`advanced_example_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/advanced_example_dsl.rb)

More complex patterns including multi-condition rules, variable bindings, and negation patterns. Shows advanced RETE features and rule chaining.

**Features:**

- Multi-condition pattern matching
- Variable binding and join tests
- Negation (NOT conditions)
- Rule priorities

## Stock Trading Systems

### Basic Trading Demo
**Files:** [`trading_demo.rb`](https://github.com/madbomber/kbs/blob/main/examples/trading_demo.rb) | [`trading_demo_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/trading_demo_dsl.rb)

Foundational trading signals including momentum detection and volume analysis.

**Features:**

- Buy/sell signal generation
- Volume-based alerts
- Price momentum tracking

### Advanced Stock Trading
**Files:** [`stock_trading_advanced.rb`](https://github.com/madbomber/kbs/blob/main/examples/stock_trading_advanced.rb) | [`stock_trading_advanced_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/stock_trading_advanced_dsl.rb)

Sophisticated trading system with technical indicators, portfolio management, and risk controls.

**Features:**

- Golden cross detection (MA crossover)
- Momentum breakout signals
- RSI indicators
- Volume ratio analysis
- Risk management rules

### CSV Trading System
**Files:** [`csv_trading_system.rb`](https://github.com/madbomber/kbs/blob/main/examples/csv_trading_system.rb) | [`csv_trading_system_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/csv_trading_system_dsl.rb)

Complete trading system that processes historical stock data from CSV files, calculates technical indicators, and generates trading signals.

**Features:**

- CSV data ingestion
- Moving average calculations
- Technical indicator generation
- Backtesting support
- Portfolio tracking

### Portfolio Rebalancing System
**Files:** [`portfolio_rebalancing_system.rb`](https://github.com/madbomber/kbs/blob/main/examples/portfolio_rebalancing_system.rb) | [`portfolio_rebalancing_system_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/portfolio_rebalancing_system_dsl.rb)

Sector-based portfolio management with automatic rebalancing, drift detection, and underperformer replacement.

**Features:**

- Target allocation management
- Sector drift detection
- Automatic rebalancing rules
- Underperformer identification
- Position replacement logic

### Timestamped Trading
**Files:** [`timestamped_trading.rb`](https://github.com/madbomber/kbs/blob/main/examples/timestamped_trading.rb) | [`timestamped_trading_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/timestamped_trading_dsl.rb)

Time-aware trading system demonstrating temporal reasoning and time-based rule activation.

**Features:**

- Time-based rule conditions
- Stale data detection
- Market hours awareness
- Temporal pattern matching

### Redis High-Frequency Trading
**Files:** [`redis_trading_demo.rb`](https://github.com/madbomber/kbs/blob/main/examples/redis_trading_demo.rb) | [`redis_trading_demo_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/redis_trading_demo_dsl.rb)

High-performance trading system using Redis for fast in-memory fact storage, ideal for low-latency trading applications.

**Features:**

- Redis-backed persistence
- High-frequency market data processing
- Fast fact lookup and updates
- Distributed knowledge base support

## Expert Systems

### Car Diagnostic System
**Files:** [`car_diagnostic.rb`](https://github.com/madbomber/kbs/blob/main/examples/car_diagnostic.rb) | [`car_diagnostic_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/car_diagnostic_dsl.rb)

Expert system for diagnosing car problems based on symptoms. Demonstrates classic expert system pattern with IF-THEN diagnostic rules.

**Features:**

- Symptom-based diagnosis
- Multiple diagnostic rules
- Recommendation generation
- Negation for ruling out conditions

### IoT Monitoring System
**File:** [`iot_demo_using_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/iot_demo_using_dsl.rb)

IoT sensor monitoring system with temperature alerts, inventory management, and customer VIP upgrades. Shows real-world DSL usage patterns.

**Features:**

- Sensor monitoring
- Temperature threshold alerts
- Inventory tracking
- Multi-domain rules (IoT, inventory, CRM)

## AI-Enhanced Systems

### AI-Enhanced Knowledge Base
**Files:** [`ai_enhanced_kbs.rb`](https://github.com/madbomber/kbs/blob/main/examples/ai_enhanced_kbs.rb) | [`ai_enhanced_kbs_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/ai_enhanced_kbs_dsl.rb)

Integration with Large Language Models (LLMs) for AI-powered sentiment analysis, market insights, and intelligent trading decisions.

**Features:**

- LLM integration via `ruby_llm` gem
- News sentiment analysis
- AI-powered market insights
- MCP agent support
- Hybrid AI + rule-based reasoning

**Requirements:**

- Ollama running locally (or compatible LLM provider)
- `ruby_llm` and `ruby_llm-mcp` gems

## Advanced Features

### Blackboard Memory System
**Files:** [`blackboard_demo.rb`](https://github.com/madbomber/kbs/blob/main/examples/blackboard_demo.rb) | [`blackboard_demo_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/blackboard_demo_dsl.rb)

Demonstrates persistent blackboard architecture with SQLite storage, message queues, audit logs, and fact history tracking.

**Features:**
+
- SQLite-backed persistence
- UUID-based fact tracking
- Message queue (priority-based)
- Complete audit trail
- Fact update history
- Database statistics

### Concurrent Inference Patterns
**Files:** [`concurrent_inference_demo.rb`](https://github.com/madbomber/kbs/blob/main/examples/concurrent_inference_demo.rb) | [`concurrent_inference_demo_dsl.rb`](https://github.com/madbomber/kbs/blob/main/examples/concurrent_inference_demo_dsl.rb)

Advanced patterns for multi-threaded knowledge bases including reactive engines, background inference, and event-driven architectures.

**Features:**

- Auto-inference mode (reactive)
- Background thread inference
- Event-driven processing
- Thread-safe fact addition
- Continuous reasoning loops

## Running Examples

### Run Individual Examples

Each example is executable from the command line:

```bash
# Run a specific example
ruby examples/working_demo.rb

# Run DSL version
ruby examples/working_demo_dsl.rb

# Run AI-enhanced example (requires Ollama)
OLLAMA_MODEL=gpt-oss:latest ruby examples/ai_enhanced_kbs.rb
```

### Run All Examples

Run all examples at once:

```bash
# Run all low-level API examples
ruby examples/run_all.rb

# Run all DSL examples
ruby examples/run_all_dsl.rb
```

## Example Organization

- **Low-level API examples** (`*.rb`) - Direct use of `KBS::Engine`, `KBS::Rule`, `KBS::Condition`
- **DSL examples** (`*_dsl.rb`) - Using `KBS.knowledge_base` and declarative syntax
- Both versions demonstrate the same functionality with different APIs

## Further Reading

- **[Quick Start Guide](../quick-start.md)** - Step-by-step tutorial
- **[DSL Reference](../guides/dsl.md)** - Complete DSL syntax guide
- **[Writing Rules](../guides/writing-rules.md)** - Best practices for rule design
- **[Blackboard Memory](../guides/blackboard-memory.md)** - Persistence guide
- **[API Reference](../api/index.md)** - Complete API documentation
