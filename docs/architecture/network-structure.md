# Network Structure

How RETE compiles rules into an efficient discrimination network.

## Overview

When you add a rule to the engine, KBS compiles it into a discrimination network—a directed acyclic graph (DAG) of nodes that efficiently matches patterns against facts. This document explains the compilation process, node types, and optimization strategies.

## Network Compilation Process

### Step 1: Parse Rule Conditions

```ruby
rule = Rule.new("example") do |r|
  r.conditions = [
    Condition.new(:stock, { symbol: :sym?, price: :price? }),
    Condition.new(:threshold, { symbol: :sym?, max: :max? })
  ]
  r.action = lambda { |facts, bindings| ... }
end
```

The engine extracts:
- Condition types (`:stock`, `:threshold`)
- Patterns (attribute constraints)
- Variable bindings (`:sym?`, `:price?`, `:max?`)
- Join tests (`:sym?` appears in both conditions)

### Step 2: Create or Reuse Alpha Memories

For each condition, the engine creates or reuses an `AlphaMemory` node:

```ruby
# Pattern for first condition
pattern1 = { type: :stock, symbol: :sym?, price: :price? }
alpha1 = get_or_create_alpha_memory(pattern1)

# Pattern for second condition
pattern2 = { type: :threshold, symbol: :sym?, max: :max? }
alpha2 = get_or_create_alpha_memory(pattern2)
```

**Network Sharing**: If another rule has the same pattern, they share the same alpha memory node.

**Finding a fact's memories**: `KBS::AlphaNetwork` groups the alpha memories by fact type. Within a type, a memory whose pattern tests an attribute against a constant is filed in a hash under that attribute and value. A new fact reaches those memories with one lookup on its own value, and is only tested against the memories of its type that have no constant test. The number of rules on other fact types, or testing other constants, does not affect the cost of asserting a fact.

### Step 3: Build Join Network

Connect conditions through join nodes:

Simplified from `Engine#build_network_for_rule` and `#add_condition_node`:

```ruby
# Start with root beta memory (contains dummy token)
current_beta = @root_beta_memory

# Build join tests for variable consistency, one list per condition
join_tests = JoinTestBuilder.new(rule.conditions).tests

rule.conditions.each_with_index do |condition, index|
  alpha_memory = get_or_create_alpha_memory(condition.pattern.merge(type: condition.type))

  # Create join, negation or exists node
  node_class = if condition.negated then NegationNode
               elsif condition.exists then ExistsNode
               else JoinNode
               end
  node = node_class.new(alpha_memory, current_beta, join_tests[index])

  # Create beta memory to store results
  new_beta = BetaMemory.new
  node.successors << new_beta
  replay_tokens(current_beta, node)  # match tokens that already exist
  current_beta = new_beta
end
```

### Step 4: Attach Production Node

```ruby
production_node = ProductionNode.new(rule, @agenda, order: @rules.size)
current_beta.successors << production_node
@production_nodes[rule.name] = production_node
```

The production node puts each complete match on the engine's `Agenda`; `engine.run` fires them.

## Node Types

### Alpha Memory Nodes

**Purpose**: Store facts matching a specific pattern

**Structure**:
```ruby
class AlphaMemory
  attr_reader :items        # Facts that match pattern (a copy; a Set inside)
  attr_accessor :successors # Join/negation/exists nodes using this alpha
  attr_accessor :pattern    # Pattern to match
  attr_reader :linked       # Unlinking state
  # index_on(fields) → MemoryIndex used by joins on shared variables
end
```

**Example**:
```
AlphaMemory(stock, symbol: "AAPL")
  items: [stock(symbol: "AAPL", price: 150), ...]
  successors: [JoinNode1, JoinNode2, ...]
```

### Beta Memory Nodes

**Purpose**: Store partial matches (tokens) as they propagate

**Structure**:
```ruby
class BetaMemory
  attr_reader :tokens       # Partial matches (a copy; a Set inside)
  attr_accessor :successors # Next nodes in network
  attr_reader :linked       # Unlinking state
  attr_accessor :listener   # Told of removed tokens (truth maintenance)
  # index_on(specs) → MemoryIndex used by joins on shared variables
end
```

