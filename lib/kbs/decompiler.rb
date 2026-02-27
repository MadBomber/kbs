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
    def initialize(proc_obj)
      @iseq  = RubyVM::InstructionSequence.of(proc_obj)
      @arr   = @iseq.to_a
      @locals = @arr[10]          # [:a, :b, ...]
      @params = @arr[11]          # {lead_num: 2, ...}
      @body   = @arr[13]          # [1, :EVENT, [:instruction, ...], ...]
      @children = []
      @iseq.each_child { |c| @children << c }
      @child_index = 0
      @lambda = proc_obj.lambda?
    end

    def decompile
      expr = decompile_body(@body)
      params = build_params
      if @lambda
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

      instructions.each do |inst|
        op = inst[0]
        case op
        when :getlocal_WC_0
          idx = inst[1]
          name = slot_to_name(idx)
          stack.push(name.to_s)

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
          op_sym = inst[1][:mid]
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
      @locals, @params, @body = child_locals, child_params, child_body
      expr = decompile_body(child_body)
      @locals, @params, @body = saved

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

    def slot_to_name(slot_idx)
      name_idx = @locals.size + 2 - slot_idx
      @locals[name_idx] || "?local_#{slot_idx}"
    end
  end
end
