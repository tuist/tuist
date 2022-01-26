# frozen_string_literal: true

module Cucumber
  module MultilineArgument
    class DocString < SimpleDelegator
      def append_to(array)
        array << to_s
      end
    end
  end
end
