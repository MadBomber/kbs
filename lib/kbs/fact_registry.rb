# frozen_string_literal: true

module KBS
  # Finds the fact in working memory that has a given type and attributes,
  # so an engine can refuse to hold the same fact twice.
  #
  # A fact is filed under a copy of its attributes taken when it is
  # added, so it is still found, and still removed, after its attributes
  # change.
  class FactRegistry
    def initialize
      @facts = {}
      @keys = {}
    end

    # Files `fact` unless an equal fact is already filed.
    #
    # @return [Boolean] whether the fact was filed
    def add(fact)
      key = self.class.key(fact.type, fact.attributes)
      return false if @facts.key?(key)

      @facts[key] = fact
      @keys[fact] = key
      true
    end

    def remove(fact)
      key = @keys.delete(fact)
      @facts.delete(key) if key
    end

    # @return [Object, nil] the filed fact with this type and attributes
    def find(type, attributes)
      @facts[self.class.key(type, attributes)]
    end

    def size
      @facts.size
    end

    def clear
      @facts.clear
      @keys.clear
    end

    def self.key(type, attributes)
      [type, attributes.dup.freeze]
    end
  end
end
