# frozen_string_literal: true

module KBS
  # A hash index over the items of an alpha or beta memory. Items that
  # share a key sit in one bucket, so a join looks up only the facts or
  # tokens that can pass its equality tests instead of scanning the memory.
  #
  # The key is computed once, when the item is added, and remembered:
  # removing an item finds its bucket even if its attributes changed since.
  #
  # A join on an id usually files one item per key, so a bucket holds a
  # lone item itself and becomes a Set only for the second. Sets compare
  # with eql?, as the index's own key table does, so a blackboard fact
  # read again from its store is the same item. Adding and removing an
  # item do not depend on the size of the bucket.
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
      bucket = @buckets[key]
      case bucket
      when nil then @buckets[key] = item
      when Set then bucket << item
      else @buckets[key] = Set[bucket, item] unless bucket.eql?(item)
      end
    end

    def remove(item)
      return unless @keys.key?(item)

      key = @keys.delete(item)
      bucket = @buckets[key]
      if bucket.is_a?(Set)
        bucket.delete(item)
        return unless bucket.empty?
      end
      @buckets.delete(key)
    end

    # @return [Enumerable] the items filed under `key`, in the order they
    #   were added; do not modify it
    def lookup(key)
      bucket = @buckets[key]
      case bucket
      when nil then EMPTY
      when Set then bucket
      else [bucket]
      end
    end

    def clear
      @buckets.clear
      @keys.clear
    end

    def size
      @keys.size
    end

    # The index key for a fact: its value for the field, or its values for
    # several fields. A single field is the common case and needs no Array.
    def self.fact_key(fact, fields)
      attributes = fact.attributes
      return normalize(attributes[fields.first]) if fields.size == 1

      fields.map { |field| normalize(attributes[field]) }
    end

    # The index key for a token, built like #fact_key: for each [condition
    # index, field] pair, that attribute of the fact the condition matched.
    def self.token_key(token, specs)
      return token_value(token, *specs.first) if specs.size == 1

      specs.map { |index, field| token_value(token, index, field) }
    end

    # The normalized attribute `field` of the fact the condition at
    # `index` matched; nil when that condition matched no fact.
    def self.token_value(token, index, field)
      normalize(token.fact_at(index)&.attributes&.[](field))
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
