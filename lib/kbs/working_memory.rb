# frozen_string_literal: true

module KBS
  class WorkingMemory
    attr_reader :facts

    def initialize
      @facts = []
      @observers = []
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

    def add_observer(observer)
      @observers << observer
    end

    def notify_observers(action, fact)
      @observers.each { |obs| obs.update(action, fact) }
    end
  end
end
