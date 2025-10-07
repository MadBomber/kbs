# frozen_string_literal: true

require 'sqlite3'
require 'json'
require_relative 'store'

module KBS
  module Blackboard
    module Persistence
      class SqliteStore < Store
        attr_reader :db, :db_path, :session_id

        def initialize(db_path: ':memory:', session_id: nil)
          @db_path = db_path
          @session_id = session_id
          @transaction_depth = 0
          setup_database
        end

        def setup_database
          @db = SQLite3::Database.new(@db_path)
          @db.results_as_hash = true
          create_tables
          create_indexes
          setup_triggers
        end

        def create_tables
          @db.execute_batch <<-SQL
            CREATE TABLE IF NOT EXISTS facts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              uuid TEXT UNIQUE NOT NULL,
              fact_type TEXT NOT NULL,
              attributes TEXT NOT NULL,
              fact_timestamp TIMESTAMP,
              market_timestamp TIMESTAMP,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              session_id TEXT,
              retracted BOOLEAN DEFAULT 0,
              retracted_at TIMESTAMP,
              data_source TEXT,
              market_session TEXT
            );

            CREATE TABLE IF NOT EXISTS knowledge_sources (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT UNIQUE NOT NULL,
              description TEXT,
              topics TEXT,
              active BOOLEAN DEFAULT 1,
              registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
          SQL
        end

        def create_indexes
          @db.execute_batch <<-SQL
            CREATE INDEX IF NOT EXISTS idx_facts_type ON facts(fact_type);
            CREATE INDEX IF NOT EXISTS idx_facts_session ON facts(session_id);
            CREATE INDEX IF NOT EXISTS idx_facts_retracted ON facts(retracted);
            CREATE INDEX IF NOT EXISTS idx_facts_timestamp ON facts(fact_timestamp);
            CREATE INDEX IF NOT EXISTS idx_facts_market_timestamp ON facts(market_timestamp);
            CREATE INDEX IF NOT EXISTS idx_facts_market_session ON facts(market_session);
          SQL
        end

        def setup_triggers
          @db.execute_batch <<-SQL
            CREATE TRIGGER IF NOT EXISTS update_fact_timestamp
            AFTER UPDATE ON facts
            BEGIN
              UPDATE facts SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
            END;
          SQL
        end

        def add_fact(uuid, type, attributes)
          attributes_json = JSON.generate(attributes)

          @db.execute(
            "INSERT INTO facts (uuid, fact_type, attributes, session_id) VALUES (?, ?, ?, ?)",
            [uuid, type.to_s, attributes_json, @session_id]
          )
        end

        def remove_fact(uuid)
          result = @db.get_first_row(
            "SELECT fact_type, attributes FROM facts WHERE uuid = ? AND retracted = 0",
            [uuid]
          )

          if result
            @db.execute(
              "UPDATE facts SET retracted = 1, retracted_at = CURRENT_TIMESTAMP WHERE uuid = ?",
              [uuid]
            )

            {
              type: result['fact_type'].to_sym,
              attributes: JSON.parse(result['attributes'], symbolize_names: true)
            }
          end
        end

        def update_fact(uuid, attributes)
          attributes_json = JSON.generate(attributes)

          @db.execute(
            "UPDATE facts SET attributes = ? WHERE uuid = ? AND retracted = 0",
            [attributes_json, uuid]
          )

          get_fact_type(uuid)
        end

        def get_fact(uuid)
          result = @db.get_first_row(
            "SELECT * FROM facts WHERE uuid = ? AND retracted = 0",
            [uuid]
          )

          if result
            {
              uuid: result['uuid'],
              type: result['fact_type'].to_sym,
              attributes: JSON.parse(result['attributes'], symbolize_names: true)
            }
          end
        end

        def get_facts(type = nil, pattern = {})
          query = "SELECT * FROM facts WHERE retracted = 0"
          params = []

          if type
            query += " AND fact_type = ?"
            params << type.to_s
          end

          results = @db.execute(query, params)

          results.map do |row|
            attributes = JSON.parse(row['attributes'], symbolize_names: true)

            if matches_pattern?(attributes, pattern)
              {
                uuid: row['uuid'],
                type: row['fact_type'].to_sym,
                attributes: attributes
              }
            end
          end.compact
        end

        def query_facts(sql_conditions = nil, params = [])
          query = "SELECT * FROM facts WHERE retracted = 0"
          query += " AND #{sql_conditions}" if sql_conditions

          results = @db.execute(query, params)

          results.map do |row|
            {
              uuid: row['uuid'],
              type: row['fact_type'].to_sym,
              attributes: JSON.parse(row['attributes'], symbolize_names: true)
            }
          end
        end

        def register_knowledge_source(name, description: nil, topics: [])
          topics_json = JSON.generate(topics)

          @db.execute(
            "INSERT OR REPLACE INTO knowledge_sources (name, description, topics) VALUES (?, ?, ?)",
            [name, description, topics_json]
          )
        end

        def clear_session(session_id)
          @db.execute(
            "UPDATE facts SET retracted = 1, retracted_at = CURRENT_TIMESTAMP WHERE session_id = ?",
            [session_id]
          )
        end

        def vacuum
          @db.execute("VACUUM")
        end

        def stats
          {
            total_facts: @db.get_first_value("SELECT COUNT(*) FROM facts"),
            active_facts: @db.get_first_value("SELECT COUNT(*) FROM facts WHERE retracted = 0"),
            knowledge_sources: @db.get_first_value("SELECT COUNT(*) FROM knowledge_sources WHERE active = 1")
          }
        end

        def transaction(&block)
          @transaction_depth += 1
          result = nil
          begin
            if @transaction_depth == 1
              @db.transaction do
                result = yield
              end
            else
              result = yield
            end
          ensure
            @transaction_depth -= 1
          end
          result
        end

        def close
          @db.close if @db
        end

        private

        def get_fact_type(uuid)
          result = @db.get_first_row(
            "SELECT fact_type FROM facts WHERE uuid = ?",
            [uuid]
          )
          result ? result['fact_type'].to_sym : nil
        end

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
