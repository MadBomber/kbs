## [Unreleased]

### Added
- `benchmarks/regex_baseline.rb` measures regex pattern matching in the RETE network; results are in `docs/advanced/performance.md` (#4).

### Changed
- `KBS::Fact#to_s` and `KBS::Rule#to_s` now render DSL source, such as `fact :sensor, temp: 22` and a `rule "name" do ... end` block (#3).
- `RedisStore#query_facts` and `HybridStore#query_facts` now raise `NotImplementedError` instead of returning every fact, since Redis cannot run SQL conditions (#16).
- The gem now ships only the Ruby files under `lib/`, plus `README.md`, `CHANGELOG.md` and `LICENSE.txt`. It used to include `docs/`, `examples/`, `benchmarks/`, `.github/` and other repo files such as `Rakefile` and `mkdocs.yml`, which are still in the repository (#31).

### Removed
- `examples/temp_dsl.txt`, a captured demo output file, is no longer shipped in the gem (#15).

### Fixed
- `KBS::Blackboard::Memory#clear_session` now clears the session's facts when a store is passed in, such as a `SqliteStore`, `RedisStore` or `HybridStore` made without a `session_id`. The memory now uses the store's session id, and `SqliteStore` and `HybridStore` make one when none is given (#51).
- `rake` and `rake test` now run the test suite. SimpleCov's exit hook used to fire first and abort before any test ran. One side effect: the existing 35% minimum-coverage gate now applies to rake runs, so a narrowly filtered run or `rake test:deps` can fail on coverage alone.
- `KBS.knowledge_base(engine: ...)` and `KBS::DSL::KnowledgeBase.new(engine: ...)` now accept an engine, such as a `KBS::Blackboard::Engine`. Passing one used to raise `ArgumentError`, which broke the README's SQLite and Redis blackboard examples and the docs examples that pass `engine:`. Without the keyword a new `KBS::Engine` is used, as before (#10).
- The Redis store tests no longer connect to `localhost:6379` and flush database 15 there. They are skipped unless `KBS_TEST_REDIS_URL` names a disposable Redis database, such as a throwaway server; see `test/README.md`.
- `require 'kbs/blackboard'` no longer fails when the `redis` gem is not installed, so the SQLite blackboard works without it. `RedisStore` and `HybridStore` still need redis, and raise `LoadError` when they open a connection without it.
- Variable bindings are now correct when a `without` (negated) condition comes before other conditions in a rule. The action used to receive values from the wrong facts, or miss variables, and the blackboard audit log recorded the same wrong bindings. `KBS::Rule#bindings_for(facts)` is now public and is used by both.
- `KBS::Rule#to_s`, and `KnowledgeBase#rule_source` for a rule with no source file, now print simple literals, such as integers and plain strings, that helpers like `greater_than` and `not_equal` capture, so `greater_than(80)` shows `v > 80`. It used to show `v > /* getlocal_WC_1 */`. `not_equal(5)` now prints `!=`; it used to print `==` (#33).
- `KBS::Rule#to_s` and `KnowledgeBase#rule_source` no longer raise `NoMethodError` when a condition value cannot be decompiled, such as `satisfies(&:even?)` in a rule with no source file. That value now prints as `<decompilation failed: ...>`, the same way an action that cannot be decompiled already did (#43).
- A rule that starts with a `without` condition now fires when no matching fact exists, including right after the rule is added and after `reset` (#11).
- Rule actions written as zero-argument lambdas, such as `perform -> { ... }`, no longer raise `ArgumentError` when the rule fires (#14).
- `rule "name", priority: N do ... end` and `defrule` now accept a `priority:` keyword, as the README and docs show. It used to raise `ArgumentError`. A `priority` call inside the block still wins (#29).
- `KBS::Blackboard::Engine#remove_fact` now retracts the fact from the Rete network. It used to stay in its alpha memory, so a rule negated on it never fired and a rule matched on it still fired. `KBS::Blackboard::Fact` now compares, and hashes, by `uuid` (#42).
- `KBS::Rule#to_s` and `KnowledgeBase#rule_source` now print the condition of a ternary whose branch is `0`, `1`, `nil` or an expression, so `v ? 1 : 2` shows `v ? 1 : 2`. It used to show only `2`, and could show the wrong branch values. A ternary that cannot be decompiled now prints `/* branchunless */` instead of dropping its condition (#52).
- `KBS::Rule#to_s` and `KnowledgeBase#rule_source` now print string literals in decompiled conditions on Ruby 4.1, so `->(v) { v == "hi" }` no longer shows `v == /* dupchilledstring */` (#50).
- A rule with two or more conditions now fires once per match when its facts arrive in a different order from its conditions. It used to fire once per extra join, and `KBS::Blackboard::Engine` wrote duplicate audit rows (#41).
- Condition helpers such as `greater_than`, `less_than`, `satisfies`, `one_of`, `not_equal`, `range` and `equals` now work inside the block form of `on`. They used to be recorded as pattern keys of their own (or raise for multi-argument helpers), so the rule never fired. An attribute named after a helper in the block form now means the helper (#40).
- `KBS::Rule#to_s` and `KnowledgeBase#rule_source` now render `&&` and `||` in decompiled conditions, so `between(1, 9)` prints as `->(v) { v >= 1 && v <= 9 }` instead of `v >= 1; v <= 9`. An `||` used as a side of `&&` is parenthesized (#36).
- Rule `priority` now sets firing order in `KBS::Engine` and `KBS::Blackboard::Engine`: higher-priority rules fire first, and rules of equal priority keep definition order. Rules used to fire in definition order regardless of priority, which changes the order for anyone who already sets priorities (#35).
- Adding a rule after facts exist no longer makes earlier rules fire again for facts they already matched. A late rule now picks up existing facts without replaying them into every alpha memory (#34).
- Condition helpers `greater_than`, `less_than`, `between`, `range` and `matches` now just fail to match a value of the wrong type, such as a String compared with `greater_than(5)`. `add_fact` used to raise and leave the fact in working memory, where other rules still fired on it (#67).
- The README "Using the DSL" breakout rule and `examples/advanced_example_dsl.rb` now put each stock's checks in one `on :stock` condition. Two separate conditions matched different stocks, so the README reported stocks that did not qualify, twice, and the example printed a buy signal for a stock with no P/E (#66).
- A condition helper such as `one_of`, or a `?variable`, on a user attribute named `type` now matches, and blocks in a `without` condition. It used to make a positive condition never match and a negated one never block; a literal value already worked (#65).
- `KBS::Engine#facts`, `KBS::Blackboard::Engine#close` and `KnowledgeBase#close` now exist, as the getting-started, persistence and blackboard guides use them. Those examples used to raise `NoMethodError`. `facts` returns the working memory facts on both engines; `KnowledgeBase#close` closes an engine that can be closed and does nothing otherwise (#64).

## [0.2.1] - 2026-02-26

### Added
- **Rule Source Introspection**: New `rule_source` and `print_rule_source` methods on `KnowledgeBase` to retrieve and display the DSL source code for any rule by name
- **Rule Decompiler**: `KBS::Decompiler` can reconstruct source for dynamically-created rules from Proc and Lambda objects
- **Working Memory Reset**: `KnowledgeBase#reset` now clears working memory while preserving the compiled rule network, enabling reuse with different initial facts
- **Rule Source Introspection Demo**: New `examples/rule_source_demo.rb` showcasing both file-based and dynamic rule source retrieval

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
