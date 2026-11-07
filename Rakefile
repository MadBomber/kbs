# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

# Load test_helper (which starts SimpleCov) before minitest/autorun. Otherwise
# SimpleCov's at_exit hook runs before the tests and gates only load-time
# coverage; that fails the minimum, and its non-zero exit makes autorun skip
# the tests.
Minitest::TestTask.create do |t|
  t.test_prelude = %(require "test_helper")
end

task default: :test
