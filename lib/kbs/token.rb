# frozen_string_literal: true

module KBS
  # A partial match: the facts matched so far, as a chain of tokens with
  # one link per condition.
  class Token
    attr_accessor :parent, :fact, :node

    EMPTY_CHILDREN = Set.new.freeze

    def initialize(parent, fact, node)
      @parent = parent
      @fact = fact
      @node = node
      @children = nil
      @fired = false
      @retracted = false
      @slots = build_slots
    end

    # @return [Set<KBS::Token>] the tokens that extend this one, so that
    #   removing this token can remove them without a search. Frozen and
    #   empty until the first #add_child.
    def children
      @children || EMPTY_CHILDREN
    end

    def add_child(token)
      (@children ||= Set.new) << token
    end

    def remove_child(token)
      @children&.delete(token)
    end

    def clear_children
      @children = nil
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
      "Token(#{facts.join(', ')})"
    end

    def fired?
      @fired
    end

    def mark_fired!
      @fired = true
    end

    # Whether the engine has seen this token leave its beta memory. Only
    # recorded for tokens that can logically support facts.
    def retracted?
      @retracted
    end

    def mark_retracted!
      @retracted = true
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
