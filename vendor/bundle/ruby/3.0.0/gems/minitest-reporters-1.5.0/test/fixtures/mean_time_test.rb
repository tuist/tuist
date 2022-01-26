require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/reporters/mean_time_reporter'

Minitest::Reporters.use! Minitest::Reporters::MeanTimeReporter.new

class TestClass < Minitest::Test
  def test_assertion
    assert true
  end

  def test_fail
    fail
  end
end

class AnotherTestClass < Minitest::Test
  def test_assertion
    assert true
  end

  def test_fail
    fail
  end
end

class LastTestClass < Minitest::Test
  def test_assertion
    assert true
  end

  def test_fail
    fail
  end
end
