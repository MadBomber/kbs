# frozen_string_literal: true

module KBS
  class BetaMemory
    attr_accessor :tokens, :successors
    attr_reader :linked

    def initialize
      @tokens = []
      @successors = []
      @linked = true
      @indexes = {}
    end

    def unlink!
      @linked = false
      @successors.each { |s| s.left_unlink! if s.respond_to?(:left_unlink!) }
    end

    def relink!
      @linked = true
      @successors.each { |s| s.left_relink! if s.respond_to?(:left_relink!) }
    end

    def activate(token)
      add_token(token)
      @successors.each do |s|
        if s.respond_to?(:left_activate)
          s.left_activate(token)
        elsif s.respond_to?(:activate)
          s.activate(token)
        end
      end
    end

    def deactivate(token)
      remove_token(token)
      @successors.each do |s|
        if s.respond_to?(:left_deactivate)
          s.left_deactivate(token)
        elsif s.respond_to?(:deactivate)
          s.deactivate(token)
        end
      end
    end

    def add_token(token)
      @tokens << token
      @indexes.each_value { |index| index.add(token) }
      relink! if @tokens.size == 1
    end

    def remove_token(token)
      @tokens.delete(token)
      @indexes.each_value { |index| index.remove(token) }
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
