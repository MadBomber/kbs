# frozen_string_literal: true

module KBS
  # A rule matched by a token, waiting on the agenda to fire.
  class Activation
    attr_reader :node, :token, :salience, :rule_order, :timetag

    # The conflict resolution strategy of the agenda the activation is on,
    # which #sort_key follows. Set by the agenda; :definition until then.
    attr_accessor :strategy

    def initialize(node, token, rule_order:, timetag:)
      @node = node
      @token = token
      @salience = node.rule.priority
      @rule_order = rule_order
      @timetag = timetag
      @cancelled = false
      @strategy = :definition
    end

    # Where the activation sorts on its agenda, lowest first. Built when
    # asked for: the agenda orders activations without it.
    def sort_key
      key_for(@strategy)
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

    # The rule's name and one entry per condition, separated by "; ": the
    # matched fact, or * for a negated or exists condition.
    def description
      "#{rule.name}: #{@token.slots.map { |fact| fact ? fact.to_s : '*' }.join('; ')}"
    end

    # Cancels the activation unless it already is.
    #
    # @return [Boolean] whether this call cancelled it
    def withdraw
      return false if @cancelled

      @cancelled = true
    end

    # Where the activation sorts on an agenda that uses `strategy`:
    # lowest first.
    def key_for(strategy)
      priority = -@salience
      case strategy
      when :depth then [priority, -@timetag, 0]
      when :breadth then [priority, @timetag, 0]
      else [priority, @rule_order, @timetag]
      end
    end

    def to_s
      "#{@salience} #{description}"
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
  # Activations are grouped the way CLIPS groups them: by salience, and
  # under :definition also by rule. Groups are kept in firing order, and
  # within a group the order follows from where an activation is put:
  # :depth takes the newest first (a stack), the others the oldest first
  # (a queue). Nothing is compared to add or pop an activation; only an
  # add that opens a new group finds its place, by binary search on a
  # number. Removing an activation marks it cancelled, and it is dropped
  # when it reaches the front of its group.
  class Agenda
    # Activations taken oldest first.
    class Fifo
      def initialize
        @items = []
      end

      def <<(activation)
        @items << activation
        self
      end

      # self when an activation is pending, after dropping the cancelled
      # ones in front of it; nil otherwise.
      def front
        @items.shift while @items.first&.cancelled?
        self unless @items.empty?
      end

      # The activation to take next. Call #front first.
      def next
        @items.first
      end

      def take
        @items.shift
      end

      def each_activation(&)
        @items.each(&)
      end

      private

      attr_reader :items
    end

    # Activations taken newest first.
    class Lifo < Fifo
      def front
        items.pop while items.last&.cancelled?
        self unless items.empty?
      end

      def next
        items.last
      end

      def take
        items.pop
      end
    end

    # Members filed under numeric keys and kept in key order: the salience
    # levels of an agenda, or the rules within one level. A member is
    # made by the block when its key is first used, and is a Fifo, a Lifo
    # or another Groups.
    class Groups
      def initialize(&make)
        @make = make
        @members = {}
        @keys = []
      end

      # The member for `key`, made and filed in order if it is new.
      def fetch(key)
        @members[key] || file(key)
      end

      # The first queue with an activation pending, found through the
      # members in key order. Members left with nothing pending are
      # dropped on the way. nil when nothing is pending.
      def front
        until @keys.empty?
          queue = @members[@keys.first].front
          return queue if queue

          @members.delete(@keys.shift)
        end
        nil
      end

      def each_activation(&)
        @members.each_value { |member| member.each_activation(&) }
      end

      private

      # Activations mostly arrive for keys after the existing ones, so
      # the last key is checked before searching.
      def file(key)
        last = @keys.last
        position = last.nil? || last < key ? @keys.size : @keys.bsearch_index { |other| other >= key }
        @keys.insert(position, key)
        @members[key] = @make.call
      end
    end

    STRATEGIES = %i[definition depth breadth].freeze

    # For each strategy: the queue its groups use, and the key that files
    # an activation into a group within its salience level (the position
    # of its rule under :definition, one key for all otherwise).
    LAYOUTS = {
      definition: [Fifo, :rule_order.to_proc],
      depth: [Lifo, proc { 0 }],
      breadth: [Fifo, proc { 0 }]
    }.freeze

    attr_reader :strategy, :size

    # An object told about each activation that is added, and each one
    # removed before it fired, through activation_added(activation) and
    # activation_removed(activation).
    attr_accessor :listener

    def initialize(strategy: :definition)
      @listener = nil
      validate_strategy(strategy)
      @strategy = strategy
      @size = 0
      @timetag = 0
      @levels = self.class.levels_for(strategy)
      @rule_key = LAYOUTS.fetch(strategy).last
    end

    # Regroups the pending activations, oldest first, so each new group
    # is in timetag order whatever the old strategy was.
    def strategy=(strategy)
      validate_strategy(strategy)
      pending = to_a.sort_by(&:timetag)
      @strategy = strategy
      @levels = self.class.levels_for(strategy)
      @rule_key = LAYOUTS.fetch(strategy).last
      pending.each { |activation| push(activation) }
    end

    # @return [Activation] the new activation, to pass to #remove later
    def add(node, token, rule_order: 0)
      activation = Activation.new(node, token, rule_order: rule_order, timetag: @timetag += 1)
      push(activation)
      @size += 1
      @listener&.activation_added(activation)
      activation
    end

    def remove(activation)
      return unless activation&.withdraw

      @size -= 1
      @listener&.activation_removed(activation)
    end

    # Removes and returns the next activation to fire, or nil when empty.
    def pop
      activation = @levels.front&.take
      return nil unless activation

      activation.cancel!
      @size -= 1
      activation
    end

    def peek
      @levels.front&.next
    end

    def empty?
      @size.zero?
    end

    def clear
      @levels.each_activation(&:cancel!)
      @levels = self.class.levels_for(@strategy)
      @size = 0
    end

    # Pending activations in firing order.
    def to_a
      @levels.enum_for(:each_activation).reject(&:cancelled?).sort_by(&:sort_key)
    end

    def sort_key_for(activation)
      activation.key_for(@strategy)
    end

    # Empty salience levels for `strategy`. Each level holds one group per
    # rule under :definition, and a single group otherwise.
    def self.levels_for(strategy)
      queue = LAYOUTS.fetch(strategy).first
      Groups.new { Groups.new { queue.new } }
    end

    # The key of the salience level an activation is filed under: its
    # salience negated, so that higher salience sorts first, and
    # normalized, so that 1 and 1.0 share a level.
    def self.level_key(activation)
      -MemoryIndex.normalize(activation.salience)
    end

    private

    def validate_strategy(strategy)
      return if STRATEGIES.include?(strategy)

      raise ArgumentError, "unknown strategy #{strategy.inspect}; use one of #{STRATEGIES.inspect}"
    end

    def push(activation)
      activation.strategy = @strategy
      @levels.fetch(self.class.level_key(activation)).fetch(@rule_key.call(activation)) << activation
    end
  end
end
