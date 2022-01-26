# frozen_string_literal: true

module Cucumber
  module Formatter
    # The formatter used for <tt>--format steps</tt>
    class Steps
      def initialize(runtime, path_or_io, options)
        @io = ensure_io(path_or_io, nil)
        @options = options
        @step_definition_files = collect_steps(runtime)
      end

      def after_features(_features)
        print_summary
      end

      private

      def print_summary
        count = 0
        @step_definition_files.keys.sort.each do |step_definition_file|
          @io.puts step_definition_file

          sources = @step_definition_files[step_definition_file]
          source_indent = source_indent(sources)
          sources.sort.each do |file_colon_line, regexp_source|
            @io.print regexp_source.indent(2)
            @io.print " # #{file_colon_line}".indent(source_indent - regexp_source.unpack('U*').length)
            @io.puts
          end
          @io.puts
          count += sources.size
        end
        @io.puts "#{count} step definition(s) in #{@step_definition_files.size} source file(s)."
      end

      def collect_steps(runtime)
        runtime.step_definitions.each_with_object({}) do |step_definition, step_definitions|
          step_definitions[step_definition.file] ||= []
          step_definitions[step_definition.file] << [step_definition.file_colon_line, step_definition.regexp_source]
        end
      end

      def source_indent(sources)
        sources.map { |_file_colon_line, regexp| regexp.size }.max + 1
      end
    end
  end
end
