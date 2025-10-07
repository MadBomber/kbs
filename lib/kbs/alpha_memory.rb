# frozen_string_literal: true

module KBS
  class AlphaMemory
    attr_accessor :items, :successors, :pattern
    attr_reader :linked

    def initialize(pattern = {})
      @items = []
      @successors = []
      @pattern = pattern
      @linked = true
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
      @items << fact
      @successors.each { |s| s.right_activate(fact) }
    end

    def deactivate(fact)
      return unless @linked
      @items.delete(fact)
      @successors.each { |s| s.right_deactivate(fact) if s.respond_to?(:right_deactivate) }
    end
  end
end
