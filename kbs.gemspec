# frozen_string_literal: true

require_relative "lib/kbs/version"

Gem::Specification.new do |spec|
  spec.name = "kbs"
  spec.version = KBS::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dvanhoozer@gmail.com"]

  spec.summary = "Knowledge-Based System with RETE inference, Blackboard architecture, and AI integration"
  spec.description = <<~DESC
    A comprehensive Ruby implementation of a Knowledge-Based System featuring:

    • RETE Algorithm: Optimized forward-chaining inference engine with unlinking optimization for high-performance pattern matching
    • Declarative DSL: Readable, expressive syntax for rule definition with built-in condition helpers
    • Blackboard Architecture: Multi-agent coordination with message passing and knowledge source registration
    • Flexible Persistence: SQLite (durable), Redis (fast), and hybrid storage backends with audit trails
    • Concurrent Execution: Thread-safe auto-inference mode for real-time processing
    • AI Integration: Native support for LLM integration (Ollama, OpenAI) for hybrid symbolic/neural reasoning
    • Production Features: Session management, fact history, query API, statistics tracking

    Perfect for expert systems, trading algorithms, IoT monitoring, portfolio management, and AI-enhanced decision systems.
  DESC
  spec.homepage = "https://github.com/madbomber/kbs"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/madbomber/kbs"
  spec.metadata["changelog_uri"] = "https://github.com/madbomber/kbs/blob/main/CHANGELOG.md"

  # Ship only the library and the top-level docs; the docs site, examples,
  # benchmarks and repo plumbing stay in the repository.
  spec.files = Dir.glob(%w[lib/**/*.rb README.md CHANGELOG.md LICENSE.txt], base: __dir__)
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "sqlite3", ">= 1.6"

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.16"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "redis", "~> 5.0"
end
