# frozen_string_literal: true

module Cucumber
  module Filters
    class Quit
      def initialize(receiver = nil)
        @receiver = receiver
      end

      def test_case(test_case)
        test_case.describe_to @receiver unless Cucumber.wants_to_quit
        self
      end

      def done
        @receiver.done
        self
      end

      def with_receiver(receiver)
        self.class.new(receiver)
      end
    end
  end
end
