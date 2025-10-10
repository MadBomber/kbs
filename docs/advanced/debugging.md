# Debugging

Debug KBS applications using network visualization, token tracing, fact inspection, and rule execution logging. This guide provides tools and techniques to understand rule behavior and diagnose issues.

## Debugging Overview

Common debugging scenarios:

1. **Rules not firing** - Conditions don't match expected facts
2. **Unexpected rule firing** - Rules fire when they shouldn't
3. **Performance issues** - Slow rule execution
4. **Incorrect bindings** - Variables bound to wrong values
5. **Network structure** - Understanding compilation

## Enable Debug Output

### Basic Logging

```ruby
require 'kbs'

engine = KBS::Engine.new

# Enable debug output
engine.instance_variable_set(:@debug, true)

# Or create debug wrapper
class DebugEngine < KBS::Engine
  def add_fact(type, attributes = {})
    fact = super
    puts "[FACT ADDED] #{fact.type}: #{fact.attributes.inspect}"
    fact
  end

  def remove_fact(fact)
    puts "[FACT REMOVED] #{fact.type}: #{fact.attributes.inspect}"
    super
  end
end
```

### Rule Execution Logging

```ruby
class LoggingEngine < KBS::Engine
  def initialize
    super
    @rule_log = []
  end

  def run
    puts "\n=== Engine Run Started ==="
    puts "Facts: #{facts.size}"
    puts "Rules: #{@rules.size}"

    result = super

    puts "\n=== Engine Run Completed ==="
    puts "Rules fired: #{@rule_log.size}"
    @rule_log.each_with_index do |entry, i|
      puts "  #{i + 1}. #{entry[:rule]} (#{entry[:timestamp]})"
    end

    result
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
        puts "     ID: #{fact.id}"
        puts "     Created: #{fact.created_at}"
      end
    end
  end

  puts "\nTotal facts: #{engine.facts.size}"
end

# Usage
inspect_facts(engine)
```

### Query Fact History (Blackboard)

```ruby
def inspect_fact_history(engine, fact_id)
  return unless engine.is_a?(KBS::Blackboard::Engine)

  puts "\n=== Fact History: #{fact_id} ==="

  history = engine.fact_history(fact_id)

  history.each do |entry|
    puts "\n#{entry[:timestamp]}"
    puts "  Operation: #{entry[:operation]}"
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

## Rule Debugging

### Trace Rule Execution

```ruby
class RuleTracer
  def initialize(engine)
    @engine = engine
    @traces = []
  end

  def wrap_rules
    @engine.instance_variable_get(:@rules).each do |rule|
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

      puts "\n[RULE FIRING] #{rule.name}"
      puts "  Facts: #{facts.map(&:type).join(', ')}"
      puts "  Bindings: #{bindings.inspect}"

      result = original_action.call(facts, bindings)

      trace[:duration] = (Time.now - trace[:timestamp])
      @traces << trace

      puts "  Duration: #{trace[:duration]}s"

      result
    end
  end

  attr_reader :traces
end

# Usage
tracer = RuleTracer.new(engine)
tracer.wrap_rules
engine.run
puts "\nTotal rule firings: #{tracer.traces.size}"
```

### Test Individual Conditions

```ruby
def test_condition(engine, condition)
  puts "\n=== Testing Condition ==="
  puts "Type: #{condition.pattern[:type]}"
  puts "Pattern: #{condition.pattern.inspect}"

  # Find matching facts
  matches = engine.facts.select do |fact|
    fact.matches?(condition.pattern)
  end

  puts "\nMatching facts: #{matches.size}"
  matches.each do |fact|
    puts "  #{fact.attributes.inspect}"

    # Test predicate if present
    if condition.predicate
      predicate_result = condition.predicate.call(fact)
      puts "  Predicate: #{predicate_result}"
    end
  end

  matches
end

# Usage
condition = KBS::Condition.new(:sensor, {
  type: "temperature",
  value: :v?
}, predicate: lambda { |f| f[:value] > 25 })

