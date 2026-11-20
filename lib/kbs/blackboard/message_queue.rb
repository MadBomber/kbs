# frozen_string_literal: true

require 'json'
require 'time'

module KBS
  module Blackboard
    # A priority message queue between knowledge sources, kept in SQLite.
    class MessageQueue
      def initialize(db)
        @db = db
        setup_table
      end

      def setup_table
        @db.execute_batch <<-SQL
          CREATE TABLE IF NOT EXISTS blackboard_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            topic TEXT NOT NULL,
            content TEXT NOT NULL,
            priority INTEGER DEFAULT 0,
            posted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            consumed BOOLEAN DEFAULT 0,
            consumed_by TEXT,
            consumed_at TIMESTAMP
          );
        SQL

        @db.execute <<-SQL
          CREATE INDEX IF NOT EXISTS idx_messages_topic ON blackboard_messages(topic);
        SQL

        @db.execute <<-SQL
          CREATE INDEX IF NOT EXISTS idx_messages_consumed ON blackboard_messages(consumed);
        SQL
      end

      def post(sender, topic, content, priority: 0)
        content_json = content.is_a?(String) ? content : JSON.generate(content)

        @db.execute(
          "INSERT INTO blackboard_messages (sender, topic, content, priority) VALUES (?, ?, ?, ?)",
          [sender.to_s, topic.to_s, content_json, priority]
        )
      end

      def consume(topic, consumer)
        result = nil

        loop do
          result = @db.get_first_row(
            "SELECT * FROM blackboard_messages WHERE topic = ? AND consumed = 0 ORDER BY priority DESC, posted_at ASC LIMIT 1",
            [topic.to_s]
          )
          break unless result

          # Claim the message only if no other consumer took it since the SELECT
          @db.execute(
            "UPDATE blackboard_messages SET consumed = 1, consumed_by = ?, consumed_at = CURRENT_TIMESTAMP WHERE id = ? AND consumed = 0",
            [consumer.to_s, result['id']]
          )
          break if @db.changes == 1
        end

        result && message_from(result)
      end

      # A row of blackboard_messages as the Hash handed to consumers.
      def message_from(row)
        {
          id: row['id'],
          sender: row['sender'],
          topic: row['topic'],
          content: parse_content(row['content']),
          priority: row['priority'],
          posted_at: Time.parse("#{row['posted_at']} UTC").localtime
        }
      end

      def peek(topic, limit: 10)
        results = @db.execute(
          "SELECT * FROM blackboard_messages WHERE topic = ? AND consumed = 0 ORDER BY priority DESC, posted_at ASC LIMIT ?",
          [topic.to_s, limit]
        )

        results.map { |row| message_from(row) }
      end

      def stats
        {
          total_messages: @db.get_first_value("SELECT COUNT(*) FROM blackboard_messages"),
          unconsumed_messages: @db.get_first_value("SELECT COUNT(*) FROM blackboard_messages WHERE consumed = 0")
        }
      end

      private

      # A String posted as content is stored as is, so it may not be JSON.
      def parse_content(content)
        JSON.parse(content, symbolize_names: true)
      rescue JSON::ParserError
        content
      end
    end
  end
end
