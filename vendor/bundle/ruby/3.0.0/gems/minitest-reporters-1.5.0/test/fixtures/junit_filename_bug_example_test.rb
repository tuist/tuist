# This is a test for a bug that was happening when the JUnit Reporter was
# creating filenames from `describe`s that contained slashes, which would crash
# since it was trying to create directories then.

require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::JUnitReporter.new

describe 'something/other' do
  it 'does something' do
    1.must_equal 1
  end
end

describe 'something/other' do
  it 'does something else' do
    1.must_equal 2
  end
end

class Eval
  class Issue258Tset < Minitest::Test
    def test_true
      assert true
    end

    [
        ["bool1", "true", "true"],
        ["bool2", "false", "false"]
    ].each do |a|
      (type, expectation1, expectation2) = a
      eval(%{
       def test_eval_#{type}_#{expectation1}
         assert_equal(#{expectation1}, #{expectation2})
       end
      })
    end
  end
end
