# frozen_string_literal: true

module KBS
  class Rule
    attr_reader :name, :priority
    attr_accessor :conditions, :action

    def initialize(name, conditions: [], action: nil, priority: 0, &block)
      @name = name
      @conditions = conditions
      @action = action
      @priority = priority
      @fired_count = 0

      yield self if block_given?
    end

    def fire(facts)
      @fired_count += 1
      return unless @action

      bindings = extract_bindings(facts)

      # Support 0-parameter, 1-parameter and 2-parameter actions
      if @action.arity == 0
        @action.call
      elsif @action.arity == 1 || @action.arity == -1
        @action.call(facts)
      else
        @action.call(facts, bindings)
      end
    end

    def to_s
      lines = ["rule #{@name.inspect} do"]
      lines << "  priority #{@priority}" unless @priority.zero?

      @conditions.each do |condition|
        keyword = condition.negated ? "without" : "on"
        pattern = condition.pattern.map do |key, value|
          value = value.is_a?(Proc) ? KBS::Decompiler.new(value).decompile : value.inspect
          "#{key}: #{value}"
        end.join(", ")
        line = "  #{keyword} #{condition.type.inspect}"
        line += ", #{pattern}" unless pattern.empty?
        lines << line
      end

      if @action
        action = begin
          KBS::Decompiler.new(@action).decompile_block
        rescue StandardError => e
          "{ <decompilation failed: #{e.message}> }"
        end
        lines << "  perform #{action}"
      end

      lines << "end"
      lines.join("\n")
    end

    private

    def extract_bindings(facts)
      bindings = {}
      @conditions.each_with_index do |condition, index|
        next if condition.negated
        fact = facts[index]
        condition.variable_bindings.each do |var, field|
          bindings[var] = fact.attributes[field] if fact
        end
      end
      bindings
    end
  end
end
