#!/usr/bin/env ruby

require_relative '../lib/kbs'

puts "Creating a simple expert system for diagnosing car problems..."
puts "-" * 60

kb = KBS.knowledge_base do
  rule "dead_battery" do
    on :symptom, problem: "won't start"
    on :symptom, problem: "no lights"

    perform do |facts, bindings|
      puts "DIAGNOSIS: Dead battery - The car won't start and has no lights"
      puts "RECOMMENDATION: Jump start the battery or replace it"
    end
  end

  rule "flat_tire" do
    on :symptom, problem: "pulling to side"
    on :symptom, problem: "low tire pressure"

    perform do |facts, bindings|
      puts "DIAGNOSIS: Flat or low tire"
      puts "RECOMMENDATION: Check tire pressure and inflate or replace tire"
    end
  end

  rule "overheating" do
    on :symptom, problem: "high temperature"
    on :symptom, problem: "steam from hood"
    without.on :symptom, problem: "coolant leak"

    perform do |facts, bindings|
      puts "DIAGNOSIS: Engine overheating (no coolant leak detected)"
      puts "RECOMMENDATION: Check radiator and cooling system"
    end
  end
end

puts "\nAdding symptoms..."
kb.fact :symptom, { problem: "won't start", severity: "high" }
kb.fact :symptom, { problem: "no lights", severity: "high" }

puts "\nRunning inference engine..."
kb.run

puts "\n" + "-" * 60
puts "\nAdding more symptoms..."
kb.fact :symptom, { problem: "high temperature", severity: "critical" }
kb.fact :symptom, { problem: "steam from hood", severity: "high" }

puts "\nRunning inference engine again..."
kb.run
