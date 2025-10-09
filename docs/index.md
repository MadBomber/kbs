![KBS - Knowledge-Based System](assets/images/kbs.jpg)

# KBS - Knowledge-Based Systems for Ruby

**A Ruby implementation of the RETE algorithm for building intelligent, rule-based systems with persistent memory.**

[![Gem Version](https://badge.fury.io/rb/kbs.svg)](https://badge.fury.io/rb/kbs)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%202.7-ruby.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## What is KBS?

KBS (Knowledge-Based Systems) is a powerful Ruby gem that brings production rule systems to your applications. At its core is the **RETE algorithm**, a highly optimized pattern-matching engine originally developed for expert systems and now used in modern applications ranging from trading systems to IoT automation.

### Key Features

- **🚀 RETE Algorithm**: State-of-the-art pattern matching with unlinking optimization
- **💾 Persistent Blackboard Memory**: SQLite, Redis, or hybrid storage for facts and audit trails
- **🎯 Declarative DSL**: Write rules in natural, readable Ruby syntax
- **🔄 Incremental Matching**: Process only changes, not entire fact sets
- **🚫 Negation Support**: Express "absence of pattern" conditions naturally
- **📊 Multi-Agent Systems**: Build collaborative systems with message passing
- **🔍 Full Auditability**: Complete history of fact changes and rule firings
- **⚡ High Performance**: Handle millions of facts with sub-millisecond updates

## Quick Example

```ruby
require 'kbs'

# Create a rule-based trading system
engine = KBS::Engine.new

# Define a rule using the DSL
engine.add_rule(Rule.new("buy_signal") do |r|
  r.conditions = [
    # Stock price is below threshold
    Condition.new(:stock, { symbol: :?symbol, price: :?price }),
    Condition.new(:threshold, { symbol: :?symbol, buy_below: :?threshold }),

    # No pending order exists (negation)
    Condition.new(:order, { symbol: :?symbol }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    if bindings[:?price] < bindings[:?threshold]
      puts "BUY #{bindings[:?symbol]} at #{bindings[:?price]}"
    end
  end
end)

# Add facts to working memory
engine.add_fact(:stock, symbol: "AAPL", price: 145.50)
engine.add_fact(:threshold, symbol: "AAPL", buy_below: 150.0)

# Fire matching rules
engine.run  # => BUY AAPL at 145.5
```

## Why RETE?

Traditional rule engines re-evaluate all rules against all facts on every change—extremely inefficient. RETE solves this through:

1. **Network Compilation**: Rules are compiled into a discrimination network that shares common patterns
2. **State Preservation**: Partial matches are cached between cycles
3. **Incremental Updates**: Only changed facts propagate through the network
4. **Unlinking Optimization (RETE)**: Empty nodes automatically disconnect to skip unnecessary work

Result: **Near-constant time** per fact change, regardless of rule set size.

## Use Cases

### 💹 Algorithmic Trading
Real-time market analysis, signal detection, and automated order execution with complex multi-condition rules.

### 🏭 Industrial Automation
IoT sensor monitoring, predictive maintenance, and automated control systems with temporal reasoning.

### 🏥 Expert Systems
Medical diagnosis, troubleshooting assistants, and decision support systems with knowledge representation.

### 🤖 Multi-Agent Systems
Collaborative agents with shared blackboard memory for distributed problem-solving.

### 📧 Business Rules Engines
Policy enforcement, workflow automation, and compliance checking with auditable decision trails.

## Architecture

KBS consists of several integrated components:

- **RETE Engine**: Core pattern matching and rule execution
- **Working Memory**: Transient in-memory fact storage
- **Blackboard System**: Persistent memory with SQLite/Redis backends
- **DSL**: Natural language rule definition syntax
- **Message Queue**: Priority-based inter-agent communication
- **Audit Log**: Complete history for compliance and debugging

See [Architecture Overview](architecture/index.md) for details.

## Getting Started

1. **[Installation](installation.md)** - Add KBS to your project
2. **[Quick Start](quick-start.md)** - Build your first rule-based system in 5 minutes
3. **[RETE Algorithm](architecture/rete-algorithm.md)** - Deep dive into how it works
4. **[Writing Rules](guides/writing-rules.md)** - Master the DSL and pattern matching
5. **[Examples](examples/index.md)** - Learn from real-world applications

## Performance

KBS is built for production workloads:

- **Fact Addition**: O(N) where N = activated nodes (typically << total nodes)
- **Rule Firing**: O(M) where M = matched tokens
- **Memory Efficient**: Network sharing reduces redundant storage
- **Scalable**: Tested with millions of facts, thousands of rules

Benchmarks on M2 Max:
- Add 100,000 facts: ~500ms
- Match complex 5-condition rule: <1ms per fact
- Redis backend: 100x faster than SQLite for high-frequency updates

## Project Status

KBS is **actively maintained**:

- ✅ Core RETE implementation complete
- ✅ Persistent blackboard with multiple backends
- ✅ Full DSL support with negation
- ✅ Comprehensive test coverage
- ✅ Real-world usage in trading systems
- 🚧 Additional examples and guides in progress

## Community & Support

- **GitHub**: [madbomber/kbs](https://github.com/madbomber/kbs)
- **RubyGems**: [kbs](https://rubygems.org/gems/kbs)
- **Issues**: [Report bugs or request features](https://github.com/madbomber/kbs/issues)
- **Discussions**: [Ask questions](https://github.com/madbomber/kbs/discussions)

## License

KBS is released under the [MIT License](https://opensource.org/licenses/MIT).

Copyright © 2024 Dewayne VanHoozer

## Acknowledgments

The RETE algorithm was invented by Charles Forgy in 1979. This implementation draws inspiration from:

- Forgy, C. (1982). "Rete: A Fast Algorithm for the Many Pattern/Many Object Pattern Match Problem"
- Doorenbos, R. (1995). "Production Matching for Large Learning Systems" (RETE/UL)
- Modern production rule systems: Drools, Jess, CLIPS

---

**Ready to build intelligent systems?** Start with the [Quick Start Guide](quick-start.md)!
