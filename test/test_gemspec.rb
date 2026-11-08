# frozen_string_literal: true

require "minitest/autorun"

class TestGemspec < Minitest::Test
  def test_captured_dsl_output_is_not_packaged
    spec = Gem::Specification.load(File.expand_path("../kbs.gemspec", __dir__))

    refute_includes spec.files, "examples/temp_dsl.txt"
  end
end
