# frozen_string_literal: true

module KBS
  class Fact
    attr_reader :id, :type, :attributes

    def initialize(type, attributes = {})
      @id = object_id
      @type = type
      @attributes = attributes
    end

    def [](key)
      @attributes[key]
    end

    def []=(key, value)
      @attributes[key] = value
    end

    def matches?(pattern)
      return false if pattern[:type] && pattern[:type] != @type

      pattern.each do |key, value|
        next if key == :type

        if value.is_a?(Proc)
          return false unless @attributes[key] && value.call(@attributes[key])
        elsif value.is_a?(Symbol) && value.to_s.end_with?('?')
          next
        else
          return false unless @attributes[key] == value
        end
      end

      true
    end

    def to_s
      "#{@type}(#{@attributes.map { |k, v| "#{k}: #{v}" }.join(', ')})"
    end
  end
end
