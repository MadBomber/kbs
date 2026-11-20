# frozen_string_literal: true

module KBS
  class AlphaMemory
    attr_accessor :successors, :pattern
    attr_reader :linked

    def initialize(pattern = {})
      @items = Set.new
      @successors = []
      @pattern = pattern
      @linked = true
      @indexes = {}
    end

    # @return [Array] the facts in this memory, in the order they arrived.
    #   A copy: use #add_item and #remove_item to change the memory.
    def items
      @items.to_a
    end

    def each_item(&block)
      @items.each(&block)
    end

    def size
      @items.size
    end

    def include?(fact)
      @items.include?(fact)
    end

    def unlink!
      @linked = false
      @successors.each { |s| s.right_unlink! if s.respond_to?(:right_unlink!) }
    end

    def relink!
      @linked = true
      @successors.each { |s| s.right_relink! if s.respond_to?(:right_relink!) }
    end

    def activate(fact)
      return unless @linked
      add_item(fact)
      @successors.each { |s| s.right_activate(fact) }
    end

    def deactivate(fact)
      return unless @linked
      remove_item(fact)
      @successors.each { |s| s.right_deactivate(fact) if s.respond_to?(:right_deactivate) }
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
