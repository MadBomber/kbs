# frozen_string_literal: true

require 'redis'
require 'json'
require 'securerandom'
require_relative 'store'

module KBS
  module Blackboard
    module Persistence
      class RedisStore < Store
        attr_reader :redis, :session_id

        def initialize(url: 'redis://localhost:6379/0', session_id: nil, redis: nil)
          @session_id = session_id || SecureRandom.uuid
          @redis = redis || Redis.new(url: url)
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

            if matches_pattern?(attributes, pattern)
              facts << {
                uuid: fact_data['uuid'],
                type: fact_data['type'].to_sym,
                attributes: attributes
              }
            end
          end

          facts
        end

        def query_facts(conditions = nil, params = [])
          # Redis doesn't support SQL queries
          # For complex queries, use get_facts with pattern matching
          # or implement custom Redis Lua scripts
          get_facts
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

        def vacuum
          # Remove retracted facts from Redis to free memory
          all_uuids = @redis.smembers('facts:all')

          all_uuids.each do |uuid|
            fact_data = @redis.hgetall("fact:#{uuid}")
            if fact_data['retracted'] == '1'
              # Calculate if fact is old enough to remove (e.g., > 30 days)
              retracted_at = fact_data['retracted_at'].to_f
              if Time.now.to_f - retracted_at > (30 * 24 * 60 * 60)
                type = fact_data['type']
                session_id = fact_data['session_id']

                @redis.multi do |pipeline|
                  pipeline.del("fact:#{uuid}")
                  pipeline.srem('facts:all', uuid)
                  pipeline.srem("facts:type:#{type}", uuid)
                  pipeline.srem("facts:session:#{session_id}", uuid) if session_id
                end
              end
            end
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

        def transaction(&block)
          @transaction_depth += 1
          begin
            if @transaction_depth == 1
              # Redis MULTI/EXEC happens in individual operations
              # This provides a consistent interface
              yield
            else
              yield
            end
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

        def matches_pattern?(attributes, pattern)
          pattern.all? do |key, value|
            if value.is_a?(Proc)
              attributes[key] && value.call(attributes[key])
            else
              attributes[key] == value
            end
          end
        end
      end
    end
  end
end
