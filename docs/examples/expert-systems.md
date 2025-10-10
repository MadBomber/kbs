# Expert Systems

Build diagnostic expert systems using KBS with knowledge representation, inference engines, explanation facilities, and confidence factors.

## System Overview

This example demonstrates a medical diagnostic system with:

- **Knowledge Base** - Medical symptoms and disease rules
- **Inference Engine** - Forward and backward chaining
- **Explanation Facility** - Justification for diagnoses
- **Confidence Factors** - Probabilistic reasoning
- **User Interface** - Interactive consultation

## Architecture

```
Patient Symptoms → Symptom Analysis → Disease Hypotheses → Diagnosis
                       ↓                      ↓                ↓
                  Working Memory      Confidence Scores    Explanation
```

## Complete Implementation

### Medical Diagnosis System

```ruby
require 'kbs'

class MedicalExpertSystem
  def initialize(db_path: 'medical.db')
    @engine = KBS::Blackboard::Engine.new(db_path: db_path)
    @explanations = []
    setup_knowledge_base
  end

  def setup_knowledge_base
    # Rule 1: Detect fever pattern
    fever_rule = KBS::Rule.new("detect_fever", priority: 100) do |r|
      r.conditions = [
        KBS::Condition.new(:symptom, {
          type: "temperature",
          value: :temp?
        }, predicate: lambda { |f| f[:value] > 38.0 }),

        KBS::Condition.new(:fever_detected, {}, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        confidence = calculate_fever_confidence(bindings[:temp?])

        @engine.add_fact(:fever_detected, {
          severity: fever_severity(bindings[:temp?]),
          confidence: confidence,
          temperature: bindings[:temp?]
        })

        @explanations << {
          rule: "detect_fever",
          reasoning: "Temperature #{bindings[:temp?]}°C exceeds normal (37°C)",
          confidence: confidence
        }
      end
    end

    # Rule 2: Flu hypothesis
    flu_rule = KBS::Rule.new("hypothesize_flu", priority: 90) do |r|
      r.conditions = [
        KBS::Condition.new(:fever_detected, { severity: :severity? }),

        KBS::Condition.new(:symptom, {
          type: "body_aches",
          present: true
        }),

        KBS::Condition.new(:symptom, {
          type: "fatigue",
          present: true
        }),

        KBS::Condition.new(:diagnosis, { disease: "flu" }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        # Calculate confidence based on symptom presence
        base_confidence = 0.6

        # Adjust for fever severity
        fever_bonus = bindings[:severity?] == "high" ? 0.2 : 0.1

        # Check for additional symptoms
        cough = @engine.facts.any? { |f|
          f.type == :symptom && f[:type] == "cough" && f[:present]
        }
        cough_bonus = cough ? 0.1 : 0.0

        confidence = [base_confidence + fever_bonus + cough_bonus, 1.0].min

        @engine.add_fact(:diagnosis, {
          disease: "flu",
          confidence: confidence,
          symptoms: ["fever", "body_aches", "fatigue"]
        })

        @explanations << {
          rule: "hypothesize_flu",
          reasoning: "Classic flu triad: fever + body aches + fatigue",
          confidence: confidence
        }
      end
    end

    # Rule 3: Strep throat hypothesis
    strep_rule = KBS::Rule.new("hypothesize_strep_throat", priority: 90) do |r|
      r.conditions = [
        KBS::Condition.new(:symptom, {
          type: "sore_throat",
          severity: :throat_severity?
        }),

        KBS::Condition.new(:symptom, {
          type: "swollen_lymph_nodes",
          present: true
        }),

        KBS::Condition.new(:fever_detected, {}),

        # No cough (distinguishes from viral)
        KBS::Condition.new(:symptom, {
          type: "cough",
          present: true
        }, negated: true),

        KBS::Condition.new(:diagnosis, { disease: "strep_throat" }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        base_confidence = 0.7

        # Severe sore throat increases confidence
        severity_bonus = bindings[:throat_severity?] == "severe" ? 0.2 : 0.1

        confidence = [base_confidence + severity_bonus, 0.95].min

        @engine.add_fact(:diagnosis, {
          disease: "strep_throat",
          confidence: confidence,
          symptoms: ["sore_throat", "swollen_lymph_nodes", "fever", "no_cough"]
        })

        @explanations << {
          rule: "hypothesize_strep_throat",
          reasoning: "Sore throat + swollen nodes + fever WITHOUT cough suggests bacterial infection",
          confidence: confidence
        }
      end
    end

    # Rule 4: Common cold hypothesis
    cold_rule = KBS::Rule.new("hypothesize_cold", priority: 85) do |r|
      r.conditions = [
        KBS::Condition.new(:symptom, {
          type: "runny_nose",
          present: true
        }),

        KBS::Condition.new(:symptom, {
          type: "sneezing",
          present: true
        }),

        KBS::Condition.new(:symptom, {
          type: "congestion",
          present: true
        }),

        # Mild or no fever
        KBS::Condition.new(:fever_detected, {
          severity: "high"
        }, negated: true),

        KBS::Condition.new(:diagnosis, { disease: "common_cold" }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        confidence = 0.75

        # Adjust if low fever present
        low_fever = @engine.facts.any? { |f|
          f.type == :fever_detected && f[:severity] == "low"
        }
        confidence += 0.1 if low_fever

        @engine.add_fact(:diagnosis, {
          disease: "common_cold",
          confidence: confidence,
          symptoms: ["runny_nose", "sneezing", "congestion"]
        })

        @explanations << {
          rule: "hypothesize_cold",
          reasoning: "Upper respiratory symptoms without high fever typical of viral cold",
          confidence: confidence
        }
      end
    end

    # Rule 5: Allergy hypothesis
    allergy_rule = KBS::Rule.new("hypothesize_allergy", priority: 85) do |r|
      r.conditions = [
        KBS::Condition.new(:symptom, {
          type: "sneezing",
          frequency: :freq?
        }, predicate: lambda { |f| f[:frequency] == "frequent" }),

        KBS::Condition.new(:symptom, {
          type: "itchy_eyes",
          present: true
        }),

        KBS::Condition.new(:symptom, {
          type: "runny_nose",
          present: true
        }),

        # No fever (key differentiator from infection)
        KBS::Condition.new(:fever_detected, {}, negated: true),

        KBS::Condition.new(:diagnosis, { disease: "allergies" }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        confidence = 0.8

        @engine.add_fact(:diagnosis, {
          disease: "allergies",
          confidence: confidence,
          symptoms: ["frequent_sneezing", "itchy_eyes", "runny_nose", "no_fever"]
        })

        @explanations << {
          rule: "hypothesize_allergy",
          reasoning: "Frequent sneezing + itchy eyes + runny nose WITHOUT fever suggests allergic reaction",
          confidence: confidence
        }
      end
    end

    # Rule 6: Migraine hypothesis
    migraine_rule = KBS::Rule.new("hypothesize_migraine", priority: 88) do |r|
      r.conditions = [
        KBS::Condition.new(:symptom, {
          type: "headache",
          location: "unilateral",
          severity: :severity?
        }, predicate: lambda { |f| f[:severity] == "severe" }),

        KBS::Condition.new(:symptom, {
          type: "nausea",
          present: true
        }),

        KBS::Condition.new(:symptom, {
          type: "light_sensitivity",
          present: true
        }),

        KBS::Condition.new(:diagnosis, { disease: "migraine" }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        base_confidence = 0.85

        # Check for aura
        aura = @engine.facts.any? { |f|
          f.type == :symptom && f[:type] == "visual_disturbance"
        }
        aura_bonus = aura ? 0.1 : 0.0

        confidence = [base_confidence + aura_bonus, 0.95].min

        @engine.add_fact(:diagnosis, {
          disease: "migraine",
          confidence: confidence,
          symptoms: ["severe_unilateral_headache", "nausea", "photophobia"]
        })

        @explanations << {
          rule: "hypothesize_migraine",
          reasoning: "Severe one-sided headache with nausea and light sensitivity characteristic of migraine",
          confidence: confidence
        }
      end
    end

    # Rule 7: Recommend diagnostic test
    test_rule = KBS::Rule.new("recommend_diagnostic_test", priority: 70) do |r|
      r.conditions = [
        KBS::Condition.new(:diagnosis, {
          disease: :disease?,
          confidence: :conf?
        }, predicate: lambda { |f| f[:confidence] > 0.7 && f[:confidence] < 0.9 }),

        KBS::Condition.new(:test_recommended, {
          disease: :disease?
        }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        test = diagnostic_test_for(bindings[:disease?])

        @engine.add_fact(:test_recommended, {
          disease: bindings[:disease?],
          test: test,
          reason: "Confidence #{bindings[:conf?]} warrants confirmation"
        })

        @explanations << {
          rule: "recommend_diagnostic_test",
          reasoning: "Moderate confidence (#{bindings[:conf?]}) suggests #{test} for confirmation",
          confidence: 1.0
        }
      end
    end

    # Rule 8: Final diagnosis
    final_diagnosis_rule = KBS::Rule.new("select_final_diagnosis", priority: 60) do |r|
      r.conditions = [
        KBS::Condition.new(:diagnosis, {
          disease: :disease?,
          confidence: :conf?
        }),

        KBS::Condition.new(:final_diagnosis, {}, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        # Find highest confidence diagnosis
        all_diagnoses = facts.select { |f| f.type == :diagnosis }
        best = all_diagnoses.max_by { |d| d[:confidence] }

        @engine.add_fact(:final_diagnosis, {
          disease: best[:disease],
          confidence: best[:confidence],
          symptoms: best[:symptoms],
          timestamp: Time.now
        })

        @explanations << {
          rule: "select_final_diagnosis",
          reasoning: "Selected #{best[:disease]} (#{best[:confidence]} confidence) as most likely diagnosis",
          confidence: 1.0
        }
      end
    end

    @engine.add_rule(fever_rule)
    @engine.add_rule(flu_rule)
    @engine.add_rule(strep_rule)
    @engine.add_rule(cold_rule)
    @engine.add_rule(allergy_rule)
    @engine.add_rule(migraine_rule)
    @engine.add_rule(test_rule)
    @engine.add_rule(final_diagnosis_rule)
  end

  def add_symptom(type, attributes = {})
    @engine.add_fact(:symptom, { type: type, **attributes })
  end

  def diagnose
    @explanations.clear
    @engine.run

    final = @engine.facts.find { |f| f.type == :final_diagnosis }

    {
      diagnosis: final,
      all_hypotheses: @engine.facts.select { |f| f.type == :diagnosis },
      explanations: @explanations,
      recommended_tests: @engine.facts.select { |f| f.type == :test_recommended }
    }
  end

  def explain_reasoning
    @explanations.each_with_index do |exp, i|
      puts "\n#{i + 1}. Rule: #{exp[:rule]} (Confidence: #{exp[:confidence]})"
      puts "   Reasoning: #{exp[:reasoning]}"
    end
  end

  private

  def calculate_fever_confidence(temp)
    case temp
    when 38.0..38.5
      0.6
    when 38.5..39.0
      0.75
    when 39.0..40.0
      0.9
    else
      0.95
    end
  end

  def fever_severity(temp)
    case temp
    when 38.0..38.5
      "low"
    when 38.5..39.5
      "moderate"
    else
      "high"
    end
  end

  def diagnostic_test_for(disease)
    {
      "flu" => "Rapid influenza test",
      "strep_throat" => "Rapid strep test (throat swab)",
      "migraine" => "MRI (if first occurrence or atypical presentation)",
      "common_cold" => "None (clinical diagnosis)",
      "allergies" => "Allergy skin test or IgE blood test"
    }[disease] || "Consult physician"
  end
end

# Usage Example 1: Flu Diagnosis
puts "=== Example 1: Flu Diagnosis ==="
system = MedicalExpertSystem.new(db_path: ':memory:')

system.add_symptom("temperature", value: 39.2)
system.add_symptom("body_aches", present: true)
system.add_symptom("fatigue", present: true)
system.add_symptom("cough", present: true)

result = system.diagnose

puts "\nFinal Diagnosis:"
if result[:diagnosis]
  puts "  Disease: #{result[:diagnosis][:disease]}"
  puts "  Confidence: #{(result[:diagnosis][:confidence] * 100).round(1)}%"
  puts "  Symptoms: #{result[:diagnosis][:symptoms].join(', ')}"
end

puts "\nAll Hypotheses:"
result[:all_hypotheses].each do |h|
  puts "  - #{h[:disease]}: #{(h[:confidence] * 100).round(1)}%"
end

puts "\nReasoning Chain:"
system.explain_reasoning

# Usage Example 2: Strep Throat
puts "\n\n=== Example 2: Strep Throat Diagnosis ==="
system2 = MedicalExpertSystem.new(db_path: ':memory:')

system2.add_symptom("temperature", value: 38.8)
system2.add_symptom("sore_throat", severity: "severe", present: true)
system2.add_symptom("swollen_lymph_nodes", present: true)
# Note: No cough symptom added

result2 = system2.diagnose

puts "\nFinal Diagnosis:"
if result2[:diagnosis]
  puts "  Disease: #{result2[:diagnosis][:disease]}"
  puts "  Confidence: #{(result2[:diagnosis][:confidence] * 100).round(1)}%"
end

if result2[:recommended_tests].any?
  puts "\nRecommended Tests:"
  result2[:recommended_tests].each do |test|
    puts "  - #{test[:test]} for #{test[:disease]}"
    puts "    Reason: #{test[:reason]}"
  end
end

puts "\nReasoning Chain:"
system2.explain_reasoning

# Usage Example 3: Allergies
puts "\n\n=== Example 3: Allergy Diagnosis ==="
system3 = MedicalExpertSystem.new(db_path: ':memory:')

system3.add_symptom("sneezing", frequency: "frequent", present: true)
system3.add_symptom("itchy_eyes", present: true)
system3.add_symptom("runny_nose", present: true)
system3.add_symptom("congestion", present: true)
# Note: No fever

result3 = system3.diagnose

puts "\nFinal Diagnosis:"
if result3[:diagnosis]
  puts "  Disease: #{result3[:diagnosis][:disease]}"
  puts "  Confidence: #{(result3[:diagnosis][:confidence] * 100).round(1)}%"
end

puts "\nReasoning Chain:"
system3.explain_reasoning
```

