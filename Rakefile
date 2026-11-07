# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

# test_helper starts SimpleCov, then loads minitest/autorun. Loading autorun
# first lets SimpleCov's at_exit hook run first and exit before any test runs.
Minitest::TestTask.create do |t|
  t.framework = %(require "test_helper")
end

task default: :test
