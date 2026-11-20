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

    # Marks a lookup that has not been tried yet; its result may be nil.
    UNRESOLVED = Object.new.freeze

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
      @creator_locals = UNRESOLVED
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

    # The state of one pass over a body: the simulated stack, the
    # statements finished so far, the && / || operators still waiting
    # for their label, the || expressions built (to parenthesize them
    # inside &&), how many steps to skip, and whether the pass is over.
    Pass = Struct.new(:steps, :stack, :statements, :pending, :or_exprs, :skip, :done)

    # Instructions that push a fixed piece of source.
    FIXED_SOURCES = {
      putobject_INT2FIX_0_: "0",
      putobject_INT2FIX_1_: "1",
      putself: "self",
      putnil: "nil"
    }.freeze

    BINARY_OPERATIONS = %i[
      opt_plus opt_minus opt_mult opt_div opt_mod
      opt_eq opt_neq opt_lt opt_le opt_gt opt_ge opt_ltlt
    ].freeze

    # Instruction => the method that translates it.
    HANDLERS = {
      dup: :translate_dup,
      getlocal_WC_0: :translate_getlocal,
      getlocal_WC_1: :translate_outer_getlocal,
      setlocal_WC_0: :translate_setlocal,
      putobject: :translate_literal,
      putchilledstring: :translate_literal,
      dupchilledstring: :translate_literal,
      putstring: :translate_literal,
      opt_send_without_block: :translate_call,
      send: :translate_call_with_block,
      newarray: :translate_newarray,
      newhash: :translate_newhash,
      branchunless: :translate_branchunless,
      pop: :translate_pop,
      leave: :translate_nothing,
      nop: :translate_nothing # Ruby 3.x starts a block with nop
    }.merge(BINARY_OPERATIONS.to_h { |op| [op, :translate_binary] }).freeze

    private_constant :Pass, :FIXED_SOURCES, :BINARY_OPERATIONS, :HANDLERS

    def decompile_body(body)
      pass = new_pass(body)
      pass.steps.each_with_index do |inst, index|
        break if pass.done

        translate_step(pass, inst, index)
      end
      body_source(pass)
    end

    def new_pass(body)
      steps = body.select { |item| item.is_a?(Array) || label?(item) }
      Pass.new(steps, [], [], [], {}.compare_by_identity, 0, false)
    end

    # Translates one step, unless an earlier step already consumed it.
    def translate_step(pass, inst, index)
      if pass.skip.positive?
        pass.skip -= 1
      elsif label?(inst)
        close_logical_ops(inst, pass.pending, pass.stack, pass.or_exprs)
      else
        translate_instruction(pass, inst, index)
      end
    end

    def translate_instruction(pass, inst, index)
      op = inst[0]
      fixed = FIXED_SOURCES[op]
      handler = HANDLERS[op]
      if fixed
        pass.stack.push(fixed)
      elsif handler
        send(handler, pass, inst, index)
      else
        pass.stack.push("/* #{op} */")
      end
    end

    # The source of a finished pass: its statements, then the value left
    # on the stack. An operator whose label lies outside the steps never
    # closed, and becomes a placeholder.
    def body_source(pass)
      pending = pass.pending
      return "/* #{pending.last[0]} */" if pending.any?

      (pass.statements + [pass.stack.last].compact).join("; ")
    end

    def translate_dup(pass, _inst, index)
      steps = pass.steps
      stack = pass.stack
      logical = logical_op_at(steps, index)
      if logical
        pass.pending.push([logical, stack.pop, steps[index + 1][1]])
        pass.skip = 2
      else
        stack.push("/* dup */")
      end
    end

    def translate_getlocal(pass, inst, _index)
      pass.stack.push(slot_to_name(inst[1]).to_s)
    end

    def translate_outer_getlocal(pass, inst, _index)
      slot = inst[1]
      name = if @outer_locals.empty?
               captured_value(slot)
             else
               slot_to_name(slot, @outer_locals.last).to_s
             end
      pass.stack.push(name || '/* getlocal_WC_1 */')
    end

    def translate_setlocal(pass, inst, _index)
      pass.statements << "#{slot_to_name(inst[1])} = #{pass.stack.pop}"
    end

    def translate_literal(pass, inst, _index)
      pass.stack.push(inst[1].inspect)
    end

    def translate_binary(pass, inst, _index)
      stack = pass.stack
      right = stack.pop
      left = stack.pop
      stack.push("#{left} #{inst.last[:mid]} #{right}") # opt_neq carries == then !=
    end

    def translate_call(pass, inst, _index)
      pass.stack.push(pop_call(pass.stack, inst[1]))
    end

    def translate_call_with_block(pass, inst, _index)
      call = pop_call(pass.stack, inst[1])
      child_iseq = @children[@child_index]
      @child_index += 1
      pass.stack.push("#{call} { #{decompile_child(child_iseq)} }")
    end

    # Takes a call's arguments and receiver off the stack and returns the
    # call as source.
    def pop_call(stack, calldata)
      args = stack.pop(calldata[:orig_argc])
      format_call(stack.pop, calldata[:mid], args)
    end

    def translate_newarray(pass, inst, _index)
      stack = pass.stack
      stack.push("[#{stack.pop(inst[1]).join(', ')}]")
    end

    def translate_newhash(pass, inst, _index)
      stack = pass.stack
      entries = stack.pop(inst[1]).each_slice(2).map { |key, value| "#{key} => #{value}" }
      stack.push("{ #{entries.join(', ')} }")
    end

    # Ends the pass: what follows is the two branches of a ternary.
    # Anything else on the stack, such as from a bare branchif, would be
    # lost, so that case becomes a placeholder.
    def translate_branchunless(pass, inst, index)
      stack = pass.stack
      lone = stack.size == 1
      stack.push(lone ? ternary(stack.pop, pass.steps[(index + 1)..], inst[1]) : '/* branchunless */')
      pass.done = true
    end

    def translate_pop(pass, _inst, _index)
      value = pass.stack.pop
      pass.statements << value if value
    end

    def translate_nothing(_pass, _inst, _index); end

    # Ruby compiles `a && b` as `a; dup; branchunless L; pop; b; L:`, and
    # `a || b` the same way with branchif. Returns "&&" or "||" when the
    # dup at index starts that sequence, else nil.
    def logical_op_at(steps, index)
      branch = steps[index + 1]
      pop = steps[index + 2]
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
      prefix = receiver == "self" ? "" : "#{receiver}."
      if args.empty?
        "#{prefix}#{method}"
      else
        "#{prefix}#{method}(#{args.join(', ')})"
      end
    end

    def decompile_child(child_iseq)
      child = child_iseq.to_a
      locals = child[10]
      params = child[11]
      count = params[:lead_num] || 0
      expr = in_scope(locals, params, child[13]) { decompile_body(@body) }

      count.positive? ? "|#{locals.first(count).join(', ')}| #{expr}" : expr
    end

    # Runs the block with a nested block's locals, parameters and body in
    # place of the current ones.
    def in_scope(locals, params, body)
      saved = [@locals, @params, @body]
      @outer_locals.push(@locals)
      @locals = locals
      @params = params
      @body = body
      yield
    ensure
      @locals, @params, @body = saved
      @outer_locals.pop
    end

    # `cond ? a : b` compiles to `branchunless L; a; leave; L: b; leave`.
    # Any other shape becomes a placeholder, so the condition is never
    # silently dropped.
    def ternary(condition, rest, else_label)
      split = rest.index(else_label)
      sources = split && [rest[0...split], rest[(split + 1)..]].map { |steps| branch_source(steps) }
      return '/* branchunless */' unless sources&.all?

      "#{condition} ? #{sources.join(' : ')}"
    end

    # Source of a ternary branch that ends the block with one
    # expression, else nil.
    def branch_source(steps)
      return unless steps.last.is_a?(Array) && steps.last[0] == :leave

      src = decompile_body(steps)
      src unless src.empty? || src.include?(';')
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
      return @creator_locals unless @creator_locals.equal?(UNRESOLVED)

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