## Key Features

### 1. Knowledge Representation

Rules encode medical knowledge in a structured format:

```ruby
# Rule encodes: "IF fever AND body_aches AND fatigue THEN possibly flu"
KBS::Rule.new("hypothesize_flu") do |r|
  r.conditions = [
    KBS::Condition.new(:fever_detected, { severity: :severity? }),
    KBS::Condition.new(:symptom, { type: "body_aches", present: true }),
    KBS::Condition.new(:symptom, { type: "fatigue", present: true })
  ]

  r.action = lambda do |facts, bindings|
    # Calculate confidence and add diagnosis
  end
end
```

### 2. Confidence Factors

Probabilistic reasoning using confidence scores:

```ruby
base_confidence = 0.6
fever_bonus = bindings[:severity?] == "high" ? 0.2 : 0.1
cough_bonus = cough_present? ? 0.1 : 0.0

confidence = [base_confidence + fever_bonus + cough_bonus, 1.0].min
```

### 3. Explanation Facility

Track reasoning for transparency:

```ruby
@explanations << {
  rule: "hypothesize_flu",
  reasoning: "Classic flu triad: fever + body aches + fatigue",
  confidence: confidence
}
```

### 4. Differential Diagnosis

Multiple hypotheses with varying confidence:

```ruby
# System can maintain:
# - Flu: 85% confidence
# - Common cold: 60% confidence
# - Strep throat: 40% confidence

all_diagnoses = facts.select { |f| f.type == :diagnosis }
best = all_diagnoses.max_by { |d| d[:confidence] }
```

