# frozen_string_literal: true

# Measures how the RETE network scales with the number of facts and rules.
#
#   ruby -Ilib benchmarks/rete_scaling.rb
#   SIZES=500,1000,2000 REPEATS=5 ruby -Ilib benchmarks/rete_scaling.rb
#
# Each scenario reports the median wall time and a rate. A scenario that
# scales linearly keeps its rate as the size grows.

require "benchmark"
require "kbs"

sizes = ENV.fetch("SIZES", "500,1000,2000").split(",").map { |size| Integer(size) }
repeats = Integer(ENV.fetch("REPEATS", "3"))
abort "SIZES and REPEATS must be positive" unless sizes.all?(&:positive?) && repeats.positive?

def median(values)
  values.sort[values.length / 2]
end

# Median time of the block over `repeats` runs. `setup` runs before each
# one and is not timed; its result is passed to the block.
def measure(repeats, setup)
  times = Array.new(repeats) do
    state = setup.call
    Benchmark.realtime { yield state }
  end
  median(times)
end

def join_engine
  engine = KBS::Engine.new
  engine.add_rule(KBS::Rule.new(
    "paid",
    conditions: [
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:payment, { order_id: :id? })
    ]
  ))
  engine
end

def negation_engine
  engine = KBS::Engine.new
  engine.add_rule(KBS::Rule.new(
    "unpaid",
    conditions: [
      KBS::Condition.new(:order, { id: :id? }),
      KBS::Condition.new(:payment, { order_id: :id? }, negated: true)
    ]
  ))
  engine
end

# `count` single-condition rules, each on its own fact type.
def many_rules_engine(count)
  engine = KBS::Engine.new
  count.times do |i|
    engine.add_rule(KBS::Rule.new("rule_#{i}", conditions: [KBS::Condition.new(:"type_#{i}", {})]))
  end
  engine
end

# `count` rules on one fact type, each testing a different constant.
def constant_rules_engine(count)
  engine = KBS::Engine.new
  count.times do |i|
    engine.add_rule(KBS::Rule.new("rule_#{i}", conditions: [KBS::Condition.new(:event, { code: i })]))
  end
  engine
end

# `count` rules that start with the same two joined conditions and end
# with a third condition of their own.
def shared_prefix_engine(count)
  engine = KBS::Engine.new
  count.times do |i|
    engine.add_rule(KBS::Rule.new(
      "rule_#{i}",
      conditions: [
        KBS::Condition.new(:order, { id: :id? }),
        KBS::Condition.new(:payment, { order_id: :id? }),
        KBS::Condition.new(:"flag_#{i}", {})
      ]
    ))
  end
  engine
end

scenarios = {
  "join: n orders + n payments on a shared ?id" => {
    setup: ->(_n) { join_engine },
    work: lambda do |engine, n|
      n.times { |i| engine.add_fact(:order, id: i) }
      n.times { |i| engine.add_fact(:payment, order_id: i) }
    end,
    operations: ->(n) { 2 * n }
  },
  "negation: n orders, n payments, shared ?id" => {
    setup: ->(_n) { negation_engine },
    work: lambda do |engine, n|
      n.times { |i| engine.add_fact(:order, id: i) }
      n.times { |i| engine.add_fact(:payment, order_id: i) }
    end,
    operations: ->(n) { 2 * n }
  },
  "retract: remove n joined payments" => {
    setup: lambda do |n|
      engine = join_engine
      n.times { |i| engine.add_fact(:order, id: i) }
      payments = Array.new(n) { |i| engine.add_fact(:payment, order_id: i) }
      [engine, payments]
    end,
    work: ->((engine, payments), _n) { payments.each { |payment| engine.remove_fact(payment) } },
    operations: ->(n) { n }
  },
  "negation retract: remove n payments that block n orders" => {
    setup: lambda do |n|
      engine = negation_engine
      n.times { |i| engine.add_fact(:order, id: i) }
      payments = Array.new(n) { |i| engine.add_fact(:payment, order_id: i) }
      [engine, payments]
    end,
    work: ->((engine, payments), _n) { payments.each { |payment| engine.remove_fact(payment) } },
    operations: ->(n) { n }
  },
  "shared prefix: 50 rules on the same join, n orders + n payments" => {
    setup: ->(_n) { shared_prefix_engine(50) },
    work: lambda do |engine, n|
      n.times { |i| engine.add_fact(:order, id: i) }
      n.times { |i| engine.add_fact(:payment, order_id: i) }
    end,
    operations: ->(n) { 2 * n }
  },
  "alpha: 2000 asserts against n rules on n fact types" => {
    setup: ->(n) { many_rules_engine(n) },
    work: ->(engine, n) { 2000.times { |i| engine.add_fact(:"type_#{i % n}", {}) } },
    operations: ->(_n) { 2000 }
  },
  "alpha: 2000 asserts against n constant tests on one type" => {
    setup: ->(n) { constant_rules_engine(n) },
    work: ->(engine, n) { 2000.times { |i| engine.add_fact(:event, code: i % n) } },
    operations: ->(_n) { 2000 }
  }
}

lines = scenarios.flat_map do |name, scenario|
  rows = sizes.map do |n|
    seconds = measure(repeats, -> { scenario[:setup].call(n) }) { |state| scenario[:work].call(state, n) }
    rate = scenario[:operations].call(n) / seconds
    format("  n=%-6d %9.2f ms %12.0f ops/s", n, seconds * 1000, rate)
  end
  [name, *rows, ""]
end

puts <<~REPORT
  KBS RETE scaling benchmark
  Ruby: #{RUBY_DESCRIPTION}
  Sizes: #{sizes.join(', ')}; repeats: #{repeats} (median)

  #{lines.join("\n").rstrip}
REPORT
