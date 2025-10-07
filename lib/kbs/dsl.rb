# frozen_string_literal: true

require_relative '../kbs'

# DSL components
require_relative 'dsl/variable'
require_relative 'dsl/pattern_evaluator'
require_relative 'dsl/rule_builder'
require_relative 'dsl/knowledge_base'
require_relative 'dsl/condition_helpers'

module KBS
  def self.knowledge_base(&block)
    kb = DSL::KnowledgeBase.new
    kb.instance_eval(&block) if block_given?
    kb
  end
end
