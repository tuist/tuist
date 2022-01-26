# frozen_string_literal: true

module Cucumber
  module Core
    module Test
      # Step Definitions that match a plain text Step with a multiline argument table
      # will receive it as an instance of DataTable. A DataTable object holds the data of a
      # table parsed from a feature file and lets you access and manipulate the data
      # in different ways.
      #
      # For example:
      #
      #   Given I have:
      #     | a | b |
      #     | c | d |
      #
      # And a matching StepDefinition:
      #
      #   Given /I have:/ do |table|
      #     data = table.raw
      #   end
      #
      # This will store <tt>[['a', 'b'], ['c', 'd']]</tt> in the <tt>data</tt> variable.
      #
      class DataTable
        # Creates a new instance. +raw+ should be an Array of Array of String
        # or an Array of Hash
        # You don't typically create your own DataTable objects - Cucumber will do
        # it internally and pass them to your Step Definitions.
        #
        def initialize(rows)
          raw = ensure_array_of_array(rows)
          verify_rows_are_same_length(raw)
          @raw = raw.freeze
        end
        attr_reader :raw

        def describe_to(visitor, *args)
          visitor.data_table(self, *args)
        end

        def to_step_definition_arg
          dup
        end

        def data_table?
          true
        end

        def doc_string?
          false
        end

        # Creates a copy of this table
        #
        def dup
          self.class.new(raw.dup)
        end

        # Returns a new, transposed table. Example:
        #
        #   | a | 7 | 4 |
        #   | b | 9 | 2 |
        #
        # Gets converted into the following:
        #
        #   | a | b |
        #   | 7 | 9 |
        #   | 4 | 2 |
        #
        def transpose
          self.class.new(raw.transpose)
        end

        def map(&block)
          new_raw = raw.map do |row|
            row.map(&block)
          end

          self.class.new(new_raw)
        end

        def ==(other)
          other.class == self.class && raw == other.raw
        end

        def inspect
          %{#<#{self.class} #{raw.inspect})>}
        end

        private

        def verify_rows_are_same_length(raw)
          begin
            raw.transpose
          rescue IndexError
            raise ArgumentError, "Rows must all be the same length"
          end
        end

        def ensure_array_of_array(array)
          Hash === array[0] ? hashes_to_array(array) : array
        end

        def hashes_to_array(hashes)
          header = hashes[0].keys.sort
          [header] + hashes.map {|hash| header.map {|key| hash[key]}}
        end

      end
    end
  end
end
