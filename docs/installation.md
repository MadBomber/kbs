# Installation

## Requirements

- **Ruby**: 2.7 or higher
- **SQLite3**: For persistent blackboard memory (optional)
- **Redis**: For high-performance persistence (optional)

## Installing the Gem

### From RubyGems

```bash
gem install kbs
```

### Using Bundler

Add to your `Gemfile`:

```ruby
gem 'kbs'
```

Then run:

```bash
bundle install
```

### From Source

```bash
git clone https://github.com/madbomber/kbs.git
cd kbs
bundle install
rake install
```

## Optional Dependencies

### SQLite3 (Default Blackboard Backend)

```bash
gem install sqlite3
```

Or in your `Gemfile`:

```ruby
gem 'sqlite3'
```

### Redis (High-Performance Backend)

Install Redis server:

```bash
# macOS
brew install redis
brew services start redis

# Ubuntu/Debian
sudo apt-get install redis-server
sudo systemctl start redis

# Docker
docker run -d -p 6379:6379 redis:latest
```

Install Ruby Redis gem:

```bash
gem install redis
```

Or in your `Gemfile`:

```ruby
gem 'redis'
```

## Verification

Verify the installation:

```ruby
require 'kbs'

puts "KBS version: #{KBS::VERSION}"
# => KBS version: 0.1.0

# Test basic functionality
engine = KBS::Engine.new
engine.add_fact(:test, value: 42)
puts "✓ KBS is working!"
```

## Development Setup

For contributing or running tests:

```bash
git clone https://github.com/madbomber/kbs.git
cd kbs
bundle install

# Run tests
bundle exec rake test

# Run examples
bundle exec ruby examples/working_demo.rb
```

## Troubleshooting

### SQLite3 Installation Issues

On macOS with M1/M2:

```bash
gem install sqlite3 -- --with-sqlite3-include=/opt/homebrew/opt/sqlite/include \
  --with-sqlite3-lib=/opt/homebrew/opt/sqlite/lib
```

On Ubuntu/Debian:

```bash
sudo apt-get install libsqlite3-dev
gem install sqlite3
```

### Redis Connection Issues

Check Redis is running:

```bash
redis-cli ping
# => PONG
```

Test connection from Ruby:

```ruby
require 'redis'
redis = Redis.new(url: 'redis://localhost:6379/0')
redis.ping
# => "PONG"
```

## Next Steps

- **[Quick Start Guide](quick-start.md)** - Build your first rule-based system
- **[RETE Algorithm](architecture/rete-algorithm.md)** - Understand the engine
- **[Writing Rules](guides/writing-rules.md)** - Master the DSL
- **[Examples](examples/index.md)** - See real-world applications
