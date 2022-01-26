require 'bundler/setup'
require 'minitest'
require 'minitest/reporters'
require 'minitest/autorun'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

describe String do
  describe '#length' do
    it 'works' do
      assert_equal 5, 'hello'.length
    end

    it 'doesn\'t works' do
      assert_equal 6, 'hello'.length
    end
  end
end
