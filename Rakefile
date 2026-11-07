# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

# Load test_helper (which starts SimpleCov) before minitest/autorun.
# Otherwise SimpleCov's at_exit hook runs first and exits before any test runs.
Minitest::TestTask.create do |t|
  t.test_prelude = %(require "test_helper")
end

task default: :test
