# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'

# redis is a development dependency only, so the SQLite blackboard must work
# for users who never installed it.
class TestOptionalRedis < Minitest::Test
  LIB = File.expand_path('../lib', __dir__)

  # Makes `require 'redis'` fail, as it does when the redis gem is absent.
  HIDE_REDIS = <<~RUBY
    module Kernel
      alias_method :__kbs_test_require, :require
      def require(name)
        raise LoadError, 'cannot load such file -- redis' if name == 'redis'
        __kbs_test_require(name)
      end
    end
  RUBY

  def run_without_redis(code)
    Open3.capture2e(RbConfig.ruby, '-I', LIB, '-e', HIDE_REDIS + code)
  end

  def test_sqlite_blackboard_works_without_the_redis_gem
    output, status = run_without_redis(<<~RUBY)
      require 'kbs/blackboard'
      memory = KBS::Blackboard::Memory.new
      memory.add_fact(:sensor, temp: 22)
      print memory.get_facts(:sensor).size
    RUBY

    assert status.success?, output
    assert_equal '1', output
  end

  def test_redis_store_still_needs_the_redis_gem
    output, status = run_without_redis(<<~RUBY)
      require 'kbs/blackboard'
      KBS::Blackboard::Persistence::RedisStore.new
    RUBY

    refute status.success?
    assert_match(/cannot load such file -- redis/, output)
  end
end