### 5. Negation for Diagnosis

Use absence of symptoms to refine diagnosis:

```ruby
# Strep throat: sore throat + fever WITHOUT cough
KBS::Condition.new(:symptom, {
  type: "cough",
  present: true
}, negated: true)
```

## Expert System Patterns

### Forward Chaining

Data-driven reasoning from symptoms to diagnosis:

```
Symptoms → Intermediate Facts → Hypotheses → Final Diagnosis
```

```ruby
# 1. Symptom facts added
add_symptom("temperature", value: 39.2)

# 2. Engine detects fever
fever_detected fact created

# 3. Engine hypothesizes diseases
diagnosis facts created

# 4. Engine selects best diagnosis
final_diagnosis fact created
```

### Backward Chaining

Goal-driven reasoning (query mode):

```ruby
class BackwardChainingExpert < MedicalExpertSystem
  def why_diagnosis?(disease)
    diagnosis = @engine.facts.find { |f|
      f.type == :diagnosis && f[:disease] == disease
    }

    return nil unless diagnosis

    # Find which symptoms led to this diagnosis
    required_symptoms = diagnosis[:symptoms]
    present_symptoms = @engine.facts.select { |f|
      f.type == :symptom && required_symptoms.include?(f[:type])
    }

    {
      disease: disease,
      confidence: diagnosis[:confidence],
      supporting_symptoms: present_symptoms,
      reasoning: @explanations.find { |e| e[:rule].include?(disease) }
    }
  end
end

# Usage
expert = BackwardChainingExpert.new
expert.add_symptom("fever", value: 39.0)
expert.add_symptom("body_aches", present: true)
expert.diagnose

why = expert.why_diagnosis?("flu")
puts "Why flu?"
puts "  Confidence: #{why[:confidence]}"
puts "  Supporting: #{why[:supporting_symptoms].map(&:type).join(', ')}"
```

