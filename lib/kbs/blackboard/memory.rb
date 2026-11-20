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
        self.class.check_store(store) if store
        @session_id = store&.session_id || SecureRandom.uuid
        @observers = []
        @added_in_transaction = nil
        @store = store || Persistence::SqliteStore.new(db_path: db_path, session_id: @session_id)
        @message_queue, @audit_log = build_components
      end

      # Raises ArgumentError unless the memory can build its message queue
      # and audit log on `store`.
      def self.check_store(store)
        return if store.respond_to?(:connection) || store.respond_to?(:db)

        raise ArgumentError, "Store must respond to either :connection (Redis) or :db (SQLite)"
      end

      private

      # The message queue and audit log that go with the store. A store is
      # told apart by what it offers: a hybrid store keeps messages in
      # Redis and the audit log in SQLite, a store with a connection is
      # Redis, and one with a db is SQLite.
      def build_components
        if @store.respond_to?(:hybrid?) && @store.hybrid?
          hybrid_components
        elsif @store.respond_to?(:connection)
          redis_components
        else
          sqlite_components
        end
      end

      def hybrid_components
        require_relative 'redis_message_queue'
        [RedisMessageQueue.new(@store.connection), AuditLog.new(@store.db, @session_id)]
      end

      def redis_components
        require_relative 'redis_message_queue'
        require_relative 'redis_audit_log'
        connection = @store.connection
        [RedisMessageQueue.new(connection), RedisAuditLog.new(connection, @session_id)]
      end

      def sqlite_components
        database = @store.db
        [MessageQueue.new(database), AuditLog.new(database, @session_id)]
      end

      # A fact's uuid, given the fact or the uuid itself.
      def uuid_of(fact)
        fact.is_a?(Fact) ? fact.uuid : fact
      end

      # The Fact for a row the store returned.
      def fact_from(data)
        Fact.new(*data.values_at(:uuid, :type, :attributes), self)
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
        @added_in_transaction[uuid] = fact if @added_in_transaction
        notify_observers(:add, fact)
        fact
      end

      # @return [KBS::Blackboard::Fact, nil] the removed fact, or nil when
      #   it was not active
      def remove_fact(fact)
        uuid = uuid_of(fact)

        @store.transaction do
          result = @store.remove_fact(uuid)
          next unless result

          @audit_log.log_fact_change(uuid, result[:type], result[:attributes], 'REMOVE')

          fact_obj = Fact.new(uuid, result[:type], result[:attributes], self)
          @added_in_transaction&.delete(uuid)
          notify_observers(:remove, fact_obj)
          fact_obj
        end
      end

      def update_fact(fact, new_attributes)
        uuid = uuid_of(fact)

        @store.transaction do
          fact_type = @store.update_fact(uuid, new_attributes)

          if fact_type
            @audit_log.log_fact_change(uuid, fact_type, new_attributes, 'UPDATE')
          end
        end
      end

      # The fact with this uuid as the store holds it now, or nil.
      #
      # @param fact [KBS::Blackboard::Fact, String] a fact or its uuid
      def find_fact(fact)
        uuid = uuid_of(fact)
        data = @store.get_fact(uuid)
        data && Fact.new(uuid, data[:type], data[:attributes], self)
      end

      # Merges `changes` into a fact's attributes and tells the observers
      # it was removed and added again, so an engine matches the new
      # values. The uuid is kept.
      #
      # @return [KBS::Blackboard::Fact, nil] the fact with its new
      #   attributes, or nil when it is not in the store
      def modify_fact(fact, changes)
        current = find_fact(fact)
        return nil unless current

        # A Fact passed in still has its attributes as they were given;
        # the store's copy has been through JSON, which turns Symbol
        # values into Strings.
        attributes = (fact.is_a?(Fact) ? fact : current).attributes.merge(changes)
        update_fact(current, attributes)

        notify_observers(:remove, current)
        modified = Fact.new(current.uuid, current.type, attributes, self)
        notify_observers(:add, modified)
        modified
      end

      def get_facts(type = nil, pattern = {})
        fact_data = @store.get_facts(type, pattern)

        fact_data.map { |data| fact_from(data) }
      end

      # Alias for compatibility with WorkingMemory interface
      def facts
        get_facts
      end

      def query_facts(sql_conditions = nil, params = [])
        fact_data = @store.query_facts(sql_conditions, params)

        fact_data.map { |data| fact_from(data) }
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

      # Runs the block in a store transaction. When the block raises, the
      # facts it added that the store rolled back are removed from the
      # observers (an engine) as well. A store that cannot roll back, such
      # as Redis, keeps them, and so do the observers. Facts the block
      # removed or modified are not restored in the observers.
      def transaction(&)
        return @store.transaction(&) if @added_in_transaction

        @added_in_transaction = {}
        begin
          @store.transaction(&)
        rescue StandardError
          withdraw_rolled_back(@added_in_transaction.values)
          raise
        ensure
          @added_in_transaction = nil
        end
      end

      # Tells the observers each fact the store no longer holds was
      # removed, newest first.
      def withdraw_rolled_back(facts)
        facts.reverse_each do |fact|
          notify_observers(:remove, fact) unless @store.get_fact(fact.uuid)
        end
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
      alias db store
    end
  end
end