**Example**:
```
BetaMemory
  tokens: [
    Token(parent: root, fact: stock(...)),
    Token(parent: root, fact: stock(...))
  ]
  successors: [JoinNode2]
```

### Join Nodes

**Purpose**: Combine facts from alpha memory with tokens from beta memory

**Structure**:
```ruby
class JoinNode
  attr_reader :alpha_memory    # Right input
  attr_reader :beta_memory     # Left input
  attr_reader :tests           # Join tests to perform
  attr_accessor :successors    # Beta memory nodes
  # @tokens_by_fact: tokens built from each fact, for retraction
end
```

Equality tests between a token and a fact are used as hash-index keys on both memories (`KBS::JoinIndexing`), so a join on a shared variable looks up only matching entries; other tests are checked on those candidates.

**Join Tests**:
```ruby
{
  token_field_index: 0,    # Check first fact in token
  token_field: :symbol,    # Get its :symbol attribute
  fact_field: :symbol,     # Compare with new fact's :symbol
  operation: :eq           # Must be equal
}
```

### Negation Nodes

**Purpose**: Implement negated conditions (match when pattern is absent)

**Structure**:
```ruby
class NegationNode < QuantifierNode
  attr_reader :alpha_memory       # Pattern to check
  attr_reader :beta_memory        # Tokens to test
  attr_reader :tests              # Join tests
  # @facts_matching:    token → Set of facts blocking it
  # @tokens_matched_by: fact  → Set of tokens it blocks
end
```

**Behavior**:
- Token arrives → link it to the matching facts in alpha memory
- No matches found → propagate token (condition satisfied)
- Matches found → block token (condition not satisfied)
- Last blocking fact removed → unblock token (only the tokens linked to that fact are visited)

### Exists Nodes

**Purpose**: Implement `exists` conditions (match once while at least one fact fits)

`ExistsNode < QuantifierNode` uses the same links as `NegationNode` with the test inverted: a token passes when it gains its first matching fact and is withdrawn when it loses its last. It adds no fact to the token and binds no variables for later conditions.

### Production Nodes

**Purpose**: Queue rule actions when all conditions match

**Structure**:
```ruby
class ProductionNode
  attr_accessor :rule   # Rule to fire
  attr_reader :tokens   # Complete matches, fired or not (a copy)
  attr_reader :order    # Rule's position, for :definition ordering
  # @activations: token → its Activation on the agenda
end
```

A complete match becomes an `Activation` on the engine's `Agenda`. If the match is retracted before it fires, the activation is cancelled.

### Agenda

**Purpose**: Hold pending activations in firing order

`KBS::Agenda` is a binary heap ordered by rule priority, then by the conflict resolution strategy (`:definition`, `:depth` or `:breadth`). `engine.run(limit = nil)` pops and fires one activation at a time until the agenda is empty, so facts asserted by an action can fire other rules in the same run.

## Complete Example

### Rule Definition

```ruby
rule = Rule.new("trading_signal") do |r|
  r.conditions = [
    Condition.new(:stock, { symbol: :sym?, price: :price? }),
    Condition.new(:threshold, { symbol: :sym?, buy_below: :threshold? }),
    Condition.new(:order, { symbol: :sym? }, negated: true)
  ]

  r.action = lambda do |facts, bindings|
    if bindings[:price?] < bindings[:threshold?]
      puts "BUY #{bindings[:sym?]}"
    end
  end
end
```

### Compiled Network

![Trading Signal Network](../assets/images/trading-signal-network.svg)

*The trading signal rule compiles into a network with three join points. The first two join nodes combine stock and threshold facts based on matching symbols. The negation node ensures no existing order for that symbol. Tokens propagate through beta memories, carrying partial matches until reaching the production node.*

## Optimization Strategies

### Network Sharing

Multiple rules with common patterns share alpha memory nodes:

