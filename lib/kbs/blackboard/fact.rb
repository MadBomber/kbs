# frozen_string_literal: true

module KBS
  module Blackboard
    # A fact in the blackboard with persistence capabilities
    class Fact
      attr_reader :uuid, :type, :attributes

      def initialize(uuid, type, attributes, blackboard = nil)
        @uuid = uuid
        @type = type
        @attributes = attributes
        @blackboard = blackboard
      end

      def [](key)
        @attributes[key]
      end

      def []=(key, value)
        @attributes[key] = value
        @blackboard.update_fact(self, @attributes) if @blackboard
      end

      def update(new_attributes)
        @attributes.merge!(new_attributes)
        @blackboard.update_fact(self, @attributes) if @blackboard
      end

      def retract
        @blackboard.remove_fact(self) if @blackboard
      end

      def matches?(pattern)
        return false if pattern[:type] && pattern[:type] != @type

        pattern.each do |key, value|
          next if key == :type

          if value.is_a?(Proc)
            return false unless @attributes[key] && value.call(@attributes[key])
          elsif value.is_a?(Symbol) && value.to_s.start_with?('?')
            next
          else
            return false unless @attributes[key] == value
          end
        end

        true
      end

      def to_s
        "#{@type}(#{@uuid[0..7]}...: #{@attributes.map { |k, v| "#{k}=#{v}" }.join(', ')})"
      end

      def to_h
        {
          uuid: @uuid,
          type: @type,
          attributes: @attributes
        }
      end
    end
  end
end
