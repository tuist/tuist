require 'ansi/code'

module ANSI

  # Diff produces colorized differences of two string or objects.
  #
  class Diff

    # Highlights the differnce between two strings.
    #
    # This class method is equivalent to calling:
    #
    #   ANSI::Diff.new(object1, object2).to_a
    #
    def self.diff(object1, object2, options={})
      new(object1, object2, options={}).to_a
    end

    # Setup new Diff object. If the objects given are not Strings
    # and do not have `#to_str` defined to coerce them to such, then
    # their `#inspect` methods are used to convert them to strings
    # for comparison.
    #
    # @param [Object] object1
    #   First object to compare.
    #
    # @param [Object] object2
    #   Second object to compare.
    #
    # @param [Hash] options
    #   Options for contoller the way difference is shown. (Not yet used.)
    #
    def initialize(object1, object2, options={})
      @object1 = convert(object1)
      @object2 = convert(object2)

      @diff1, @diff2 = diff_string(@object1, @object2)
    end

    # Returns the first object's difference string.
    def diff1
      @diff1
    end

    # Returns the second object's difference string.
    def diff2
      @diff2
    end

    # Returns both first and second difference strings separated by a
    # new line character.
    #
    # @todo Should we use `$/` record separator instead?
    #
    # @return [String] Joined difference strings.
    def to_s
      "#{@diff1}\n#{@diff2}"
    end

    # Returns both first and second difference strings separated by a
    # the given `separator`. The default is `$/`, the record separator.
    #
    # @param [String] separator
    #   The string to use as the separtor between the difference strings.
    #
    # @return [String] Joined difference strings.
    def join(separator=$/)
      "#{@diff1}#{separator}#{@diff2}"
    end

    # Returns the first and second difference strings in an array.
    #
    # @return [Array] Both difference strings.
    def to_a
      [diff1, diff2]
    end

  private

    # Take two plain strings and produce colorized
    # versions of each highlighting their differences.
    #
    # @param [String] string1
    #   First string to compare.
    #
    # @param [String] string2
    #   Second string to compare.
    #
    # @return [Array<String>] The two difference strings.
    def diff_string(string1, string2)
      compare(string1, string2)
    end

    # Ensure the object of comparison is a string. If +object+ is not
    # an instance of String then it wll be converted to one by calling
    # either #to_str, if the object responds to it, or #inspect.
    def convert(object)
      if String === object
        object
      elsif object.respond_to?(:to_str)
        object.to_str
      else
        object.inspect
      end
    end

    # Rotation of colors for diff output.
    COLORS = [:red, :yellow, :magenta]

    # Take two plain strings and produce colorized
    # versions of each highlighting their differences.
    #
    # @param [String] x
    #   First string to compare.
    #
    # @param [String] y
    #   Second string to compare.
    #
    # @return [Array<String>] The two difference strings.
    def compare(x, y)
      c = common(x, y)
      a = x.dup
      b = y.dup
      oi = 0
      oj = 0
      c.each_with_index do |m, q|
        i = a.index(m, oi)
        j = b.index(m, oj)
        a[i,m.size] = ANSI.ansi(m, COLORS[q%3]) if i
        b[j,m.size] = ANSI.ansi(m, COLORS[q%3]) if j
        oi = i + m.size if i
        oj = j + m.size if j
      end
      return a, b
    end

    # Oh, I should have documented this will I knew what the
    # hell it was doing ;)
    def common(x,y)
      c = lcs(x, y)

      i = x.index(c)
      j = y.index(c)

      ix = i + c.size
      jx = j + c.size

      if i == 0 
        l = y[0...j]
      elsif j == 0
        l = x[0...i]
      else
        l = common(x[0...i], y[0...j])
      end

      if ix == x.size - 1
        r = y[jx..-1]
      elsif jx = y.size - 1
        r = x[ix..-1]
      else
        r = common(x[ix..-1], y[jx..-1])
      end

      [l, c, r].flatten.reject{ |s| s.empty? }
    end

    # Least common string.
    def lcs(s1, s2)
      res="" 
      num=Array.new(s1.size){Array.new(s2.size)}
      len,ans=0
      lastsub=0
      s1.scan(/./).each_with_index do |l1,i |
        s2.scan(/./).each_with_index do |l2,j |
          unless l1==l2
            num[i][j]=0
          else
            (i==0 || j==0)? num[i][j]=1 : num[i][j]=1 + num[i-1][j-1]
            if num[i][j] > len
              len = ans = num[i][j]
              thissub = i
              thissub -= num[i-1][j-1] unless num[i-1][j-1].nil?  
              if lastsub==thissub
                res+=s1[i,1]
              else
                lastsub=thissub
                res=s1[lastsub, (i+1)-lastsub]
              end
            end
          end
        end
      end
      res
    end

    # Hmm... is this even useful?
    def lcs_size(s1, s2)
      num=Array.new(s1.size){Array.new(s2.size)}
      len,ans=0,0
      s1.scan(/./).each_with_index do |l1,i |
        s2.scan(/./).each_with_index do |l2,j |
          unless l1==l2
            num[i][j]=0
          else
            (i==0 || j==0)? num[i][j]=1 : num[i][j]=1 + num[i-1][j-1]
            len = ans = num[i][j] if num[i][j] > len
          end
        end
      end
      ans
    end

  end

end