### Certainty Factors

Combine evidence with certainty calculus:

```ruby
def combine_certainty_factors(cf1, cf2)
  if cf1 > 0 && cf2 > 0
    cf1 + cf2 * (1 - cf1)
  elsif cf1 < 0 && cf2 < 0
    cf1 + cf2 * (1 + cf1)
  else
    (cf1 + cf2) / (1 - [cf1.abs, cf2.abs].min)
  end
end

# Example: Multiple pieces of evidence for flu
fever_cf = 0.6
aches_cf = 0.4
cough_cf = 0.3

combined = combine_certainty_factors(fever_cf, aches_cf)
combined = combine_certainty_factors(combined, cough_cf)
# Result: Higher confidence with more evidence
```

### Meta-Rules

Rules about rules:

```ruby
# Meta-rule: If confidence moderate, recommend test
KBS::Rule.new("recommend_test_meta", priority: 50) do |r|
  r.conditions = [
    KBS::Condition.new(:diagnosis, {
      confidence: :conf?
    }, predicate: lambda { |f| f[:confidence].between?(0.5, 0.85) })
  ]

  r.action = lambda do |facts, bindings|
    @engine.add_fact(:action_needed, {
      type: "diagnostic_test",
      reason: "Confidence not high enough for treatment"
    })
  end
end
```

