# frozen_string_literal: true

module KBS
  module Blackboard
    # A fact in the blackboard with persistence capabilities
    class Fact
      include PatternMatching

      attr_reader :uuid, :type, :attributes

      def initialize(uuid, type, attributes, blackboard = nil)
        @uuid = uuid
        @type = type
        @attributes = attributes
        @blackboard = blackboard
      end

      # Facts are identified by uuid. The blackboard builds a new Fact
      # object each time it reads or removes one, so the Rete network
      # must find the object it holds by uuid, not by identity.
      def ==(other)
        other.is_a?(Fact) && other.uuid == @uuid
      end
      alias eql? ==

      def hash
        [Fact, @uuid].hash
      end

      def [](key)
        @attributes[key]
      end

      def []=(key, value)
        @attributes[key] = value
        @blackboard&.update_fact(self, @attributes)
      end

      def update(new_attributes)
        @attributes.merge!(new_attributes)
        @blackboard&.update_fact(self, @attributes)
      end

      def retract
        @blackboard&.remove_fact(self)
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
