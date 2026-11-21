# frozen_string_literal: true

module KBS
  # The facts that fit one condition pattern. Shared by every rule that
  # uses the pattern; tells its join nodes when a fact arrives or leaves.
  class AlphaMemory
    attr_accessor :successors
    attr_reader :pattern, :linked

    def initialize(pattern = {})
      @items = Set.new
      @successors = []
      @linked = true
      @indexes = {}
      @pattern = pattern
      @fact_type, @tests = self.class.compile(pattern)
    end

    # Sets the pattern and prepares the tests #admits? runs.
    def pattern=(pattern)
      @pattern = pattern
      @fact_type, @tests = self.class.compile(pattern)
    end

    # The fact type a pattern requires (nil for any) and the tests from
    # PatternMatching.tests_for.
    def self.compile(pattern)
      [pattern[:type], PatternMatching.tests_for(pattern)]
    end

    # Whether `fact` fits the pattern: the answer of
    # fact.matches?(pattern), found without looking at the pattern's
    # ?variables, which fit anything.
    def admits?(fact)
      fact_type = @fact_type
      return false if fact_type && fact_type != fact.type

      PatternMatching.passes?(@tests, fact.attributes)
    end

    # @return [Array] the facts in this memory, in the order they arrived.
    #   A copy: use #add_item and #remove_item to change the memory.
    def items
      @items.to_a
    end

    def each_item(&)
      @items.each(&)
    end

    def size
      @items.size
    end

    def include?(fact)
      @items.include?(fact)
    end

    def unlink!
      @linked = false
      @successors.each(&:right_unlink!)
    end

    def relink!
      @linked = true
      @successors.each(&:right_relink!)
    end

    def activate(fact)
      return unless @linked
      add_item(fact)
      @successors.each { |successor| successor.right_activate(fact) }
    end

    def deactivate(fact)
      return unless @linked
      remove_item(fact)
      @successors.each { |successor| successor.right_deactivate(fact) }
    end

    # Stores a fact without telling the successors.
    def add_item(fact)
      @items << fact
      @indexes.each_value { |index| index.add(fact) }
    end

    def remove_item(fact)
      @items.delete(fact)
      @indexes.each_value { |index| index.remove(fact) }
    end

    def clear
      @items.clear
      @indexes.each_value(&:clear)
    end

    # A hash index of the items on `fields`, kept up to date as facts
    # come and go. Joins with the same fields share one index.
    #
    # @param fields [Array<Symbol>] fact attributes that make up the key
    # @return [KBS::MemoryIndex]
    def index_on(fields)
      @indexes[fields] ||= MemoryIndex.new { |fact| MemoryIndex.fact_key(fact, fields) }.tap do |index|
        @items.each { |fact| index.add(fact) }
      end
    end
  end
end
