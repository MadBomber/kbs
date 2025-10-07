#!/usr/bin/env ruby

require_relative '../lib/kbs/blackboard'

puts "Blackboard Memory System Demonstration"
puts "=" * 70

engine = KBS::Blackboard::Engine.new(db_path: 'knowledge_base.db')

puts "\nAdding persistent facts..."
sensor1 = engine.add_fact(:sensor, { location: "room_1", type: "temperature", value: 22 })
sensor2 = engine.add_fact(:sensor, { location: "room_2", type: "humidity", value: 65 })
alert = engine.add_fact(:alert, { level: "warning", message: "Check sensors" })

puts "Facts added with UUIDs:"
puts "  Sensor 1: #{sensor1.uuid}"
puts "  Sensor 2: #{sensor2.uuid}"
puts "  Alert: #{alert.uuid}"

puts "\nPosting messages to blackboard..."
engine.post_message("TemperatureMonitor", "sensor_data", { reading: 25, timestamp: Time.now }, priority: 5)
engine.post_message("HumidityMonitor", "sensor_data", { reading: 70, timestamp: Time.now }, priority: 3)
engine.post_message("SystemController", "commands", { action: "calibrate", target: "all_sensors" }, priority: 10)

puts "\nConsuming high-priority message..."
message = engine.consume_message("commands", "MainController")
puts "  Received: #{message[:content]}" if message

puts "\nUpdating sensor value..."
sensor1[:value] = 28

puts "\nDatabase Statistics:"
stats = engine.stats
stats.each do |key, value|
  puts "  #{key.to_s.gsub('_', ' ').capitalize}: #{value}"
end

puts "\nFact History (last 5 entries):"
history = engine.blackboard.get_history(limit: 5)
history.each do |entry|
  puts "  [#{entry[:timestamp].strftime('%H:%M:%S')}] #{entry[:action]}: #{entry[:fact_type]}(#{entry[:attributes]})"
end

puts "\nQuerying facts by type..."
sensors = engine.blackboard.get_facts(:sensor)
puts "  Found #{sensors.size} sensor(s)"
sensors.each { |s| puts "    - #{s}" }

puts "\n" + "=" * 70
puts "Blackboard persisted to: knowledge_base.db"
