#!/usr/bin/env ruby

require_relative '../lib/kbs'

engine = KBS::Engine.new

puts "Creating a simple expert system for diagnosing car problems..."
puts "-" * 60

rule1 = KBS::Rule.new(
  "dead_battery",
  conditions: [
    KBS::Condition.new(:symptom, { problem: "won't start" }),
    KBS::Condition.new(:symptom, { problem: "no lights" })
  ],
  action: lambda do |facts, bindings|
    puts "DIAGNOSIS: Dead battery - The car won't start and has no lights"
    puts "RECOMMENDATION: Jump start the battery or replace it"
  end
)

rule2 = KBS::Rule.new(
  "flat_tire",
  conditions: [
    KBS::Condition.new(:symptom, { problem: "pulling to side" }),
    KBS::Condition.new(:symptom, { problem: "low tire pressure" })
  ],
  action: lambda do |facts, bindings|
    puts "DIAGNOSIS: Flat or low tire"
    puts "RECOMMENDATION: Check tire pressure and inflate or replace tire"
  end
)

rule3 = KBS::Rule.new(
  "overheating",
  conditions: [
    KBS::Condition.new(:symptom, { problem: "high temperature" }),
    KBS::Condition.new(:symptom, { problem: "steam from hood" }, negated: false),
    KBS::Condition.new(:symptom, { problem: "coolant leak" }, negated: true)
  ],
  action: lambda do |facts, bindings|
    puts "DIAGNOSIS: Engine overheating (no coolant leak detected)"
    puts "RECOMMENDATION: Check radiator and cooling system"
  end
)

engine.add_rule(rule1)
engine.add_rule(rule2)
engine.add_rule(rule3)

puts "\nAdding symptoms..."
engine.add_fact(:symptom, { problem: "won't start", severity: "high" })
engine.add_fact(:symptom, { problem: "no lights", severity: "high" })

puts "\nRunning inference engine..."
engine.run

puts "\n" + "-" * 60
puts "\nAdding more symptoms..."
engine.add_fact(:symptom, { problem: "high temperature", severity: "critical" })
engine.add_fact(:symptom, { problem: "steam from hood", severity: "high" })

puts "\nRunning inference engine again..."
engine.run
