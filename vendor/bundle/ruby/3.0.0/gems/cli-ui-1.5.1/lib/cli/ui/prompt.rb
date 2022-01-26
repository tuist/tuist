# coding: utf-8
require 'cli/ui'
require 'readline'

module Readline
  unless const_defined?(:FILENAME_COMPLETION_PROC)
    FILENAME_COMPLETION_PROC = proc do |input|
      directory = input[-1] == '/' ? input : File.dirname(input)
      filename = input[-1] == '/' ? '' : File.basename(input)

      (Dir.entries(directory).select do |fp|
        fp.start_with?(filename)
      end - (input[-1] == '.' ? [] : ['.', '..'])).map do |fp|
        File.join(directory, fp).gsub(/\A\.\//, '')
      end
    end
  end
end

module CLI
  module UI
    module Prompt
      autoload :InteractiveOptions,  'cli/ui/prompt/interactive_options'
      autoload :OptionsHandler,      'cli/ui/prompt/options_handler'
      private_constant :InteractiveOptions, :OptionsHandler

      class << self
        # Ask a user a question with either free form answer or a set of answers (multiple choice)
        # Can use arrows, y/n, numbers (1/2), and vim bindings to control multiple choice selection
        # Do not use this method for yes/no questions. Use +confirm+
        #
        # * Handles free form answers (options are nil)
        # * Handles default answers for free form text
        # * Handles file auto completion for file input
        # * Handles interactively choosing answers using +InteractiveOptions+
        #
        # https://user-images.githubusercontent.com/3074765/33799822-47f23302-dd01-11e7-82f3-9072a5a5f611.png
        #
        # ==== Attributes
        #
        # * +question+ - (required) The question to ask the user
        #
        # ==== Options
        #
        # * +:options+ - Options that the user may select from. Will use +InteractiveOptions+ to do so.
        # * +:default+ - The default answer to the question (e.g. they just press enter and don't input anything)
        # * +:is_file+ - Tells the input to use file auto-completion (tab completion)
        # * +:allow_empty+ - Allows the answer to be empty
        # * +:multiple+ - Allow multiple options to be selected
        # * +:filter_ui+ - Enable option filtering (default: true)
        # * +:select_ui+ - Enable long-form option selection (default: true)
        #
        # Note:
        # * +:options+ or providing a +Block+ conflicts with +:default+ and +:is_file+,
        #              you cannot set options with either of these keywords
        # * +:default+ conflicts with +:allow_empty:, you cannot set these together
        # * +:options+ conflicts with providing a +Block+ , you may only set one
        # * +:multiple+ can only be used with +:options+ or a +Block+; it is ignored, otherwise.
        #
        # ==== Block (optional)
        #
        # * A Proc that provides a +OptionsHandler+ and uses the public +:option+ method to add options and their
        #   respective handlers
        #
        # ==== Return Value
        #
        # * If a +Block+ was not provided, the selected option or response to the free form question will be returned
        # * If a +Block+ was provided, the evaluated value of the +Block+ will be returned
        #
        # ==== Example Usage:
        #
        # Free form question
        #   CLI::UI::Prompt.ask('What color is the sky?')
        #
        # Free form question with a file answer
        #   CLI::UI::Prompt.ask('Where is your Gemfile located?', is_file: true)
        #
        # Free form question with a default answer
        #   CLI::UI::Prompt.ask('What color is the sky?', default: 'blue')
        #
        # Free form question when the answer can be empty
        #   CLI::UI::Prompt.ask('What is your opinion on this question?', allow_empty: true)
        #
        # Interactive (multiple choice) question
        #   CLI::UI::Prompt.ask('What kind of project is this?', options: %w(rails go ruby python))
        #
        # Interactive (multiple choice) question with defined handlers
        #   CLI::UI::Prompt.ask('What kind of project is this?') do |handler|
        #     handler.option('rails')  { |selection| selection }
        #     handler.option('go')     { |selection| selection }
        #     handler.option('ruby')   { |selection| selection }
        #     handler.option('python') { |selection| selection }
        #   end
        #
        def ask(
          question,
          options: nil,
          default: nil,
          is_file: nil,
          allow_empty: true,
          multiple: false,
          filter_ui: true,
          select_ui: true,
          &options_proc
        )
          if (options || block_given?) && ((default && !multiple) || is_file)
            raise(ArgumentError, 'conflicting arguments: options provided with default or is_file')
          end

          if options && multiple && default && !(default - options).empty?
            raise(ArgumentError, 'conflicting arguments: default should only include elements present in options')
          end

          if options || block_given?
            ask_interactive(
              question,
              options,
              multiple: multiple,
              default: default,
              filter_ui: filter_ui,
              select_ui: select_ui,
              &options_proc
            )
          else
            ask_free_form(question, default, is_file, allow_empty)
          end
        end

        # Asks the user for a single-line answer, without displaying the characters while typing.
        # Typically used for password prompts
        #
        # ==== Return Value
        #
        # The password, without a trailing newline.
        # If the user simply presses "Enter" without typing any password, this will return an empty string.
        def ask_password(question)
          require 'io/console'

          CLI::UI.with_frame_color(:blue) do
            STDOUT.print(CLI::UI.fmt('{{?}} ' + question)) # Do not use puts_question to avoid the new line.

            # noecho interacts poorly with Readline under system Ruby, so do a manual `gets` here.
            # No fancy Readline integration (like echoing back) is required for a password prompt anyway.
            password = STDIN.noecho do
              # Chomp will remove the one new line character added by `gets`, without touching potential extra spaces:
              # " 123 \n".chomp => " 123 "
              STDIN.gets.chomp
            end

            STDOUT.puts # Complete the line

            password
          end
        end

        # Asks the user a yes/no question.
        # Can use arrows, y/n, numbers (1/2), and vim bindings to control
        #
        # ==== Example Usage:
        #
        # Confirmation question
        #   CLI::UI::Prompt.confirm('Is the sky blue?')
        #
        #   CLI::UI::Prompt.confirm('Do a dangerous thing?', default: false)
        #
        def confirm(question, default: true)
          ask_interactive(question, default ? %w(yes no) : %w(no yes), filter_ui: false) == 'yes'
        end

        private

        def ask_free_form(question, default, is_file, allow_empty)
          if default && !allow_empty
            raise(ArgumentError, 'conflicting arguments: default enabled but allow_empty is false')
          end

          if default
            puts_question("#{question} (empty = #{default})")
          else
            puts_question(question)
          end

          # Ask a free form question
          loop do
            line = readline(is_file: is_file)

            if line.empty? && default
              write_default_over_empty_input(default)
              return default
            end

            if !line.empty? || allow_empty
              return line
            end
          end
        end

        def ask_interactive(question, options = nil, multiple: false, default: nil, filter_ui: true, select_ui: true)
          raise(ArgumentError, 'conflicting arguments: options and block given') if options && block_given?

          options ||= if block_given?
            handler = OptionsHandler.new
            yield handler
            handler.options
          end

          raise(ArgumentError, 'insufficient options') if options.nil? || options.empty?
          navigate_text = if CLI::UI::OS.current.supports_arrow_keys?
            'Choose with ↑ ↓ ⏎'
          else
            "Navigate up with 'k' and down with 'j', press Enter to select"
          end

          instructions = (multiple ? 'Toggle options. ' : '') + navigate_text
          instructions += ", filter with 'f'" if filter_ui
          instructions += ", enter option with 'e'" if select_ui && (options.size > 9)
          puts_question("#{question} {{yellow:(#{instructions})}}")
          resp = interactive_prompt(options, multiple: multiple, default: default)

          # Clear the line
          print(ANSI.previous_line + ANSI.clear_to_end_of_line)
          # Force StdoutRouter to prefix
          print(ANSI.previous_line + "\n")

          # reset the question to include the answer
          resp_text = resp
          if multiple
            resp_text = case resp.size
            when 0
              '<nothing>'
            when 1..2
              resp.join(' and ')
            else
              "#{resp.size} items"
            end
          end
          puts_question("#{question} (You chose: {{italic:#{resp_text}}})")

          return handler.call(resp) if block_given?
          resp
        end

        # Useful for stubbing in tests
        def interactive_prompt(options, multiple: false, default: nil)
          InteractiveOptions.call(options, multiple: multiple, default: default)
        end

        def write_default_over_empty_input(default)
          CLI::UI.raw do
            STDERR.puts(
              CLI::UI::ANSI.cursor_up(1) +
              "\r" +
              CLI::UI::ANSI.cursor_forward(4) + # TODO: width
              default +
              CLI::UI::Color::RESET.code
            )
          end
        end

        def puts_question(str)
          CLI::UI.with_frame_color(:blue) do
            STDOUT.puts(CLI::UI.fmt('{{?}} ' + str))
          end
        end

        def readline(is_file: false)
          if is_file
            Readline.completion_proc = Readline::FILENAME_COMPLETION_PROC
            Readline.completion_append_character = ''
          else
            Readline.completion_proc = proc { |*| nil }
            Readline.completion_append_character = ' '
          end

          # because Readline is a C library, CLI::UI's hooks into $stdout don't
          # work. We could work around this by having CLI::UI use a pipe and a
          # thread to manage output, but the current strategy feels like a
          # better tradeoff.
          prefix = CLI::UI.with_frame_color(:blue) { CLI::UI::Frame.prefix }
          # If a prompt is interrupted on Windows it locks the colour of the terminal from that point on, so we should
          # not change the colour here.
          prompt = prefix + CLI::UI.fmt('{{blue:> }}')
          prompt += CLI::UI::Color::YELLOW.code if CLI::UI::OS.current.supports_color_prompt?

          begin
            line = Readline.readline(prompt, true)
            print(CLI::UI::Color::RESET.code)
            line.to_s.chomp
          rescue Interrupt
            CLI::UI.raw { STDERR.puts('^C' + CLI::UI::Color::RESET.code) }
            raise
          end
        end
      end
    end
  end
end
