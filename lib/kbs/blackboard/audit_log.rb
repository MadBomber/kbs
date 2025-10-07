# frozen_string_literal: true

require 'json'
require 'time'

module KBS
  module Blackboard
    class AuditLog
      def initialize(db, session_id)
        @db = db
        @session_id = session_id
        setup_tables
      end

      def setup_tables
        @db.execute_batch <<-SQL
          CREATE TABLE IF NOT EXISTS fact_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fact_uuid TEXT NOT NULL,
            fact_type TEXT NOT NULL,
            attributes TEXT NOT NULL,
            action TEXT NOT NULL,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            session_id TEXT
          );

          CREATE TABLE IF NOT EXISTS rules_fired (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_name TEXT NOT NULL,
            fact_uuids TEXT NOT NULL,
            bindings TEXT,
            fired_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            session_id TEXT
          );
        SQL

        @db.execute_batch <<-SQL
          CREATE INDEX IF NOT EXISTS idx_fact_history_uuid ON fact_history(fact_uuid);
          CREATE INDEX IF NOT EXISTS idx_rules_fired_session ON rules_fired(session_id);
        SQL
      end

      def log_fact_change(fact_uuid, fact_type, attributes, action)
        attributes_json = attributes.is_a?(String) ? attributes : JSON.generate(attributes)

        @db.execute(
          "INSERT INTO fact_history (fact_uuid, fact_type, attributes, action, session_id) VALUES (?, ?, ?, ?, ?)",
          [fact_uuid, fact_type.to_s, attributes_json, action, @session_id]
        )
      end

      def log_rule_firing(rule_name, fact_uuids, bindings = {})
        @db.execute(
          "INSERT INTO rules_fired (rule_name, fact_uuids, bindings, session_id) VALUES (?, ?, ?, ?)",
          [rule_name, JSON.generate(fact_uuids), JSON.generate(bindings), @session_id]
        )
      end

      def fact_history(fact_uuid = nil, limit: 100)
        if fact_uuid
          results = @db.execute(
            "SELECT * FROM fact_history WHERE fact_uuid = ? ORDER BY timestamp DESC, id DESC LIMIT ?",
            [fact_uuid, limit]
          )
        else
          results = @db.execute(
            "SELECT * FROM fact_history ORDER BY timestamp DESC, id DESC LIMIT ?",
            [limit]
          )
        end

        results.map do |row|
          {
            fact_uuid: row['fact_uuid'],
            fact_type: row['fact_type'].to_sym,
            attributes: JSON.parse(row['attributes'], symbolize_names: true),
            action: row['action'],
            timestamp: Time.parse(row['timestamp']),
            session_id: row['session_id']
          }
        end
      end

      def rule_firings(rule_name = nil, limit: 100)
        if rule_name
          results = @db.execute(
            "SELECT * FROM rules_fired WHERE rule_name = ? ORDER BY fired_at DESC LIMIT ?",
            [rule_name, limit]
          )
        else
          results = @db.execute(
            "SELECT * FROM rules_fired ORDER BY fired_at DESC LIMIT ?",
            [limit]
          )
        end

        results.map do |row|
          {
            rule_name: row['rule_name'],
            fact_uuids: JSON.parse(row['fact_uuids']),
            bindings: row['bindings'] ? JSON.parse(row['bindings'], symbolize_names: true) : {},
            fired_at: Time.parse(row['fired_at']),
            session_id: row['session_id']
          }
        end
      end

      def stats
        {
          rules_fired: @db.get_first_value("SELECT COUNT(*) FROM rules_fired")
        }
      end
    end
  end
end
