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

# The Redis store tests flush the database they connect to, so they run only
# when KBS_TEST_REDIS_URL names a disposable one, such as a throwaway server:
#   KBS_TEST_REDIS_URL=redis://localhost:6399/15 bundle exec rake test
module RedisTestSupport
  ENV_VAR = 'KBS_TEST_REDIS_URL'

  def self.url(env = ENV)
    url = env[ENV_VAR]
    url unless url.nil? || url.empty?
  end

  # Skips the calling test unless the Redis tests were opted in.
  def redis_test_connection(env = ENV)
    url = RedisTestSupport.url(env)
    skip "set #{ENV_VAR} to a disposable Redis database to run the Redis tests" unless url

    require 'redis'
    Redis.new(url: url)
  end
end
