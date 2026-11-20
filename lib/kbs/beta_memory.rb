# frozen_string_literal: true

module KBS
  # The partial matches (tokens) of a rule up to one condition. Passes each
  # new token on to the nodes for the next condition.
  class BetaMemory
    attr_accessor :successors
    attr_reader :linked

    # An object told, through token_removed(token), about each token
    # that leaves this memory.
    attr_accessor :listener

    def initialize
      @tokens = Set.new
      @successors = []
      @linked = true
      @indexes = {}
      @listener = nil
    end

    # @return [Array<KBS::Token>] the tokens in this memory, in the order
    #   they arrived. A copy: use #add_token and #remove_token to change
    #   the memory.
    def tokens
      @tokens.to_a
    end

    def each_token(&)
      @tokens.each(&)
    end

    def size
      @tokens.size
    end

    def include?(token)
      @tokens.include?(token)
    end

    def unlink!
      @linked = false
      @successors.each(&:left_unlink!)
    end

    def relink!
      @linked = true
      @successors.each(&:left_relink!)
    end

    def activate(token)
      add_token(token)
      @successors.each { |successor| successor.left_activate(token) }
    end

    def deactivate(token)
      remove_token(token)
      @successors.each { |successor| successor.left_deactivate(token) }
    end

    def add_token(token)
      @tokens << token
      @indexes.each_value { |index| index.add(token) }
      relink! if @tokens.size == 1
    end

    def remove_token(token)
      @tokens.delete(token)
      @indexes.each_value { |index| index.remove(token) }
      @listener&.token_removed(token)
      unlink! if @tokens.empty?
    end

    # Forgets every token without telling the successors.
    def clear
      @tokens.clear
      @indexes.each_value(&:clear)
    end

    # A hash index of the tokens, kept up to date as tokens come and go.
    # Joins with the same specs share one index.
    #
    # @param specs [Array<Array(Integer, Symbol)>] [condition index, field]
    #   pairs whose values make up the key
    # @return [KBS::MemoryIndex]
    def index_on(specs)
      @indexes[specs] ||= MemoryIndex.new { |token| MemoryIndex.token_key(token, specs) }.tap do |index|
        @tokens.each { |token| index.add(token) }
      end
    end
  end
end