## Advanced Features

### Temporal Reasoning

Track symptom progression:

```ruby
class TemporalExpertSystem < MedicalExpertSystem
  def add_symptom_with_timing(type, onset, attributes = {})
    @engine.add_fact(:symptom, {
      type: type,
      onset: onset,
      **attributes
    })
  end

  def setup_temporal_rules
    # Rule: Rapid onset fever + headache suggests infection
    rapid_onset_rule = KBS::Rule.new("rapid_onset_infection") do |r|
      r.conditions = [
        KBS::Condition.new(:symptom, {
          type: "fever",
          onset: :onset1?
        }, predicate: lambda { |f|
          (Time.now - f[:onset]) < 3600 * 24  # < 24 hours
        }),

        KBS::Condition.new(:symptom, {
          type: "headache",
          onset: :onset2?
        }, predicate: lambda { |f|
          (Time.now - f[:onset]) < 3600 * 24
        })
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:diagnosis, {
          disease: "acute_infection",
          confidence: 0.75,
          reasoning: "Rapid onset suggests acute process"
        })
      end
    end

    @engine.add_rule(rapid_onset_rule)
  end
end
```

### Conflict Resolution

Handle contradictory evidence:

```ruby
# Rule: Resolve conflicting diagnoses
KBS::Rule.new("resolve_conflicts", priority: 55) do |r|
  r.conditions = [
    KBS::Condition.new(:diagnosis, {
      disease: "flu",
      confidence: :flu_conf?
    }),

    KBS::Condition.new(:diagnosis, {
      disease: "common_cold",
      confidence: :cold_conf?
    })
  ]

  r.action = lambda do |facts, bindings|
    # Flu and cold are mutually exclusive
    if bindings[:flu_conf?] > bindings[:cold_conf?]
      cold = facts.find { |f| f.type == :diagnosis && f[:disease] == "common_cold" }
      @engine.remove_fact(cold)
    else
      flu = facts.find { |f| f.type == :diagnosis && f[:disease] == "flu" }
      @engine.remove_fact(flu)
    end
  end
end
```

