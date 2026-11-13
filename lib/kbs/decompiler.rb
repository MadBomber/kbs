# frozen_string_literal: true

module KBS
  # Reconstruct Ruby source from YARV bytecode.
  #
  # YARV bytecode is a stack machine.  We simulate the stack,
  # translating instructions back into Ruby expressions.
  #
  # Usage:
  #   KBS::Decompiler.new(some_proc).decompile       # => "proc { |x| x + 1 }"
  #   KBS::Decompiler.new(some_lambda).decompile      # => "->(x) { x + 1 }"
  #   KBS::Decompiler.new(some_proc).decompile_block   # => "{ |x| x + 1 }"
  #
  class Decompiler
    # Classes whose #inspect is Ruby source for an equal value.
    LITERAL_CLASSES = [Integer, Symbol, NilClass, TrueClass, FalseClass].freeze

    def initialize(proc_obj)
      @iseq  = RubyVM::InstructionSequence.of(proc_obj)
      @arr   = @iseq.to_a
      @locals = @arr[10]          # [:a, :b, ...]
      @params = @arr[11]          # {lead_num: 2, ...}
      @body   = @arr[13]          # [1, :EVENT, [:instruction, ...], ...]
      @children = []
      @iseq.each_child { |c| @children << c }
      @child_index = 0
      @proc = proc_obj
      @outer_locals = []          # local tables of enclosing blocks
    end

    def decompile
      expr = decompile_body(@body)
      params = build_params
      if @proc.lambda?
        "->(#{params}) { #{expr} }"
      else
        "proc { |#{params}| #{expr} }"
      end
    end

    # Returns just the block literal: { |params| body }
    # Useful when the surrounding keyword (perform, satisfies, etc.)
    # is supplied by the caller.
    def decompile_block
      expr = decompile_body(@body)
      params = build_params
      if params.empty?
        "{ #{expr} }"
      else
        "{ |#{params}| #{expr} }"
      end
    end

    private

    def build_params
      count = @params[:lead_num] || 0
      @locals.first(count).join(", ")
    end

    def decompile_body(body)
      stack = []
      statements = []
      instructions = body.select { |i| i.is_a?(Array) }
      steps = body.select { |i| i.is_a?(Array) || label?(i) }
      pending = []        # open && / || operators waiting for their label
      or_exprs = {}.compare_by_identity
      skip = 0

      steps.each_with_index do |inst, index|
        if skip.positive?
          skip -= 1
          next
        end

        if label?(inst)
          close_logical_ops(inst, pending, stack, or_exprs)
          next
        end

        op = inst[0]
        case op
        when :dup
          logical = logical_op_at(steps, index)
          if logical
            pending.push([logical, stack.pop, steps[index + 1][1]])
            skip = 2
          else
            stack.push("/* dup */")
          end

        when :getlocal_WC_0
          idx = inst[1]
          name = slot_to_name(idx)
          stack.push(name.to_s)

        when :getlocal_WC_1
          name = if @outer_locals.empty?
                   captured_value(inst[1])
                 else
                   slot_to_name(inst[1], @outer_locals.last).to_s
                 end
          stack.push(name || '/* getlocal_WC_1 */')

        when :setlocal_WC_0
          idx = inst[1]
          name = slot_to_name(idx)
          val = stack.pop
          statements << "#{name} = #{val}"

        when :putobject
          stack.push(inst[1].inspect)

        when :putobject_INT2FIX_0_
          stack.push("0")

        when :putobject_INT2FIX_1_
          stack.push("1")

        when :putself
          stack.push("self")

        when :putnil
          stack.push("nil")

        when :putchilledstring, :putstring
          stack.push(inst[1].inspect)

        when :opt_plus, :opt_minus, :opt_mult, :opt_div, :opt_mod,
             :opt_eq, :opt_neq, :opt_lt, :opt_le, :opt_gt, :opt_ge,
             :opt_ltlt
          op_sym = inst.last[:mid] # opt_neq carries == then !=
          b = stack.pop
          a = stack.pop
          stack.push("#{a} #{op_sym} #{b}")

        when :opt_send_without_block
          calldata = inst[1]
          method   = calldata[:mid]
          argc     = calldata[:orig_argc]
          args = stack.pop(argc)
          receiver = stack.pop
          call_str = format_call(receiver, method, args)
          stack.push(call_str)

        when :send
          calldata = inst[1]
          method   = calldata[:mid]
          argc     = calldata[:orig_argc]
          args     = stack.pop(argc)
          receiver = stack.pop

          child_iseq = @children[@child_index]
          @child_index += 1
          child_src = decompile_child(child_iseq)

          base = format_call(receiver, method, args)
          stack.push("#{base} { #{child_src} }")

        when :newarray
          count = inst[1]
          items = stack.pop(count)
          stack.push("[#{items.join(', ')}]")

        when :newhash
          count = inst[1]
          pairs = stack.pop(count)
          entries = pairs.each_slice(2).map { |k, v| "#{k} => #{v}" }
          stack.push("{ #{entries.join(', ')} }")

        when :branchunless
          condition = stack.pop
          remaining = instructions[instructions.index(inst) + 1..]
          true_val = extract_value(remaining, 0)
          false_val = extract_value(remaining, 1)
          if true_val && false_val
            stack.push("#{condition} ? #{true_val} : #{false_val}")
            break
          end

        when :leave
          # ignore

        when :pop
          val = stack.pop
          statements << val if val

        else
          stack.push("/* #{op} */")
        end
      end

      all = statements + [stack.last].compact
      all.join("; ")
    end

    # Ruby compiles `a && b` as `a; dup; branchunless L; pop; b; L:`, and
    # `a || b` the same way with branchif. Returns "&&" or "||" when the
    # dup at index starts that sequence, else nil.
    def logical_op_at(steps, index)
      branch, pop = steps[index + 1], steps[index + 2]
      return unless pop.is_a?(Array) && pop[0] == :pop && branch.is_a?(Array)

      { branchunless: "&&", branchif: "||" }[branch[0]]
    end

    # At a jump target, joins each pending operator whose branch goes
    # there with the expression on top of the stack, innermost first.
    # An || result used as either side of && is parenthesized.
    def close_logical_ops(label, pending, stack, or_exprs)
      while pending.any? && pending.last[2] == label
        op, left, _label = pending.pop
        right = stack.pop
        left, right = [left, right].map { |side| or_exprs.key?(side) ? "(#{side})" : side } if op == "&&"
        expr = "#{left} #{op} #{right}"
        or_exprs[expr] = true if op == "||"
        stack.push(expr)
      end
    end

    def label?(item)
      item.is_a?(Symbol) && item.start_with?("label_")
    end

    def format_call(receiver, method, args)
      prefix = (receiver == "self") ? "" : "#{receiver}."
      if args.empty?
        "#{prefix}#{method}"
      else
        "#{prefix}#{method}(#{args.join(', ')})"
      end
    end

    def decompile_child(child_iseq)
      child_arr = child_iseq.to_a
      child_locals = child_arr[10]
      child_params = child_arr[11]
      child_body   = child_arr[13]
      count = child_params[:lead_num] || 0
      param_names = child_locals.first(count).join(", ")

      saved = [@locals, @params, @body]
      @outer_locals.push(@locals)
      @locals, @params, @body = child_locals, child_params, child_body
      expr = decompile_body(child_body)
      @locals, @params, @body = saved
      @outer_locals.pop

      if count > 0
        "|#{param_names}| #{expr}"
      else
        expr
      end
    end

    def extract_value(instructions, index)
      values = instructions.select { |i|
        i.is_a?(Array) && (i[0] == :putchilledstring || i[0] == :putstring || i[0] == :putobject)
      }
      val = values[index]
      val[1].inspect if val
    end

    # The value of a variable the proc captured from the method that
    # created it, as Ruby source, or nil when it can't be resolved or has
    # no literal form.
    def captured_value(slot_idx)
      table = creator_locals or return nil
      value = @proc.binding.local_variable_get(slot_to_name(slot_idx, table))
      value.inspect if literal?(value)
    rescue NameError, TypeError
      nil
    end

    def literal?(value)
      case value
      when Float then value.finite?
      when String
        value.instance_of?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding?
      else LITERAL_CLASSES.include?(value.class)
      end
    end

    # Local table of the method whose body created the proc, or nil when
    # the proc was made anywhere else (a nested block, a class body, the
    # top level), where the slot would index some other scope.
    def creator_locals
      return @creator_locals if defined?(@creator_locals)

      @creator_locals = begin
        scope = @proc.binding
        name = scope.eval('__method__')
        method = name && Kernel.instance_method(:method).bind_call(scope.receiver, name)
        creating_iseq(method)&.to_a&.[](10)
      rescue NameError, TypeError, ArgumentError
        nil
      end
    end

    # Walks the method's super chain for the definition whose body holds
    # the proc as a direct child.
    def creating_iseq(method)
      while method
        iseq = RubyVM::InstructionSequence.of(method)
        return iseq if iseq && direct_child?(iseq)

        method = method.super_method
      end
    end

    def direct_child?(iseq)
      iseq.each_child { |child| return true if child.to_a == @arr }
      false
    end

    def slot_to_name(slot_idx, locals = @locals)
      locals[locals.size + 2 - slot_idx] || "?local_#{slot_idx}"
    end
  end
end
