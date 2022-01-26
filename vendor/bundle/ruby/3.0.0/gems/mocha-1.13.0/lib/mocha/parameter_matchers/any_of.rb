require 'mocha/parameter_matchers/base'

module Mocha
  module ParameterMatchers
    # Matches if any +matchers+ match.
    #
    # @param [*Array<Base>] matchers parameter matchers.
    # @return [AnyOf] parameter matcher.
    #
    # @see Expectation#with
    #
    # @example One parameter matcher matches.
    #   object = mock()
    #   object.expects(:method_1).with(any_of(1, 3))
    #   object.method_1(1)
    #   # no error raised
    #
    # @example The other parameter matcher matches.
    #   object = mock()
    #   object.expects(:method_1).with(any_of(1, 3))
    #   object.method_1(3)
    #   # no error raised
    #
    # @example Neither parameter matcher matches.
    #   object = mock()
    #   object.expects(:method_1).with(any_of(1, 3))
    #   object.method_1(2)
    #   # error raised, because method_1 was not called with 1 or 3
    def any_of(*matchers)
      AnyOf.new(*matchers)
    end

    # Parameter matcher which combines a number of other matchers using a logical OR.
    class AnyOf < Base
      # @private
      def initialize(*matchers)
        @matchers = matchers
      end

      # @private
      def matches?(available_parameters)
        parameter = available_parameters.shift
        @matchers.any? { |matcher| matcher.to_matcher.matches?([parameter]) }
      end

      # @private
      def mocha_inspect
        "any_of(#{@matchers.map(&:mocha_inspect).join(', ')})"
      end
    end
  end
end