### Learning from Cases

Update confidence factors based on outcomes:

```ruby
class LearningExpertSystem < MedicalExpertSystem
  def initialize(db_path: 'medical_learning.db')
    super
    @case_history = load_case_history
  end

  def record_outcome(symptoms, actual_diagnosis)
    # Store case for learning
    @case_history << {
      symptoms: symptoms,
      diagnosis: actual_diagnosis,
      timestamp: Time.now
    }

    save_case_history
    update_confidence_weights
  end

  def update_confidence_weights
    # Analyze historical accuracy
    # Adjust confidence factors for rules
    @case_history.group_by { |c| c[:diagnosis] }.each do |disease, cases|
      accuracy = calculate_accuracy(disease, cases)
      adjust_rule_confidence(disease, accuracy)
    end
  end

  private

  def calculate_accuracy(disease, cases)
    # Calculate how often diagnosis was correct
    cases.count { |c| c[:confirmed] }.to_f / cases.size
  end

  def adjust_rule_confidence(disease, accuracy)
    # Modify confidence factors based on historical performance
    # Implementation depends on your confidence model
  end
end
```

## Testing

```ruby
require 'minitest/autorun'

class TestMedicalExpertSystem < Minitest::Test
  def setup
    @system = MedicalExpertSystem.new(db_path: ':memory:')
  end

  def test_flu_diagnosis
    @system.add_symptom("temperature", value: 39.0)
    @system.add_symptom("body_aches", present: true)
    @system.add_symptom("fatigue", present: true)

    result = @system.diagnose

    assert_equal "flu", result[:diagnosis][:disease]
    assert result[:diagnosis][:confidence] > 0.6
  end

  def test_strep_throat_vs_viral
    @system.add_symptom("temperature", value: 38.8)
    @system.add_symptom("sore_throat", severity: "severe", present: true)
    @system.add_symptom("swollen_lymph_nodes", present: true)
    # No cough - key differentiator

    result = @system.diagnose

    assert_equal "strep_throat", result[:diagnosis][:disease]
    assert result[:diagnosis][:confidence] > 0.7
  end

  def test_allergy_no_fever
    @system.add_symptom("sneezing", frequency: "frequent", present: true)
    @system.add_symptom("itchy_eyes", present: true)
    @system.add_symptom("runny_nose", present: true)

    result = @system.diagnose

    assert_equal "allergies", result[:diagnosis][:disease]

    # Should NOT detect fever
    fever_facts = @system.instance_variable_get(:@engine).facts.select { |f|
      f.type == :fever_detected
    }
    assert_empty fever_facts
  end

  def test_differential_diagnosis
    @system.add_symptom("temperature", value: 38.2)
    @system.add_symptom("runny_nose", present: true)
    @system.add_symptom("congestion", present: true)
    @system.add_symptom("sneezing", present: true)

    result = @system.diagnose

    # Should have multiple hypotheses
    assert result[:all_hypotheses].size > 1

    # Cold should win (has all symptoms)
    assert_equal "common_cold", result[:diagnosis][:disease]
  end

  def test_confidence_factors
    @system.add_symptom("temperature", value: 40.5)  # Very high fever
    @system.add_symptom("body_aches", present: true)
    @system.add_symptom("fatigue", present: true)
    @system.add_symptom("cough", present: true)

    result = @system.diagnose

    # High fever + all symptoms = high confidence
    assert result[:diagnosis][:confidence] > 0.8
  end

  def test_explanation_facility
    @system.add_symptom("temperature", value: 39.0)
    @system.add_symptom("body_aches", present: true)
    @system.add_symptom("fatigue", present: true)

    result = @system.diagnose

    explanations = result[:explanations]

    # Should have explanations for each rule fired
    assert explanations.size > 0

    # Each explanation should have rule, reasoning, confidence
    explanations.each do |exp|
      assert exp[:rule]
      assert exp[:reasoning]
      assert exp[:confidence]
    end
  end

  def test_diagnostic_test_recommendation
    @system.add_symptom("temperature", value: 38.5)
    @system.add_symptom("body_aches", present: true)
    @system.add_symptom("fatigue", present: true)
    # Moderate confidence scenario

    result = @system.diagnose

    # Should recommend confirmatory test if confidence moderate
    if result[:diagnosis][:confidence].between?(0.7, 0.9)
      assert result[:recommended_tests].any?
    end
  end
end
```

