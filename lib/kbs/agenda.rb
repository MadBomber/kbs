# frozen_string_literal: true

module KBS
  # A rule matched by a token, waiting on the agenda to fire.
  class Activation
    attr_reader :node, :token, :salience, :rule_order, :timetag
    attr_accessor :sort_key

    def initialize(node, token, rule_order:, timetag:)
      @node = node
      @token = token
      @salience = node.rule.priority
      @rule_order = rule_order
      @timetag = timetag
      @cancelled = false
    end

    def rule
      @node.rule
    end

    def cancel!
      @cancelled = true
    end

    def cancelled?
      @cancelled
    end

    def to_s
      "#{@salience} #{rule.name}: #{@token.facts.map(&:to_s).join(', ')}"
    end
  end

  # The conflict set: every activation that has not fired yet, ordered
  # by rule priority (salience) and then by the conflict resolution
  # strategy.
  #
  #   :definition  rules in the order they were added, each rule's
  #                activations oldest first (the default)
  #   :depth       newest activation first
  #   :breadth     oldest activation first
  #
  # Activations sit in a binary heap. Removing one marks it cancelled and
  # it is dropped when it reaches the top, so add, remove and pop are
  # O(log n).
  class Agenda
    STRATEGIES = %i[definition depth breadth].freeze

    attr_reader :strategy

    def initialize(strategy: :definition)
      validate_strategy(strategy)
      @strategy = strategy
      @heap = []
      @size = 0
      @timetag = 0
    end

    def strategy=(strategy)
      validate_strategy(strategy)
      @strategy = strategy
      pending = to_a
      @heap = []
      pending.each { |activation| push(activation) }
    end

    # @return [Activation] the new activation, to pass to #remove later
    def add(node, token, rule_order: 0)
      activation = Activation.new(node, token, rule_order: rule_order, timetag: @timetag += 1)
      push(activation)
      @size += 1
      activation
    end

    def remove(activation)
      return if activation.nil? || activation.cancelled?

      activation.cancel!
      @size -= 1
    end

    # Removes and returns the next activation to fire, or nil when empty.
    def pop
      drop_cancelled
      return nil if @heap.empty?

      activation = pop_top
      activation.cancel!
      @size -= 1
      activation
    end

    def peek
      drop_cancelled
      @heap.first
    end

    def empty?
      @size.zero?
    end

    attr_reader :size

    def clear
      @heap.each(&:cancel!)
      @heap = []
      @size = 0
    end

    # Pending activations in firing order.
    def to_a
      @heap.reject(&:cancelled?).sort_by(&:sort_key)
    end

    def sort_key_for(activation)
      case @strategy
      when :depth then [-activation.salience, -activation.timetag, 0]
      when :breadth then [-activation.salience, activation.timetag, 0]
      else [-activation.salience, activation.rule_order, activation.timetag]
      end
    end

    private

    def validate_strategy(strategy)
      return if STRATEGIES.include?(strategy)

      raise ArgumentError, "unknown strategy #{strategy.inspect}; use one of #{STRATEGIES.inspect}"
    end

    def drop_cancelled
      pop_top while @heap.first&.cancelled?
    end

    def push(activation)
      activation.sort_key = sort_key_for(activation)
      @heap << activation
      sift_up(@heap.size - 1)
    end

    def pop_top
      top = @heap.first
      last = @heap.pop
      unless @heap.empty?
        @heap[0] = last
        sift_down(0)
      end
      top
    end

    def before?(a, b)
      (@heap[a].sort_key <=> @heap[b].sort_key).negative?
    end

    def sift_up(index)
      while index.positive?
        parent = (index - 1) / 2
        break unless before?(index, parent)

        @heap[index], @heap[parent] = @heap[parent], @heap[index]
        index = parent
      end
    end

    def sift_down(index)
      loop do
        smallest = index
        [2 * index + 1, 2 * index + 2].each do |child|
          smallest = child if child < @heap.size && before?(child, smallest)
        end
        break if smallest == index

        @heap[index], @heap[smallest] = @heap[smallest], @heap[index]
        index = smallest
      end
    end
  end
end
