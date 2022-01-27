# frozen-string-literal: true
require 'cli/ui'

module CLI
  module UI
    module Spinner
      autoload :Async,      'cli/ui/spinner/async'
      autoload :SpinGroup,  'cli/ui/spinner/spin_group'

      PERIOD = 0.1 # seconds
      TASK_FAILED = :task_failed

      RUNES = CLI::UI::OS.current.supports_emoji? ? %w(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏).freeze : %w(\\ | / - \\ | / -).freeze

      colors = [CLI::UI::Color::CYAN.code] * (RUNES.size / 2).ceil +
        [CLI::UI::Color::MAGENTA.code] * (RUNES.size / 2).to_i
      GLYPHS = colors.zip(RUNES).map(&:join)

      class << self
        attr_accessor(:index)

        # We use this from CLI::UI::Widgets::Status to render an additional
        # spinner next to the "working" element. While this global state looks
        # a bit repulsive at first, it's worth realizing that:
        #
        # * It's managed by the SpinGroup#wait method, not individual tasks; and
        # * It would be complete insanity to run two separate but concurrent SpinGroups.
        #
        # While it would be possible to stitch through some connection between
        # the SpinGroup and the Widgets included in its title, this is simpler
        # in practice and seems unlikely to cause issues in practice.
        def current_rune
          RUNES[index || 0]
        end
      end

      # Adds a single spinner
      # Uses an interactive session to allow the user to pick an answer
      # Can use arrows, y/n, numbers (1/2), and vim bindings to control
      #
      # https://user-images.githubusercontent.com/3074765/33798295-d94fd822-dce3-11e7-819b-43e5502d490e.gif
      #
      # ==== Attributes
      #
      # * +title+ - Title of the spinner to use
      #
      # ==== Options
      #
      # * +:auto_debrief+ - Automatically debrief exceptions? Default to true
      #
      # ==== Block
      #
      # * *spinner+ - Instance of the spinner. Can call +update_title+ to update the user of changes
      #
      # ==== Example Usage:
      #
      #   CLI::UI::Spinner.spin('Title') { sleep 1.0 }
      #
      def self.spin(title, auto_debrief: true, &block)
        sg = SpinGroup.new(auto_debrief: auto_debrief)
        sg.add(title, &block)
        sg.wait
      end
    end
  end
end
