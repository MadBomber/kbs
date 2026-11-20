# frozen_string_literal: true

module KBS
  # A hash index over the items of an alpha or beta memory. Items that
  # share a key sit in one bucket, so a join looks up only the facts or
  # tokens that can pass its equality tests instead of scanning the memory.
  #
  # The key is computed once, when the item is added, and remembered:
  # removing an item finds its bucket even if its attributes changed since.
  # Buckets are Sets, so adding and removing an item do not depend on the
  # size of the bucket.
  class MemoryIndex
    EMPTY = Set.new.freeze

    # @yield [item] returns the key to file the item under
    def initialize(&key_for)
      @key_for = key_for
      @buckets = {}
      @keys = {}
    end

    def add(item)
      key = @key_for.call(item)
      @keys[item] = key
      (@buckets[key] ||= Set.new) << item
    end

    def remove(item)
      return unless @keys.key?(item)

      key = @keys.delete(item)
      bucket = @buckets[key]
      bucket.delete(item)
      @buckets.delete(key) if bucket.empty?
    end

    # @return [Set] the items filed under `key`, in the order they were
    #   added; do not modify it
    def lookup(key)
      @buckets[key] || EMPTY
    end

    def clear
      @buckets.clear
      @keys.clear
    end

    def size
      @keys.size
    end

    # The index key for a fact: its values for `fields`.
    def self.fact_key(fact, fields)
      fields.map { |field| normalize(fact.attributes[field]) }
    end

    # The index key for a token: for each [condition index, field] pair,
    # that attribute of the fact the condition matched.
    def self.token_key(token, specs)
      specs.map { |index, field| normalize(token.fact_at(index)&.attributes&.[](field)) }
    end

    # Join tests compare with ==, and a Hash key with eql?. They differ
    # for numbers: 1 == 1.0, but 1 and 1.0 are different keys. Whole
    # numbers are filed as Integers and Rationals as Floats, so values
    # that are == land in the same bucket.
    def self.normalize(value)
      return value if value.is_a?(Integer) || !value.is_a?(Numeric) || !value.real?
      return value unless value.finite?
      return value.to_i if value == value.to_i

      value.is_a?(Rational) ? value.to_f : value
    end
  end
end
