# frozen_string_literal: true

require 'cucumber/multiline_argument'

module Cucumber
  # Represents the match found between a Test Step and its activation
  class StepMatch #:nodoc:
    attr_reader :step_definition, :step_arguments

    def initialize(step_definition, step_name, step_arguments)
      raise "step_arguments can't be nil (but it can be an empty array)" if step_arguments.nil?
      @step_definition = step_definition
      @name_to_match = step_name
      @step_arguments = step_arguments
    end

    def args
      current_world = @step_definition.registry.current_world
      @step_arguments.map do |arg|
        arg.value(current_world)
      end
    end

    def activate(test_step)
      test_step.with_action(@step_definition.location) do
        invoke(MultilineArgument.from_core(test_step.multiline_arg))
      end
    end

    def invoke(multiline_arg)
      all_args = args
      multiline_arg.append_to(all_args)
      @step_definition.invoke(all_args)
    end

    # Formats the matched arguments of the associated Step. This method
    # is usually called from visitors, which render output.
    #
    # The +format+ can either be a String or a Proc.
    #
    # If it is a String it should be a format string according to
    # <tt>Kernel#sprinf</tt>, for example:
    #
    #   '<span class="param">%s</span></tt>'
    #
    # If it is a Proc, it should take one argument and return the formatted
    # argument, for example:
    #
    #   lambda { |param| "[#{param}]" }
    #
    def format_args(format = ->(a) { a }, &proc)
      replace_arguments(@name_to_match, @step_arguments, format, &proc)
    end

    def location
      @step_definition.location
    end

    def file_colon_line
      location.to_s
    end

    def backtrace_line
      "#{file_colon_line}:in `#{@step_definition.expression}'"
    end

    def text_length
      @step_definition.expression.source.to_s.unpack('U*').length
    end

    def replace_arguments(string, step_arguments, format)
      s = string.dup
      offset = past_offset = 0
      step_arguments.each do |step_argument|
        group = step_argument.group
        next if group.value.nil? || group.start < past_offset

        replacement = if block_given?
                        yield(group.value)
                      elsif Proc == format.class
                        format.call(group.value)
                      else
                        format % group.value
                      end

        s[group.start + offset, group.value.length] = replacement
        offset += replacement.unpack('U*').length - group.value.unpack('U*').length
        past_offset = group.start + group.value.length
      end
      s
    end

    def inspect #:nodoc:
      "#<#{self.class}: #{location}>"
    end
  end

  class SkippingStepMatch
    def activate(test_step)
      test_step.with_action { raise Core::Test::Result::Skipped }
    end
  end

  class NoStepMatch #:nodoc:
    attr_reader :step_definition, :name

    def initialize(step, name)
      @step = step
      @name = name
    end

    def format_args(*_args)
      @name
    end

    def location
      raise "No location for #{@step}" unless @step.location
      @step.location
    end

    def file_colon_line
      location.to_s
    end

    def backtrace_line
      @step.backtrace_line
    end

    def text_length
      @step.text.length
    end

    def step_arguments
      []
    end

    def activate(test_step)
      # noop
      test_step
    end
  end

  class AmbiguousStepMatch
    def initialize(error)
      @error = error
    end

    def activate(test_step)
      test_step.with_action { raise @error }
    end
  end
end
