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
    #   empty while there are none. Use #add_child and #remove_child to
    #   change them.
    def children
      case @children
      when nil then EMPTY_CHILDREN
      when Set then @children
      else Set[@children].freeze
      end
    end

    # Most tokens have one child or none, so @children holds a lone child
    # itself and becomes a Set only for the second.
    def add_child(token)
      case @children
      when nil then @children = token
      when Set then @children << token
      else @children = Set.new.compare_by_identity << @children << token unless @children.equal?(token)
      end
    end

    def remove_child(token)
      case @children
      when Set then @children.delete(token)
      when token then @children = nil
      end
    end

    def clear_children
      @children = nil
    end

    # The matched facts, one per positive condition.
    def facts
      @slots.compact
    end

    # One entry per condition matched so far: the matched fact, or nil
    # for a negated or exists condition. Frozen.
    attr_reader :slots

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

    private

    # One entry per condition matched so far, nil for a negated one. The
    # root dummy token (no parent, no fact) matches no condition.
    def build_slots
      return (@fact ? [@fact] : []).freeze unless @parent

      [*@parent.slots, @fact].freeze
    end
  end
end
