# frozen_string_literal: true

require "minitest/autorun"

class TestGemspec < Minitest::Test
  TOP_LEVEL_FILES = %w[README.md CHANGELOG.md LICENSE.txt].freeze

  def setup
    @spec = Gem::Specification.load(File.expand_path("../kbs.gemspec", __dir__))
  end

  def test_captured_dsl_output_is_not_packaged
    refute_includes @spec.files, "examples/temp_dsl.txt"
  end

  def test_packages_only_library_code_and_top_level_docs
    stray = @spec.files.reject { |f| f.start_with?("lib/") || TOP_LEVEL_FILES.include?(f) }

    assert_empty stray
  end

  def test_packages_library_entry_point_and_top_level_docs
    assert_includes @spec.files, "lib/kbs.rb"
    TOP_LEVEL_FILES.each { |f| assert_includes @spec.files, f }
  end

  def test_does_not_package_docs_examples_or_ci_config
    refute(@spec.files.any? { |f| f.start_with?("docs/", "examples/", ".github/") })
  end
end
