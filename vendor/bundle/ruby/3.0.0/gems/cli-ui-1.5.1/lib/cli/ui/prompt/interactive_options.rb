# coding: utf-8
require 'io/console'

module CLI
  module UI
    module Prompt
      class InteractiveOptions
        DONE = 'Done'
        CHECKBOX_ICON = { false => '☐', true => '☑' }

        # Prompts the user with options
        # Uses an interactive session to allow the user to pick an answer
        # Can use arrows, y/n, numbers (1/2), and vim bindings to control
        # For more than 9 options, hitting 'e', ':', or 'G' will enter select
        # mode allowing the user to type in longer numbers
        # Pressing 'f' or '/' will allow the user to filter the results
        #
        # https://user-images.githubusercontent.com/3074765/33797984-0ebb5e64-dcdf-11e7-9e7e-7204f279cece.gif
        #
        # ==== Example Usage:
        #
        # Ask an interactive question
        #   CLI::UI::Prompt::InteractiveOptions.call(%w(rails go python))
        #
        def self.call(options, multiple: false, default: nil)
          list = new(options, multiple: multiple, default: default)
          selected = list.call
          if multiple
            selected.map { |s| options[s - 1] }
          else
            options[selected - 1]
          end
        end

        # Initializes a new +InteractiveOptions+
        # Usually called from +self.call+
        #
        # ==== Example Usage:
        #
        #   CLI::UI::Prompt::InteractiveOptions.new(%w(rails go python))
        #
        def initialize(options, multiple: false, default: nil)
          @options = options
          @active = 1
          @marker = '>'
          @answer = nil
          @state = :root
          @multiple = multiple
          # Indicate that an extra line (the "metadata" line) is present and
          # the terminal output should be drawn over when processing user input
          @displaying_metadata = false
          @filter = ''
          # 0-indexed array representing if selected
          # @options[0] is selected if @chosen[0]
          if multiple
            @chosen = if default
              @options.map { |option| default.include?(option) }
            else
              Array.new(@options.size) { false }
            end
          end
          @redraw = true
          @presented_options = []
        end

        # Calls the +InteractiveOptions+ and asks the question
        # Usually used from +self.call+
        #
        def call
          calculate_option_line_lengths
          CLI::UI.raw { print(ANSI.hide_cursor) }
          while @answer.nil?
            render_options
            process_input_until_redraw_required
            reset_position
          end
          clear_output

          @answer
        ensure
          CLI::UI.raw do
            print(ANSI.show_cursor)
          end
        end

        private

        def calculate_option_line_lengths
          @terminal_width_at_calculation_time = CLI::UI::Terminal.width
          # options will be an array of questions but each option can be multi-line
          # so to get the # of lines, you need to join then split

          # since lines may be longer than the terminal is wide, we need to
          # determine how many extra lines would be taken up by them
          max_width = (@terminal_width_at_calculation_time -
                       @options.count.to_s.size - # Width of the displayed number
                       5 -                        # Extra characters added during rendering
                       (@multiple ? 1 : 0)        # Space for the checkbox, if rendered
                      ).to_f

          @option_lengths = @options.map do |text|
            width = 1 if text.empty?
            width ||= text
              .split("\n")
              .reject(&:empty?)
              .map { |l| (CLI::UI.fmt(l, enable_color: false).length / max_width).ceil }
              .reduce(&:+)

            width
          end
        end

        def reset_position(number_of_lines = num_lines)
          # This will put us back at the beginning of the options
          # When we redraw the options, they will be overwritten
          CLI::UI.raw do
            number_of_lines.times { print(ANSI.previous_line) }
          end
        end

        def clear_output(number_of_lines = num_lines)
          CLI::UI.raw do
            # Write over all lines with whitespace
            number_of_lines.times { puts(' ' * CLI::UI::Terminal.width) }
          end
          reset_position(number_of_lines)

          # Update if metadata is being displayed
          # This must be done _after_ the output is cleared or it won't draw over
          # the entire output
          @displaying_metadata = display_metadata?
        end

        # Don't use this in place of +@displaying_metadata+, this updates too
        # quickly to be useful when drawing to the screen.
        def display_metadata?
          filtering? || selecting? || has_filter?
        end

        def num_lines
          calculate_option_line_lengths if terminal_width_changed?

          option_length = presented_options.reduce(0) do |total_length, (_, option_number)|
            # Handle continuation markers and "Done" option when multiple is true
            next total_length + 1 if option_number.nil? || option_number.zero?
            total_length + @option_lengths[option_number - 1]
          end

          option_length + (@displaying_metadata ? 1 : 0)
        end

        def terminal_width_changed?
          @terminal_width_at_calculation_time != CLI::UI::Terminal.width
        end

        ESC = "\e"
        BACKSPACE = "\u007F"
        CTRL_C = "\u0003"
        CTRL_D = "\u0004"

        def up
          active_index = @filtered_options.index { |_, num| num == @active } || 0

          previous_visible = @filtered_options[active_index - 1]
          previous_visible ||= @filtered_options.last

          @active = previous_visible ? previous_visible.last : -1
          @redraw = true
        end

        def down
          active_index = @filtered_options.index { |_, num| num == @active } || 0

          next_visible = @filtered_options[active_index + 1]
          next_visible ||= @filtered_options.first

          @active = next_visible ? next_visible.last : -1
          @redraw = true
        end

        # n is 1-indexed selection
        # n == 0 if "Done" was selected in @multiple mode
        def select_n(n)
          if @multiple
            if n == 0
              @answer = []
              @chosen.each_with_index do |selected, i|
                @answer << i + 1 if selected
              end
            else
              @active = n
              @chosen[n - 1] = !@chosen[n - 1]
            end
          elsif n == 0
            # Ignore pressing "0" when not in multiple mode
          else
            @active = n
            @answer = n
          end
          @redraw = true
        end

        def select_bool(char)
          return unless (@options - %w(yes no)).empty?
          opt = @options.detect { |o| o.start_with?(char) }
          @active = @options.index(opt) + 1
          @answer = @options.index(opt) + 1
          @redraw = true
        end

        def build_selection(char)
          @active = (@active.to_s + char).to_i
          @redraw = true
        end

        def chop_selection
          @active = @active.to_s.chop.to_i
          @redraw = true
        end

        def update_search(char)
          @redraw = true

          # Control+D or Backspace on empty search closes search
          if (char == CTRL_D) || (@filter.empty? && (char == BACKSPACE))
            @filter = ''
            @state = :root
            return
          end

          if char == BACKSPACE
            @filter.chop!
          else
            @filter += char
          end
        end

        def select_current
          # Prevent selection of invisible options
          return unless presented_options.any? { |_, num| num == @active }
          select_n(@active)
        end

        def process_input_until_redraw_required
          @redraw = false
          wait_for_user_input until @redraw
        end

        # rubocop:disable Style/WhenThen,Layout/SpaceBeforeSemicolon,Style/Semicolon
        def wait_for_user_input
          char = read_char
          @last_char = char

          case char
          when :timeout ; raise Interrupt # Timeout, use interrupt to simulate
          when CTRL_C   ; raise Interrupt
          end

          max_digit = [@options.size, 9].min.to_s
          case @state
          when :root
            case char
            when ESC              ; @state = :esc
            when 'k'              ; up
            when 'j'              ; down
            when 'e', ':', 'G'    ; start_line_select
            when 'f', '/'         ; start_filter
            when ('0'..max_digit) ; select_n(char.to_i)
            when 'y', 'n'         ; select_bool(char)
            when ' ', "\r", "\n"  ; select_current # <enter>
            end
          when :filter
            case char
            when ESC        ; @state = :esc
            when "\r", "\n" ; select_current
            when "\b"       ; update_search(BACKSPACE) # Happens on Windows
            else            ; update_search(char)
            end
          when :line_select
            case char
            when ESC             ; @state = :esc
            when 'k'             ; up   ; @state = :root
            when 'j'             ; down ; @state = :root
            when 'e', ':', 'G', 'q' ; stop_line_select
            when '0'..'9'        ; build_selection(char)
            when BACKSPACE       ; chop_selection # Pop last input on backspace
            when ' ', "\r", "\n" ; select_current
            end
          when :esc
            case char
            when '['      ; @state = :esc_bracket
            else          ; raise Interrupt # unhandled escape sequence.
            end
          when :esc_bracket
            @state = has_filter? ? :filter : :root
            case char
            when 'A'      ; up
            when 'B'      ; down
            when 'C'      ; # Ignore right key
            when 'D'      ; # Ignore left key
            else          ; raise Interrupt # unhandled escape sequence.
            end
          end
        end
        # rubocop:enable Style/WhenThen,Layout/SpaceBeforeSemicolon

        def selecting?
          @state == :line_select
        end

        def filtering?
          @state == :filter
        end

        def has_filter?
          !@filter.empty?
        end

        def start_filter
          @state = :filter
          @redraw = true
        end

        def start_line_select
          @state  = :line_select
          @active = 0
          @redraw = true
        end

        def stop_line_select
          @state = :root
          @active = 1 if @active.zero?
          @redraw = true
        end

        def read_char
          if $stdin.tty? && !ENV['TEST']
            $stdin.getch # raw mode for tty
          else
            $stdin.getc
          end
        rescue IOError
          "\e"
        end

        def presented_options(recalculate: false)
          return @presented_options unless recalculate

          @presented_options = @options.zip(1..Float::INFINITY)
          if has_filter?
            @presented_options.select! { |option, _| option.downcase.include?(@filter.downcase) }
          end

          # Used for selection purposes
          @presented_options.push([DONE, 0]) if @multiple
          @filtered_options = @presented_options.dup

          ensure_visible_is_active if has_filter?

          # Must have more lines before the selection than we can display
          if distance_from_start_to_selection > max_lines
            @presented_options.shift(distance_from_start_to_selection - max_lines)
            ensure_first_item_is_continuation_marker
          end

          # Must have more lines after the selection than we can display
          if distance_from_selection_to_end > max_lines
            @presented_options.pop(distance_from_selection_to_end - max_lines)
            ensure_last_item_is_continuation_marker
          end

          while num_lines > max_lines
            # try to keep the selection centered in the window:
            if distance_from_selection_to_end > distance_from_start_to_selection
              # selection is closer to top than bottom, so trim a row from the bottom
              ensure_last_item_is_continuation_marker
              @presented_options.delete_at(-2)
            else
              # selection is closer to bottom than top, so trim a row from the top
              ensure_first_item_is_continuation_marker
              @presented_options.delete_at(1)
            end
          end

          @presented_options
        end

        def ensure_visible_is_active
          unless presented_options.any? { |_, num| num == @active }
            @active = presented_options.first&.last.to_i
          end
        end

        def distance_from_selection_to_end
          @presented_options.count - index_of_active_option
        end

        def distance_from_start_to_selection
          index_of_active_option
        end

        def index_of_active_option
          @presented_options.index { |_, num| num == @active }.to_i
        end

        def ensure_last_item_is_continuation_marker
          @presented_options.push(['...', nil]) if @presented_options.last.last
        end

        def ensure_first_item_is_continuation_marker
          @presented_options.unshift(['...', nil]) if @presented_options.first.last
        end

        def max_lines
          CLI::UI::Terminal.height - (@displaying_metadata ? 3 : 2) # Keeps a one line question visible
        end

        def render_options
          previously_displayed_lines = num_lines

          @displaying_metadata = display_metadata?

          options = presented_options(recalculate: true)

          clear_output(previously_displayed_lines) if previously_displayed_lines > num_lines

          max_num_length = (@options.size + 1).to_s.length

          metadata_text = if selecting?
            select_text = @active
            select_text = '{{info:e, q, or up/down anytime to exit}}' if @active == 0
            "Select: #{select_text}"
          elsif filtering? || has_filter?
            filter_text = @filter
            filter_text = '{{info:Ctrl-D anytime or Backspace now to exit}}' if @filter.empty?
            "Filter: #{filter_text}"
          end

          if metadata_text
            CLI::UI.with_frame_color(:blue) do
              puts CLI::UI.fmt("  {{green:#{metadata_text}}}#{ANSI.clear_to_end_of_line}")
            end
          end

          options.each do |choice, num|
            is_chosen = @multiple && num && @chosen[num - 1] && num != 0

            padding = ' ' * (max_num_length - num.to_s.length)
            message = "  #{num}#{num ? "." : " "}#{padding}"

            format = '%s'
            # If multiple, bold only selected. If not multiple, bold everything
            format = "{{bold:#{format}}}" if !@multiple || is_chosen
            format = "{{cyan:#{format}}}" if @multiple && is_chosen && num != @active
            format = " #{format}"

            message += format(format, CHECKBOX_ICON[is_chosen]) if @multiple && num && num > 0
            message += format_choice(format, choice)

            if num == @active

              color = filtering? || selecting? ? 'green' : 'blue'
              message = message.split("\n").map { |l| "{{#{color}:> #{l.strip}}}" }.join("\n")
            end

            CLI::UI.with_frame_color(:blue) do
              puts CLI::UI.fmt(message)
            end
          end
        end

        def format_choice(format, choice)
          eol = CLI::UI::ANSI.clear_to_end_of_line
          lines = choice.split("\n")

          return eol if lines.empty? # Handle blank options

          lines.map! { |l| format(format, l) + eol }
          lines.join("\n")
        end
      end
    end
  end
end
