# frozen_string_literal: true

require_relative '../kbs'

# Blackboard pattern components
require_relative 'blackboard/fact'
require_relative 'blackboard/message_queue'
require_relative 'blackboard/audit_log'
require_relative 'blackboard/redis_message_queue'
require_relative 'blackboard/redis_audit_log'
require_relative 'blackboard/persistence/store'
require_relative 'blackboard/persistence/sqlite_store'
require_relative 'blackboard/persistence/redis_store'
require_relative 'blackboard/persistence/hybrid_store'
require_relative 'blackboard/memory'
require_relative 'blackboard/engine'

# Backward compatibility aliases (deprecated - will be removed in v1.0)
module KBS
  BlackboardMemory = Blackboard::Memory
  BlackboardEngine = Blackboard::Engine
  PersistedFact = Blackboard::Fact
end
