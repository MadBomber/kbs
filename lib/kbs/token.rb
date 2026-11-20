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
      @slots = build_slots
    end

    # The matched facts, one per positive condition.
    def facts
      @slots.compact
    end

    # The fact matched by the condition at `index` in the rule, or nil
    # when that condition is negated.
    def fact_at(index)
      @slots[index]
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

    protected

    attr_reader :slots

    private

    # One entry per condition matched so far, nil for a negated one. The
    # root dummy token (no parent, no fact) matches no condition.
    def build_slots
      return @fact ? [@fact] : [] unless @parent

      @parent.slots + [@fact]
    end
  end
end
