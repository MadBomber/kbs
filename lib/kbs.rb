# frozen_string_literal: true

require_relative "kbs/version"

# Core RETE II classes
require_relative "kbs/fact"
require_relative "kbs/working_memory"
require_relative "kbs/token"
require_relative "kbs/alpha_memory"
require_relative "kbs/beta_memory"
require_relative "kbs/join_node"
require_relative "kbs/negation_node"
require_relative "kbs/production_node"
require_relative "kbs/condition"
require_relative "kbs/rule"
require_relative "kbs/rete_engine"

module KBS
  class Error < StandardError; end
end
