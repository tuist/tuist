module Protobuf
  module Generators
    module Printable

      PARENT_CLASS_MESSAGE = "::Protobuf::Message".freeze
      PARENT_CLASS_ENUM    = "::Protobuf::Enum".freeze
      PARENT_CLASS_SERVICE = "::Protobuf::Rpc::Service".freeze

      # Initialize the printer.
      # Must be called by any class/module that includes the Printable module.
      #
      def init_printer(indent_level)
        @io = ::StringIO.new
        self.current_indent = indent_level.to_i
      end

      protected

      attr_accessor :current_indent

      private

      # Print a one-line comment.
      #
      def comment(message)
        puts "# #{message}"
      end

      # Print a "header" comment.
      #
      #   header("Lorem ipsum dolor")
      #   ##
      #   # Lorem ipsum dolor
      #   #
      def header(message)
        puts
        puts "##"
        puts "# #{message}"
        puts "#"
      end

      # Increase the indent level. An outdent will only occur if given a block
      # (after the block is finished).
      #
      def indent
        self.current_indent += 1
        yield
        outdent
      end

      # Take a string and upcase the first character of each namespace.
      # Due to the nature of varying standards about how class/modules are named
      # (e.g. CamelCase, Underscore_Case, SCREAMING_SNAKE_CASE), we only want
      # to capitalize the first character to ensure ruby will treat the value
      # as a constant. Otherwise we do not attempt to change the
      # token's definition.
      #
      #   modulize("foo.bar.Baz") -> "::Foo::Bar::Baz"
      #   modulize("foo.bar.baz") -> "::Foo::Bar::Baz"
      #   modulize("foo.bar.BAZ") -> "::Foo::Bar::BAZ"
      #
      def modulize(name)
        name = name.gsub(/\./, '::')
        name = name.gsub(/(^(?:::)?[a-z]|::[a-z])/, &:upcase)
        name
      end

      # Decrease the indent level. Cannot be negative.
      #
      def outdent
        self.current_indent -= 1 unless current_indent.zero?
      end

      # Return the parent class for a given type.
      # Valid types are :message, :enum, and :service, otherwise an error
      # will be thrown.
      #
      def parent_class(type)
        case type
        when :message then
          PARENT_CLASS_MESSAGE
        when :enum then
          PARENT_CLASS_ENUM
        when :service then
          PARENT_CLASS_SERVICE
        else
          fail "Unknown parent class type #{type}: #{caller[0..5].join("\n")}"
        end
      end

      # Print a class or module block, indicated by type.
      # If a class, can be given a parent class to inherit from.
      # If a block is given, call the block from within an indent block.
      # Otherwise, end the block on the same line.
      #
      def print_block(name, parent_klass, type)
        name = modulize(name)
        block_def = "#{type} #{name}"
        block_def += " < #{parent_class(parent_klass)}" if parent_klass

        if block_given?
          puts block_def
          indent { yield }
          puts "end"
          puts
        else
          block_def += "; end"
          puts block_def
        end
      end

      # Use print_block to print a class, with optional parent class
      # to inherit from. Accepts a block for use with print_block.
      #
      def print_class(name, parent_klass, &block)
        print_block(name, parent_klass, :class, &block)
      end

      # Use print_block to print a module.
      # Accepts a block for use with print_block.
      #
      def print_module(name, &block)
        print_block(name, nil, :module, &block)
      end

      # Print a file require.
      #
      #   print_require('foo/bar/baz') -> "require 'foo/bar/baz'"
      #
      def print_require(file, relative = false)
        puts "require#{'_relative' if relative} '#{file}'"
      end

      # Puts the given message prefixed by the indent level.
      # If no message is given print a newline.
      #
      def puts(message = nil)
        if message
          @io.puts(("  " * current_indent) + message)
        else
          @io.puts
        end
      end

      # Print the given message raw, no indent.
      #
      def print(contents)
        @io.print(contents)
      end

      # Returns the contents of the underlying StringIO object.
      #
      def print_contents
        @io.rewind
        @io.read
      end

    end
  end
end
