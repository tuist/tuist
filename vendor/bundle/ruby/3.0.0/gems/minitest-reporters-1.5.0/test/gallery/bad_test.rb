require_relative "../test_helper"

module MinitestReportersTest
  class BadTest < TestCase
    def test_a
      assert_equal 1, 2
    end

    def test_b
      assert false # simple failure
    end

    def test_b
      assert_equal "ab\nc", "ab\nd" # some nice diff
    end

    def test_boom
      raise "A random exception"
    end

    def test_long_method_name
      skip
    end
  end
end
