# frozen_string_literal: true

require_relative "lib/kbs/version"

Gem::Specification.new do |spec|
  spec.name = "kbs"
  spec.version = KBS::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dvanhoozer@gmail.com"]

  spec.summary = "Production-ready Knowledge-Based System with RETE II inference, Blackboard architecture, and AI integration"
  spec.description = <<~DESC
    A comprehensive Ruby implementation of a Knowledge-Based System featuring:

    • RETE II Algorithm: Optimized forward-chaining inference engine with unlinking optimization for high-performance pattern matching
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

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "sqlite3", "~> 1.6"

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.16"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "redis", "~> 5.0"
end
