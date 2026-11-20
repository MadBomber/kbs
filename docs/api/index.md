# API Reference

Complete class documentation for KBS.

## Core Classes
- **[Engine](engine.md)** - `KBS::Engine`, the RETE engine: rules, facts, `modify`, duplicate-fact rejection, the agenda and truth maintenance; also `KBS::Blackboard::Engine`
- **[Facts & Conditions](facts.md)** - `KBS::Fact`, `KBS::Blackboard::Fact`, `KBS::WorkingMemory` and `KBS::Condition`; pattern matching
- **[Rules](rules.md)** - `KBS::Rule`, production rules
- **[Blackboard](blackboard.md)** - `KBS::Blackboard::Memory`, message queues, audit logs and the persistence stores (`SqliteStore`, `RedisStore`, `HybridStore`). Load with `require 'kbs/blackboard'`

## Architecture
See [Architecture Overview](../architecture/index.md) for system design.