test_condition(engine, condition)
```

### Why Did Rule Fire?

```ruby
def why_rule_fired(engine, rule_name)
  rule = engine.instance_variable_get(:@rules).find { |r| r.name == rule_name }

  return unless rule

  puts "\n=== Why '#{rule_name}' Fired ==="

  # Check each condition
  rule.conditions.each_with_index do |condition, i|
    puts "\nCondition #{i + 1}: #{condition.pattern[:type]}"
    puts "  Pattern: #{condition.pattern.inspect}"
    puts "  Negated: #{condition.negated?}"

    matches = engine.facts.select { |f| f.matches?(condition.pattern) }

    if condition.predicate
      matches = matches.select { |f| condition.predicate.call(f) }
    end

    puts "  Matches: #{matches.size} facts"
    matches.each do |fact|
      puts "    - #{fact.attributes.inspect}"
    end
  end
end
```

### Why Didn't Rule Fire?

```ruby
def why_rule_didnt_fire(engine, rule_name)
  rule = engine.instance_variable_get(:@rules).find { |r| r.name == rule_name }

  return unless rule

  puts "\n=== Why '#{rule_name}' Didn't Fire ==="

  # Check each condition
  failing_condition = nil

  rule.conditions.each_with_index do |condition, i|
    puts "\nCondition #{i + 1}: #{condition.pattern[:type]}"

    matches = engine.facts.select { |f| f.matches?(condition.pattern) }

    if condition.negated?
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
    else
      if matches.empty?
        puts "  ✗ FAILED (no matching facts)"
        failing_condition = i

        # Suggest similar facts
        similar = engine.facts.select { |f| f.type == condition.pattern[:type] }
        if similar.any?
          puts "  Similar facts (#{similar.size}):"
          similar.first(3).each do |fact|
            puts "    - #{fact.attributes.inspect}"
          end
        end
      else
        # Check predicate
        if condition.predicate
          pred_matches = matches.select { |f| condition.predicate.call(f) }
          if pred_matches.empty?
            puts "  ✗ FAILED (#{matches.size} facts match pattern, but predicate failed)"
            failing_condition = i
            matches.first(3).each do |fact|
              puts "    - #{fact.attributes.inspect} (predicate: false)"
            end
          else
            puts "  ✓ PASSED (#{pred_matches.size} facts)"
          end
        else
          puts "  ✓ PASSED (#{matches.size} facts)"
        end
      end
    end

    break if failing_condition
  end

  if failing_condition
    puts "\n⚠️  Rule failed at condition #{failing_condition + 1}"
  else
    puts "\n✓ All conditions passed (rule should fire on next run)"
  end
end

# Usage
why_rule_didnt_fire(engine, "detect_high_temperature")
```

## Network Visualization

### Print Network Structure

```ruby
def visualize_network(engine)
  puts "\n=== RETE Network Structure ==="

  # Alpha network
  puts "\nALPHA NETWORK:"
  alpha_memories = []

  engine.instance_eval do
    @alpha_network.each do |pattern, memory|
      puts "  #{pattern.inspect}"
      puts "    Items: #{memory.items.size}"
      alpha_memories << memory
    end
  end

  # Beta network
  puts "\nBETA NETWORK:"
  # Simplified - actual inspection depends on implementation

  puts "\nSTATISTICS:"
  puts "  Alpha memories: #{alpha_memories.size}"
  puts "  Total facts: #{engine.facts.size}"
  puts "  Rules: #{engine.instance_variable_get(:@rules).size}"
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
    engine.instance_eval do
      @alpha_network.each_with_index do |(pattern, memory), i|
        node_id = "alpha_#{i}"
        label = "#{pattern[:type]}\\n#{memory.items.size} facts"
        f.puts "  #{node_id} [label=\"#{label}\", style=filled, fillcolor=lightblue];"
      end
    end

    # Production nodes
    f.puts "\n  // Production Nodes"
    engine.instance_variable_get(:@rules).each_with_index do |rule, i|
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

    puts "[#{node_type}] #{node_id}: #{token.inspect}"
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
alpha_memory.define_singleton_method(:right_activate) do |fact|
  tracer.log_activation("AlphaMemory", object_id, fact)
  super(fact)
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
      input = gets.chomp

      break if input == "exit"

      case input
      when "facts"
        inspect_facts(@engine)
      when "rules"
        list_rules
      when "run"
        @engine.run
        puts "Engine ran successfully"
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
    @engine.instance_variable_get(:@rules).each_with_index do |rule, i|
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

