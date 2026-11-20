## [Unreleased]

### Added
- `benchmarks/regex_baseline.rb` measures regex pattern matching in the RETE network; results are in `docs/advanced/performance.md` (#4).

### Added
- Truth maintenance, as in CLIPS `logical`. Conditions in a `logical do ... end` block (or `KBS::Condition.new(..., logical: true)`) support the facts the rule's action asserts: when those conditions stop matching, the facts are retracted, and facts derived from them in turn. Works on `KBS::Engine` and `KBS::Blackboard::Engine`. `Engine#logically_supported?`, `#dependencies` and `#dependents` show the links. See `docs/guides/truth-maintenance.md`.
- `Engine#modify(fact, changes)` on both engines, and `KnowledgeBase#modify`: changes a fact's attributes and matches it again, as a retraction followed by an assertion. `KBS::Engine` keeps the same fact object; `KBS::Blackboard::Engine` keeps the uuid and logs an `UPDATE`, through the new `Blackboard::Memory#modify_fact` and `#find_fact`. Setting an attribute directly still does not re-match.
- `fact_duplication:` on `KBS::Engine.new` and `KBS::Blackboard::Engine.new`, and `engine.fact_duplication=`. With it off, `add_fact` returns the existing fact instead of adding one with the same type and attributes. It is on by default, as before. `Engine#duplicate_of(type, attributes)` finds the existing fact.
- `KBS::MatchInProgressError`: `add_fact`, `remove_fact` and `modify` raise it when a pattern predicate or a working-memory observer calls them while another fact is being matched. Such a call used to change the network halfway through a match. `Engine#matching?` reports the state. Error classes now live in `lib/kbs/errors.rb`.
- `KBS::Condition.new(type, pattern, exists: true)` and `KBS::ExistsNode`: a condition that matches once while at least one fact fits the pattern. `Condition#binds_fact?` tells whether a condition adds a fact to the match, and `Condition#keyword` gives its DSL keyword.
- `benchmarks/rete_scaling.rb` measures how joins, negation, retraction and fact assertion scale with the number of facts and rules; see `docs/advanced/performance.md`.
- `KBS::Agenda` holds every rule match that has not fired yet, as CLIPS does. `engine.agenda` exposes it: `size`, `empty?`, `peek` and `to_a` (pending activations in firing order).
- Conflict resolution strategies: `KBS::Engine.new(strategy:)`, `KBS::Blackboard::Engine.new(strategy:)` and `engine.strategy=` take `:definition` (the default, and the order used before), `:depth` (newest match first) or `:breadth` (oldest match first). Priority still comes first.
- `run(limit)` on both engines and on `KnowledgeBase` stops after `limit` firings, and `halt` stops a run from inside a rule action. `run` now returns the number of rules fired.

### Changed
- The DSL keyword `exists` now means "at least one such fact": the rule matches once however many facts fit, the action receives no fact for that condition, and a variable first used in it is not bound for later conditions. `exists` used to be an alias for `on`, which matched once per fact. Use `on` for the old behaviour.
- `without` conditions no longer search when a fact is added or retracted. `KBS::NegationNode` links each partial match to the facts that block it and each fact to the matches it blocks, as CLIPS does, and shares that code with `ExistsNode` through `KBS::QuantifierNode`. Retracting 2000 blocking facts takes 8 ms; it took 407 ms. `NegationNode#matched?`, `#facts_matching` and `#tokens_matched_by` expose the links.
- Asserting a fact no longer tests it against every alpha memory. `KBS::AlphaNetwork` groups the memories by fact type and hashes those that compare an attribute with a constant, so a fact reaches its memories with a lookup. 2000 asserts against 2000 rules that each test a different constant take 6 ms; they took 1 s. `Engine#alpha_memories` is unchanged.
- Retracting a fact no longer searches the network. The engine records the alpha memories each fact entered (`Engine#alpha_memories_for`), each `JoinNode` records the tokens it built from each fact (`JoinNode#tokens_built_from`), and working memory, alpha memories, beta memories, production nodes and index buckets are Sets. Removing 2000 joined facts takes 4 ms; it took 470 ms. Asserting a fact costs about 20% more for the bookkeeping. A fact is now retracted from the memories it was matched into, so it is removed cleanly even if its attributes changed after it was asserted.
- `WorkingMemory#facts`, `AlphaMemory#items`, `BetaMemory#tokens` and `ProductionNode#tokens` now return a copy, as an Array in arrival order. Appending to or clearing the returned Array no longer changes the memory; use `add_item` / `remove_item`, `add_token` / `remove_token`, and the new `clear`, `size`, `include?` and `each_fact` / `each_item` / `each_token`. `ProductionNode#tokens=`, `AlphaMemory#items=` and `BetaMemory#tokens=` are gone.
- `KBS::Token#children` is now a Set, frozen and empty until `Token#add_child` adds the first child. Use `add_child`, `remove_child` and `clear_children` to change it.
- Joins on a shared `?variable` are now hash joins. `AlphaMemory#index_on` and `BetaMemory#index_on` keep a `KBS::MemoryIndex` on the joined fields, and `JoinNode` and `NegationNode` look up only the facts or tokens with the same value instead of scanning the memory. Joining 2000 orders with 2000 payments on `?id` takes 11 ms; it took 970 ms. Whole-number Floats and Integers that are `==` still join.
- `run` now fires until no rule matches are left. A fact that a rule action asserts can fire any other rule in the same `run`, including one defined earlier or with a higher priority, and the highest-priority pending match always fires next. It used to walk the rules once in priority order, so a match created for a rule already passed waited for the next `run`. A rule set that keeps asserting facts that match its own rules now runs until `run(limit)` or `halt` stops it.
- `KBS::Fact#to_s` and `KBS::Rule#to_s` now render DSL source, such as `fact :sensor, temp: 22` and a `rule "name" do ... end` block (#3).
- `RedisStore#query_facts` and `HybridStore#query_facts` now raise `NotImplementedError` instead of returning every fact, since Redis cannot run SQL conditions (#16).
- The gem now ships only the Ruby files under `lib/`, plus `README.md`, `CHANGELOG.md` and `LICENSE.txt`. It used to include `docs/`, `examples/`, `benchmarks/`, `.github/` and other repo files such as `Rakefile` and `mkdocs.yml`, which are still in the repository (#31).
- The gem now passes the shared `asgard quality` gates. RuboCop is configured (`.rubocop.yml`) and its offenses are corrected; Reek is configured (`.reek.yml`) and reports no smells, with no baseline; `Decompiler#decompile_body` is a dispatch table instead of one long `case`; `Rule#to_s` and `KnowledgeBase#rule_source` share the new `KBS::RuleSource`. Development dependencies moved from the gemspec to the Gemfile. Visible effects: the `between` and `range` helpers decompile as `v.between?(min, max)`; `KnowledgeBase#query` matches like a rule condition, so a pattern value may be a predicate; `KBS::Engine#close` exists and does nothing. Network nodes now share `KBS::NetworkNode`, so a memory calls every successor the same way: an object used as a successor must include it.
- The Rakefile and the `rake` development dependency are gone. Tests, build, install and release run through [asgard](https://github.com/MadBomber/asgard) tasks defined in `.loki` (`asgard test_check`, `asgard build`, `asgard install`, `asgard release`). CI runs the test command directly.

### Removed
- `examples/temp_dsl.txt`, a captured demo output file, is no longer shipped in the gem (#15).

### Fixed
- A `?variable` used in two conditions of a rule now joins them: the rule matches only facts that hold the same value for it, as the README and the variable-binding guide describe. It used to match every combination, so `on :order, id: :id?` with `on :payment, order_id: :id?` fired for each order with each payment. A `without` condition now blocks only on facts that match the variables bound before it; it used to block on any fact of that type. A variable used twice in one condition requires both attributes of that fact to be equal. This changes which rules fire for anyone who reused a variable name across conditions without meaning a join.
- Join tests now find the earlier fact by its condition's position in the rule, through the new `KBS::Token#fact_at(index)`. They used `token.facts[index]`, which leaves out negated conditions, so a test placed after a `without` condition read the wrong fact.
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
- A String posted as message content with `post_message` now comes back as that String from `consume_message` and `peek_messages`, on both the SQLite and Redis queues. Reading it used to raise `JSON::ParserError`, and on SQLite the message stayed at the head of its topic, so every later read of that topic raised too (#63).
- With the SQLite store, message `posted_at`, rule firing `fired_at` and fact history `timestamp` values are now read back as UTC and shown in local time. SQLite writes them as UTC text with no zone, and they used to be read as local time, so they were off by the local UTC offset. The Redis store was already correct (#62).
- Two consumers sharing one SQLite or Redis blackboard can no longer both receive the same message from `consume_message`. The SQLite queue now claims a message with an update guarded by `consumed = 0` and moves on if another consumer got there first, and the Redis queue pops the message with `ZPOPMIN` before reading it (#60).
- The docs now describe pattern variables as symbols ending with `?`, such as `:id?`, as the code matches them. The `docs/advanced/debugging.md` join-variable helper used `start_with?('?')`, found no variables and reported every rule as independent. The `Fact#to_s` and `print_facts` examples now show the `fact :temperature, value: 85` output (#59).
- `KnowledgeBase#print_rules` now shows each condition in DSL form, so `greater_than(80)` prints as `temperature(value: ->(v) { v > 80 })`. It used to print the raw `Proc` object (#58).

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
