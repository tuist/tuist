module CLI
  module Kit
    module Util
      class << self
        def snake_case(camel_case, seperator = "_")
          camel_case.to_s # MyCoolThing::MyAPIModule
            .gsub(/::/, '/') # MyCoolThing/MyAPIModule
            .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1#{seperator}\\2") # MyCoolThing::MyAPI_Module
            .gsub(/([a-z\d])([A-Z])/, "\\1#{seperator}\\2") # My_Cool_Thing::My_API_Module
            .downcase # my_cool_thing/my_api_module
        end

        def dash_case(camel_case)
          snake_case(camel_case, '-')
        end

        # The following methods is taken from activesupport
        # All credit for this method goes to the original authors.
        # https://github.com/rails/rails/blob/d66e7835bea9505f7003e5038aa19b6ea95ceea1/activesupport/lib/active_support/core_ext/string/strip.rb
        #
        # Copyright (c) 2005-2018 David Heinemeier Hansson
        #
        # Permission is hereby granted, free of charge, to any person obtaining
        # a copy of this software and associated documentation files (the
        # "Software"), to deal in the Software without restriction, including
        # without limitation the rights to use, copy, modify, merge, publish,
        # distribute, sublicense, and/or sell copies of the Software, and to
        # permit persons to whom the Software is furnished to do so, subject to
        # the following conditions:
        #
        # The above copyright notice and this permission notice shall be
        # included in all copies or substantial portions of the Software.
        #
        # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
        # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
        # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
        # LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
        # OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
        # WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        #
        # Strips indentation by removing the amount of leading whitespace in the least indented
        # non-empty line in the whole string
        #
        def strip_heredoc(str)
          str.gsub(/^#{str.scan(/^[ \t]*(?=\S)/).min}/, "".freeze)
        end

        # Joins an array with commas and "and", using the Oxford comma.
        def english_join(array)
          return "" if array.nil?
          return array.join(" and ") if array.length < 3

          "#{array[0..-2].join(', ')}, and #{array[-1]}"
        end

        # Execute a block within the context of a variable enviroment
        #
        def with_environment(environment, value)
          return yield unless environment

          old_env = ENV[environment]
          begin
            ENV[environment] = value
            yield
          ensure
            old_env ? ENV[environment] = old_env : ENV.delete(environment)
          end
        end

        # Converts an integer representing bytes into a human readable format
        #
        def to_filesize(bytes, precision: 2, space: false)
          to_si_scale(bytes, 'B', precision: precision, space: space, factor: 1024)
        end

        # Converts a number to a human readable format on the SI scale
        #
        def to_si_scale(number, unit = '', factor: 1000, precision: 2, space: false)
          raise ArgumentError, "factor should only be 1000 or 1024" unless [1000, 1024].include?(factor)

          small_scale = %w(m µ n p f a z y)
          big_scale = %w(k M G T P E Z Y)
          negative = number < 0
          number = number.abs.to_f

          if number == 0 || number.between?(1, factor)
            prefix = ""
            scale = 0
          else
            scale = Math.log(number, factor).floor
            if number < 1
              index = [-scale - 1, small_scale.length].min
              scale = -(index + 1)
              prefix = small_scale[index]
            else
              index = [scale - 1, big_scale.length].min
              scale = index + 1
              prefix = big_scale[index]
            end
          end

          divider = (factor**scale)
          fnum = (number / divider).round(precision)

          # Trim useless decimal
          fnum = fnum.to_i if (fnum.to_i.to_f * divider) == number

          fnum = -fnum if negative
          prefix = " " + prefix if space

          "#{fnum}#{prefix}#{unit}"
        end

        # Dir.chdir, when invoked in block form, complains when we call chdir
        # again recursively. There's no apparent good reason for this, so we
        # simply implement our own block form of Dir.chdir here.
        def with_dir(dir)
          prev = Dir.pwd
          Dir.chdir(dir)
          yield
        ensure
          Dir.chdir(prev)
        end

        def with_tmp_dir
          require 'fileutils'
          dir = Dir.mktmpdir
          with_dir(dir) do
            yield(dir)
          end
        ensure
          FileUtils.remove_entry(dir)
        end

        # Standard way of checking for CI / Tests
        def testing?
          ci? || ENV['TEST']
        end

        # Set only in IntegrationTest#session; indicates that the process was
        # called by `session.execute` from an IntegrationTest subclass.
        def integration_test_session?
          ENV['INTEGRATION_TEST_SESSION']
        end

        # Standard way of checking for CI
        def ci?
          ENV['CI']
        end

        # Must call retry_after on the result in order to execute the block
        #
        # Example usage:
        #
        # CLI::Kit::Util.begin do
        #   might_raise_if_costly_prep_not_done()
        # end.retry_after(ExpectedError) do
        #   costly_prep()
        # end
        def begin(&block_that_might_raise)
          Retrier.new(block_that_might_raise)
        end
      end

      class Retrier
        def initialize(block_that_might_raise)
          @block_that_might_raise = block_that_might_raise
        end

        def retry_after(exception = StandardError, retries: 1, &before_retry)
          @block_that_might_raise.call
        rescue exception => e
          raise if (retries -= 1) < 0
          if before_retry
            if before_retry.arity == 0
              yield
            else
              yield e
            end
          end
          retry
        end
      end

      private_constant :Retrier
    end
  end
end
