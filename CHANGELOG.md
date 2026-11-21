## [Unreleased]

## [0.4.0] - Unreleased

Faster matching and rule firing. What matches and the order rules fire in are unchanged for every strategy.

### Breaking changes
- The facts an action receives (`Token#facts`) are frozen; copy them with `dup` before changing them.
- `Token#children` for a token with a single child returns a frozen one-element Set; change children through `add_child` / `remove_child` as before.
- `Activation#sort_key` is computed when called, from the new `Activation#strategy` the agenda sets; `Activation#sort_key=` is gone.
- `MemoryIndex.fact_key` and `MemoryIndex.token_key` return the value itself for a single field, and `MemoryIndex#lookup` may return an Array.

### Changed
- **Agenda grouped by salience, as in CLIPS.** Activations are filed by salience and, under `:definition`, by rule; within a group `:depth` takes the newest first and `:breadth` / `:definition` the oldest first. Adding and popping no longer compare sort keys, which took about 40% of CPU in an assert-and-`run` profile. Firing 3n activations from three rules runs about 3 to 3.7 times faster (see `docs/advanced/performance.md`).
- **Fewer allocations per fact and per match.** A join index keys a single field by its value instead of an Array, and a bucket holds a lone fact or token without a `Set`. Each alpha memory prepares its pattern's tests once and skips the `?variables`. `Fact#matches?` no longer builds a pair per pattern entry, joins hand on their candidates without copying them, and the alpha network builds a candidate list only when more than one applies. A token with one child keeps it without a `Set`, and the Sets that hold tokens compare by identity. Joins, negation and retraction run about 15% to 45% faster at n=2000 (25% to 70% with YJIT).

### Added
- `benchmarks/rete_scaling.rb` measures firing (`run`) under the `:definition` and `:depth` strategies.
- Fasterer is in the development bundle, so the `asgard quality` Fasterer gate runs instead of being skipped; `.fasterer.yml` records the one speedup turned off.
- README and the performance guide recommend running with YJIT (`ruby --yjit` or `RUBY_YJIT_ENABLE=1`), which is roughly 1.5 to 2.5 times faster on these benchmarks.

## [0.3.0] - 2026-11-20

The engine now works like CLIPS: an agenda with conflict resolution, truth maintenance, `exists`, `modify`, and joins on shared `?variables`. Matching and retraction use indexes instead of scans.

