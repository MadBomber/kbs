require_relative 'lib/kbs'

# Test case: Rule with positive condition first, then negation
engine = KBS::Engine.new

rule = KBS::Rule.new('with_positive_first') do |r|
  r.conditions << KBS::Condition.new(:car, { color: :red })
  r.conditions << KBS::Condition.new(:problem, {}, negated: true)
  r.action = ->(facts) { puts "FIRED: with_positive_first rule" }
end

engine.add_rule(rule)
puts "Added rule with positive condition first"

engine.add_fact(:car, { color: :red })
engine.run
puts "Ran engine"
puts "Production node tokens: #{engine.production_nodes.values.first.tokens.size}"
