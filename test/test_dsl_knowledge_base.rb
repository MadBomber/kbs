# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs'

class TestDSLKnowledgeBase < Minitest::Test
  def test_initialization
    kb = KBS::DSL::KnowledgeBase.new

    assert_instance_of KBS::DSL::KnowledgeBase, kb
    assert_instance_of KBS::Engine, kb.engine
  end

  def test_add_fact
    kb = KBS::DSL::KnowledgeBase.new
    kb.fact(:car, color: :red, speed: 100)

    facts = kb.engine.working_memory.facts
    assert_equal 1, facts.size
    assert_equal :car, facts.first.type
    assert_equal :red, facts.first[:color]
  end

  def test_rule_definition
    kb = KBS::DSL::KnowledgeBase.new
    fired = false

    kb.rule 'test_rule' do
      on :car, color: :red
      perform { |facts| fired = true }
    end

    kb.fact(:car, color: :red)
    kb.run

    assert fired
  end

  def test_multiple_rules
    kb = KBS::DSL::KnowledgeBase.new
    results = []

    kb.rule 'rule1' do
      on :car, color: :red
      perform { |facts| results << :rule1 }
    end

    kb.rule 'rule2' do
      on :car, color: :red
      perform { |facts| results << :rule2 }
    end

    kb.fact(:car, color: :red)
    kb.run

    assert_equal 2, results.size
    assert_includes results, :rule1
    assert_includes results, :rule2
  end

  def test_dsl_entry_point
    kb = KBS.knowledge_base do
      fact :car, color: :red
    end

    assert_instance_of KBS::DSL::KnowledgeBase, kb
    assert_equal 1, kb.engine.working_memory.facts.size
  end

  def test_block_dsl
    result = []

    kb = KBS.knowledge_base do
      rule 'test' do
        on :car, color: :red
        perform { |facts| result << :fired }
      end

      fact :car, color: :red
      run
    end

    assert_equal 1, result.size
  end

  def test_query_facts
    kb = KBS::DSL::KnowledgeBase.new
    kb.fact(:car, color: :red, speed: 100)
    kb.fact(:car, color: :blue, speed: 80)
    kb.fact(:driver, name: "John")

    cars = kb.query(:car)
    assert_equal 2, cars.size

    red_cars = kb.query(:car, color: :red)
    assert_equal 1, red_cars.size
    assert_equal :red, red_cars.first[:color]
  end
end
