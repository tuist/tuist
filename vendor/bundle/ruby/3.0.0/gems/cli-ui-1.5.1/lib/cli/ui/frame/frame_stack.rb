module CLI
  module UI
    module Frame
      module FrameStack
        COLOR_ENVVAR = 'CLI_FRAME_STACK'
        STYLE_ENVVAR = 'CLI_STYLE_STACK'

        class StackItem
          attr_reader :color, :frame_style

          def initialize(color_name, style_name)
            @color = CLI::UI.resolve_color(color_name)
            @frame_style = CLI::UI.resolve_style(style_name)
          end
        end

        class << self
          # Fetch all items off the frame stack
          def items
            colors = ENV.fetch(COLOR_ENVVAR, '').split(':').map(&:to_sym)
            styles = ENV.fetch(STYLE_ENVVAR, '').split(':').map(&:to_sym)

            colors.length.times.map do |i|
              StackItem.new(colors[i], styles[i] || Frame.frame_style)
            end
          end

          # Push a new item onto the frame stack.
          #
          # Either an item or a :color/:style pair should be pushed onto the stack.
          #
          # ==== Attributes
          #
          # * +item+ a +StackItem+ to push onto the stack. Defaults to nil
          #
          # ==== Options
          #
          # * +:color+ the color of the new stack item. Defaults to nil
          # * +:style+ the style of the new stack item. Defaults to nil
          #
          # ==== Raises
          #
          # If both an item and a color/style pair are given, raises an +ArgumentError+
          # If the given item is not a +StackItem+, raises an +ArgumentError+
          #
          def push(item = nil, color: nil, style: nil)
            unless item.nil?
              unless item.is_a?(StackItem)
                raise ArgumentError, 'item must be a StackItem'
              end

              unless color.nil? && style.nil?
                raise ArgumentError, 'Must give one of item or color: and style:'
              end
            end

            item ||= StackItem.new(color, style)

            curr = items
            curr << item

            serialize(curr)
          end

          # Removes and returns the last stack item off the stack
          def pop
            curr = items
            ret = curr.pop

            serialize(curr)

            ret.nil? ? nil : ret
          end

          private

          # Serializes the item stack into two ENV variables.
          #
          # This is done to preserve backward compatibility with earlier versions of cli/ui.
          # This ensures that any code that relied upon previous stack behavior should continue
          # to work.
          def serialize(items)
            colors = []
            styles = []

            items.each do |item|
              colors << item.color.name
              styles << item.frame_style.name
            end

            ENV[COLOR_ENVVAR] = colors.join(':')
            ENV[STYLE_ENVVAR] = styles.join(':')
          end
        end
      end
    end
  end
end
