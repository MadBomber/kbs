# frozen_string_literal: true

# redis is optional. Load it when present so callers can still use Redis
# after requiring kbs; #connect raises LoadError when a store needs it.
begin
  require 'redis'
rescue LoadError
  nil
end
require 'json'
require 'securerandom'
require_relative 'store'

module KBS
  module Blackboard
    module Persistence
      # Keeps blackboard facts in Redis.
      class RedisStore < Store
        attr_reader :redis, :session_id

        def initialize(url: 'redis://localhost:6379/0', session_id: nil, redis: nil)
          super()
          @session_id = session_id || SecureRandom.uuid
          @redis = redis || connect(url)
          @transaction_depth = 0
        end

        def add_fact(uuid, type, attributes)
          attributes_json = JSON.generate(attributes)
          timestamp = Time.now.to_f

          @redis.multi do |pipeline|
            pipeline.hset("fact:#{uuid}", {
              'uuid' => uuid,
              'type' => type.to_s,
              'attributes' => attributes_json,
              'session_id' => @session_id,
              'created_at' => timestamp,
              'updated_at' => timestamp,
              'retracted' => '0'
            })

            # Indexes
            pipeline.sadd('facts:active', uuid)
            pipeline.sadd("facts:type:#{type}", uuid)
            pipeline.sadd("facts:session:#{@session_id}", uuid) if @session_id
            pipeline.sadd('facts:all', uuid)
          end
        end

        def remove_fact(uuid)
          fact_data = @redis.hgetall("fact:#{uuid}")
          return nil if fact_data.empty? || fact_data['retracted'] == '1'

          type = fact_data['type'].to_sym
          attributes = JSON.parse(fact_data['attributes'], symbolize_names: true)

          @redis.multi do |pipeline|
            pipeline.hset("fact:#{uuid}", 'retracted', '1')
            pipeline.hset("fact:#{uuid}", 'retracted_at', Time.now.to_f)
            pipeline.srem('facts:active', uuid)
            pipeline.srem("facts:type:#{type}", uuid)
          end

          { type: type, attributes: attributes }
        end

        def update_fact(uuid, attributes)
          fact_data = @redis.hgetall("fact:#{uuid}")
          return nil if fact_data.empty? || fact_data['retracted'] == '1'

          attributes_json = JSON.generate(attributes)

          @redis.multi do |pipeline|
            pipeline.hset("fact:#{uuid}", 'attributes', attributes_json)
            pipeline.hset("fact:#{uuid}", 'updated_at', Time.now.to_f)
          end

          fact_data['type'].to_sym
        end

        def get_fact(uuid)
          fact_data = @redis.hgetall("fact:#{uuid}")
          return nil if fact_data.empty? || fact_data['retracted'] == '1'

          {
            uuid: fact_data['uuid'],
            type: fact_data['type'].to_sym,
            attributes: JSON.parse(fact_data['attributes'], symbolize_names: true)
          }
        end

        def get_facts(type = nil, pattern = {})
          # Get UUIDs from appropriate index
          uuids = if type
                    @redis.sinter('facts:active', "facts:type:#{type}")
                  else
                    @redis.smembers('facts:active')
                  end

          # Fetch and filter facts
          facts = []
          uuids.each do |uuid|
            fact_data = @redis.hgetall("fact:#{uuid}")
            next if fact_data.empty? || fact_data['retracted'] == '1'

            attributes = JSON.parse(fact_data['attributes'], symbolize_names: true)

            next unless matches_pattern?(attributes, pattern)
            facts << {
              uuid: fact_data['uuid'],
              type: fact_data['type'].to_sym,
              attributes: attributes
            }
          end

          facts
        end

        def query_facts(_conditions = nil, _params = [])
          raise NotImplementedError, "#{self.class} does not support SQL queries"
        end

        def register_knowledge_source(name, description: nil, topics: [])
          topics_json = JSON.generate(topics)

          @redis.hset("ks:#{name}", {
            'name' => name,
            'description' => description,
            'topics' => topics_json,
            'active' => '1',
            'registered_at' => Time.now.to_f
          })

          @redis.sadd('knowledge_sources:active', name)
        end

        def clear_session(session_id)
          uuids = @redis.smembers("facts:session:#{session_id}")

          uuids.each do |uuid|
            remove_fact(uuid)
          end

          @redis.del("facts:session:#{session_id}")
        end

        # How long a retracted fact is kept before vacuum removes it.
        RETENTION_SECONDS = 30 * 24 * 60 * 60

        # Removes retracted facts older than RETENTION_SECONDS from Redis
        # to free memory.
        def vacuum
          @redis.smembers('facts:all').each do |uuid|
            fact_data = @redis.hgetall("fact:#{uuid}")
            purge_fact(uuid, fact_data) if expired?(fact_data)
          end
        end

        def stats
          active_count = @redis.scard('facts:active')
          total_count = @redis.scard('facts:all')
          ks_count = @redis.scard('knowledge_sources:active')

          {
            total_facts: total_count,
            active_facts: active_count,
            knowledge_sources: ks_count
          }
        end

        def transaction(&)
          @transaction_depth += 1
          begin
            # Redis MULTI/EXEC happens in individual operations; this
            # provides a consistent interface.
            yield
          ensure
            @transaction_depth -= 1
          end
        end

        def close
          @redis.close if @redis
        end

        # Redis-specific helper to get connection for MessageQueue/AuditLog
        def connection
          @redis
        end

        private

        # Raises LoadError here, not at require time, when redis is missing.
        def connect(url)
          require 'redis'
          Redis.new(url: url)
        end

        # Whether a fact's hash says it was retracted long enough ago.
        def expired?(fact_data, now = Time.now.to_f)
          fact_data['retracted'] == '1' && now - fact_data['retracted_at'].to_f > RETENTION_SECONDS
        end

        # Deletes a fact's hash and takes its uuid out of every index.
        def purge_fact(uuid, fact_data)
          session_id = fact_data['session_id']
          @redis.multi do |pipeline|
            pipeline.del("fact:#{uuid}")
            pipeline.srem('facts:all', uuid)
            pipeline.srem("facts:type:#{fact_data['type']}", uuid)
            pipeline.srem("facts:session:#{session_id}", uuid) if session_id
          end
        end

        def matches_pattern?(attributes, pattern)
          pattern.all? do |key, value|
            actual = attributes[key]
            value.is_a?(Proc) ? actual && value.call(actual) : actual == value
          end
        end
      end
    end
  end
end
