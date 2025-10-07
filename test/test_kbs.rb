# frozen_string_literal: true

require "test_helper"

class TestKbs < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::KBS::VERSION
  end

  def test_basic_knowledge_base_creation
    kb = KBS.knowledge_base do
      # Basic knowledge base can be created
    end
    assert_instance_of KBS::DSL::KnowledgeBase, kb
  end
end
