#!/usr/bin/env ruby

require_relative '../lib/kbs'

puts "Rule Source Introspection Demo"
puts "=" * 60
puts
puts "KBS can show the source of any rule — whether it was defined"
puts "in a file (exact source) or built dynamically at runtime"
puts "(reconstructed from bytecode via KBS::Decompiler)."
puts

# ── Part 1: File-defined rules ───────────────────────────────

puts "PART 1: File-Defined Rules"
puts "-" * 60
puts

kb = KBS.knowledge_base do
  rule "dead_battery" do
    on :symptom, problem: "won't start"
    on :symptom, problem: "no lights"

    perform do |facts, bindings|
      puts "DIAGNOSIS: Dead battery"
      puts "RECOMMENDATION: Replace or jump-start the battery"
    end
  end

  rule "overheating" do
    on :symptom, problem: "high temperature"
    on :symptom, problem: "steam from hood"
    without :symptom, problem: "coolant leak"

    perform do |facts, bindings|
      puts "DIAGNOSIS: Engine overheating (no coolant leak)"
      puts "RECOMMENDATION: Check radiator and cooling system"
    end
  end
end

kb.rules.each_key do |name|
  puts "Source for '#{name}':"
  puts
  kb.print_rule_source(name)
  puts
end

# ── Part 2: Dynamically-created rules ────────────────────────

puts
puts "PART 2: Dynamically-Created Rules"
puts "-" * 60
puts
puts "These rules have no source file — KBS reconstructs them"
puts "from their internal state using YARV bytecode decompilation."
puts

# Simulate what an AI agent framework might do: build rules at
# runtime from configuration data, user input, or LLM output.

dynamic_kb = KBS::DSL::KnowledgeBase.new

# Rule with lambda condition helpers
builder = KBS::DSL::RuleBuilder.new("high_temp_alert")
builder.desc "Fire when temperature exceeds safe threshold"
builder.priority 5
builder.on :sensor, location: "server_room", temp: ->(v) { v > 85 }
builder.without :alert, type: :cooling_active
builder.perform { |facts| puts "ALERT: Server room temperature critical!" }

rule = builder.build
dynamic_kb.instance_variable_get(:@rule_builders)["high_temp_alert"] = builder
dynamic_kb.instance_variable_get(:@rules)["high_temp_alert"] = rule
dynamic_kb.engine.add_rule(rule)

# Rule with multiple proc-based conditions
builder2 = KBS::DSL::RuleBuilder.new("buy_signal")
builder2.on :stock, price: ->(v) { v < 150 }, volume: ->(v) { v > 1_000_000 }
builder2.without :position, status: :open
builder2.perform { |facts| puts "BUY signal triggered" }

rule2 = builder2.build
dynamic_kb.instance_variable_get(:@rule_builders)["buy_signal"] = builder2
dynamic_kb.instance_variable_get(:@rules)["buy_signal"] = rule2
dynamic_kb.engine.add_rule(rule2)

["high_temp_alert", "buy_signal"].each do |name|
  puts "Reconstructed source for '#{name}':"
  puts
  dynamic_kb.print_rule_source(name)
  puts
end

# ── Part 3: Decompiler standalone ─────────────────────────────

puts
puts "PART 3: KBS::Decompiler Standalone"
puts "-" * 60
puts
puts "The decompiler works on any Proc or Lambda:"
puts

examples = {
  "lambda"  => ->(x) { x * 2 + 1 },
  "proc"    => proc { |a, b| a > b },
  "complex" => ->(items) { items.select { |x| x > 0 }.map { |x| x * 2 } },
}

examples.each do |label, pr|
  puts "  #{label}:"
  puts "    decompile       => #{KBS::Decompiler.new(pr).decompile}"
  puts "    decompile_block => #{KBS::Decompiler.new(pr).decompile_block}"
  puts
end

# ── Part 4: Unknown rule ──────────────────────────────────────

puts "PART 4: Unknown Rule"
puts "-" * 60
puts
kb.print_rule_source("nonexistent")
puts "  rule_source returns: #{kb.rule_source('nonexistent').inspect}"
