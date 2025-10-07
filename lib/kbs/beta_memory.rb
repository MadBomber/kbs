# frozen_string_literal: true

module KBS
  class BetaMemory
    attr_accessor :tokens, :successors
    attr_reader :linked

    def initialize
      @tokens = []
      @successors = []
      @linked = true
    end

    def unlink!
      @linked = false
      @successors.each { |s| s.left_unlink! if s.respond_to?(:left_unlink!) }
    end

    def relink!
      @linked = true
      @successors.each { |s| s.left_relink! if s.respond_to?(:left_relink!) }
    end

    def activate(token)
      add_token(token)
      @successors.each do |s|
        if s.respond_to?(:left_activate)
          s.left_activate(token)
        elsif s.respond_to?(:activate)
          s.activate(token)
        end
      end
    end

    def deactivate(token)
      remove_token(token)
      @successors.each do |s|
        if s.respond_to?(:left_deactivate)
          s.left_deactivate(token)
        elsif s.respond_to?(:deactivate)
          s.deactivate(token)
        end
      end
    end

    def add_token(token)
      @tokens << token
      unlink! if @tokens.empty?
      relink! if @tokens.size == 1
    end

    def remove_token(token)
      @tokens.delete(token)
      unlink! if @tokens.empty?
    end
  end
end
