# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in kbs.gemspec
gemspec

gem "irb"

gem "fasterer", require: false
gem "minitest", "~> 5.16"
gem "redis", "~> 5.0"
gem "rubocop", require: false
gem "simplecov", "~> 0.22", require: false

gem 'debug_me'

# The CSV trading examples require csv, a bundled (not default) gem since Ruby 3.4.
gem "csv"

# The scripts in benchmarks/ require benchmark, a bundled (not default) gem since Ruby 3.5.
gem "benchmark"

# The AI examples (examples/ai_enhanced_kbs*.rb) reach a local LLM through RubyLLM:
# LM Studio (`lms server start`) or Apple's on-device model (`apfel --serve`).
gem "ruby_llm", "~> 2.2.3"
gem "ruby_llm-providers-lms", require: false
gem "ruby_llm-providers-apfel", require: false
