# frozen_string_literal: true

# SimpleCov must be loaded before application code
require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter '/examples/'
  add_group 'Core RETE', 'lib/kbs'
  add_group 'DSL', 'lib/kbs/dsl'

  # Coverage thresholds (temporarily lowered during development)
  minimum_coverage 35
  # minimum_coverage_by_file temporarily disabled during test suite development
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "kbs"
require "kbs/blackboard"

require "minitest/autorun"
require "minitest/pride"
