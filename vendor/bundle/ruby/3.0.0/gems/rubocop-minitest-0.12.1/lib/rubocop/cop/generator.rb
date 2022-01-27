# frozen_string_literal: true

module RuboCop
  module Cop
    # Source and test generator for new cops
    #
    # This generator will take a cop name and generate a source file
    # and test file when given a valid qualified cop name.
    class Generator
      TEST_TEMPLATE = <<~TEST
        # frozen_string_literal: true

        require 'test_helper'

        class %<cop_name>sTest < Minitest::Test
          def test_registers_offense_when_using_bad_method
            assert_offense(<<~RUBY)
              bad_method
              ^^^^^^^^^^ Use `#good_method` instead of `#bad_method`.
            RUBY

            assert_correction(<<~RUBY)
              good_method
            RUBY
          end

          def test_does_not_register_offense_when_using_good_method
            assert_no_offenses(<<~RUBY)
              good_method
            RUBY
          end
        end
      TEST

      def write_test
        write_unless_file_exists(test_path, generated_test)
      end

      private

      def test_path
        File.join(
          'test',
          'rubocop',
          'cop',
          'minitest',
          "#{snake_case(badge.cop_name.to_s)}_test.rb"
        )
      end

      def generated_test
        generate(TEST_TEMPLATE)
      end
    end
  end
end
