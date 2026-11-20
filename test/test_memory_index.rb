# frozen_string_literal: true

require_relative 'test_helper'

class TestMemoryIndex < Minitest::Test
  def setup
    @index = KBS::MemoryIndex.new { |fact| [fact[:id]] }
    @a = KBS::Fact.new(:order, id: 1)
    @b = KBS::Fact.new(:order, id: 1)
    @c = KBS::Fact.new(:order, id: 2)
  end

  def test_lookup_of_a_missing_key_is_empty
    assert_empty @index.lookup([1])
    assert_predicate @index.lookup([1]), :frozen?
  end

  def test_add_files_items_by_key
    [@a, @b, @c].each { |fact| @index.add(fact) }

    assert_equal [@a, @b], @index.lookup([1])
    assert_equal [@c], @index.lookup([2])
    assert_equal 3, @index.size
  end

  def test_remove
    [@a, @b].each { |fact| @index.add(fact) }

    @index.remove(@a)

    assert_equal [@b], @index.lookup([1])
    assert_equal 1, @index.size
  end

  def test_remove_last_item_drops_the_bucket
    @index.add(@a)
    @index.remove(@a)

    assert_empty @index.lookup([1])
    assert_equal 0, @index.size
  end

  def test_remove_of_an_unknown_item_is_ignored
    @index.add(@a)
    @index.remove(@c)

    assert_equal [@a], @index.lookup([1])
  end

  def test_remove_uses_the_key_from_when_the_item_was_added
    @index.add(@a)
    @a[:id] = 99

    @index.remove(@a)

    assert_empty @index.lookup([1])
    assert_equal 0, @index.size
  end

  def test_clear
    [@a, @c].each { |fact| @index.add(fact) }

    @index.clear

    assert_empty @index.lookup([1])
    assert_equal 0, @index.size
  end

  def test_fact_key
    fact = KBS::Fact.new(:order, id: 1, region: "eu")

    assert_equal [1, "eu"], KBS::MemoryIndex.fact_key(fact, %i[id region])
    assert_equal [nil], KBS::MemoryIndex.fact_key(fact, %i[missing])
  end

  def test_token_key_reads_facts_by_condition_position
    first = KBS::Token.new(nil, KBS::Fact.new(:a, x: 1), nil)
    negated = KBS::Token.new(first, nil, nil)
    third = KBS::Token.new(negated, KBS::Fact.new(:c, y: 2), nil)

    assert_equal [1, 2], KBS::MemoryIndex.token_key(third, [[0, :x], [2, :y]])
    assert_equal [nil], KBS::MemoryIndex.token_key(third, [[1, :x]])
  end

  def test_normalize_makes_equal_numbers_the_same_key
    assert_equal 1.hash, KBS::MemoryIndex.normalize(1.0).hash
    assert KBS::MemoryIndex.normalize(1.0).eql?(1)
    assert KBS::MemoryIndex.normalize(Rational(2, 1)).eql?(2)
    assert KBS::MemoryIndex.normalize(Rational(1, 2)).eql?(0.5)
  end

  def test_normalize_leaves_other_values_alone
    assert_equal 1.5, KBS::MemoryIndex.normalize(1.5)
    assert_equal "1", KBS::MemoryIndex.normalize("1")
    assert_nil KBS::MemoryIndex.normalize(nil)
    assert_equal :a, KBS::MemoryIndex.normalize(:a)
    assert_predicate KBS::MemoryIndex.normalize(Float::NAN), :nan?
    assert_equal Float::INFINITY, KBS::MemoryIndex.normalize(Float::INFINITY)
    assert_equal Complex(1, 2), KBS::MemoryIndex.normalize(Complex(1, 2))
  end
end
