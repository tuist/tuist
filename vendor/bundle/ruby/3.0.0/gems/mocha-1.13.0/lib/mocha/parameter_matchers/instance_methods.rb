require 'mocha/parameter_matchers/equals'

module Mocha
  module ParameterMatchers
    # @private
    module InstanceMethods
      # @private
      def to_matcher
        Mocha::ParameterMatchers::Equals.new(self)
      end
    end
  end
end

# @private
class Object
  include Mocha::ParameterMatchers::InstanceMethods
end
