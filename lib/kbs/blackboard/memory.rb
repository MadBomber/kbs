# frozen_string_literal: true

require 'securerandom'
require_relative 'persistence/store'
require_relative 'persistence/sqlite_store'
require_relative 'message_queue'
require_relative 'audit_log'
require_relative 'fact'

module KBS
  module Blackboard
    # The Blackboard Memory - central workspace for facts and coordination
    class Memory
      attr_reader :session_id, :store, :message_queue, :audit_log

      def initialize(db_path: ':memory:', store: nil)
        @session_id = SecureRandom.uuid
        @observers = []

        # Use provided store or create default SqliteStore
        @store = store || Persistence::SqliteStore.new(
          db_path: db_path,
          session_id: @session_id
        )

        # Initialize composed components based on store type
        setup_components
      end

      private

      def setup_components
        # Detect store type and create appropriate MessageQueue and AuditLog
        if @store.respond_to?(:hybrid?) && @store.hybrid?
          # Hybrid store: Redis for messages, SQLite for audit
          require_relative 'redis_message_queue'
          @message_queue = RedisMessageQueue.new(@store.connection)
          @audit_log = AuditLog.new(@store.db, @session_id)
        elsif @store.respond_to?(:connection)
          # Pure Redis store
          require_relative 'redis_message_queue'
          require_relative 'redis_audit_log'
          @message_queue = RedisMessageQueue.new(@store.connection)
          @audit_log = RedisAuditLog.new(@store.connection, @session_id)
        elsif @store.respond_to?(:db)
          # Pure SQLite store
          @message_queue = MessageQueue.new(@store.db)
          @audit_log = AuditLog.new(@store.db, @session_id)
        else
          raise ArgumentError, "Store must respond to either :connection (Redis) or :db (SQLite)"
        end
      end

      public

      # Fact Management
      def add_fact(type, attributes = {})
        uuid = SecureRandom.uuid

        @store.transaction do
          @store.add_fact(uuid, type, attributes)
          @audit_log.log_fact_change(uuid, type, attributes, 'ADD')
        end

        fact = Fact.new(uuid, type, attributes, self)
        notify_observers(:add, fact)
        fact
      end

      def remove_fact(fact)
        uuid = fact.is_a?(Fact) ? fact.uuid : fact

        @store.transaction do
          result = @store.remove_fact(uuid)

          if result
            @audit_log.log_fact_change(uuid, result[:type], result[:attributes], 'REMOVE')

            fact_obj = Fact.new(uuid, result[:type], result[:attributes], self)
            notify_observers(:remove, fact_obj)
          end
        end
      end

      def update_fact(fact, new_attributes)
        uuid = fact.is_a?(Fact) ? fact.uuid : fact

        @store.transaction do
          fact_type = @store.update_fact(uuid, new_attributes)

          if fact_type
            @audit_log.log_fact_change(uuid, fact_type, new_attributes, 'UPDATE')
          end
        end
      end

      def get_facts(type = nil, pattern = {})
        fact_data = @store.get_facts(type, pattern)

        fact_data.map do |data|
          Fact.new(data[:uuid], data[:type], data[:attributes], self)
        end
      end

      # Alias for compatibility with WorkingMemory interface
      def facts
        get_facts
      end

      def query_facts(sql_conditions = nil, params = [])
        fact_data = @store.query_facts(sql_conditions, params)

        fact_data.map do |data|
          Fact.new(data[:uuid], data[:type], data[:attributes], self)
        end
      end

      # Message Queue delegation
      def post_message(sender, topic, content, priority: 0)
        @message_queue.post(sender, topic, content, priority: priority)
      end

      def consume_message(topic, consumer)
        @store.transaction do
          @message_queue.consume(topic, consumer)
        end
      end

      def peek_messages(topic, limit: 10)
        @message_queue.peek(topic, limit: limit)
      end

      # Knowledge Source registry
      def register_knowledge_source(name, description: nil, topics: [])
        @store.register_knowledge_source(name, description: description, topics: topics)
      end

      # Audit Log delegation
      def log_rule_firing(rule_name, fact_uuids, bindings = {})
        @audit_log.log_rule_firing(rule_name, fact_uuids, bindings)
      end

      def get_history(fact_uuid = nil, limit: 100)
        @audit_log.fact_history(fact_uuid, limit: limit)
      end

      def get_rule_firings(rule_name = nil, limit: 100)
        @audit_log.rule_firings(rule_name, limit: limit)
      end

      # Observer pattern
      def add_observer(observer)
        @observers << observer
      end

      def notify_observers(action, fact)
        @observers.each { |obs| obs.update(action, fact) }
      end

      # Session management
      def clear_session
        @store.clear_session(@session_id)
      end

      def transaction(&block)
        @store.transaction(&block)
      end

      # Statistics
      def stats
        store_stats = @store.stats
        message_stats = @message_queue.stats
        audit_stats = @audit_log.stats

        store_stats.merge(message_stats).merge(audit_stats)
      end

      # Maintenance
      def vacuum
        @store.vacuum
      end

      def close
        @store.close
      end

      # For backward compatibility with ReteEngine
      alias_method :db, :store
    end
  end
end
