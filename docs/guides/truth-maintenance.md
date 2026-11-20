# Truth Maintenance

A rule often asserts a fact that is only true while the rule's conditions hold: a sensor above 90 degrees *is* overheating, an order with no payment *is* overdue. Without help, such a derived fact stays in working memory after the reason for it is gone, and you write a second rule to clean it up.

Mark the conditions as `logical` and the engine does the cleanup. A fact asserted by the rule is then *supported* by the match of those conditions. When the match goes away, the fact is retracted.

## A First Example

```ruby
kb = KBS.knowledge_base

kb.rule "overheating" do
  logical do
    on :sensor, id: :id?, temp: greater_than(90)
  end
  perform { |_facts, bindings| kb.assert(:overheating, sensor: bindings[:id?]) }
end

reading = kb.assert(:sensor, id: 1, temp: 95)
kb.run
kb.facts.map(&:type)   # => [:sensor, :overheating]

kb.modify(reading, temp: 60)
kb.facts.map(&:type)   # => [:sensor]
```

The `:overheating` fact was never retracted by a rule. It went because the sensor no longer matched.

A match stops when one of its facts is retracted, when `modify` changes a fact so it no longer fits, or when a fact arrives that a `without` condition in the block forbids.

## What the Support Covers

Only the conditions inside `logical do ... end` carry the support, and the block has to come before the rule's other conditions:

```ruby
rule "page the operator" do
  logical do
    on :overheating, sensor: :id?
  end
  on :shift_change            # a trigger, not a reason
  perform { |_f, b| kb.assert(:page, sensor: b[:id?]) }
end
```

Retracting `:shift_change` leaves the `:page` alone. Retracting `:overheating` removes it.

A logical condition after a plain one raises `ArgumentError` when the rule is added.

`without` and `exists` work inside the block:

```ruby
rule "overdue" do
  logical do
    on :order, id: :id?
    without :payment, order_id: :id?
  end
  perform { |_f, b| kb.assert(:overdue, order: b[:id?]) }
end
```

Asserting the payment retracts `:overdue`.

## Chains

A derived fact can support others. Retracting the first fact unwinds the whole chain:

```ruby
rule "overheating" do
  logical { on :sensor, temp: greater_than(90) }
  perform { kb.assert(:overheating) }
end

rule "alarm" do
  logical { on :overheating }
  perform { kb.assert(:alarm) }
end
```

Retract the sensor and both `:overheating` and `:alarm` go.

## Unconditional Facts

A fact is supported only when a rule with logical conditions asserts it. Facts you assert yourself, and facts asserted by rules without a `logical` block, are *unconditional*: they stay until something retracts them.

When the engine rejects duplicate facts (`fact_duplication: false`), the same fact can be asserted more than once, and the two kinds of support combine:

| A supported fact is asserted again... | Result |
|---|---|
| by another logical match | it gains a second support, and goes when both are gone |
| from outside a logical rule | it becomes unconditional |

An unconditional fact asserted again by a logical rule stays unconditional.

With duplication on, which is the default, each assertion makes a separate fact with its own single support.

## Looking at the Support

```ruby
engine.logically_supported?(fact)  # true while the fact depends on a match
engine.dependencies(fact)          # the matches that support it, as arrays of facts
engine.dependents(fact)            # the facts that have this fact in a supporting match
```

## Details

- Unsupported facts are retracted as soon as the change that removed their support has been matched, before the next rule fires.
- Retracting a supported fact yourself is fine; its support is forgotten.
- If a rule's action removes its own support and then asserts a fact, that fact is not added and `add_fact` returns `nil`.
- A rule whose action asserts the very fact its logical `without` forbids retracts that fact at once, matches again, and fires again. Bound it with `run(limit)` or restructure the rule.
- Supports live in the engine's memory. With a persistent blackboard, derived facts are stored like any other fact, but the links to their supports are not saved.

## With the Low-Level API

```ruby
KBS::Rule.new(
  "overheating",
  conditions: [KBS::Condition.new(:sensor, { temp: ->(t) { t > 90 } }, logical: true)],
  action: ->(_facts) { engine.add_fact(:overheating, {}) }
)
```
