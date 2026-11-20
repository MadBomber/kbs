# frozen_string_literal: true

module KBS
  class Engine
    attr_reader :working_memory, :rules, :alpha_memories, :production_nodes, :agenda

    # @param strategy [Symbol] conflict resolution strategy; see KBS::Agenda
    # @param fact_duplication [Boolean] whether working memory may hold two
    #   facts with the same type and attributes; see #fact_duplication=
    def initialize(strategy: :definition, fact_duplication: true)
      @fact_duplication = fact_duplication
      @fact_registry = FactRegistry.new
      @matching = false
      @truth_maintenance = TruthMaintenance.new
      @pending_retractions = []
      @retracting = false
      @firing = nil
      @agenda = Agenda.new(strategy: strategy)
      @halted = false
      @working_memory = WorkingMemory.new
      @rules = []
      @alpha_network = AlphaNetwork.new
      @alpha_memories = @alpha_network.memories
      @fact_memories = {}
      @beta_nodes = []
      @production_nodes = {}
      @root_beta_memory = BetaMemory.new

      # Add initial dummy token to root beta memory
      # This represents "no conditions matched yet" and allows the first condition to match
      @root_beta_memory.add_token(Token.new(nil, nil, nil))

      @working_memory.add_observer(self)
    end

    def add_rule(rule)
      unless rule.logical_conditions_first?
        raise ArgumentError, "rule #{rule.name.inspect}: logical conditions must come before the other conditions"
      end

      @rules << rule
      build_network_for_rule(rule)
    end

    # Adds a fact to working memory and matches it against the rules.
    #
    # With fact duplication off, a fact equal to one already in working
    # memory is not added and the existing fact is returned.
    #
    # A fact added by the action of a rule with logical conditions is
    # supported by the match of those conditions and is retracted when
    # that match goes away. If the match is already gone, because an
    # earlier step of the same action removed it, the fact is not added
    # and nil is returned.
    def add_fact(type, attributes = {})
      ensure_not_matching!
      support = current_support
      return nil if support&.retracted?

      existing = duplicate_of(type, attributes)
      if existing
        reinforce(existing, support)
        return existing
      end

      fact = create_fact(type, attributes)
      attach_support(fact, support) if support
      fact
    end

    # Makes the fact and puts it in working memory, which matches it.
    def create_fact(type, attributes)
      fact = Fact.new(type, attributes)
      @working_memory.add_fact(fact)
      fact
    end

    def remove_fact(fact)
      ensure_not_matching!
      @working_memory.remove_fact(fact)
    end

    # Changes a fact's attributes and matches it again, as a retraction
    # followed by an assertion: matches that depended on the old values
    # go away, and rules the new values satisfy are activated, including
    # rules that already fired for this fact.
    #
    # Setting an attribute with fact[:key] = value does not do this; the
    # network keeps matching the values the fact had when it was added.
    #
    # @param changes [Hash] attributes to merge into the fact's
    # @return [KBS::Fact, nil] the fact; the existing equal fact when
    #   duplication is off and the change makes this fact a duplicate (this
    #   fact is then removed); nil when the fact is not in working memory
    def modify(fact, changes)
      ensure_not_matching!
      return nil unless @working_memory.include?(fact)

      @working_memory.remove_fact(fact)
      existing = duplicate_of(fact.type, fact.attributes.merge(changes))
      return existing if existing

      fact.attributes.merge!(changes)
      @working_memory.add_fact(fact)
    end

    # Whether working memory may hold two facts with the same type and
    # attributes. True by default.
    attr_reader :fact_duplication

    # Turning duplication off makes add_fact return the existing fact
    # instead of adding an equal one. Duplicates already in working
    # memory stay.
    def fact_duplication=(allowed)
      @fact_duplication = allowed
      @fact_registry.clear
      @working_memory.facts.each { |fact| @fact_registry.add(fact) } unless allowed
    end

    # The fact in working memory with this type and attributes, when
    # duplication is off; nil otherwise.
    def duplicate_of(type, attributes)
      return nil if @fact_duplication

      @fact_registry.find(type, attributes)
    end

    # Whether `fact` was asserted under logical conditions and will be
    # retracted when the matches that support it are gone.
    def logically_supported?(fact)
      @truth_maintenance.supported?(fact)
    end

    # The matches that support `fact`, each as the facts that matched the
    # rule's logical conditions. Empty for an unconditional fact.
    def dependencies(fact)
      @truth_maintenance.supports_of(fact).map(&:facts)
    end

    # The facts that will lose a support if `fact` is retracted.
    def dependents(fact)
      @truth_maintenance.facts_depending_on(fact)
    end

    # A beta memory calls this when a token that can support facts
    # leaves it. Facts left without support are retracted once the
    # current match is done.
    def token_removed(token)
      token.mark_retracted!
      @pending_retractions.concat(@truth_maintenance.withdraw(token))
    end

    # The token that supports facts asserted right now: the match of the
    # firing rule's logical conditions. nil outside such a rule.
    def current_support
      return nil unless @firing

      rule = @firing.rule
      logical = rule.logical_count
      return nil if logical.zero?

      token = @firing.token
      (rule.conditions.size - logical).times { token = token.parent }
      token
    end

    # A fact that already exists was asserted again. From a logical rule
    # it gains a support, unless it is unconditional. From anywhere else
    # it becomes unconditional.
    def reinforce(fact, support)
      if support.nil?
        @truth_maintenance.release(fact)
      elsif @truth_maintenance.supported?(fact)
        @truth_maintenance.support(fact, support)
      end
    end

    # Records the support of a new fact. Matching the fact may itself
    # have removed the support, in which case the fact goes straight
    # back out.
    def attach_support(fact, support)
      if support.retracted?
        @pending_retractions << fact
      else
        @truth_maintenance.support(fact, support)
      end
      retract_unsupported_facts
    end

    # Retracts the facts whose last support was withdrawn. Retracting
    # one can withdraw the support of others; the loop takes those too.
    def retract_unsupported_facts
      return if @matching || @retracting

      @retracting = true
      begin
        while (fact = @pending_retractions.shift)
          remove_fact(fact)
        end
      ensure
        @retracting = false
      end
    end

    # Every join, negation and exists node in the network. Rules that
    # start with the same conditions share nodes, so there can be fewer
    # nodes than conditions.
    def beta_nodes
      @beta_nodes.dup
    end

    # Whether the engine is matching a fact right now.
    def matching?
      @matching
    end

    def ensure_not_matching!
      raise MatchInProgressError if @matching
    end

    def facts
      @working_memory.facts
    end

    # Working memory calls this when a fact is added or removed.
    def update(action, fact)
      ensure_not_matching!
      @matching = true
      begin
        if action == :add
          @fact_registry.add(fact) unless @fact_duplication
          match_fact(fact)
        elsif action == :remove
          @fact_registry.remove(fact)
          @truth_maintenance.release(fact)
          unmatch_fact(fact)
        end
      ensure
        @matching = false
      end
      retract_unsupported_facts
    end

    # Sends a new fact to every alpha memory whose pattern it matches,
    # and remembers which ones, so that retracting it needs no matching.
    def match_fact(fact)
      memories = matching_alpha_memories(fact)
      return if memories.empty?

      @fact_memories[fact] = memories
      memories.each { |memory| memory.activate(fact) }
    end

    # Takes a fact out of the alpha memories it went into. The fact is
    # not matched again, so this works even if its attributes changed.
    def unmatch_fact(fact)
      memories = @fact_memories.delete(fact)
      memories&.each { |memory| memory.deactivate(fact) }
    end

    # The alpha memories whose pattern `fact` matches.
    def matching_alpha_memories(fact)
      @alpha_network.memories_for(fact)
    end

    # The alpha memories that hold `fact`.
    def alpha_memories_for(fact)
      @fact_memories.fetch(fact, []).dup
    end

    # Fires activations from the agenda until it is empty: the highest
    # priority first, then by the agenda's strategy. Facts that a rule
    # asserts or retracts change the agenda before the next firing, so
    # rules chain within one run. An activation fires once.
    #
    # @param limit [Integer, nil] stop after this many firings
    # @return [Integer] the number of rules fired
    def run(limit = nil)
      @halted = false
      fired = 0

      until @halted || (limit && fired >= limit)
        activation = @agenda.pop
        break unless activation

        fire_activation(activation)
        fired += 1
      end

      fired
    end

    # Stops the current run after the rule that is firing. Call it from a
    # rule action.
    def halt
      @halted = true
    end

    def strategy
      @agenda.strategy
    end

    def strategy=(strategy)
      @agenda.strategy = strategy
    end

    def fire_activation(activation)
      @firing = activation
      activation.node.fire_rule(activation.token)
    ensure
      @firing = nil
    end

    # Production nodes in firing order: higher rule priority first, and
    # definition order among rules of equal priority.
    def prioritized_production_nodes
      @production_nodes.values.sort_by.with_index { |node, index| [-node.rule.priority, index] }
    end

    # Clear all transient RETE state while preserving the compiled rule network.
    #
    # The RETE network has four levels of transient state:
    #   1. WorkingMemory — holds all asserted facts
    #   2. AlphaMemory   — holds facts matching each pattern
    #   3. BetaMemory    — holds tokens from condition joins
    #   4. ProductionNode — holds tokens ready to fire
    #
    # Simply clearing working memory facts doesn't cascade reliably
    # through intermediate beta memories. Stale tokens in beta memories
    # cause false matches when new facts are asserted on the next cycle.
    #
    # This method clears all four levels directly while preserving the
    # root beta memory's dummy token (needed for first-condition joins).
    def reset
      # 1. Clear working memory directly (bypass observer — we clear everything)
      @working_memory.clear if @working_memory.respond_to?(:clear)
      @fact_memories.clear
      @fact_registry.clear
      @truth_maintenance.clear
      @pending_retractions.clear

      # 2. Clear alpha memories and their downstream beta memories
      @alpha_memories.each_value do |alpha_mem|
        alpha_mem.clear

        # Each alpha memory successor is a JoinNode or NegationNode.
        # Their successors are intermediate BetaMemory nodes.
        # The root beta memory is never a join node successor, so
        # its dummy token is preserved.
        alpha_mem.successors.each do |join_node|
          join_node.reset if join_node.respond_to?(:reset)
          next unless join_node.respond_to?(:successors)
          join_node.successors.each do |beta_or_prod|
            beta_or_prod.clear if beta_or_prod.is_a?(BetaMemory)
          end
        end
      end

      # 3. Clear production node tokens and their pending activations
      @production_nodes.each_value(&:reset)
      @agenda.clear

      # 4. Clear stale child references from the root dummy token
      @root_beta_memory.each_token { |t| t.clear_children }

      # 5. Restore leading negation matches for the now-empty working memory
      @root_beta_memory.successors.grep(NegationNode).each do |node|
        @root_beta_memory.tokens.each { |token| node.left_activate(token) }
      end
    end

    private

    def build_network_for_rule(rule)
      current_beta = @root_beta_memory

      join_tests = JoinTestBuilder.new(rule.conditions).tests
      logical_count = rule.logical_count

      rule.conditions.each_with_index do |condition, index|
        # Build alpha memory pattern - merge condition type
        pattern = condition.pattern.merge(type: condition.type)
        alpha_memory = get_or_create_alpha_memory(pattern)
        tests = join_tests[index]

        node = shareable_node(current_beta, node_class_for(condition), alpha_memory, tests) ||
               build_node(current_beta, node_class_for(condition), alpha_memory, tests)
        current_beta = node.successors.grep(BetaMemory).first
        current_beta.listener = self if index == logical_count - 1
      end

      production_node = ProductionNode.new(rule, @agenda, order: @rules.size)
      current_beta.successors << production_node
      @production_nodes[rule.name] = production_node
      unless rule.conditions.empty?
        current_beta.tokens.each { |token| production_node.activate(token) }
      end
    end

    # A node already below `beta_memory` that does the same work: the
    # same kind of node, on the same alpha memory, with the same tests.
    # Rules that start with the same conditions share those nodes and
    # the partial matches in their beta memories.
    def shareable_node(beta_memory, node_class, alpha_memory, tests)
      beta_memory.successors.find do |node|
        node.instance_of?(node_class) && node.alpha_memory.equal?(alpha_memory) && node.tests == tests
      end
    end

    # A new node with its beta memory, brought up to date with the
    # tokens already in `beta_memory`.
    def build_node(beta_memory, node_class, alpha_memory, tests)
      node = node_class.new(alpha_memory, beta_memory, tests)
      node.successors << BetaMemory.new
      @beta_nodes << node
      beta_memory.tokens.each { |token| node.left_activate(token) }
      node
    end

    def node_class_for(condition)
      return NegationNode if condition.negated
      return ExistsNode if condition.exists

      JoinNode
    end

    # A new alpha memory starts with the facts already in working memory.
    # Facts go straight into its items: the memory has no successors yet,
    # and existing alpha memories already hold their facts.
    def get_or_create_alpha_memory(pattern)
      @alpha_network.fetch(pattern) do |memory|
        @working_memory.facts.each do |fact|
          next unless fact.matches?(pattern)

          memory.add_item(fact)
          (@fact_memories[fact] ||= []) << memory
        end
      end
    end
  end
end
