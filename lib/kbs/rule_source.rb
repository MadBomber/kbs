# frozen_string_literal: true

module KBS
  # Writes a rule as DSL source, from its parts. Procs in patterns and the
  # action are decompiled; one that can't be is replaced by a placeholder.
  #
  #   KBS::RuleSource.new(name: "hot", conditions: rule.conditions).to_s
  #   # => "rule \"hot\" do\n  on :sensor\nend"
  class RuleSource
    def initialize(name:, conditions:, action: nil, priority: 0, description: nil)
      @name = name
      @conditions = conditions
      @action = action
      @priority = priority
      @description = description
    end

    def to_s
      ["rule #{@name.inspect} do", *header_lines, *condition_lines, *action_lines, "end"].join("\n")
    end

    # The desc and priority lines, when the rule has them.
    def header_lines
      lines = []
      lines << "  desc #{@description.inspect}" if @description
      lines << "  priority #{@priority}" unless @priority.zero?
      lines
    end

    # One line per condition, the leading logical ones inside a
    # `logical do ... end` block.
    def condition_lines
      count = @conditions.take_while(&:logical).size
      lines = @conditions.each_with_index.map do |condition, index|
        RuleSource.condition_line(condition, index < count ? "    " : "  ")
      end
      return lines if count.zero?

      lines.insert(count, "  end").unshift("  logical do")
    end

    def action_lines
      @action ? ["  perform #{RuleSource.block_source(@action)}"] : []
    end

    class << self
      def condition_line(condition, indent)
        pattern = pattern_source(condition.pattern)
        line = "#{indent}#{condition.keyword} #{condition.type.inspect}"
        pattern.empty? ? line : "#{line}, #{pattern}"
      end

      # A pattern as the keyword arguments of a condition.
      def pattern_source(pattern)
        pattern.map { |key, value| "#{key}: #{value_source(value)}" }.join(", ")
      end

      def value_source(value)
        return value.inspect unless value.is_a?(Proc)

        Decompiler.new(value).decompile
      rescue StandardError => e
        "<decompilation failed: #{e.message}>"
      end

      # A proc as a block literal: { |params| body }
      def block_source(block)
        Decompiler.new(block).decompile_block
      rescue StandardError => e
        "{ <decompilation failed: #{e.message}> }"
      end
    end
  end
end