### Breaking changes
- Requires Ruby 4.0 or later (was 3.2).
- A `?variable` used in more than one condition now joins them: the facts must share the value. It used to match every combination. A `without` condition now blocks only on facts that agree with the variables bound before it.
- `run` fires until no matches remain, so a fact asserted by one action can fire any rule in the same `run`, in priority order. `run` returns the number of rules fired. Rules that keep re-matching need `run(limit)` or `halt`.
- `priority` now sets firing order on both engines; equal priorities keep definition order (#35).
- The DSL keyword `exists` now means "at least one such fact" and matches once; it used to be an alias for `on`.
- `WorkingMemory#facts`, `AlphaMemory#items`, `BetaMemory#tokens` and `ProductionNode#tokens` return copies; change the memories through their methods (`add_item`, `remove_token`, `clear`, …). `Token#children` is a frozen Set changed through `add_child` / `remove_child`.
- `RedisStore#query_facts` and `HybridStore#query_facts` raise `NotImplementedError` instead of returning every fact (#16).
- Shared nodes mean shared tokens, so whether a rule fired is now `ProductionNode#fired?(token)`; `Token#fired?` no longer prevents a second firing. `Activation#to_s` separates facts with `; ` and shows `*` for a `without` or `exists` condition.
- The gem ships only `lib/`, `README.md`, `CHANGELOG.md` and `LICENSE.txt` (#31). The Rakefile is gone; development tasks run through [asgard](https://github.com/MadBomber/asgard) (`.loki`).

### Added
- **Agenda** (`engine.agenda`) holding pending matches, with conflict resolution `strategy:` `:definition` (default), `:depth` or `:breadth`; `run(limit)` and `halt`.
- **Truth maintenance**: conditions in a `logical do … end` block support the facts the action asserts, which are retracted when the support goes away. `logically_supported?`, `dependencies`, `dependents`.
- **`modify(fact, changes)`** on both engines and `KnowledgeBase`: updates a fact and re-matches it, keeping its identity (and uuid / `UPDATE` audit entry on the blackboard).
- **`fact_duplication: false`**: `add_fact` returns the existing equal fact instead of adding another; `duplicate_of` finds it.
- **`exists` conditions** (`KBS::ExistsNode`).
- **`KBS::MatchInProgressError`** when a pattern predicate changes working memory during a match.
- Bare `fact`, `assert`, `retract`, `modify`, `query` and `halt` work inside a DSL `perform` block; condition keywords after the rule is built raise `KBS::RuleBuiltError`.
- Block-form conditions accept bare names and comparisons: `on(:t) { location loc; value > 80 }`.
- `KnowledgeBase#query` accepts condition helpers such as `greater_than(80)`.
- `Engine#facts`, `Engine#close`, `KnowledgeBase#close`, `KBS.knowledge_base(engine:)` (#10, #64).
- `Fact#to_s` and `Rule#to_s` print DSL source (#3).
- **Introspection, as in CLIPS**: `watch` / `unwatch` (`:facts`, `:activations`, `:rules`) with `trace_output=`; `matches(rule_name)` shows the facts and partial matches per condition; `join_activity`, `reset_join_activity`, `network_stats` and `beta_nodes` measure the network. Also on `KnowledgeBase`.
- Benchmarks: `benchmarks/rete_scaling.rb` and `benchmarks/regex_baseline.rb` (#4).

### Performance
With 2,000 facts or rules:
- Asserting finds alpha memories by type and constant: 1 s → 6 ms.
- Rules that start with the same conditions share those join, negation and exists nodes and their partial matches: 50 such rules over 2000 orders and payments, 517 ms → 37 ms.
- Shared-variable joins use hash indexes: 970 ms → 11 ms.
- Retracting follows recorded links instead of searching: 470 ms → 4 ms; removing negation blockers: 407 ms → 8 ms. Asserting costs about 20% more for the bookkeeping.

### Fixed
- **Matching**
  - Rules fire once per match whatever order facts arrive in (#41).
  - Adding a rule late no longer re-fires earlier rules (#34).
  - A rule that starts with `without` fires when nothing blocks it (#11).
  - Bindings are correct after a leading `without`.
  - Helpers and variables work on an attribute named `type` (#65).
  - Helpers fail to match, instead of raising, on values of the wrong type (#67).
- **DSL**
  - Condition helpers work in the block form of `on` (#40).
  - `priority:` keyword on `rule` / `defrule` (#29).
  - Zero-argument lambda actions (#14).
  - `print_rules` shows DSL conditions (#58).
- **Rule source and decompiler**: literals, `!=`, `&&` / `||`, ternaries and Ruby 4.1 strings print correctly; undecompilable values no longer raise (#33, #36, #43, #50, #52).
- **Blackboard**
  - `remove_fact` retracts from the network and returns the fact (#42).
  - A rolled-back transaction withdraws the facts it added.
  - `clear_session` works with a store passed in (#51).
  - `fact_duplication: false` covers facts already stored.
  - Symbol rule names and message topics work on SQLite.
  - `register_knowledge_source` without a description works on Redis/Hybrid stores.
  - `HybridStore#stats[:audit_records]` counts audit rows.
  - The `Store` base class defines `session_id` and `register_knowledge_source`.
  - `require 'kbs/blackboard'` works without the redis gem.
- **Messages and audit**
  - String message content round-trips (#63).
  - SQLite timestamps are read as UTC (#62).
  - Two consumers can no longer receive the same message (#60).
- **Docs and examples**: every doc and snippet was checked against the code and corrected; the README and example DSL rules were fixed (#59, #66).

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
