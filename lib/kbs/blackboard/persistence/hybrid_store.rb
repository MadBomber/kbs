# frozen_string_literal: true

require 'securerandom'
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
        # The SQLite tables the audit log writes to.
        AUDIT_TABLES = %w[fact_history rules_fired].freeze

        attr_reader :redis_store, :sqlite_store, :session_id

        def initialize(
          redis_url: 'redis://localhost:6379/0',
          redis: nil,
          db_path: 'audit.db',
          session_id: nil
        )
          super()
          @session_id = session_id || SecureRandom.uuid

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

        # The Redis store's stats, plus :audit_records from SQLite.
        def stats
          @redis_store.stats.merge(audit_records: audit_record_count)
        end

        # Rows the audit log has written to SQLite: fact changes plus rule
        # firings. Zero before a Memory has created the audit tables.
        def audit_record_count
          AUDIT_TABLES.sum { |table| row_count(table) }
        end

        def vacuum
          @redis_store.vacuum
          @sqlite_store.vacuum
        end

        def transaction(&)
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

        # The number of rows in a SQLite table, or 0 when it does not exist.
        def row_count(table)
          exists = db.get_first_value("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?", [table])
          exists.zero? ? 0 : db.get_first_value("SELECT COUNT(*) FROM #{table}")
        end
      end
    end
  end
end
