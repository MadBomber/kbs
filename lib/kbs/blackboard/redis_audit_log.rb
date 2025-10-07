# frozen_string_literal: true

require 'json'
require 'time'

module KBS
  module Blackboard
    # Redis-based audit log using lists for history
    class RedisAuditLog
      def initialize(redis, session_id)
        @redis = redis
        @session_id = session_id
      end

      def log_fact_change(fact_uuid, fact_type, attributes, action)
        attributes_json = attributes.is_a?(String) ? attributes : JSON.generate(attributes)
        timestamp = Time.now.to_f

        entry = {
          'fact_uuid' => fact_uuid,
          'fact_type' => fact_type.to_s,
          'attributes' => attributes_json,
          'action' => action,
          'timestamp' => timestamp,
          'session_id' => @session_id
        }

        entry_json = JSON.generate(entry)

        # Add to global history (as list - newest first)
        @redis.lpush('fact_history:all', entry_json)

        # Add to fact-specific history
        @redis.lpush("fact_history:#{fact_uuid}", entry_json)

        # Optionally limit history size (e.g., keep last 10000 entries)
        @redis.ltrim('fact_history:all', 0, 9999)
        @redis.ltrim("fact_history:#{fact_uuid}", 0, 999)
      end

      def log_rule_firing(rule_name, fact_uuids, bindings = {})
        timestamp = Time.now.to_f

        entry = {
          'rule_name' => rule_name,
          'fact_uuids' => JSON.generate(fact_uuids),
          'bindings' => JSON.generate(bindings),
          'fired_at' => timestamp,
          'session_id' => @session_id
        }

        entry_json = JSON.generate(entry)

        # Add to global rules fired list
        @redis.lpush('rules_fired:all', entry_json)

        # Add to rule-specific history
        @redis.lpush("rules_fired:#{rule_name}", entry_json)

        # Limit size
        @redis.ltrim('rules_fired:all', 0, 9999)
        @redis.ltrim("rules_fired:#{rule_name}", 0, 999)
      end

      def fact_history(fact_uuid = nil, limit: 100)
        key = fact_uuid ? "fact_history:#{fact_uuid}" : 'fact_history:all'
        entries_json = @redis.lrange(key, 0, limit - 1)

        entries_json.map do |entry_json|
          entry = JSON.parse(entry_json, symbolize_names: true)
          {
            fact_uuid: entry[:fact_uuid],
            fact_type: entry[:fact_type].to_sym,
            attributes: JSON.parse(entry[:attributes], symbolize_names: true),
            action: entry[:action],
            timestamp: Time.at(entry[:timestamp]),
            session_id: entry[:session_id]
          }
        end
      end

      def rule_firings(rule_name = nil, limit: 100)
        key = rule_name ? "rules_fired:#{rule_name}" : 'rules_fired:all'
        entries_json = @redis.lrange(key, 0, limit - 1)

        entries_json.map do |entry_json|
          entry = JSON.parse(entry_json, symbolize_names: true)
          {
            rule_name: entry[:rule_name],
            fact_uuids: JSON.parse(entry[:fact_uuids]),
            bindings: JSON.parse(entry[:bindings], symbolize_names: true),
            fired_at: Time.at(entry[:fired_at]),
            session_id: entry[:session_id]
          }
        end
      end

      def stats
        rules_fired_count = @redis.llen('rules_fired:all')

        {
          rules_fired: rules_fired_count
        }
      end
    end
  end
end
