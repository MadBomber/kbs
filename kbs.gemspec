# frozen_string_literal: true

require_relative "lib/kbs/version"

Gem::Specification.new do |spec|
  spec.name = "kbs"
  spec.version = KBS::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dewayne@vanhoozer.me"]

  spec.summary = "Knowledge-Based System using RETE II algorithm for forward-chaining inference"
  spec.description = "A Ruby implementation of a Knowledge-Based System featuring the RETE II algorithm with unlinking optimization, declarative DSL for rule definition, and Blackboard architecture for multi-agent coordination. Supports SQLite and Redis persistence backends."
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
