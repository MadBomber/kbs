#!/usr/bin/env ruby

require_relative '../lib/kbs'

puts "Rule Source Introspection Demo"
puts "=" * 60
puts
puts "This demo shows how to retrieve the DSL source code"
puts "of any rule by name using rule_source / print_rule_source."
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

  rule "flat_tire" do
    on :symptom, problem: "pulling to side"
    on :symptom, problem: "low tire pressure"

    perform do |facts, bindings|
      puts "DIAGNOSIS: Flat or low tire"
      puts "RECOMMENDATION: Check and inflate or replace tire"
    end
  end
end

# ── Show all rule names ──────────────────────────────────────

puts "Available rules: #{kb.rules.keys.join(', ')}"
puts

# ── Print source for each rule ───────────────────────────────

kb.rules.each_key do |name|
  puts "-" * 60
  puts "Source for '#{name}':"
  puts "-" * 60
  kb.print_rule_source(name)
  puts
end

# ── Programmatic access via rule_source ──────────────────────

puts "-" * 60
puts "Programmatic access — rule_source returns a String:"
puts "-" * 60

source = kb.rule_source("overheating")
puts "  class:  #{source.class}"
puts "  lines:  #{source.lines.count}"
puts "  includes 'without': #{source.include?('without')}"
puts

# ── Unknown rule ─────────────────────────────────────────────

puts "-" * 60
puts "Requesting source for a rule that doesn't exist:"
puts "-" * 60
kb.print_rule_source("nonexistent")
puts
puts "rule_source returns: #{kb.rule_source('nonexistent').inspect}"