## Performance Optimization

### Use Blackboard for Complex Cases

```ruby
# For large knowledge bases, use persistent storage
system = MedicalExpertSystem.new(db_path: 'medical_kb.db')

# Facts persist across consultations
# Audit trail for medical record keeping
```

### Index Common Queries

```ruby
class OptimizedExpertSystem < MedicalExpertSystem
  def initialize(db_path:)
    super
    @symptom_index = {}
    @diagnosis_cache = {}
  end

  def add_symptom(type, attributes = {})
    super

    # Index for fast lookup
    @symptom_index[type] ||= []
    @symptom_index[type] << attributes
  end

  def has_symptom?(type)
    @symptom_index.key?(type)
  end
end
```

## Production Considerations

### Disclaimer and Safety

```ruby
def diagnose
  result = super

  result[:disclaimer] = "This is an expert system for educational purposes. " \
                        "Always consult a qualified healthcare professional " \
                        "for medical advice."

  result
end
```

### Audit Trail

```ruby
# Blackboard automatically logs all reasoning
system = MedicalExpertSystem.new(db_path: 'medical_audit.db')

# Later: Review consultation
consultation = system.instance_variable_get(:@engine)
  .fact_history
  .select { |h| h[:fact_type] == :diagnosis }

puts "Diagnosis history:"
consultation.each do |entry|
  puts "#{entry[:timestamp]}: #{entry[:attributes][:disease]} (#{entry[:attributes][:confidence]})"
end
```

### Integration with Clinical Systems

```ruby
class ClinicalExpertSystem < MedicalExpertSystem
  def import_from_ehr(patient_id, ehr_client)
    # Import symptoms from Electronic Health Record
    symptoms = ehr_client.get_symptoms(patient_id)

    symptoms.each do |symptom|
      add_symptom(symptom[:type], symptom[:attributes])
    end
  end

  def export_diagnosis_to_ehr(patient_id, ehr_client)
    result = diagnose

    ehr_client.add_note(patient_id, {
      type: "expert_system_consultation",
      diagnosis: result[:diagnosis],
      confidence: result[:diagnosis][:confidence],
      reasoning: result[:explanations],
      timestamp: Time.now
    })
  end
end
```

## Next Steps

- **[Multi-Agent Example](multi-agent.md)** - Multiple expert systems collaborating
- **[Blackboard Memory](../guides/blackboard-memory.md)** - Persistent knowledge bases
- **[Performance Guide](../advanced/performance.md)** - Optimize large knowledge bases
- **[Testing Guide](../advanced/testing.md)** - Test expert system rules

---

*Expert systems encode domain expertise in rules and reasoning. KBS provides the inference engine, you provide the knowledge.*
