# frozen_string_literal: true

module KBS
  # Base class of the errors this gem raises.
  class Error < StandardError; end

  # Raised when a fact is added, removed or modified while the engine is
  # in the middle of matching another fact. This happens when a pattern
  # predicate changes facts. A working-memory observer added with
  # add_observer runs after the engine has matched the fact, so it does
  # not raise. Change facts from rule actions instead, which run between
  # matches.
  class MatchInProgressError < Error
    def initialize(message = "facts cannot be added, removed or modified while a fact is being matched")
      super
    end
  end

  # Raised when a DSL condition keyword such as `on`, `without` or
  # `perform` is called on a rule builder whose rule has already been
  # built, for example from inside the rule's `perform` block. The call
  # could no longer change the rule.
  class RuleBuiltError < Error
    def initialize(rule_name, keyword)
      super("rule #{rule_name.inspect} is already built; `#{keyword}` cannot change it " \
            "(inside perform, use fact/assert/retract/modify/query to change working memory)")
    end
  end

  # Raised when a DSL rule builder is asked to change working memory
  # (fact, assert, retract, modify, query, ...) but was created without a
  # knowledge base to forward the call to.
  class NoKnowledgeBaseError < Error
    def initialize(rule_name, method)
      super("rule #{rule_name.inspect} has no knowledge base, so `#{method}` cannot reach working memory")
    end
  end
end
