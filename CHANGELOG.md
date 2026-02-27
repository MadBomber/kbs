## [Unreleased]

## [0.2.1] - 2026-02-26

### Added
- **Rule Source Introspection**: New `rule_source` and `print_rule_source` methods on `KnowledgeBase` to retrieve and display the DSL source code for any rule by name
- **Rule Decompiler**: `KBS::Decompiler` can reconstruct source for dynamically-created rules from Proc and Lambda objects
- **Working Memory Reset**: `KnowledgeBase#reset` now clears working memory while preserving the compiled rule network, enabling reuse with different initial facts
- **Rule Source Introspection Demo**: New `examples/rule_source_introspection_demo.rb` showcasing both file-based and dynamic rule source retrieval

### Changed
- **README rewritten to use DSL API**: Removed references to `KBS::ReteEngine` and `KBS::Rule`; all examples now use the DSL-based `KnowledgeBase` API
- **Dependencies bumped**: minitest updated to ~> 5.26

### Removed
- Deleted obsolete `expert-systems` example
- Deleted `DOCUMENTATION_STATUS.md`

### Fixed
- Updated `perform` method signatures in API documentation

## [0.1.0] - 2025-10-09

### Added
- **DSL Example Suite**: Created DSL versions of all raw API examples (12 new files)
  - advanced_example_dsl.rb - Complex trading strategies with DSL syntax
  - ai_enhanced_kbs_dsl.rb - AI-powered sentiment analysis and risk assessment
  - blackboard_demo_dsl.rb - Multi-agent blackboard pattern
  - car_diagnostic_dsl.rb - Simple diagnostic expert system
  - concurrent_inference_demo_dsl.rb - Thread-safe concurrent inference
  - csv_trading_system_dsl.rb - CSV-based trading data processing
  - portfolio_rebalancing_system_dsl.rb - Portfolio optimization and rebalancing
  - redis_trading_demo_dsl.rb - Redis-backed trading system
  - stock_trading_advanced_dsl.rb - Advanced trading with technical indicators
  - timestamped_trading_dsl.rb - Time-aware trading rules
  - trading_demo_dsl.rb - Basic trading scenarios
  - working_demo_dsl.rb - Introductory DSL examples

### Fixed
- **Symbol Syntax**: Corrected Ruby symbol syntax from `:'?name'` to `:name?` throughout codebase
- **Method Scope in Perform Blocks**: Fixed instance method access within DSL perform blocks
  - Implemented self-capture pattern (`obj = self`) before knowledge_base blocks
  - Applied to trading_demo_dsl.rb (demo), timestamped_trading_dsl.rb (ts_sys), ai_enhanced_kbs_dsl.rb (ai_sys), portfolio_rebalancing_system_dsl.rb (port_sys)
- **Kernel#system Conflict**: Renamed captured variable from `system` to avoid shadowing Ruby's built-in method
- **Instance Variable Access**: Added `attr_reader :kb` to ai_enhanced_kbs_dsl.rb for fact insertion from perform blocks
- **Array Processing**: Fixed `portfolio_rebalancing_system.rb:447` - changed `sum` to `map` to prevent calling `compact` on Float
- **File Operations**: Fixed `run_all.rb:13` - changed `basename` method call for String paths instead of Pathname objects

### Changed
- **DSL Syntax Improvements**: Standardized DSL rule definitions
  - Priority declarations moved inside rule blocks: `rule "name" do priority 15`
  - Hash parameters passed to `on` statements instead of inside blocks
  - Consistent use of `kb.reset` instead of `kb.clear`

## [0.0.1] - 2025-10-07

### Added
- **RETE Inference Engine**: Optimized forward-chaining inference with unlinking optimization
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
