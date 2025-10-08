## [Unreleased]

## [0.0.1] - 2025-10-07

### Added
- **RETE II Inference Engine**: Optimized forward-chaining inference with unlinking optimization
- **Declarative DSL**: Readable rule definition syntax with condition helpers (greater_than, less_than, range, one_of, matches)
- **Blackboard Architecture**: Multi-agent coordination with message passing and knowledge source registration
- **Flexible Persistence**:
  - SQLite storage for durable, transactional fact storage with audit trails
  - Redis storage for high-speed in-memory fact storage (100x faster)
  - Hybrid storage combining Redis performance with SQLite durability
- **Concurrent Execution**: Thread-safe auto-inference mode for real-time processing
- **AI Integration**: Native LLM support via RubyLLM gem (Ollama, OpenAI) for hybrid symbolic/neural reasoning
- **Session Management**: Isolated reasoning sessions with UUIDs and cleanup
- **Query API**: Powerful fact retrieval with pattern matching and SQL queries
- **Audit Trails**: Complete history of all fact changes and reasoning steps

### Examples (13 total)
- **Basic**: car_diagnostic.rb, working_demo.rb
- **DSL**: iot_demo_using_dsl.rb, trading_demo.rb
- **Advanced Trading**: advanced_example.rb, stock_trading_advanced.rb, timestamped_trading.rb, csv_trading_system.rb, portfolio_rebalancing_system.rb
- **Persistence**: blackboard_demo.rb, redis_trading_demo.rb
- **Concurrency**: concurrent_inference_demo.rb
- **AI Integration**: ai_enhanced_kbs.rb

### Documentation
- Comprehensive README.md with architecture diagrams and quick start examples
- Detailed examples/README.md with learning path and feature showcase
- 100% test coverage (199 runs, 447 assertions, 0 failures)

### Dependencies
- Ruby >= 3.2.0
- sqlite3 ~> 1.6 (runtime)
- minitest ~> 5.16 (development)
- simplecov ~> 0.22 (development)
- redis ~> 5.0 (development, optional for Redis storage)
- ruby_llm (optional for AI integration)
