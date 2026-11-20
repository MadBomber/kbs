# frozen_string_literal: true

module KBS
  # What a memory may ask of any node below it. A node overrides the
  # calls it acts on; the rest do nothing, so a memory can tell every
  # successor the same thing without asking what kind of node it is.
  module NetworkNode
    def left_unlink!; end

    def left_relink!; end

    def right_unlink!; end

    def right_relink!; end

    # A fact left the node's alpha memory.
    def right_deactivate(_fact); end

    private

    # Passes a new token on to the memories below this node.
    def activate_successors(token)
      @successors.each { |successor| successor.activate(token) }
    end

    # Takes a token back from the memories below this node.
    def deactivate_successors(token)
      @successors.each { |successor| successor.deactivate(token) }
    end
  end
end
