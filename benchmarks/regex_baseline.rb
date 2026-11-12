# frozen_string_literal: true

require "benchmark"
require "kbs"

iterations = Integer(ENV.fetch("ITERATIONS", "20000"))
repeats = Integer(ENV.fetch("REPEATS", "5"))
abort "ITERATIONS and REPEATS must be positive" unless iterations.positive? && repeats.positive?

regexp = /\AINV-\d{6}\z/
samples = Array.new(iterations) do |index|
  "#{index.even? ? 'INV' : 'ORD'}-%06d" % index
end

def median(values)
  values.sort[values.length / 2]
end

def measure(repeats)
  times = Array.new(repeats) { Benchmark.realtime { yield } }
  median(times)
end

def build_engine(predicate)
  engine = KBS::Engine.new
  rule = KBS::Rule.new(
    "regex_benchmark",
    conditions: [KBS::Condition.new(:event, { code: predicate })]
  )
  engine.add_rule(rule)
  engine
end

results = {
  "Direct Regexp#match?" => measure(repeats) do
    samples.count { |code| code.match?(regexp) }
  end,
  "Direct String#start_with?" => measure(repeats) do
    samples.count { |code| code.start_with?("INV-") }
  end,
  "RETE regex predicate" => measure(repeats) do
    engine = build_engine(->(code) { code.match?(regexp) })
    samples.each { |code| engine.add_fact(:event, code: code) }
    engine.alpha_memories.values.first.items.length
  end,
  "RETE prefix predicate" => measure(repeats) do
    engine = build_engine(->(code) { code.start_with?("INV-") })
    samples.each { |code| engine.add_fact(:event, code: code) }
    engine.alpha_memories.values.first.items.length
  end
}

puts "Ruby #{RUBY_VERSION} (#{RUBY_ENGINE}), #{RUBY_PLATFORM}"
puts "#{iterations} assertions/comparisons per sample, #{repeats} samples; 50% expected matches"
results.each do |name, seconds|
  puts "%-30s %8.4fs %10.0f operations/s" % [name, seconds, iterations / seconds]
end
