# frozen_string_literal: true

require 'json'
require 'time'

module KBS
  module Blackboard
    # Redis-based message queue using sorted sets for priority ordering
    class RedisMessageQueue
      def initialize(redis)
        @redis = redis
        @message_id_counter = "message_id_counter"
      end

      def post(sender, topic, content, priority: 0)
        message_id = @redis.incr(@message_id_counter)
        content_json = content.is_a?(String) ? content : JSON.generate(content)
        timestamp = Time.now.to_f

        message_data = {
          'id' => message_id,
          'sender' => sender,
          'topic' => topic,
          'content' => content_json,
          'priority' => priority,
          'posted_at' => timestamp,
          'consumed' => '0'
        }

        # Store message data
        @redis.hset("message:#{message_id}", message_data)

        # Add to topic queue with score = -priority (for DESC ordering) + timestamp (for ASC within priority)
        # Score: higher priority = lower score (negative), then by timestamp
        score = (-priority * 1_000_000) + timestamp
        @redis.zadd("messages:#{topic}", score, message_id)

        message_id
      end

      def consume(topic, consumer)
        # Get highest priority (lowest score) unconsumed message
        messages = @redis.zrange("messages:#{topic}", 0, 0)
        return nil if messages.empty?

        message_id = messages.first
        message_data = @redis.hgetall("message:#{message_id}")

        return nil if message_data.empty? || message_data['consumed'] == '1'

        # Mark as consumed
        @redis.multi do |pipeline|
          pipeline.hset("message:#{message_id}", 'consumed', '1')
          pipeline.hset("message:#{message_id}", 'consumed_by', consumer)
          pipeline.hset("message:#{message_id}", 'consumed_at', Time.now.to_f)
          pipeline.zrem("messages:#{topic}", message_id)
        end

        {
          id: message_data['id'].to_i,
          sender: message_data['sender'],
          topic: message_data['topic'],
          content: JSON.parse(message_data['content'], symbolize_names: true),
          priority: message_data['priority'].to_i,
          posted_at: Time.at(message_data['posted_at'].to_f)
        }
      end

      def peek(topic, limit: 10)
        # Get top N messages without consuming
        message_ids = @redis.zrange("messages:#{topic}", 0, limit - 1)
        messages = []

        message_ids.each do |message_id|
          message_data = @redis.hgetall("message:#{message_id}")
          next if message_data.empty? || message_data['consumed'] == '1'

          messages << {
            id: message_data['id'].to_i,
            sender: message_data['sender'],
            topic: message_data['topic'],
            content: JSON.parse(message_data['content'], symbolize_names: true),
            priority: message_data['priority'].to_i,
            posted_at: Time.at(message_data['posted_at'].to_f)
          }
        end

        messages
      end

      def stats
        # Count all unconsumed messages across all topics
        topics = @redis.keys('messages:*')
        total_unconsumed = 0

        topics.each do |topic_key|
          total_unconsumed += @redis.zcard(topic_key)
        end

        # Count all messages (including consumed)
        all_message_keys = @redis.keys('message:*')
        total_messages = all_message_keys.size

        {
          total_messages: total_messages,
          unconsumed_messages: total_unconsumed
        }
      end
    end
  end
end
