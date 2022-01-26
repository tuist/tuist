# frozen_string_literal: true
module Cucumber
  module Core

    # Filters process test cases.
    #
    # Each filter must respond to the following protocol:
    #
    #   * `with_receiver(new_receiver)`
    #   * `test_case(test_case, &describe_test_steps)`
    #   * `done`
    #
    # The `with_receiver` method is used to assemble the filters into a chain. It should return a new instance of the
    # filter with the receiver attribute set to the new receiver. The receiver will also respond to the filter protocol.
    #
    # When a `test_case` message is received, the filter can choose to:
    #
    # 1. pass the test_case directly to its receiver (no-op)
    # 2. pass a modified copy of the test_case to its receiver
    # 3. not pass the test_case to its receiver at all
    #
    # Finally, the `done` message is sent. A filter should pass this message directly to its receiver.
    #
    module Filter

      # Utility method for quick construction of filter classes.
      #
      # @example Example usage:
      #
      #   class BlankingFilter < Filter.new(:name_to_blank, :receiver)
      #     def test_case(test_case)
      #       if name_to_blank == test_case.name
      #         test_case.with_steps([]).describe_to(receiver)
      #       else
      #         test_case.describe_to(receiver)
      #       end
      #     end
      #   end
      #
      # The attribute names passed to the Filter constructor will become private attributes of
      # your filter class.
      #
      def self.new(*attributes, &block)
        attributes << :receiver

        result = Class.new do
          attr_reader(*attributes)
          private(*attributes)

          define_method(:initialize) do |*args|
            attributes.zip(args) do |name, value|
              instance_variable_set("@#{name}".to_sym, value)
            end
          end

          def test_case(test_case)
            test_case.describe_to receiver
            self
          end

          def done
            receiver.done
            self
          end

          define_method(:with_receiver) do |new_receiver|
            args = attributes.map { |name|
              instance_variable_get("@#{name}".to_sym)
            }
            args[-1] = new_receiver
            self.class.new(*args)
          end

        end

        if block
          Class.new(result, &block)
        else
          result
        end
      end
    end
  end
end
