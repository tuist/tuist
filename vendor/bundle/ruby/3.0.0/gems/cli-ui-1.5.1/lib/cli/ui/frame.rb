# coding: utf-8
require 'cli/ui'
require 'cli/ui/frame/frame_stack'
require 'cli/ui/frame/frame_style'

module CLI
  module UI
    module Frame
      class UnnestedFrameException < StandardError; end
      class << self
        DEFAULT_FRAME_COLOR = CLI::UI.resolve_color(:cyan)

        def frame_style
          @frame_style ||= FrameStyle::Box
        end

        # Set the default frame style.
        #
        # Raises ArgumentError if +frame_style+ is not valid
        #
        # ==== Attributes
        #
        # * +symbol+ or +FrameStyle+ - the default frame style to use for frames
        #
        def frame_style=(frame_style)
          @frame_style = CLI::UI.resolve_style(frame_style)
        end

        # Opens a new frame. Can be nested
        # Can be invoked in two ways: block and blockless
        # * In block form, the frame is closed automatically when the block returns
        # * In blockless form, caller MUST call +Frame.close+ when the frame is logically done
        # * Blockless form is strongly discouraged in cases where block form can be made to work
        #
        # https://user-images.githubusercontent.com/3074765/33799861-cb5dcb5c-dd01-11e7-977e-6fad38cee08c.png
        #
        # The return value of the block determines if the block is a "success" or a "failure"
        #
        # ==== Attributes
        #
        # * +text+ - (required) the text/title to output in the frame
        #
        # ==== Options
        #
        # * +:color+ - The color of the frame. Defaults to +DEFAULT_FRAME_COLOR+
        # * +:failure_text+ - If the block failed, what do we output? Defaults to nil
        # * +:success_text+ - If the block succeeds, what do we output? Defaults to nil
        # * +:timing+ - How long did the frame content take? Invalid for blockless. Defaults to true for the block form
        # * +frame_style+ - The frame style to use for this frame
        #
        # ==== Example
        #
        # ===== Block Form (Assumes +CLI::UI::StdoutRouter.enable+ has been called)
        #
        #   CLI::UI::Frame.open('Open') { puts 'hi' }
        #
        # Default Output:
        #   ┏━━ Open ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        #   ┃ hi
        #   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ (0.0s) ━━
        #
        # ===== Blockless Form
        #
        #   CLI::UI::Frame.open('Open')
        #
        # Default Output:
        #   ┏━━ Open ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        #
        #
        def open(
          text,
          color: DEFAULT_FRAME_COLOR,
          failure_text: nil,
          success_text: nil,
          timing:       nil,
          frame_style:  self.frame_style
        )
          frame_style = CLI::UI.resolve_style(frame_style)
          color = CLI::UI.resolve_color(color)

          unless block_given?
            if failure_text
              raise ArgumentError, 'failure_text is not compatible with blockless invocation'
            elsif success_text
              raise ArgumentError, 'success_text is not compatible with blockless invocation'
            elsif timing
              raise ArgumentError, 'timing is not compatible with blockless invocation'
            end
          end

          t_start = Time.now
          CLI::UI.raw do
            print(prefix.chop)
            puts frame_style.open(text, color: color)
          end
          FrameStack.push(color: color, style: frame_style)

          return unless block_given?

          closed = false
          begin
            success = false
            success = yield
          rescue
            closed = true
            t_diff = elasped(t_start, timing)
            close(failure_text, color: :red, elapsed: t_diff)
            raise
          else
            success
          ensure
            unless closed
              t_diff = elasped(t_start, timing)
              if success != false
                close(success_text, color: color, elapsed: t_diff)
              else
                close(failure_text, color: :red, elapsed: t_diff)
              end
            end
          end
        end

        # Adds a divider in a frame
        # Used to separate information within a single frame
        #
        # ==== Attributes
        #
        # * +text+ - (required) the text/title to output in the frame
        #
        # ==== Options
        #
        # * +:color+ - The color of the frame. Defaults to +DEFAULT_FRAME_COLOR+
        # * +frame_style+ - The frame style to use for this frame
        #
        # ==== Example
        #
        #   CLI::UI::Frame.open('Open') { CLI::UI::Frame.divider('Divider') }
        #
        # Default Output:
        #   ┏━━ Open ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        #   ┣━━ Divider ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        #   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        #
        # ==== Raises
        #
        # MUST be inside an open frame or it raises a +UnnestedFrameException+
        #
        def divider(text, color: nil, frame_style: nil)
          fs_item = FrameStack.pop
          raise UnnestedFrameException, 'No frame nesting to unnest' unless fs_item

          color = CLI::UI.resolve_color(color) || fs_item.color
          frame_style = CLI::UI.resolve_style(frame_style) || fs_item.frame_style

          CLI::UI.raw do
            print(prefix.chop)
            puts frame_style.divider(text, color: color)
          end

          FrameStack.push(fs_item)
        end

        # Closes a frame
        # Automatically called for a block-form +open+
        #
        # ==== Attributes
        #
        # * +text+ - (required) the text/title to output in the frame
        #
        # ==== Options
        #
        # * +:color+ - The color of the frame. Defaults to nil
        # * +:elapsed+ - How long did the frame take? Defaults to nil
        # * +frame_style+ - The frame style to use for this frame.  Defaults to nil
        #
        # ==== Example
        #
        #   CLI::UI::Frame.close('Close')
        #
        # Default Output:
        #   ┗━━ Close ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        #
        # ==== Raises
        #
        # MUST be inside an open frame or it raises a +UnnestedFrameException+
        #
        def close(text, color: nil, elapsed: nil, frame_style: nil)
          fs_item = FrameStack.pop
          raise UnnestedFrameException, 'No frame nesting to unnest' unless fs_item

          color = CLI::UI.resolve_color(color) || fs_item.color
          frame_style = CLI::UI.resolve_style(frame_style) || fs_item.frame_style

          kwargs = {}
          if elapsed
            kwargs[:right_text] = "(#{elapsed.round(2)}s)"
          end

          CLI::UI.raw do
            print(prefix.chop)
            puts frame_style.close(text, color: color, **kwargs)
          end
        end

        # Determines the prefix of a frame entry taking multi-nested frames into account
        #
        # ==== Options
        #
        # * +:color+ - The color of the prefix. Defaults to +Thread.current[:cliui_frame_color_override]+
        #
        def prefix(color: Thread.current[:cliui_frame_color_override])
          +''.tap do |output|
            items = FrameStack.items

            items[0..-2].each do |item|
              output << item.color.code << item.frame_style.prefix
            end

            if (item = items.last)
              final_color = color || item.color
              output << CLI::UI.resolve_color(final_color).code \
                << item.frame_style.prefix \
                << ' ' \
                << CLI::UI::Color::RESET.code
            end
          end
        end

        # The width of a prefix given the number of Frames in the stack
        def prefix_width
          w = FrameStack.items.reduce(0) do |width, item|
            width + item.frame_style.prefix_width
          end

          w.zero? ? w : w + 1
        end

        # Override a color for a given thread.
        #
        # ==== Attributes
        #
        # * +color+ - The color to override to
        #
        def with_frame_color_override(color)
          prev = Thread.current[:cliui_frame_color_override]
          Thread.current[:cliui_frame_color_override] = color
          yield
        ensure
          Thread.current[:cliui_frame_color_override] = prev
        end

        private

        # If timing is:
        #   Numeric: return it
        #   false: return nil
        #   true or nil: defaults to Time.new
        #   Time: return the difference with start
        def elasped(start, timing)
          return timing if timing.is_a?(Numeric)
          return if timing.is_a?(FalseClass)

          timing = Time.new if timing.is_a?(TrueClass) || timing.nil?
          timing - start
        end
      end
    end
  end
end
