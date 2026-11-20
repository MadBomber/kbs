# frozen_string_literal: true

module KBS
  # The set of facts the engine knows, with observers told of each change.
  class WorkingMemory
    def initialize
      @facts = Set.new
      @observers = []
    end

    # @return [Array<KBS::Fact>] the facts, in the order they were added.
    #   A copy: changing it does not change working memory.
    def facts
      @facts.to_a
    end

    def each_fact(&)
      @facts.each(&)
    end

    def size
      @facts.size
    end

    def include?(fact)
      @facts.include?(fact)
    end

    def add_fact(fact)
      @facts << fact
      notify_observers(:add, fact)
      fact
    end

    def remove_fact(fact)
      @facts.delete(fact)
      notify_observers(:remove, fact)
      fact
    end

    # Forgets every fact without telling the observers.
    def clear
      @facts.clear
    end

    def add_observer(observer)
      @observers << observer
    end

    def notify_observers(action, fact)
      @observers.each { |obs| obs.update(action, fact) }
    end
  end
end