```ruby
class StepDebugger
  def initialize(engine)
    @engine = engine
    @breakpoints = []
    @step_mode = false
  end

  def add_breakpoint(rule_name)
    @breakpoints << rule_name
    puts "Breakpoint added: #{rule_name}"
  end

  def enable_step_mode
    @step_mode = true

    @engine.instance_variable_get(:@rules).each do |rule|
      wrap_rule_with_breakpoint(rule)
    end
  end

  def wrap_rule_with_breakpoint(rule)
    original_action = rule.action

    rule.action = lambda do |facts, bindings|
      if @breakpoints.include?(rule.name) || @step_mode
        puts "\n🔴 BREAKPOINT: #{rule.name}"
        puts "Facts: #{facts.map { |f| { type: f.type, attrs: f.attributes } }}"
        puts "Bindings: #{bindings.inspect}"

        print "Continue? [y/n/i(nspect)] "
        response = gets.chomp

        case response
        when 'n'
          puts "Skipping rule"
          return
        when 'i'
          inspect_rule_context(facts, bindings)
        end
      end

      original_action.call(facts, bindings)
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
debugger.enable_step_mode
engine.run
```

## Common Debugging Patterns

### Verify Pattern Matching

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
    match = (expected == actual || expected.is_a?(Symbol))

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
  matches1 = engine.facts.select { |f| f.matches?(condition1.pattern) }
  matches2 = engine.facts.select { |f| f.matches?(condition2.pattern) }

  puts "\nCondition 1 matches: #{matches1.size}"
  matches1.first(3).each { |f| puts "  - #{f.attributes.inspect}" }

  puts "\nCondition 2 matches: #{matches2.size}"
  matches2.first(3).each { |f| puts "  - #{f.attributes.inspect}" }

  # Find join variables
  vars1 = condition1.pattern.values.select { |v| v.is_a?(Symbol) && v.to_s.start_with?('?') }
  vars2 = condition2.pattern.values.select { |v| v.is_a?(Symbol) && v.to_s.start_with?('?') }
  join_vars = vars1 & vars2

  puts "\nJoin variables: #{join_vars.inspect}"

  if join_vars.empty?
    puts "⚠️  No shared variables - conditions are independent"
  else
    # Check if any combinations match
    combinations = 0
    matches1.each do |f1|
      matches2.each do |f2|
        # Extract bindings
        bindings1 = extract_bindings(f1, condition1.pattern)
        bindings2 = extract_bindings(f2, condition2.pattern)

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
  engine.instance_eval do
    @alpha_network.each do |_, memory|
      alpha_size += ObjectSpace.memsize_of(memory)
      alpha_size += memory.items.sum { |f| ObjectSpace.memsize_of(f) }
    end
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
- [ ] Verify rule priorities
- [ ] Inspect network structure
- [ ] Trace rule execution
- [ ] Monitor memory usage
- [ ] Check for infinite loops

## Next Steps

- **[Testing Guide](testing.md)** - Write tests to prevent bugs
- **[Performance Guide](performance.md)** - Debug performance issues
- **[Architecture](../architecture/index.md)** - Understand network internals
- **[API Reference](../api/engine.md)** - Engine API documentation

---

*Good debugging is about asking the right questions. Use these tools to understand what your rules are doing.*
