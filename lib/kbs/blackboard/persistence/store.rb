# frozen_string_literal: true

module KBS
  module Blackboard
    module Persistence
      # Abstract interface for fact persistence
      class Store
        def add_fact(uuid, type, attributes)
          raise NotImplementedError, "#{self.class} must implement #add_fact"
        end

        def remove_fact(uuid)
          raise NotImplementedError, "#{self.class} must implement #remove_fact"
        end

        def update_fact(uuid, attributes)
          raise NotImplementedError, "#{self.class} must implement #update_fact"
        end

        def get_fact(uuid)
          raise NotImplementedError, "#{self.class} must implement #get_fact"
        end

        def get_facts(type = nil, pattern = {})
          raise NotImplementedError, "#{self.class} must implement #get_facts"
        end

        def query_facts(conditions = nil, params = [])
          raise NotImplementedError, "#{self.class} must implement #query_facts"
        end

        def clear_session(session_id)
          raise NotImplementedError, "#{self.class} must implement #clear_session"
        end

        def stats
          raise NotImplementedError, "#{self.class} must implement #stats"
        end

        def close
          raise NotImplementedError, "#{self.class} must implement #close"
        end

        def vacuum
          # Optional operation - no-op by default
        end

        def transaction(&block)
          # Default: just execute the block
          yield if block_given?
        end
      end
    end
  end
end
