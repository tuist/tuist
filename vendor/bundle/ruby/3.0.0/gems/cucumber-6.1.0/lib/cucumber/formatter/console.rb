# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength

require 'cucumber/formatter/ansicolor'
require 'cucumber/formatter/duration'
require 'cucumber/gherkin/i18n'

module Cucumber
  module Formatter
    # This module contains helper methods that are used by formatters that
    # print output to the terminal.
    #
    # FORMAT is a hash of Proc objects, keyed by step-definition types, e.g.
    # "FORMAT[:passed]".  The Proc is called for each line of the step's
    # output.
    #
    # format_step calls format_string, format_string calls format_for to obtain
    # the formatting Proc.
    #
    # Example:
    #
    # The ANSI color console formatter defines a map of step-type to output
    # color (e.g. "passed" to "green"), then builds methods named for the
    # step-types (e.g. "def passed"), which themselves wrap the corresponding
    # color-named methods provided by Term::ANSIColor (e.g. "def red").
    #
    # During output, each line is processed by passing it to the formatter Proc
    # which returns the formatted (e.g. colored) string.

    module Console
      extend ANSIColor
      include Duration

      def format_step(keyword, step_match, status, source_indent)
        comment = if source_indent
                    c = ('# ' + step_match.location.to_s).indent(source_indent)
                    format_string(c, :comment)
                  else
                    ''
                  end

        format = format_for(status, :param)
        line = keyword + step_match.format_args(format) + comment
        format_string(line, status)
      end

      def format_string(o, status)
        fmt = format_for(status)
        o.to_s.split("\n").map do |line|
          if Proc == fmt.class
            fmt.call(line)
          else
            fmt % line
          end
        end.join("\n")
      end

      def print_elements(elements, status, kind)
        return if elements.empty?

        element_messages = element_messages(elements, status)
        print_element_messages(element_messages, status, kind)
      end

      def print_element_messages(element_messages, status, kind)
        if element_messages.any?
          @io.puts(format_string("(::) #{status} #{kind} (::)", status))
          @io.puts
          @io.flush
        end

        element_messages.each do |message|
          @io.puts(format_string(message, status))
          @io.puts
          @io.flush
        end
      end

      def print_statistics(duration, config, counts, issues)
        if issues.any?
          @io.puts issues.to_s
          @io.puts
        end

        @io.puts counts.to_s
        @io.puts(format_duration(duration)) if duration && config.duration?

        if config.randomize?
          @io.puts
          @io.puts "Randomized with seed #{config.seed}"
        end

        @io.flush
      end

      def print_exception(e, status, indent)
        string = exception_message_string(e, indent)
        @io.puts(format_string(string, status))
      end

      def exception_message_string(e, indent)
        message = "#{e.message} (#{e.class})".dup.force_encoding('UTF-8')
        message = linebreaks(message, ENV['CUCUMBER_TRUNCATE_OUTPUT'].to_i)

        "#{message}\n#{e.backtrace.join("\n")}".indent(indent)
      end

      # http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/10655
      def linebreaks(msg, max)
        return msg unless max && max > 0
        msg.gsub(/.{1,#{max}}(?:\s|\Z)/) { ($& + 5.chr).gsub(/\n\005/, "\n").gsub(/\005/, "\n") }.rstrip
      end

      def collect_snippet_data(test_step, ast_lookup)
        # collect snippet data for undefined steps
        keyword = ast_lookup.snippet_step_keyword(test_step)
        @snippets_input << Console::SnippetData.new(keyword, test_step)
      end

      def collect_undefined_parameter_type_names(undefined_parameter_type)
        @undefined_parameter_types << undefined_parameter_type.type_name
      end

      def print_snippets(options)
        return unless options[:snippets]

        snippet_text_proc = lambda do |step_keyword, step_name, multiline_arg|
          snippet_text(step_keyword, step_name, multiline_arg)
        end
        do_print_snippets(snippet_text_proc) unless @snippets_input.empty?

        @undefined_parameter_types.map do |type_name|
          do_print_undefined_parameter_type_snippet(type_name)
        end
      end

      def do_print_snippets(snippet_text_proc)
        snippets = @snippets_input.map do |data|
          snippet_text_proc.call(data.actual_keyword, data.step.text, data.step.multiline_arg)
        end.uniq

        text = "\nYou can implement step definitions for undefined steps with these snippets:\n\n"
        text += snippets.join("\n\n")
        @io.puts format_string(text, :undefined)

        @io.puts
        @io.flush
      end

      def print_passing_wip(config, passed_test_cases, ast_lookup)
        return unless config.wip?
        messages = passed_test_cases.map do |test_case|
          scenario_source = ast_lookup.scenario_source(test_case)
          keyword = scenario_source.type == :Scenario ? scenario_source.scenario.keyword : scenario_source.scenario_outline.keyword
          linebreaks("#{test_case.location.on_line(test_case.location.lines.max)}:in `#{keyword}: #{test_case.name}'", ENV['CUCUMBER_TRUNCATE_OUTPUT'].to_i)
        end
        do_print_passing_wip(messages)
      end

      def do_print_passing_wip(passed_messages)
        if passed_messages.any?
          @io.puts format_string("\nThe --wip switch was used, so I didn't expect anything to pass. These scenarios passed:", :failed)
          print_element_messages(passed_messages, :passed, 'scenarios')
        else
          @io.puts format_string("\nThe --wip switch was used, so the failures were expected. All is good.\n", :passed)
        end
      end

      def attach(src, media_type)
        return unless media_type == 'text/x.cucumber.log+plain'
        return unless @io
        @io.puts
        @io.puts(format_string(src, :tag))
        @io.flush
      end

      def print_profile_information
        return if @options[:skip_profile_information] || @options[:profiles].nil? || @options[:profiles].empty?
        do_print_profile_information(@options[:profiles])
      end

      def do_print_profile_information(profiles)
        profiles_sentence = if profiles.size == 1
                              profiles.first
                            else
                              "#{profiles[0...-1].join(', ')} and #{profiles.last}"
                            end

        @io.puts "Using the #{profiles_sentence} profile#{'s' if profiles.size > 1}..."
      end

      def do_print_undefined_parameter_type_snippet(type_name)
        camelized = type_name.split(/_|-/).collect(&:capitalize).join

        @io.puts [
          "The parameter #{type_name} is not defined. You can define a new one with:",
          '',
          'ParameterType(',
          "  name:        '#{type_name}',",
          '  regexp:      /some regexp here/,',
          "  type:        #{camelized},",
          '  # The transformer takes as many arguments as there are capture groups in the regexp,',
          '  # or just one if there are none.',
          "  transformer: ->(s) { #{camelized}.new(s) }",
          ')',
          ''
        ].join("\n")
      end

      private

      FORMATS = Hash.new { |hash, format| hash[format] = method(format).to_proc }

      def format_for(*keys)
        key = keys.join('_').to_sym
        fmt = FORMATS[key]
        raise "No format for #{key.inspect}: #{FORMATS.inspect}" if fmt.nil?
        fmt
      end

      def element_messages(elements, status)
        elements.map do |element|
          if status == :failed
            exception_message_string(element.exception, 0)
          else
            linebreaks(element.backtrace_line, ENV['CUCUMBER_TRUNCATE_OUTPUT'].to_i)
          end
        end
      end

      def snippet_text(step_keyword, step_name, multiline_arg)
        keyword = Cucumber::Gherkin::I18n.code_keyword_for(step_keyword).strip
        config.snippet_generators.map do |generator|
          generator.call(keyword, step_name, multiline_arg, config.snippet_type)
        end.join("\n")
      end

      class SnippetData
        attr_reader :actual_keyword, :step
        def initialize(actual_keyword, step)
          @actual_keyword = actual_keyword
          @step = step
        end
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
