# frozen_string_literal: true

module KBS
  # Writes a line for each change the engine makes while an item is
  # being watched:
  #
  #   :facts        ==> fact :sensor, id: 1        a fact entered working memory
  #                 <== fact :sensor, id: 1        a fact left it
  #   :activations  ==> Activation 0 hot: ...      a rule match went on the agenda
  #                 <== Activation 0 hot: ...      a match was withdrawn before it fired
  #   :rules        FIRE 1 hot: ...                a rule fired; the number counts firings
  #
  # An activation is written as its rule's priority, the rule's name, and
  # one entry per condition: the matched fact, or * for a negated or
  # exists condition.
  class Tracer
    ITEMS = %i[facts activations rules].freeze

    # Where the lines go: anything that responds to puts.
    attr_accessor :output

    def initialize(output = $stdout)
      @output = output
      @watched = Set.new
      @firings = 0
    end

    # Starts watching the given items, or every item when none is given.
    def watch(*items)
      @watched.merge(validated(items))
      self
    end

    # Stops watching the given items, or every item when none is given.
    def unwatch(*items)
      @watched.subtract(validated(items))
      self
    end

    def watching?(item)
      @watched.include?(item)
    end

    def watched
      ITEMS.select { |item| @watched.include?(item) }
    end

    def fact_added(fact)
      @output.puts "==> #{fact}" if watching?(:facts)
    end

    def fact_removed(fact)
      @output.puts "<== #{fact}" if watching?(:facts)
    end

    def activation_added(activation)
      @output.puts "==> Activation #{activation}" if watching?(:activations)
    end

    def activation_removed(activation)
      @output.puts "<== Activation #{activation}" if watching?(:activations)
    end

    def rule_fired(activation)
      @firings += 1
      @output.puts "FIRE #{@firings} #{activation.description}" if watching?(:rules)
    end

    private

    def validated(items)
      return ITEMS if items.empty?

      unknown = items - ITEMS
      raise ArgumentError, "cannot watch #{unknown.inspect}; use #{ITEMS.inspect}" unless unknown.empty?

      items
    end
  end
end
