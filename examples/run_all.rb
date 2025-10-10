#!/usr/bin/env ruby
# frozen_string_literal: true

# Run all example files in the examples directory

require 'pathname'

# Get the directory where this script is located
examples_dir = Pathname.new(__FILE__).dirname

# Find all Ruby files except this one
example_files = Dir.glob(examples_dir.join('*.rb'))
                   .reject { |f| File.basename(f).start_with? 'run_all' }
                   .reject { |f| File.basename(f).end_with? '_dsl.rb' }
                   .sort

puts
puts "Running #{example_files.size} examples from #{examples_dir}"
puts
puts

example_files.each_with_index do |file, index|
  filename = File.basename(file)
  filename_size = filename.size + 6

  STDERR.puts "Running example #{index + 1}/#{example_files.size}: #{filename} ..."

  puts
  puts "=" * filename_size
  puts "## #{filename} ##"
  puts "=" * filename_size
  puts

  # Run the example
  system("ruby", file)

  exit_status = $?.exitstatus

  if exit_status != 0
    puts
    puts "⚠️  Example #{filename} exited with status #{exit_status}"
  end

  puts
end

puts
puts
puts "Completed running all #{example_files.size} examples"
puts
