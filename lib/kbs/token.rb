# frozen_string_literal: true

module KBS
  class Token
    attr_accessor :parent, :fact, :node, :children

    def initialize(parent, fact, node)
      @parent = parent
      @fact = fact
      @node = node
      @children = []
      @fired = false
    end

    def facts
      facts = []
      token = self
      while token
        facts.unshift(token.fact) if token.fact
        token = token.parent
      end
      facts
    end

    def to_s
      "Token(#{facts.map(&:to_s).join(', ')})"
    end

    def fired?
      @fired
    end

    def mark_fired!
      @fired = true
    end
  end
end
