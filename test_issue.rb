require_relative 'lib/kbs'

# Test case: Rule with ONLY a negation condition (no positive conditions first)
# This should fire when no problem facts exist, but according to issue #11, it doesn't fire

engine = KBS::Engine.new

rule = KBS::Rule.new('only_negation') do |r|
  r.conditions << KBS::Condition.new(:problem, {}, negated: true)
  r.action = ->(facts) { puts "FIRED: only_negation rule" }
end

engine.add_rule(rule)
puts "Added rule with only negation condition"
puts "Production node tokens before run: #{engine.production_nodes.values.first.tokens.size}"

engine.run
puts "Ran engine - rule should have fired if issue is present"
puts "Production node tokens after run: #{engine.production_nodes.values.first.tokens.size}"
