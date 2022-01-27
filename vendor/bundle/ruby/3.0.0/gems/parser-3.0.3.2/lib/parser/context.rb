# frozen_string_literal: true

module Parser
  # Context of parsing that is represented by a stack of scopes.
  #
  # Supported states:
  # + :class - in the class body (class A; end)
  # + :module - in the module body (module M; end)
  # + :sclass - in the singleton class body (class << obj; end)
  # + :def - in the method body (def m; end)
  # + :defs - in the singleton method body (def self.m; end)
  # + :def_open_args - in the arglist of the method definition
  #                    keep in mind that it's set **only** after reducing the first argument,
  #                    if you need to handle the first argument check `lex_state == expr_fname`
  # + :block - in the block body (tap {})
  # + :lambda - in the lambda body (-> {})
  #
  class Context
    attr_reader :stack

    def initialize
      @stack = []
      freeze
    end

    def push(state)
      @stack << state
    end

    def pop
      @stack.pop
    end

    def reset
      @stack.clear
    end

    def empty?
      @stack.empty?
    end

    def in_class?
      @stack.last == :class
    end

    def indirectly_in_def?
      @stack.include?(:def) || @stack.include?(:defs)
    end

    def class_definition_allowed?
      def_index = stack.rindex { |item| [:def, :defs].include?(item) }
      sclass_index = stack.rindex(:sclass)

      def_index.nil? || (!sclass_index.nil? && sclass_index > def_index)
    end
    alias module_definition_allowed? class_definition_allowed?
    alias dynamic_const_definition_allowed? class_definition_allowed?

    def in_block?
      @stack.last == :block
    end

    def in_lambda?
      @stack.last == :lambda
    end

    def in_dynamic_block?
      in_block? || in_lambda?
    end

    def in_def_open_args?
      @stack.last == :def_open_args
    end
  end
end
