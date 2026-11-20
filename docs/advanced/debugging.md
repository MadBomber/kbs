# Debugging

Debug KBS applications using network visualization, token tracing, fact inspection, and rule execution logging. This guide provides tools and techniques to understand rule behavior and diagnose issues.

## Debugging Overview

Common debugging scenarios:

1. **Rules not firing** - Conditions don't match expected facts
2. **Unexpected rule firing** - Rules fire when they shouldn't
3. **Performance issues** - Slow rule execution
4. **Incorrect bindings** - Variables bound to wrong values
5. **Network structure** - Understanding compilation

The examples below print their diagnostics with the [debug_me](https://github.com/madbomber/debug_me) gem (`debug_me "message"`, `debug_me { :variable }`) where they log events, and with `puts` where they print a report.

## Enable Debug Output

### Basic Logging

The engine has no debug flag. Subclass it to log fact changes:

```ruby
require 'kbs'
require 'debug_me'
include DebugMe

class DebugEngine < KBS::Engine
  def add_fact(type, attributes = {})
    fact = super
    # add_fact returns nil when a logically supported fact loses its support
    # before it is added
    debug_me "[FACT ADDED] #{fact.type}: #{fact.attributes.inspect}" if fact
    fact
  end

  def remove_fact(fact)
    debug_me "[FACT REMOVED] #{fact.type}: #{fact.attributes.inspect}"
    super
  end
end

engine = DebugEngine.new
```

### Rule Execution Logging

`Engine#run` pops activations off the agenda and fires each one through `fire_activation`, so that is the place to record firings. `run` returns the number of rules fired.

```ruby
class LoggingEngine < KBS::Engine
  def initialize(**options)
    super
    @rule_log = []
  end

  def fire_activation(activation)
    @rule_log << { rule: activation.rule.name, timestamp: Time.now }
    debug_me "[RULE FIRING] #{activation}"
    super
  end

  def run(limit = nil)
    debug_me "=== Engine Run Started: #{facts.size} facts, #{rules.size} rules, #{agenda.size} activations ==="

    fired = super

    debug_me "=== Engine Run Completed: #{fired} rules fired ==="
    @rule_log.last(fired).each_with_index do |entry, i|
      debug_me "  #{i + 1}. #{entry[:rule]} (#{entry[:timestamp]})"
    end

    fired
  end

  attr_reader :rule_log
end
```

## Fact Inspection

### Inspect Current Facts

```ruby
def inspect_facts(engine)
  puts "\n=== Current Facts ==="

  # Group by type
  facts_by_type = engine.facts.group_by(&:type)

  facts_by_type.each do |type, facts|
    puts "\n#{type} (#{facts.size}):"
    facts.each_with_index do |fact, i|
      puts "  #{i + 1}. #{fact.attributes.inspect}"
      if fact.is_a?(KBS::Blackboard::Fact)
        puts "     UUID: #{fact.uuid}"
      end
    end
  end

  puts "\nTotal facts: #{engine.facts.size}"
end

# Usage
inspect_facts(engine)
```

A `KBS::DSL::KnowledgeBase` has `print_facts` and `print_rules` built in.

### Query Fact History (Blackboard)

The blackboard's audit log records every ADD, UPDATE and REMOVE of a fact, newest first.

```ruby
def inspect_fact_history(engine, fact_uuid)
  return unless engine.is_a?(KBS::Blackboard::Engine)

  puts "\n=== Fact History: #{fact_uuid} ==="

  history = engine.blackboard.get_history(fact_uuid)

  history.each do |entry|
    puts "\n#{entry[:timestamp]}"
    puts "  Action: #{entry[:action]}"
    puts "  Attributes: #{entry[:attributes].inspect}"
  end
end
```

### Find Facts by Criteria

```ruby
def find_facts(engine, **criteria)
  results = engine.facts.select do |fact|
    criteria.all? do |key, value|
      case key
      when :type
        fact.type == value
      else
        fact[key] == value
      end
    end
  end

  puts "\n=== Found #{results.size} facts ==="
  results.each do |fact|
    puts "#{fact.type}: #{fact.attributes.inspect}"
  end

  results
end

# Usage
find_facts(engine, type: :sensor, location: "bedroom")
find_facts(engine, type: :alert, severity: "critical")
```

## Built-in Tracing and Inspection

The engine can report what it does and how far each rule has matched, without wrapping rules or reading instance variables.

### watch

`watch` writes a line for each change to the items you name: `:facts`, `:activations`, `:rules`, or all three when called with no argument. `unwatch` stops it.

```ruby
kb = KBS.knowledge_base
kb.rule "paid", priority: 5 do
  on :order, id: :id?
  on :payment, order_id: :id?
  without :hold, order_id: :id?
end

kb.watch
kb.assert(:order, id: 1)
payment = kb.assert(:payment, order_id: 1)
kb.run
kb.retract(payment)
```

```
==> fact :order, id: 1
==> fact :payment, order_id: 1
==> Activation 5 paid: fact :order, id: 1; fact :payment, order_id: 1; *
FIRE 1 paid: fact :order, id: 1; fact :payment, order_id: 1; *
<== fact :payment, order_id: 1
```

| Line | Meaning |
|---|---|
| `==> fact ...` | a fact entered working memory |
| `<== fact ...` | a fact left it |
| `==> Activation P rule: ...` | a match of the rule went on the agenda; `P` is the rule's priority |
| `<== Activation P rule: ...` | a match was withdrawn before it fired |
| `FIRE N rule: ...` | the rule fired; `N` counts firings |

An activation lists one entry per condition: the matched fact, or `*` for a `without` or `exists` condition.

Lines go to `$stdout`. Send them elsewhere with `engine.trace_output = io`; anything that responds to `puts` works.

### matches

`matches(rule_name)` answers "why didn't this rule fire?". For each condition it gives the number of facts that fit the condition on its own (`alpha_matches`) and the number of partial matches of the rule up to and including it (`partial_matches`).

```ruby
kb.assert(:order, id: 2)
kb.matches("paid")
# => {rule: "paid",
#     conditions:
#      [{keyword: "on", type: :order, alpha_matches: 2, partial_matches: 2},
#       {keyword: "on", type: :payment, alpha_matches: 0, partial_matches: 0},
#       {keyword: "without", type: :hold, alpha_matches: 0, partial_matches: 0}],
#     matches: 0,
#     activations: 0}
```

Read down the list: the first condition with `partial_matches: 0` is the one that stops the rule. Here two orders match, and no payment does. When `alpha_matches` is positive and `partial_matches` is zero, facts fit the pattern but a shared variable does not line up with the earlier conditions.

`matches:` counts complete matches, and `activations:` the ones that have not fired yet.

### join_activity

`engine.join_activity(rule_name)` shows what each condition has cost since the engine started, or since `engine.reset_join_activity`.

```ruby
kb.engine.join_activity("paid")[1]
# => {keyword: "on", type: :payment, indexed: true,
#     left_activations: 2, right_activations: 1, comparisons: 1, matches: 1}
```

| Key | Meaning |
|---|---|
| `indexed` | the condition is joined through a hash index on a shared variable |
| `left_activations` | partial matches that arrived from the conditions before it |
| `right_activations` | facts that arrived for this condition |
| `comparisons` | candidates looked at |
| `matches` | candidates that passed |

A condition with `comparisons` far above `matches` is doing wasted work: it has no shared variable to index on, or its pattern is too loose. Move a more selective condition ahead of it. Rules that share a node report the same counts for it.

### network_stats

```ruby
kb.engine.network_stats
# => {rules: 1, facts: 2, alpha_memories: 3, beta_nodes: 3, conditions: 3,
#     partial_matches: 2, activations: 0}
```

`beta_nodes` below `conditions` means rules are sharing joins. A `partial_matches` count that grows much faster than `facts` points at a join without a shared variable.

## Rule Debugging

### Trace Rule Execution

`engine.rules` lists the rules, and `Rule#action` can be replaced. An action that takes two arguments receives the matched facts and the variable bindings.

```ruby
class RuleTracer
  def initialize(engine)
    @engine = engine
    @traces = []
  end

  def wrap_rules
    @engine.rules.each do |rule|
      wrap_rule(rule)
    end
  end

  def wrap_rule(rule)
    original_action = rule.action

    rule.action = lambda do |facts, bindings|
      trace = {
        rule: rule.name,
        timestamp: Time.now,
        facts: facts.map { |f| { type: f.type, attrs: f.attributes } },
        bindings: bindings.dup
      }

      debug_me "[RULE FIRING] #{rule.name}"
      debug_me "  Facts: #{facts.map(&:type).join(', ')}"
      debug_me "  Bindings: #{bindings.inspect}"

      result = original_action&.call(facts, bindings)

      trace[:duration] = (Time.now - trace[:timestamp])
      @traces << trace

      debug_me "  Duration: #{trace[:duration]}s"

      result
    end
  end

  attr_reader :traces
end

# Usage
tracer = RuleTracer.new(engine)
tracer.wrap_rules
engine.run
debug_me "Total rule firings: #{tracer.traces.size}"
```

### Test Individual Conditions

A condition's `pattern` holds only the attribute tests; its fact type is `condition.type`. A helper that checks one fact against one condition, the way the alpha network does, makes the other tools below simple. Predicates such as `greater_than(25)` are Procs inside the pattern and are called by the match.

```ruby
# Whether `fact` fits `condition` on its own, ignoring the joins on
# ?variables shared with other conditions.
def condition_matches?(fact, condition)
  fact.type == condition.type &&
    condition.pattern.all? do |key, expected|
      KBS::PatternMatching.value_matches?(fact[key], expected)
    end
end

def test_condition(engine, condition)
  puts "\n=== Testing Condition ==="
  puts "Type: #{condition.type}"
  puts "Pattern: #{condition.pattern.inspect}"

  # Find matching facts
  matches = engine.facts.select { |fact| condition_matches?(fact, condition) }

  puts "\nMatching facts: #{matches.size}"
  matches.each do |fact|
    puts "  #{fact.attributes.inspect}"
    puts "  Bindings: #{condition.bindings_from(fact).inspect}"
  end

  matches
end

# Usage
condition = KBS::Condition.new(:sensor, {
  type: "temperature",
  value: ->(v) { v > 25 }
})

test_condition(engine, condition)
```

### Why Did Rule Fire?

Each rule ends in a production node, `engine.production_nodes[rule_name]`, that holds the rule's current complete matches as tokens. A token knows its facts and whether it has fired.

```ruby
def why_rule_fired(engine, rule_name)
  node = engine.production_nodes[rule_name]

  return unless node

  puts "\n=== Why '#{rule_name}' Fired ==="

  node.tokens.each_with_index do |token, i|
    puts "\nMatch #{i + 1} (#{token.fired? ? 'fired' : 'waiting on the agenda'}):"
    token.facts.each do |fact|
      puts "    - #{fact.type}: #{fact.attributes.inspect}"
    end
    puts "  Bindings: #{node.rule.bindings_for(token.facts).inspect}"
  end
end
```

### Why Didn't Rule Fire?

This checks each condition on its own with `condition_matches?`, so a `without` condition is reported as blocked by any fact that fits it, even one whose `?variables` differ from the facts matched before it.

```ruby
def why_rule_didnt_fire(engine, rule_name)
  rule = engine.rules.find { |r| r.name == rule_name }

  return unless rule

  puts "\n=== Why '#{rule_name}' Didn't Fire ==="

  # Check each condition
  failing_condition = nil

  rule.conditions.each_with_index do |condition, i|
    puts "\nCondition #{i + 1}: #{condition.summary}"

    matches = engine.facts.select { |f| condition_matches?(f, condition) }

    if condition.negated
      puts "  Negated condition"
      if matches.empty?
        puts "  ✓ PASSED (no matching facts)"
      else
        puts "  ✗ FAILED (#{matches.size} matching facts found, but should be absent)"
        failing_condition = i
        matches.each do |fact|
          puts "    Blocking fact: #{fact.attributes.inspect}"
        end
      end
    elsif matches.empty?
      puts "  ✗ FAILED (no matching facts)"
      failing_condition = i

      # Suggest similar facts
      similar = engine.facts.select { |f| f.type == condition.type }
      if similar.any?
        puts "  Similar facts (#{similar.size}):"
        similar.first(3).each do |fact|
          puts "    - #{fact.attributes.inspect}"
        end
      end
    else
      puts "  ✓ PASSED (#{matches.size} facts)"
    end

    break if failing_condition
  end

  if failing_condition
    puts "\n⚠️  Rule failed at condition #{failing_condition + 1}"
  else
    puts <<~MSG

      ✓ Every condition has matching facts on its own. If the rule still
        has not fired, check that ?variables shared between conditions hold
        equal values, and whether it already fired for these facts: an
        activation fires once (see why_rule_fired).
    MSG
  end
end

# Usage
why_rule_didnt_fire(engine, "detect_high_temperature")
```

### Inspect the Agenda

Matches wait on the agenda until `engine.run` fires them. `engine.agenda.to_a` lists the pending activations in firing order; each prints as its priority, rule name and facts.

```ruby
def inspect_agenda(engine)
  puts "\n=== Agenda (#{engine.agenda.size} pending, strategy: #{engine.strategy}) ==="
  engine.agenda.to_a.each_with_index do |activation, i|
    puts "  #{i + 1}. #{activation}"
  end
end
```

### Logical Support

A fact asserted by a rule with `logical` conditions is retracted when the match of those conditions goes away. To see why such a fact exists, or why it vanished:

```ruby
engine.logically_supported?(fact)  # asserted under logical conditions?
engine.dependencies(fact)          # the matches supporting it, each an array of facts
engine.dependents(fact)            # facts that lose a support if this one is retracted
```

## Network Visualization

### Print Network Structure

`engine.alpha_memories` maps each condition pattern (with its fact type under `:type`) to the alpha memory that holds the facts fitting it.

```ruby
def visualize_network(engine)
  puts "\n=== RETE Network Structure ==="

  # Alpha network
  puts "\nALPHA NETWORK:"
  engine.alpha_memories.each do |pattern, memory|
    puts "  #{pattern.inspect}"
    puts "    Items: #{memory.items.size}"
  end

  # Production nodes
  puts "\nPRODUCTION NODES:"
  engine.production_nodes.each do |name, node|
    puts "  #{name}: #{node.tokens.size} matches"
  end

  puts "\nSTATISTICS:"
  puts "  Alpha memories: #{engine.alpha_memories.size}"
  puts "  Total facts: #{engine.facts.size}"
  puts "  Rules: #{engine.rules.size}"
  puts "  Pending activations: #{engine.agenda.size}"
end
```

### Graphviz Export

```ruby
def export_to_graphviz(engine, filename = "network.dot")
  File.open(filename, 'w') do |f|
    f.puts "digraph RETE {"
    f.puts "  rankdir=TB;"
    f.puts "  node [shape=box];"

    # Alpha nodes
    f.puts "\n  // Alpha Network"
    engine.alpha_memories.each_with_index do |(pattern, memory), i|
      node_id = "alpha_#{i}"
      label = "#{pattern[:type]}\\n#{memory.items.size} facts"
      f.puts "  #{node_id} [label=\"#{label}\", style=filled, fillcolor=lightblue];"
    end

    # Production nodes
    f.puts "\n  // Production Nodes"
    engine.rules.each_with_index do |rule, i|
      node_id = "rule_#{i}"
      label = "#{rule.name}\\n#{rule.priority}"
      f.puts "  #{node_id} [label=\"#{label}\", style=filled, fillcolor=lightgreen];"
    end

    # Edges (simplified)
    # ...

    f.puts "}"
  end

  puts "Network exported to #{filename}"
  puts "Render with: dot -Tpng #{filename} -o network.png"
end

# Usage
export_to_graphviz(engine)
```

## Token Tracing

### Trace Token Propagation

An alpha memory receives a new fact through `activate(fact)` and passes it on to its join nodes through `right_activate(fact)`.

```ruby
class TokenTracer
  def initialize
    @trace = []
  end

  def log_activation(node_type, node_id, token)
    @trace << {
      timestamp: Time.now,
      node_type: node_type,
      node_id: node_id,
      token: token.inspect
    }

    debug_me "[#{node_type}] #{node_id}: #{token.inspect}"
  end

  def print_trace
    puts "\n=== Token Trace ==="
    @trace.each_with_index do |entry, i|
      puts "\n#{i + 1}. [#{entry[:node_type]}] #{entry[:node_id]}"
      puts "   Time: #{entry[:timestamp]}"
      puts "   Token: #{entry[:token]}"
    end
  end

  attr_reader :trace
end

# Usage: Instrument nodes
tracer = TokenTracer.new

# Wrap alpha activation
engine.alpha_memories.each_value do |alpha_memory|
  alpha_memory.define_singleton_method(:activate) do |fact|
    tracer.log_activation("AlphaMemory", object_id, fact)
    super(fact)
  end
end
```

## Interactive Debugging

### Debug Console

```ruby
class DebugConsole
  def initialize(engine)
    @engine = engine
  end

  def start
    loop do
      print "\nkbs> "
      input = gets&.chomp

      break if input.nil? || input == "exit"

      case input
      when "facts"
        inspect_facts(@engine)
      when "rules"
        list_rules
      when "run"
        fired = @engine.run
        puts "Engine ran successfully (#{fired} rules fired)"
      when /^add (\w+) (.+)$/
        type = $1.to_sym
        attrs = eval($2)  # UNSAFE: eval user input (for demo only)
        @engine.add_fact(type, attrs)
        puts "Fact added"
      when /^remove (\d+)$/
        fact = @engine.facts[$1.to_i]
        @engine.remove_fact(fact) if fact
        puts "Fact removed"
      when /^why (.+)$/
        why_rule_didnt_fire(@engine, $1)
      when "help"
        print_help
      else
        puts "Unknown command: #{input}"
        print_help
      end
    end
  end

  def list_rules
    puts "\n=== Rules ==="
    @engine.rules.each_with_index do |rule, i|
      puts "#{i}. #{rule.name} (priority: #{rule.priority}, conditions: #{rule.conditions.size})"
    end
  end

  def print_help
    puts <<~HELP

      Commands:
        facts              - List all facts
        rules              - List all rules
        run                - Run engine
        add TYPE {ATTRS}   - Add fact
        remove INDEX       - Remove fact
        why RULE_NAME      - Explain why rule didn't fire
        exit               - Exit console
        help               - Show this help

    HELP
  end
end

# Usage
console = DebugConsole.new(engine)
console.start
```

### Step-Through Debugger

The debugger wraps every rule's action when it is created. It stops at the rules with a breakpoint, or at every rule in step mode.

```ruby
class StepDebugger
  def initialize(engine)
    @engine = engine
    @breakpoints = []
    @step_mode = false

    @engine.rules.each do |rule|
      wrap_rule_with_breakpoint(rule)
    end
  end

  def add_breakpoint(rule_name)
    @breakpoints << rule_name
    puts "Breakpoint added: #{rule_name}"
  end

  def enable_step_mode
    @step_mode = true
  end

  def wrap_rule_with_breakpoint(rule)
    original_action = rule.action

    rule.action = lambda do |facts, bindings|
      if @breakpoints.include?(rule.name) || @step_mode
        puts "\n🔴 BREAKPOINT: #{rule.name}"
        puts "Facts: #{facts.map { |f| { type: f.type, attrs: f.attributes } }}"
        puts "Bindings: #{bindings.inspect}"

        print "Continue? [y/n/i(nspect)] "
        response = gets.to_s.chomp

        case response
        when 'n'
          puts "Skipping rule"
          return
        when 'i'
          inspect_rule_context(facts, bindings)
        end
      end

      original_action&.call(facts, bindings)
    end
  end

  def inspect_rule_context(facts, bindings)
    puts "\n=== Rule Context ==="
    puts "Facts (#{facts.size}):"
    facts.each_with_index do |fact, i|
      puts "  #{i}. #{fact.type}: #{fact.attributes.inspect}"
    end

    puts "\nBindings:"
    bindings.each do |var, value|
      puts "  #{var} => #{value.inspect}"
    end

    print "\nPress Enter to continue..."
    gets
  end
end

# Usage
debugger = StepDebugger.new(engine)
debugger.add_breakpoint("high_temperature_alert")
# debugger.enable_step_mode  # stop at every rule
engine.run
```

## Common Debugging Patterns

### Verify Pattern Matching

`Fact#matches?` takes a pattern whose `:type` key, if present, is the fact type. A Proc in the pattern is called with the attribute's value, and a `?variable` matches any value.

```ruby
def verify_pattern_match(fact, pattern)
  puts "\n=== Pattern Match Verification ==="
  puts "Fact: #{fact.attributes.inspect}"
  puts "Pattern: #{pattern.inspect}"

  result = fact.matches?(pattern)
  puts "Result: #{result}"

  # Detail each attribute
  pattern.each do |key, expected|
    next if key == :type

    actual = fact[key]
    match = KBS::PatternMatching.value_matches?(actual, expected)

    puts "\n  #{key}:"
    puts "    Expected: #{expected.inspect}"
    puts "    Actual: #{actual.inspect}"
    puts "    Match: #{match ? '✓' : '✗'}"
  end

  result
end
```

### Diagnose Join Issues

```ruby
def diagnose_join(engine, condition1, condition2)
  puts "\n=== Join Diagnosis ==="

  # Find matches for each condition
  matches1 = engine.facts.select { |f| condition_matches?(f, condition1) }
  matches2 = engine.facts.select { |f| condition_matches?(f, condition2) }

  puts "\nCondition 1 matches: #{matches1.size}"
  matches1.first(3).each { |f| puts "  - #{f.attributes.inspect}" }

  puts "\nCondition 2 matches: #{matches2.size}"
  matches2.first(3).each { |f| puts "  - #{f.attributes.inspect}" }

  # Find join variables
  join_vars = condition1.variable_bindings.keys & condition2.variable_bindings.keys

  puts "\nJoin variables: #{join_vars.inspect}"

  if join_vars.empty?
    puts "⚠️  No shared variables - conditions are independent"
  else
    # Check if any combinations match
    combinations = 0
    matches1.each do |f1|
      matches2.each do |f2|
        # Extract bindings
        bindings1 = condition1.bindings_from(f1)
        bindings2 = condition2.bindings_from(f2)

        # Check join
        if join_vars.all? { |v| bindings1[v] == bindings2[v] }
          combinations += 1
        end
      end
    end

    puts "Valid combinations: #{combinations}"
  end
end
```

### Track Memory Usage

```ruby
require 'objspace'

def track_memory_usage(engine)
  puts "\n=== Memory Usage ==="

  # Facts
  fact_size = engine.facts.sum { |f| ObjectSpace.memsize_of(f) }
  puts "Facts: #{(fact_size / 1024.0).round(2)} KB (#{engine.facts.size} facts)"

  # Alpha memories
  alpha_size = 0
  engine.alpha_memories.each_value do |memory|
    alpha_size += ObjectSpace.memsize_of(memory)
    alpha_size += memory.items.sum { |f| ObjectSpace.memsize_of(f) }
  end
  puts "Alpha network: #{(alpha_size / 1024.0).round(2)} KB"

  total = fact_size + alpha_size
  puts "\nTotal: #{(total / 1024.0).round(2)} KB"
end
```

## Debugging Checklist

- [ ] Verify facts are added with correct types and attributes
- [ ] Check condition patterns match fact structure
- [ ] Test predicates independently
- [ ] Ensure variables are bound correctly across conditions
- [ ] Check negated conditions for blocking facts
- [ ] Verify rule priorities and the agenda's strategy
- [ ] Inspect the agenda for pending activations
- [ ] Inspect network structure
- [ ] Trace rule execution
- [ ] Monitor memory usage
- [ ] Check for infinite loops (`engine.run(limit)` stops after `limit` firings)

## Next Steps

- **[Testing Guide](testing.md)** - Write tests to prevent bugs
- **[Performance Guide](performance.md)** - Debug performance issues
- **[Architecture](../architecture/index.md)** - Understand network internals
- **[API Reference](../api/engine.md)** - Engine API documentation

---

*Good debugging is about asking the right questions. Use these tools to understand what your rules are doing.*
