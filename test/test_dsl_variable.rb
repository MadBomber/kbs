# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/kbs'

class TestDSLVariable < Minitest::Test
  def test_variable_creation
    var = KBS::DSL::Variable.new(:price?)

    assert_instance_of KBS::DSL::Variable, var
    assert_equal :price?, var.name
  end

  def test_variable_name_must_end_with_question_mark
    var = KBS::DSL::Variable.new(:price?)
    assert_equal :price?, var.name

    var2 = KBS::DSL::Variable.new("quantity?")
    assert_equal :quantity?, var2.name
  end

  def test_variable_equality
    var1 = KBS::DSL::Variable.new(:price?)
    var2 = KBS::DSL::Variable.new(:price?)
    var3 = KBS::DSL::Variable.new(:quantity?)

    assert_equal var1, var2
    refute_equal var1, var3
  end

  def test_variable_to_s
    var = KBS::DSL::Variable.new(:price?)
    assert_equal "price?", var.to_s
  end

  def test_variable_hash
    var1 = KBS::DSL::Variable.new(:price?)
    var2 = KBS::DSL::Variable.new(:price?)

    hash = { var1 => "value" }
    assert_equal "value", hash[var2]
  end
end
