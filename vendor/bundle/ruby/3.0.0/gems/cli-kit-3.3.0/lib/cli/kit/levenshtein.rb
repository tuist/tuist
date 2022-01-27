# Copyright (c) 2014-2016 Yuki Nishijima

# MIT License

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module CLI
  module Kit
    module Levenshtein
      # This code is based directly on the Text gem implementation
      # Copyright (c) 2006-2013 Paul Battley, Michael Neumann, Tim Fletcher.
      #
      # Returns a value representing the "cost" of transforming str1 into str2
      def distance(str1, str2)
        n = str1.length
        m = str2.length
        return m if n.zero?
        return n if m.zero?

        d = (0..m).to_a
        x = nil

        # to avoid duplicating an enumerable object, create it outside of the loop
        str2_codepoints = str2.codepoints

        str1.each_codepoint.with_index(1) do |char1, i|
          j = 0
          while j < m
            cost = char1 == str2_codepoints[j] ? 0 : 1
            x = min3(
              d[j + 1] + 1, # insertion
              i + 1,      # deletion
              d[j] + cost # substitution
            )
            d[j] = i
            i = x

            j += 1
          end
          d[m] = x
        end

        x
      end
      module_function :distance

      private

      # detects the minimum value out of three arguments. This method is
      # faster than `[a, b, c].min` and puts less GC pressure.
      # See https://github.com/yuki24/did_you_mean/pull/1 for a performance
      # benchmark.
      def min3(a, b, c)
        if a < b && a < c
          a
        elsif b < c
          b
        else
          c
        end
      end
      module_function :min3
    end
  end
end
