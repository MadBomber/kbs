# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'test_redis_store'
require_relative 'test_hybrid_store'
require 'minitest/mock'
require 'redis'

# The Redis store tests flush the database they connect to. They must not
# touch Redis at all unless KBS_TEST_REDIS_URL opts them in.
class TestRedisTestSupport < Minitest::Test
  include RedisTestSupport

  def test_url_reads_the_env_var
    assert_equal 'redis://localhost:6399/15',
                 RedisTestSupport.url(RedisTestSupport::ENV_VAR => 'redis://localhost:6399/15')
  end

  def test_url_is_nil_when_the_env_var_is_unset_or_empty
    assert_nil RedisTestSupport.url({})
    assert_nil RedisTestSupport.url(RedisTestSupport::ENV_VAR => '')
  end

  def test_redis_test_connection_skips_without_connecting_when_not_opted_in
    fake_new = ->(*) { flunk 'built a Redis client without KBS_TEST_REDIS_URL' }

    Redis.stub(:new, fake_new) do
      assert_raises(Minitest::Skip) { redis_test_connection({}) }
    end
  end

  def test_redis_tests_skip_without_connecting_when_not_opted_in
    saved = ENV.delete('KBS_TEST_REDIS_URL')

    [TestRedisStore, TestHybridStore].each do |test_class|
      fake_new = ->(*) { flunk "#{test_class} built a Redis client without KBS_TEST_REDIS_URL" }

      Redis.stub(:new, fake_new) do
        assert_raises(Minitest::Skip) { test_class.new(:test_initialization).setup }
      end
    end
  ensure
    ENV['KBS_TEST_REDIS_URL'] = saved if saved
  end
end
