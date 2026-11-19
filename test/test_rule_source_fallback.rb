# frozen_string_literal: true

require_relative 'test_helper'

# A condition value such as satisfies(&:even?) is a Symbol proc with no
# instruction sequence, so KBS::Decompiler cannot read it. rule_source must
# still return the rest of the rule.
class TestRuleSourceFallback < Minitest::Test
  def test_rule_source_falls_back_when_condition_proc_cannot_be_decompiled
    kb = KBS.knowledge_base
    # Defined from a string so there is no source file to read; rule_source
    # has to reconstruct the rule from its procs.
    kb.instance_eval(<<~DSL)
      rule "evens" do
        on :n, value: satisfies(&:even?)
        perform { }
      end
    DSL

    source = kb.rule_source("evens")

    assert_match(/^  on :n, value: <decompilation failed: .+>$/, source)
    assert_includes source, %(rule "evens" do)
  end
end
