# frozen_string_literal: true

module KBS
  # Finds the alpha memories a fact belongs in without testing every
  # pattern.
  #
  # Memories are grouped by fact type. Within a type, a memory whose
  # pattern tests an attribute against a constant is filed in a hash under
  # that attribute and value, so a fact reaches it with one lookup on its
  # own value. Only memories with no constant test are tried for every
  # fact of the type. Candidates are still checked with Fact#matches?,
  # which covers the rest of each pattern.
  class AlphaNetwork
    # @return [Hash{Hash => KBS::AlphaMemory}] every memory, by pattern
    attr_reader :memories

    def initialize
      @memories = {}
      @types = {}
      @untyped = []
      @sequence = {}.compare_by_identity
    end

    # The memory for `pattern`, made and filed if it is new. The block is
    # called with a new memory, to fill it with existing facts.
    def fetch(pattern)
      @memories[pattern] ||= AlphaMemory.new(pattern).tap do |memory|
        file(memory)
        yield memory if block_given?
      end
    end

    # @return [Array<KBS::AlphaMemory>] the memories whose pattern `fact`
    #   matches, in the order they were created
    def memories_for(fact)
      matches = candidates_for(fact).select { |memory| memory.admits?(fact) }
      matches.size > 1 ? matches.sort_by { |memory| @sequence[memory] } : matches
    end

    # @return [Array<KBS::AlphaMemory>] the memories that have to be
    #   checked for `fact`. It may be one of the network's own lists, so
    #   do not modify it: a new Array is built only when more than one
    #   list applies.
    def candidates_for(fact)
      type = @types[fact.type]
      return @untyped unless type

      candidates = self.class.join_lists(@untyped, type[:unselected])
      attributes = fact.attributes
      type[:selectors].each_pair do |attribute, table|
        selected = table[MemoryIndex.normalize(attributes[attribute])]
        candidates = self.class.join_lists(candidates, selected) if selected
      end
      candidates
    end

    # `first` followed by `second`: one of them as it is when the other is
    # empty, a new Array otherwise.
    def self.join_lists(first, second)
      return second if first.empty?
      return first if second.empty?

      first + second
    end

    # The attribute and constant a pattern is filed under: its first
    # attribute tested against a plain value. nil when it has none.
    #
    # @return [Array(Symbol, Object), nil]
    def self.selector(pattern)
      pattern.each do |attribute, value|
        next if attribute == :type || value.is_a?(Proc) || JoinTestBuilder.variable?(value)

        return [attribute, MemoryIndex.normalize(value)]
      end
      nil
    end

    private

    def file(memory)
      @sequence[memory] = @sequence.size
      fact_type = memory.pattern[:type]
      return @untyped << memory unless fact_type

      type = @types[fact_type] ||= { unselected: [], selectors: {} }
      attribute, value = self.class.selector(memory.pattern)
      if attribute
        ((type[:selectors][attribute] ||= {})[value] ||= []) << memory
      else
        type[:unselected] << memory
      end
    end
  end
end
