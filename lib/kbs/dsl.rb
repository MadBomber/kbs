# frozen_string_literal: true

unless defined?(KBS::Engine)
  require_relative '../kbs'
end

# DSL components
require_relative 'dsl/variable'
require_relative 'dsl/condition_helpers'
require_relative 'dsl/pattern_evaluator'
require_relative 'dsl/rule_builder'
require_relative 'dsl/knowledge_base'

module KBS
  # Builds a knowledge base and evaluates the block in its context.
  #
  # @param engine [KBS::Engine, nil] engine to run on, such as a
  #   KBS::Blackboard::Engine for persistence; a new KBS::Engine when nil
  # @return [KBS::DSL::KnowledgeBase]
  def self.knowledge_base(engine: nil, &block)
    kb = DSL::KnowledgeBase.new(engine: engine)
    kb.instance_eval(&block) if block_given?
    kb
  end
end