```ruby
# Rule 1
Condition.new(:stock, { symbol: "AAPL" })

# Rule 2
Condition.new(:stock, { symbol: "AAPL" })

# Both use the same AlphaMemory node
# Only one pattern match, one fact storage
```

### Unlinking

Empty nodes automatically disconnect to avoid wasted computation:

```ruby
# BetaMemory becomes empty
beta_memory.remove_token(last_token)
# => Calls unlink!

# Downstream nodes stop processing
join_node.left_activate(token)  # Returns early if !@left_linked
```

### Condition Ordering

Place selective conditions first to minimize beta memory size:

```ruby
# Good: Specific condition first
conditions = [
  Condition.new(:critical_alert, { severity: "critical" }),  # Few matches
  Condition.new(:stock, { symbol: :sym? })                   # Many matches
]

# Bad: General condition first
conditions = [
  Condition.new(:stock, { symbol: :sym? }),                  # Many matches
  Condition.new(:critical_alert, { severity: "critical" })   # Few matches
]
```

### Variable Binding Extraction

Variables create join tests automatically:

```ruby
# Rule with :sym? in two conditions
tests = [
  {
    token_field_index: 0,     # First fact in token (stock)
    token_field: :symbol,
    fact_field: :symbol,      # New fact (threshold)
    operation: :eq
  }
]
```

## Network Inspection

### Debugging Network Structure

```ruby
# See all alpha memories
engine.alpha_memories.each do |pattern, memory|
  puts "Pattern: #{pattern}"
  puts "  Facts: #{memory.items.size}"
  puts "  Linked: #{memory.linked}"
  puts "  Successors: #{memory.successors.size}"
end

# See production nodes
engine.production_nodes.each do |name, node|
  puts "Rule: #{name}"
  puts "  Tokens: #{node.tokens.size}"
end

# See pending activations in firing order
engine.agenda.to_a.each { |activation| puts activation }
```

### Visualizing Token Flow

Enable tracing in actions:

```ruby
r.action = lambda do |facts, bindings|
  puts "Rule 'trading_signal' fired"
  puts "  Facts: #{facts.map(&:to_s).join(', ')}"
  puts "  Bindings: #{bindings.inspect}"
end
```

## Performance Implications

### Time Complexity

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Add rule | O(C × F) | C = conditions, F = facts |
| Network sharing lookup | O(1) | Hash-based pattern cache |
| Alpha memory selection | O(K + U) | K = constant-tested attributes looked up, U = memories of the type with no constant test |
| Join candidate lookup | O(1) + matches | Hash index when the join has a shared `?variable`; otherwise a scan of the other memory |
| Join test | O(T) | T = number of tests |
| Token propagation | O(S) | S = successors |

### Space Complexity

| Structure | Space | Notes |
|-----------|-------|-------|
| Alpha memories | O(P) nodes | P = unique patterns across all rules (variable names count: `:p?` and `:price?` make different patterns) |
| Beta memories | O(R × C) | R = rules, C = avg conditions |
| Tokens | O(M × C) | M = complete matches |
| Join nodes | O(R × C) | One per condition |

### Optimization Tips

1. **Maximize network sharing**: Design rules to reuse common patterns
2. **Order conditions by selectivity**: Specific first, general last
3. **Join on shared variables**: Negations and joins with a shared `?variable` use hash indexes; without one they scan the other memory
4. **Use predicates sparingly**: Can't be shared across rules (each lambda is a different pattern), and a pattern with no constant test is checked for every fact of its type
5. **Profile your rules**: Use debugging to identify bottlenecks

## Next Steps

- **[RETE Algorithm](rete-algorithm.md)** - Understand the full execution cycle
- **[Blackboard System](blackboard.md)** - Persistent network state
- **[Performance Tuning](../advanced/performance.md)** - Optimize for production
- **[Debugging Guide](../advanced/debugging.md)** - Inspect network state

---

*This document describes implementation details in `KBS::Engine#build_network_for_rule` (network compilation, `lib/kbs/engine.rb`) and related node classes.*
