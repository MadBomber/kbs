# frozen_string_literal: true

require_relative 'store'
require_relative 'redis_store'
require_relative 'sqlite_store'

module KBS
  module Blackboard
    module Persistence
      # Hybrid store combining Redis (facts, messages) with SQLite (audit trail)
      #
      # Benefits:
      # - Fast in-memory fact access via Redis
      # - Durable audit trail via SQLite
      # - Best of both worlds for production systems
      class HybridStore < Store
        attr_reader :redis_store, :sqlite_store, :session_id

        def initialize(
          redis_url: 'redis://localhost:6379/0',
          redis: nil,
          db_path: 'audit.db',
          session_id: nil
        )
          @session_id = session_id

          # Redis for hot data (facts, messages)
          @redis_store = RedisStore.new(
            url: redis_url,
            redis: redis,
            session_id: @session_id
          )

          # SQLite for cold data (audit trail)
          @sqlite_store = SqliteStore.new(
            db_path: db_path,
            session_id: @session_id
          )
        end

        # Fact operations delegated to Redis (fast)
        def add_fact(uuid, type, attributes)
          @redis_store.add_fact(uuid, type, attributes)
        end

        def remove_fact(uuid)
          @redis_store.remove_fact(uuid)
        end

        def update_fact(uuid, attributes)
          @redis_store.update_fact(uuid, attributes)
        end

        def get_fact(uuid)
          @redis_store.get_fact(uuid)
        end

        def get_facts(type = nil, pattern = {})
          @redis_store.get_facts(type, pattern)
        end

        def query_facts(conditions = nil, params = [])
          @redis_store.query_facts(conditions, params)
        end

        def register_knowledge_source(name, description: nil, topics: [])
          @redis_store.register_knowledge_source(name, description: description, topics: topics)
        end

        def clear_session(session_id)
          @redis_store.clear_session(session_id)
        end

        # Stats combined from both stores
        def stats
          redis_stats = @redis_store.stats
          sqlite_stats = @sqlite_store.stats

          # Prefer Redis for fact counts (authoritative)
          redis_stats.merge(
            audit_records: sqlite_stats[:total_facts] # SQLite tracks audit records
          )
        end

        def vacuum
          @redis_store.vacuum
          @sqlite_store.vacuum
        end

        def transaction(&block)
          # Redis and SQLite transactions are separate
          # Execute block in context of both
          yield
        end

        def close
          @redis_store.close
          @sqlite_store.close
        end

        # Provide access to both connections for MessageQueue/AuditLog
        # Memory class will detect hybrid store and use appropriate components
        def connection
          @redis_store.connection
        end

        def db
          @sqlite_store.db
        end

        # Helper to check if this is a hybrid store
        def hybrid?
          true
        end
      end
    end
  end
end
