# frozen_string_literal: true

module KBS
  # A typed set of attributes in working memory.
  class Fact
    include PatternMatching

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

    def to_s
      attributes = @attributes.map { |key, value| "#{key}: #{value.inspect}" }.join(", ")
      "fact #{@type.inspect}#{", #{attributes}" unless attributes.empty?}"
    end
  end
end
