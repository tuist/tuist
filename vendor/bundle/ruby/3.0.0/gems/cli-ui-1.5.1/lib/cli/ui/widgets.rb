require('cli/ui')

module CLI
  module UI
    # Widgets are formatter objects with more custom implementations than the
    # other features, which all center around formatting text with colours,
    # etc.
    #
    # If you want to extend CLI::UI with your own widgets, you may want to do
    # something like this:
    #
    #   require('cli/ui')
    #   class MyWidget < CLI::UI::Widgets::Base
    #     # ...
    #   end
    #   CLI::UI::Widgets.register('my-widget') { MyWidget }
    #   puts(CLI::UI.fmt("{{@widget/my-widget:args}}"))
    module Widgets
      MAP = {}

      autoload(:Base, 'cli/ui/widgets/base')

      def self.register(name, &cb)
        MAP[name] = cb
      end

      autoload(:Status, 'cli/ui/widgets/status')
      register('status') { Widgets::Status }

      # Looks up a widget by handle
      #
      # ==== Raises
      # Raises InvalidWidgetHandle if the widget is not available.
      #
      # ==== Returns
      # A callable widget, to be invoked like `.call(argstring)`
      #
      def self.lookup(handle)
        MAP.fetch(handle.to_s).call
      rescue KeyError, NameError
        raise(InvalidWidgetHandle, handle)
      end

      # All available widgets by name
      #
      def self.available
        MAP.keys
      end

      class InvalidWidgetHandle < ArgumentError
        def initialize(handle)
          super
          @handle = handle
        end

        def message
          keys = Widget.available.join(',')
          "invalid widget handle: #{@handle} " \
            "-- must be one of CLI::UI::Widgets.available (#{keys})"
        end
      end

      class InvalidWidgetArguments < ArgumentError
        def initialize(argstring, pattern)
          super
          @argstring = argstring
          @pattern   = pattern
        end

        def message
          "invalid widget arguments: #{@argstring} " \
            "-- must match pattern: #{@pattern.inspect}"
        end
      end
    end
  end
end
